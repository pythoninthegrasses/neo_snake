---
id: decision-025
title: Parity capture via sway+wtype+grim, not xvfb-run
date: '2026-09-12 19:35'
status: Accepted
---
## Context

TASK-037's Description and AC#2 call for the golden-image parity suite to run "headless-adjacent via
`xvfb-run`". `xvfb-run` wraps an X11 virtual framebuffer (`Xvfb`) — it has no way to host a Wayland
compositor, and this box (`mf`, AlmaLinux 10) has no `Xvfb` package installed at all. Both the Godot
build (via its native Wayland backend, confirmed by `WARNING: Display driver x11 failed, falling
back to wayland` when launched under a Wayland-only session) and Firefox render natively under
Wayland, not X11, on this machine.

`~/git/zelda3`'s `backlog/tasks/task-005` already solved the identical problem for that repo, on
this same machine: `weston` (screenshot capture crashed), `ydotool`/`uinput` (events never reach a
headless wlroots compositor's libinput backend), and `cage` (registers keyboard capability on the
seat but never sends `wl_keyboard.enter` to client surfaces) were all tried and ruled out, leaving
`sway` (built from source against packaged `wlroots`, launched via `WLR_BACKENDS=headless
WLR_RENDERER=pixman`) + `wtype` (virtual-keyboard key injection) + `grim` (`wlr-screencopy`
screenshots) as the only combination that actually works end-to-end. All three binaries are already
built and installed at `/usr/local/bin/` on this machine from that prior work.

## Decision

**`tools/capture_parity.sh` (wired via `taskfiles/parity.yml`'s `parity:capture`) substitutes
sway+wtype+grim for `xvfb-run`**, satisfying AC#2's own explicit "in `task check` **or a documented
separate task**" alternative — a new, undocumented-in-`check` taskfile target, exactly like
`oracle:fuzz`'s existing "deliberately NOT part of `task check`" precedent.

**Godot's own state is driven programmatically, not by simulated key events.** Real OS-level key
injection via `wtype` into a live Godot window under headless sway was attempted first and does not
work: `WAYLAND_DEBUG=1` tracing showed genuine `wl_keyboard.enter`/`.keymap`/`.key` protocol events
reaching Godot's Wayland thread (including a second, unexplained `keymap` event mid-session), but no
observable game-state change ever resulted, across two independently-ordered attempts. This is a
Godot/Wayland-backend-specific issue — the identical `wtype` mechanism drives real key input into
Firefox (below) and into zelda3's SDL2 app without any trouble, so the fault isn't in `wtype` itself.
Rather than chase an open-ended Godot Wayland input bug, `game_screen.gd` gained a small,
explicitly-guarded debug hook: `_maybe_drive_capture_state()`, triggered only by an
`--capture-state=menu|playing|paused|dead` CLI user-arg the game's normal launch never passes. It
calls `GameScreen`'s own already-tested handlers directly (`_on_direction_queued()`,
`_on_pause_requested()`), the same pattern `game/tests/test_game_screen.gd` already uses to drive a
`GameScreen` without a live scene tree, and (for `dead`) drives `_process()` in a tight loop with
`set_process(false)` first so neither the manual calls nor the engine's own automatic per-frame call
double-step the simulation. This keeps rendering (sway+grim) and game-over-reachability (Godot's own
handlers) decoupled from the one thing that's actually broken (Wayland key delivery into Godot).

**The oracle side (`reference/snake.html`) is driven by real `wtype` key injection into a real
Firefox window**, not a hook — `reference/snake.html` must never be edited (frozen oracle,
`AGENTS.md`), and unlike Godot, Firefox's GTK/Wayland keyboard handling works correctly with `wtype`
out of the box: `Up` starts the run, `Space` pauses/resumes, and letting real wall-clock time pass
after a fresh start reliably runs the snake into the wall (its post-start direction is always
clobbered to right — [[decision-015]]) for a `dead` capture, all confirmed via captured screenshots.
Each state launches Firefox fresh (`--new-instance --profile <fresh temp dir> --no-remote`) rather
than reusing one window across states, avoiding any input-ordering ambiguity (a double `Space` press
toggles pause back off) that a single long-lived session risks.

## Consequences

- `task parity:capture` requires `sway`, `wtype`, `grim`, and `firefox` on `PATH`, and is gated to
  `platforms: [linux]` — it is not runnable on macOS, and is never part of `task check`.
- `game_screen.gd`'s `--capture-state=` hook is inert during normal play (no cmdline arg is ever
  passed by a real launch) and touches no simulation/canonical-state code — it only calls handlers
  that already exist and are already exercised by `test_game_screen.gd`.
- The suite's screenshots (`artifacts/parity/`, gitignored) are for a human to eyeball side by side
  against the same states from `reference/snake.html` — see `docs/build-layout.md`'s TASK-037
  section for the comparison methodology and its cross-references to [[decision-006]],
  [[decision-007]], and [[decision-022]] (the already-accepted shadowBlur and corner-radius visual
  divergences this suite is not meant to re-litigate).

---
id: decision-024
title: Screens and HUD oracle deviations (TASK-036)
date: '2026-09-12 18:50'
status: Accepted
---
## Context

TASK-036 ports `reference/snake.html`'s `showOverlay()`/`hideOverlay()` content and the score/best
HUD to real Control nodes (`game/presentation/screens/`). Several oracle behaviors don't translate
directly and needed an explicit call.

## Decision

**Mode-select scoped to the menu screen only.** The oracle's `<select id="mode">` is a permanent
sibling of `#overlay`'s rebuilt title/sub/button markup (snake.html:227-241) — it is structurally
visible whenever the overlay is shown at all, i.e. during menu, paused, and dead alike, not just
menu. This is a side effect of `showOverlay()` reusing one div rather than a designed always-on
mode picker. `OverlayPanel.configure()` only sets `show_mode_select = true` for the menu screen
(`game_screen_state.gd`). Justification: the live GDExtension world's status can never return to
`menu` after the first `start()` (mirrored from the oracle's own status lifecycle, not a narrowing
of it), so honoring a mid-run mode change would require a full `world.init()` regardless of which
screen shows the picker — scoping it to pre-first-start keeps "which mode is this run" unambiguous
for the whole session at no cost to any reachable behavior.

**HUD scoped to score, per-mode best, and status text.** `Hud` omits the oracle's Speed/Length
stats (snake.html:218-223) — TASK-036's own Description asks only for score/best/status, so adding
the rest would be scope creep past the task's AC.

**Win vs. Game Over via ABI event kind, not a derived check.** `GameScreen._process()` distinguishes
the two by which of `NS_EVENT_WIN`/`NS_EVENT_DIE` `event_drain()` returns (both already synthesized
by `core/abi.zig`'s `stepOneTick()`), not by re-deriving "board full" from the world state.

**`board_view.gd`'s pause-vignette branch stays dead code.** `_draw_pause_vignette()` checks
`status == BoardGeometry.STATUS_PAUSED`, but no export ever drives a live world's status to
`NS_STATUS_PAUSED` — `GameScreen` layers pause entirely at the app level (`_paused: bool`, gating
`TickDriver.advance_frame`'s `gate` param) since `ns_pump` already no-ops for any non-`.playing`
world. The branch is inert until/unless a later task wires a real paused world status through.

**Overlay text is plain, no `<br>`/`<b>` markup.** `showOverlay()` builds `innerHTML` strings
(e.g. `"Score <b>" + score + "</b> · Best <b>" + best + "</b><br>..."`); TASK-036's own Description
calls for real Control nodes instead of `innerHTML`, and a `Label` needs no markup to break a line
or emphasize a number, so `game_screen_state.gd`'s `overlay_content()` returns plain multi-line
strings (`"\n"` where the oracle used `<br>`).

**R-key and direction-key auto-start both faithfully discard the triggering direction.** The
oracle's R handler calls `start()` unconditionally regardless of status (snake.html:584), and
`queueDir()`'s own auto-start branch (snake.html:576) sets `nextDir` to the pressed key *before*
calling `start()` — but `start()` calls `reset()`, which unconditionally sets
`S.dir = S.nextDir = right` (snake.html:312), clobbering that just-set `nextDir`. So the keypress
that starts a run from menu/dead never steers it; only input after the run has begun does.
`GameScreen._on_direction_queued()` reproduces this: a direction input from menu/dead calls
`_start_or_restart()` and returns without ever forwarding that direction to `world.queue_dir()`.

## Consequences

All four items are either UI-only (mode-select scoping, HUD field scope, plain-text overlay) or a
faithful reproduction of an existing oracle quirk (win/die event kind, dead pause-vignette branch,
direction-on-start discard) — none change `docs/canonical-state.md` or simulation determinism.

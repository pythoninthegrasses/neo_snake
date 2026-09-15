---
id: decision-038
title: Space is pause-only, Enter/Kp Enter is select
date: '2026-09-15 16:20'
status: Accepted
---
## Context

`reference/snake.html` gives Space two jobs. Its keydown handler calls `togglePause()` while
playing, and from the menu or dead screen the same key starts or restarts a run
(`snake.html:584-591`). This port inherited both behaviors, and additionally bound Enter/Kp Enter to
`ACTION_PAUSE` so a keyboard player could confirm the overlay's action button.

That left Space meaning three things at once on desktop: pause, start/restart, and -- through
Godot's built-in `ui_accept`, whose engine default is Enter, Kp Enter *and* Space -- "activate the
focused overlay control". The overlay's action button holds focus whenever the overlay is up, so a
single Space press on the menu screen both ran `_on_pause_requested()` (which started the run) and
pressed the Start button.

## Decision

**Space is pause-only. Enter/Kp Enter is select.**

`GameScreen._on_pause_requested()` returns unless the shared status is `PLAYING`, so Space does
nothing at all on the menu and dead screens. Pause is an app-level flag and the sim's own status
stays `PLAYING` while paused (see this file's neighbors on the unreachable `NS_STATUS_PAUSED`), so
that one check covers pausing and resuming alike.

Enter/Kp Enter are removed from `ACTION_PAUSE` and become the select key, confirming whichever
overlay control has focus via `ui_accept`. `project.godot` declares its own `ui_accept` binding
(Enter + Kp Enter) purely to *replace* the engine default -- declaring the action at all is what
drops Space from it. Without that override Space would keep activating the focused button no matter
what `ACTION_PAUSE` is bound to, since `ui_accept` is handled by the GUI layer before
`input_router.gd`'s `_unhandled_input` ever sees the event.

Starting and restarting a run from the keyboard is unaffected: Enter presses the focused
Start/Play-again button, and any direction key still auto-starts through `queueDir`'s own
menu/dead branch (`snake.html:576`), which this port keeps.

## Consequences

A deliberate divergence from the oracle: a player who presses Space at the Neo Snake menu gets
nothing, where `reference/snake.html` would start the run. Per Lance's 2026-09-15 instruction the
oracle is a one-shot reference implementation rather than an authoritative spec, so matching its
key handling is not a goal when the port's own UX is better served otherwise -- and a menu with
real focusable controls (mode selector, Start, Settings) wants an unambiguous confirm key in a way
a single `<div>` overlay never did.

`game/platform/input_defaults.gd`, `game/project.godot`,
`game/presentation/screens/game_screen.gd`, `game/presentation/screens/overlay_panel.gd`'s class
comment, and `docs/build-layout.md` all changed.
`game/tests/test_game_screen.gd::test_pause_requested_from_the_menu_does_nothing` pins the new
behavior; `game/tests/test_input_defaults.gd` already pins `pause` back to Space alone, since it
asserts the loaded `InputMap` against `InputDefaults.ACTION_PHYSICAL_KEYCODES` in both directions.

The parity capture harness (`docs/build-layout.md`'s TASK-037 section) is unaffected -- it drives
`GameScreen`'s handlers directly rather than pressing keys.

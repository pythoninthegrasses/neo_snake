---
id: TASK-056
title: Make Space pause-only and Enter/Return the select key
status: In Progress
assignee:
  - '@claude'
created_date: '2026-09-15 16:09'
updated_date: '2026-09-15 16:09'
labels: []
dependencies: []
priority: medium
type: enhancement
ordinal: 56000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Split the two roles Space currently plays. Today Space both toggles pause *and* starts/restarts a
run from the menu/dead overlay, and -- via Godot's built-in `ui_accept` -- also activates whatever
overlay control has focus. Enter/Kp Enter are additionally bound to `ACTION_PAUSE` (TASK-036-era
addition) so the overlay could be confirmed from the keyboard.

Lance's spec (2026-09-15): **Space is pause-only. Enter/Return is select.**

So Space must stop starting/restarting a run and stop activating focused controls, and Enter/Kp
Enter must stop being a pause key and become the sole confirm key.

This diverges from reference/snake.html, where Space both pauses and starts (`snake.html:584-591`)
and there is no Enter handling at all. Per Lance's 2026-09-15 instruction the oracle is a one-shot
reference, not an authoritative spec -- the divergence is intended and gets recorded in
backlog/decisions/.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Space toggles pause while playing and does nothing at all on the menu and dead screens (no start, no restart)
- [ ] #2 Space no longer activates the focused overlay control (Godot's built-in ui_accept is overridden to exclude it)
- [ ] #3 Enter and Kp Enter select/confirm the focused overlay control and are no longer bound to ACTION_PAUSE
- [ ] #4 Starting and restarting a run from the keyboard still works via Enter on the overlay's action button, and via any direction key
- [ ] #5 The InputMap in project.godot and InputDefaults.ACTION_PHYSICAL_KEYCODES stay in sync, asserted by a test
- [ ] #6 The Space/Enter divergence from reference/snake.html is recorded in backlog/decisions/
- [ ] #7 task check is green
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. (TDD) Failing tests first:
   - `test_game_screen.gd`: pause from the menu leaves status MENU and the overlay up.
   - `test_game_screen.gd`: pause after death leaves status DEAD (no restart).
   - `test_input_defaults.gd`: `ui_accept` is Enter + Kp Enter and excludes Space, so a
     project.godot edit that drops the override (reverting to Godot's Space-inclusive default)
     fails loudly.
2. `input_defaults.gd`: `ACTION_PAUSE: [KEY_SPACE]`; add `ACTION_UI_ACCEPT := "ui_accept"` with
   `[KEY_ENTER, KEY_KP_ENTER]` so the override is declared as data next to everything else.
3. `project.godot`: `pause` = Space only; add a `ui_accept` override = Enter + Kp Enter (declaring
   it at all replaces Godot's built-in default, which includes Space).
4. `game_screen.gd::_on_pause_requested()`: return unless `_shared_status()` is PLAYING. Pause is
   app-level so the sim status stays PLAYING while paused -- the same check covers resume.
5. Update the class comments in `input_defaults.gd` and `overlay_panel.gd` that describe
   Space/Enter behavior, plus `docs/build-layout.md` if it documents the pause key.
6. New `backlog/decisions/` entry for the divergence from the oracle's Space-starts-and-pauses
   handler.
7. `task check`.

Note: `ACTION_UI_ACCEPT` must NOT go into `KeybindCodec.default_keybinds()`'s rebindable set in a
way that lets the settings panel erase Godot's UI navigation -- check how
`settings_panel.gd` iterates `ACTION_PHYSICAL_KEYCODES` before adding a key there.
<!-- SECTION:PLAN:END -->

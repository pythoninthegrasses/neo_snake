---
id: TASK-055
title: Fix arrow keys not steering the snake during gameplay
status: Done
assignee:
  - '@claude'
created_date: '2026-09-15 15:54'
updated_date: '2026-09-15 16:03'
labels: []
dependencies: []
modified_files:
  - game/presentation/board/board_view.gd
  - game/presentation/screens/game_screen.gd
  - game/platform/input_router.gd
  - game/platform/input_defaults.gd
  - game/project.godot
  - game/tests/test_game_screen.gd
  - docs/build-layout.md
  - >-
    backlog/decisions/decision-035 -
    Godot-layer-local-2-player-keyboard-split-shared-status-derivation-scoped-best-score.md
priority: high
type: bug
ordinal: 55000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
During active gameplay, the arrow keys (Up/Down/Left/Right) do not steer player 0's snake -- it keeps going straight and dies into walls. WASD, bound to the exact same GDScript action-to-direction pipeline (input_router.gd's `_unhandled_input` -> `direction_queued` signal -> game_screen.gd's `_on_direction_queued` -> `world.queue_dir`), works correctly when temporarily also bound to player 0's move actions for testing. This was confirmed directly by the user: with WASD mapped onto player 0's move_up/down/left/right actions (alongside the arrows) as a live A/B test, WASD steers correctly and arrows do not, in the same running session, using the identical code path.

This is NOT a core-simulation bug: core/world.zig's queue_dir/reversal-guard logic was independently verified correct via multiple headless GDScript test scripts (confirmed direction commits happen correctly once per tick, matching reference/snake.html's own queueDir semantics). It is also not a GDScript-level `is_action_pressed()` matching bug -- debug instrumentation confirmed `event.is_action_pressed(ACTION_MOVE_UP/DOWN/LEFT/RIGHT)` correctly returns true for real arrow keypresses, and `_on_direction_queued` is reliably invoked with the correct player/dir arguments for arrow presses. Despite that, the live game does not visibly respond to arrow steering during actual gameplay the way it does to WASD.

Per Lance's explicit instruction (2026-09-15): reference/snake.html is a one-shot reference implementation, not an immutable authoritative spec -- fixing this does not need to preserve any oracle quirk if the fix requires diverging from it.

## Diagnostic artifacts left in the working tree (clean these up as part of this fix)

- `game/platform/input_router.gd`: a temporary `print("DEBUG unhandled_input reached: ...")` at the top of `_unhandled_input`.
- `game/presentation/screens/game_screen.gd`: temporary `print("DEBUG dq before/after: ...")` lines in `_on_direction_queued`, and a temporary `_debug_poll_input_file()` method (polls `/tmp/godot_debug_input_cmd.txt` and feeds a synthetic `InputEventKey` via `Input.parse_input_event()`) called from `_process()` -- this was a deterministic input-injection harness used for diagnosis via the Godot MCP's `run_project`/`get_debug_output` tools, not intended to ship.
- `game/platform/input_defaults.gd` and `game/project.godot`: `ACTION_MOVE_UP/DOWN/LEFT/RIGHT` currently have WASD physical keycodes temporarily added alongside the arrow keycodes (for the A/B test above) -- revert to arrow-keys-only for player 0's actions once the real fix lands (WASD should stay exclusively bound to player 2's `ACTION_P2_MOVE_*` actions).

All of the above should be removed/reverted, not left in place, once the real root cause is fixed.

## Suggested next diagnostic step

Since is_action_pressed()/action routing/simulation logic are all confirmed correct, and only the difference between WASD and arrow *physical keys* reproduces the bug, focus on anything arrow-key-specific: physical_keycode values in the 4194319-4194322 range (Left/Up/Right/Down) vs the letter-key range, whether these events carry different flags (e.g. `echo`, `location`, modifier state) that some other code path treats differently, or platform/DisplayServer-level handling specific to the arrow/navigation key cluster on macOS.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Arrow keys (Up/Down/Left/Right) correctly steer player 0's snake during active gameplay, matching WASD's already-correct behavior in the same session
- [x] #2 Root cause is identified and documented (not just worked around)
- [x] #3 All temporary diagnostic debug prints in game/platform/input_router.gd and game/presentation/screens/game_screen.gd are removed
- [x] #4 The temporary _debug_poll_input_file() input-injection harness in game/presentation/screens/game_screen.gd is removed
- [x] #5 game/platform/input_defaults.gd and game/project.godot's ACTION_MOVE_UP/DOWN/LEFT/RIGHT are reverted to arrow-keys-only (WASD remains exclusively bound to ACTION_P2_MOVE_* for player 2)
- [x] #6 task game:test passes with no failures
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 task check is green
- [x] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [x] #3 Docs touched by the change are updated in the same commit
- [x] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## Root cause (reproduced and confirmed 2026-09-15)

Arrow keys were never broken. Reproduced a live session (`./tools/run.py godot --path game`)
and drove it with real OS-level key events (AppleScript `System Events` key codes, i.e. the
same event path a human keypress takes -- not `Input.parse_input_event()` injection). Debug
output shows arrows reaching `_unhandled_input`, dispatching to player 0, and `world.queue_dir`
committing every turn of a full Up/Left/Down/Right square.

Two separate facts explain the report:

1. **`board_view_p2` erases player 0's snake.** `board_view.gd::_draw()` unconditionally starts
   with `_draw_background()` -- an opaque full-board `draw_rect` -- then checkerboard, grid and
   food. `game_screen.gd` adds `board_view_p2` *after* `board_view`, so the second instance
   repaints that opaque stack over the first one every frame. Only player 1's snake is ever
   visible. Arrows steer player 0 (invisible); WASD steers player 1 (the only snake on screen).
   That is exactly "arrows do nothing, WASD works".
2. **The A/B test could not have worked as intended.** `_apply_settings()` calls
   `KeybindCodec.apply_to_input_map(settings.keybinds)` at startup, which `action_erase_events()`
   then rebuilds every action from `user://save.json`. The real save file already pins
   `move_*` to arrows only, so adding WASD to `project.godot`'s `move_*` never reached the live
   InputMap. Confirmed in the live log: pressing W emitted `player=1`, not player 0.

## Plan

1. (TDD) Add a failing test to `game/tests/test_game_screen.gd` asserting only the bottom-most
   BoardView paints the shared board layers.
2. Add `draws_shared_board` (default `true`) to `board_view.gd`; gate background/checkerboard/
   grid/food on it. Snake/eyes/particles/flash/vignette stay per-view (all per-player or
   translucent). `BoardGeometry.DRAW_LAYER_ORDER` is unchanged -- the bottom view still draws
   the full order.
3. Set `board_view_p2.draws_shared_board = false` in `game_screen.gd`.
4. Remove the diagnostic artifacts (AC#3, #4, #5): debug prints in `input_router.gd` and
   `game_screen.gd`, `_debug_poll_input_file()` and its `_process()` call, and revert
   `input_defaults.gd` + `project.godot` `move_*` to arrows-only.
5. Update `docs/architecture.md` for the shared-vs-per-player draw split; record the
   divergence in `backlog/decisions/` if one is warranted.
6. `task game:test` green.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## Root cause

Arrow keys were never broken. `board_view_p2` was hiding player 0.

`board_view.gd::_draw()` began with `_draw_background()` / `_draw_checkerboard()` / `_draw_grid()`
-- the first is a fully opaque full-board `draw_rect`, the next two paint over it -- plus
`_draw_food()`. `game_screen.gd` adds `board_view_p2` *after* `board_view`, so the player-1 instance
repainted that whole opaque stack on top of player 0's snake every frame. Only player 1's snake was
ever on screen. Arrows steered player 0 (invisible); WASD steered player 1 (the visible one). Hence
"arrows do nothing, WASD works".

Reproduced by running the real app (`./tools/run.py godot --path game`) and driving it with real
OS-level key events (AppleScript `System Events` key codes -- the same path a human keypress takes,
not `Input.parse_input_event()` injection). The temporary debug prints showed every arrow press
reaching `_unhandled_input`, dispatching to player 0, and `world.queue_dir` committing a full
Up/Left/Down/Right square. After the fix, a screenshot of a live session shows both snakes, with
player 0's responding to arrows.

## Why the original A/B test was misleading

`_apply_settings()` runs `KeybindCodec.apply_to_input_map(settings.keybinds)` at startup, which
`action_erase_events()` then rebuilds every action from `user://save.json`. The real save file
already pinned `move_*` to arrows only, so adding WASD to `project.godot`'s `move_*` never reached
the live InputMap at all. The live log confirms it: pressing W emitted `player=1`, not player 0. So
the "identical code path, different result" observation was really "two different players' snakes,
one of them invisible".

Worth knowing going forward: changing a default binding in `project.godot`/`input_defaults.gd` has
no effect on any machine that already has a `save.json`. Not changed here -- out of scope.

## Fix

`BoardView.draws_shared_board` (default `true`) gates background/checkerboard/grid/food.
`game_screen.gd` sets it `false` on `board_view_p2`, so only the bottom-most view paints the shared
board. Snake/eyes/particles/flash/pause-vignette stay per-view (per-player state or translucent).
`BoardGeometry.DRAW_LAYER_ORDER` is untouched -- the bottom view still draws the full oracle
sequence, so there is no new divergence from `reference/snake.html` (which is single-player and has
no stacked views). `decision-035`'s "harmlessly redundantly redrawn" claim is corrected in place.

Diagnostic artifacts removed: debug prints in `input_router.gd` and `game_screen.gd`,
`_debug_poll_input_file()` and its `_process()` call, and the WASD-on-player-0 bindings in
`input_defaults.gd` + `project.godot`.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Player 0 was steerable by the arrow keys the whole time -- it was invisible. `board_view_p2`,
stacked on top of `board_view` for local 2-player, repainted the opaque shared board layers
(background/checkerboard/grid, plus food) over player 0's snake every frame, so the only snake on
screen was player 1's, which answers to WASD.

`BoardView` gains `draws_shared_board` (default `true`, set `false` on `board_view_p2`) gating those
four layers; all other layers stay per-view. `DRAW_LAYER_ORDER` is unchanged and the bottom view
still draws the full oracle sequence, so no new divergence from `reference/snake.html`.

Regression test in `game/tests/test_game_screen.gd`; `docs/build-layout.md` and `decision-035`
updated. All diagnostic instrumentation and the temporary WASD-on-player-0 bindings reverted.
`task check` green (129/129 game tests).
<!-- SECTION:FINAL_SUMMARY:END -->

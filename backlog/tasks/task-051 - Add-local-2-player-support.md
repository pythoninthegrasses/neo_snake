---
id: TASK-051
title: Add local 2-player support
status: Done
assignee: []
created_date: '2026-09-09 22:16'
labels: []
milestone: m-8
dependencies:
  - TASK-050
priority: low
type: feature
ordinal: 51000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add local 2-player support to the Godot presentation and input layers. This should be nearly free — the C ABI carried a player index and player_count from day one specifically so this milestone would not require an ABI change. This task must NOT modify include/neo_snake.h: if it turns out to require a change there, the multiplayer-shaped-ABI freeze from m2/m5 failed, and that failure is exactly what this acceptance criterion exists to catch.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 This task does not modify include/neo_snake.h — verified by git diff on the PR containing this work
- [x] #2 Two locally-controlled players can play simultaneously on one board with independent input routing
- [x] #3 Per-player score/status HUD elements both update correctly using ns_player_view_get
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 task check is green
- [x] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [x] #3 Docs touched by the change are updated in the same commit
- [x] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

## Notes

<!-- SECTION:NOTES:BEGIN -->
The core-layer 2-player semantics (`core/world.zig`/`core/abi.zig`) were already settled by
[[decision-034]] in a prior session on this branch: shared world-level `status`, per-player `alive`
flag, `playerStatus(w,i)` projection, two-phase collision with head-to-head mutual kill, corpses
never cleared, world only reaches `.dead` once every player is eliminated.

This session's scope was the remaining Godot presentation/input layers, all judgment calls recorded
in [[decision-035]]: `GameScreen` always initializes `player_count = 2` (no togglable 1p/2p mode —
YAGNI, nothing in this task's AC asks for a mode toggle); player 0 keeps arrow keys only and player 1
gets a new WASD-only action set (`game/platform/input_defaults.gd`'s `ACTION_P2_MOVE_*`,
`game/project.godot`'s `p2_move_*` bindings) so a single keypress can't drive both players; touch
swipe and joypad analog stick stay routed to player 0 only (no natural per-player mapping exists for
either on one shared keyboard/no second controller); `GameScreen._shared_status()` reconstructs the
true shared world phase from only `ns_player_view_get` calls (no new ABI/header symbol, satisfying
AC#1) by reading player 0's status and falling back to player 1's only when player 0 reads DEAD;
best-score persistence stays player-0/mode-scoped only (per-player bests are out of scope);
`board_view.gd` needed zero changes since it was already generic over `player` — 2-player rendering
is a second `BoardView` instance (`board_view_p2`) sharing the same `SimulationWorld`; per-player
death/eat fx cues route via the event dict's existing `"player"` field so player 1's death flash
doesn't fire on player 0's board and vice versa.

AC#1 verified via `git diff --stat main -- include/neo_snake.h` producing zero output. AC#2/#3
covered by four new tests in `game/tests/test_game_screen.gd`
(`test_game_screen_wires_a_second_board_view_for_player_1`,
`test_player_1_direction_input_steers_player_1_without_touching_player_0`,
`test_player_0_direction_input_still_defaults_to_player_0`,
`test_hud_reflects_both_players_score_and_status_after_start`). Full `task check` is green: 123 test
cases / 0 errors / 0 failures / 0 flaky / 0 skipped across 20 suites, plus audio/music checks.
`docs/architecture.md` was checked (grep for `direction_queued`/`player_count`/`PLAYER_ACTIONS`) and
needs no update — it documents `reference/snake.html`'s architecture, which this Godot-layer-only
task doesn't touch.
<!-- SECTION:NOTES:END -->

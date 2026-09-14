---
id: decision-035
title: Godot-layer local 2-player -- keyboard split, ABI-free shared-status derivation, player-0-scoped best score
date: '2026-09-13 22:13'
status: Accepted
---
## Context

`decision-034` settled `core/world.zig`/`core/abi.zig`'s 2-player semantics. TASK-051's remaining
scope is the Godot presentation/input layers, and its AC#1 is a hard constraint: this task must not
modify `include/neo_snake.h`. Three judgment calls came up wiring `game/` up to the now-real
2-player ABI, none of them dictated by the task text or by `decision-034`.

## Decision

**GameScreen always initializes `player_count = 2`**, not a togglable 1p/2p mode. Extending the
existing menu's mode selector (`game/content/modes.json`) to also pick a player count would require
cross-validating against `tuning.json`'s `scoring.best_score_defaults` (`game/content/loader.gd`'s
`MODES_SCHEMA`) for no benefit this task's AC actually asks for -- YAGNI.

**Keyboard scheme split: player 0 keeps arrow keys only, player 1 gets WASD only**
(`game/platform/input_defaults.gd`'s new `ACTION_P2_MOVE_*` actions, `game/project.godot`'s
`p2_move_*` bindings). Player 0's `move_up`/`move_down`/`move_left`/`move_right` action *names* are
unchanged (save-data/keybind-codec compatibility), but their physical keycodes drop WASD -- keeping
WASD on both player 0's and player 1's actions would fire both players' movement from one keypress,
a real bug, not a style preference. Touch swipe and joypad analog stick stay routed to player 0 only
(`input_router.gd`'s `_handle_drag`/`_handle_joypad_motion` hardcode player 0) -- no natural
per-player mapping exists for either input kind on one shared keyboard/no second controller, so this
is a deliberate scope decision, not an oversight.

**`GameScreen._shared_status()` reconstructs the true shared world status from only per-player ABI
calls**, since AC#1 forbids adding any new header/ABI function to expose the shared status directly:

    func _shared_status() -> int:
        var v0: int = world.player_view_get(0).status
        if v0 != BoardGeometry.STATUS_DEAD:
            return v0
        return world.player_view_get(1).status

Correct because `core/abi.zig`'s `playerStatus` projects `w.status` onto a still-alive player
unchanged, and (per `decision-034`) the shared world only becomes `.dead` once every player is
simultaneously eliminated. So checking player 0 first and falling back to player 1 only when player
0's own projection already reads DEAD always yields the true shared phase, for every alive/dead
combination. Used for both shared decisions (pause/restart/overlay gating, the overlay's own
screen) and, separately, each player's own raw `player_view_get(i).status` still drives that
player's own HUD status label (`hud.update`/`hud.update_p2`) -- a dead player's board and status
text keep reading "dead" even while the match continues for a survivor, matching `decision-034`'s
per-player `alive` semantics.

**Best-score persistence stays player-0/mode-scoped only.** Player 1's score renders live in the HUD
(`Hud.update_p2`) but is never compared against or written to `_save_data.best_scores` -- the
existing best-score architecture is inherently single-value-per-mode, and extending it to per-player
bests is out of this task's scope.

**`BoardView` needed zero code changes.** It was already generic over `player`
(`setup(world, tuning, palette, p_player: int = 0)`, every draw call already parameterized). 2-player
rendering is a second `BoardView` instance (`board_view_p2`) at the same position/size, sharing the
same `SimulationWorld`, independently redrawing player 1's snake on top of the (harmlessly
redundantly redrawn) shared board/food/grid.

**Per-player death/eat fx cues route via the event dict's existing `"player"` field**
(`core/abi.zig`'s `pushEvent` already tags every event with its player index) -- `GameScreen._process`
picks `board_view` or `board_view_p2` per drained event before calling `.notify_eat()`/
`.fx.trigger_flash()`, so player 1's death flash doesn't fire on player 0's board and vice versa.
Coalesced sfx cues (`AudioEventCoalescer`) stay global/shared, matching a same-screen match sharing
one speaker.

## Consequences

`game/platform/input_defaults.gd`, `game/project.godot`, `game/platform/input_router.gd`,
`game/presentation/screens/hud.gd`, and `game/presentation/screens/game_screen.gd` all changed.
`board_view.gd` did not. Every existing single-player-shaped test in `game/tests/test_game_screen.gd`
passes unchanged, since `_on_direction_queued(dir, player: int = 0)` keeps the old single-arg call
shape and player 0's individually-observable behavior for those call sequences is unaffected.
`game/tests/test_input_defaults.gd` auto-covers the new P2 actions since it iterates
`InputDefaults.ACTION_PHYSICAL_KEYCODES` generically. No new ABI/header symbol was added anywhere in
this diff, satisfying AC#1.

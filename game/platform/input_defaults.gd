class_name InputDefaults
extends RefCounted

## Canonical action names this repo's project.godot [input] section must
## declare (TASK-033 AC#1) and the table input_router.gd dispatches on.
## Mirrors reference/snake.html's KEY table (snake.html:578-582): both
## arrow keys and WASD map to the same four directions, Space
## pauses/starts, R restarts (snake.html:584-591). This port splits the two
## jobs the oracle's Space key does: Space is pause-only, and Enter/Kp Enter
## select -- project.godot overrides Godot's built-in ui_accept (Enter, Kp
## Enter *and* Space by default) to drop Space, so it can never also
## activate a focused overlay button. Kept as data here (not
## just implicit in project.godot) so a gdUnit4 test can assert the
## project's actual InputMap state stays in sync with what this file
## expects, the same role board_geometry.gd's DRAW_LAYER_ORDER plays for
## _draw()'s statement order (TASK-032).

const ACTION_MOVE_UP := "move_up"
const ACTION_MOVE_DOWN := "move_down"
const ACTION_MOVE_LEFT := "move_left"
const ACTION_MOVE_RIGHT := "move_right"
const ACTION_PAUSE := "pause"
const ACTION_RESTART := "restart"

## TASK-051: player 1's own action set. Bound to WASD only -- player 0
## keeps the arrow keys exclusively (see ACTION_PHYSICAL_KEYCODES below).
## Splitting the keys is not stylistic: if both players' actions stayed
## bound to the same physical WASD keys, one keypress would move both
## snakes at once.
const ACTION_P2_MOVE_UP := "p2_move_up"
const ACTION_P2_MOVE_DOWN := "p2_move_down"
const ACTION_P2_MOVE_LEFT := "p2_move_left"
const ACTION_P2_MOVE_RIGHT := "p2_move_right"

## action name -> the physical keycodes project.godot must bind it to.
const ACTION_PHYSICAL_KEYCODES := {
	ACTION_MOVE_UP: [KEY_UP],
	ACTION_MOVE_DOWN: [KEY_DOWN],
	ACTION_MOVE_LEFT: [KEY_LEFT],
	ACTION_MOVE_RIGHT: [KEY_RIGHT],
	ACTION_PAUSE: [KEY_SPACE],
	ACTION_RESTART: [KEY_R],
	ACTION_P2_MOVE_UP: [KEY_W],
	ACTION_P2_MOVE_DOWN: [KEY_S],
	ACTION_P2_MOVE_LEFT: [KEY_A],
	ACTION_P2_MOVE_RIGHT: [KEY_D],
}

## action name -> SimulationWorld.DIR_* -- the four movement actions only,
## since pause/restart are not directions (input_router.gd branches on
## those separately).
const ACTION_TO_DIR := {
	ACTION_MOVE_UP: SimulationWorld.DIR_UP,
	ACTION_MOVE_DOWN: SimulationWorld.DIR_DOWN,
	ACTION_MOVE_LEFT: SimulationWorld.DIR_LEFT,
	ACTION_MOVE_RIGHT: SimulationWorld.DIR_RIGHT,
}

## per-player action-to-dir table, indexed by player number (TASK-051).
## input_router.gd iterates this to dispatch keyboard input to the right
## player; touch/joypad stay routed to player 0 only (no natural per-player
## mapping exists for those input kinds on one shared keyboard/no second
## controller).
const ACTION_P2_TO_DIR := {
	ACTION_P2_MOVE_UP: SimulationWorld.DIR_UP,
	ACTION_P2_MOVE_DOWN: SimulationWorld.DIR_DOWN,
	ACTION_P2_MOVE_LEFT: SimulationWorld.DIR_LEFT,
	ACTION_P2_MOVE_RIGHT: SimulationWorld.DIR_RIGHT,
}

const PLAYER_ACTIONS := [ACTION_TO_DIR, ACTION_P2_TO_DIR]

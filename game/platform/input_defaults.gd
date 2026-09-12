class_name InputDefaults
extends RefCounted

## Canonical action names this repo's project.godot [input] section must
## declare (TASK-033 AC#1) and the table input_router.gd dispatches on.
## Mirrors reference/snake.html's KEY table (snake.html:578-582): both
## arrow keys and WASD map to the same four directions, Space
## pauses/starts, R restarts (snake.html:584-591). Kept as data here (not
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

## action name -> the physical keycodes project.godot must bind it to.
const ACTION_PHYSICAL_KEYCODES := {
	ACTION_MOVE_UP: [KEY_UP, KEY_W],
	ACTION_MOVE_DOWN: [KEY_DOWN, KEY_S],
	ACTION_MOVE_LEFT: [KEY_LEFT, KEY_A],
	ACTION_MOVE_RIGHT: [KEY_RIGHT, KEY_D],
	ACTION_PAUSE: [KEY_SPACE],
	ACTION_RESTART: [KEY_R],
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

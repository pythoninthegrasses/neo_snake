class_name InputRouter
extends Node

## Translates raw platform input -- keyboard (via the InputMap actions
## project.godot declares, TASK-033 AC#1), touch swipe, and analog stick --
## into direction/pause/restart intents. Mirrors reference/snake.html's
## single-choke-point queueDir (snake.html:569-576, docs/architecture.md's
## "Input" section): one place converts raw input into an intent, rather
## than branching at each call site.
##
## Uses _unhandled_input, not _input (AC#2), so a focused UI control (e.g.
## a future settings/menu screen) gets first refusal of the event.
##
## Emits signals instead of calling SimulationWorld directly: the "no
## instant 180" reversal-legality check already lives in core/world.zig's
## queue_dir, so this stays a pure translation layer with no game-state
## knowledge of its own -- no live scene wires it up yet, matching every
## other platform/presentation script landed so far
## (game/simulation/tick_driver.gd, game/presentation/board/board_view.gd).

signal direction_queued(dir: int)
signal pause_requested
signal restart_requested

## Set by whoever owns board sizing (mirrors board_view.gd's own `cell`
## unit) so swipe_gesture.gd's threshold scales with the actual on-screen
## board instead of a compile-time guess.
var cell_px := 0.0
var swipe_threshold_cell_fraction := 0.5

var _swipe := SwipeGesture.new()
var _stick_x := AnalogLatch.new()
var _stick_y := AnalogLatch.new()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(InputDefaults.ACTION_PAUSE):
		pause_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(InputDefaults.ACTION_RESTART):
		restart_requested.emit()
		get_viewport().set_input_as_handled()
		return
	for action: String in InputDefaults.ACTION_TO_DIR:
		if event.is_action_pressed(action):
			direction_queued.emit(InputDefaults.ACTION_TO_DIR[action])
			get_viewport().set_input_as_handled()
			return
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)
	elif event is InputEventJoypadMotion:
		_handle_joypad_motion(event)

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_swipe.start(event.position)
	else:
		_swipe.end()

func _handle_drag(event: InputEventScreenDrag) -> void:
	var dir := _swipe.update(event.position, cell_px, swipe_threshold_cell_fraction)
	if dir != -1:
		direction_queued.emit(dir)
		get_viewport().set_input_as_handled()

## Left stick only (JOY_AXIS_LEFT_X/_Y) -- Y+ is down, matching the
## oracle's own dy > 0 => "down" convention in its swipe handling
## (snake.html:616).
func _handle_joypad_motion(event: InputEventJoypadMotion) -> void:
	var dir := -1
	if event.axis == JOY_AXIS_LEFT_X:
		dir = _stick_x.feed(event.axis_value, SimulationWorld.DIR_RIGHT, SimulationWorld.DIR_LEFT)
	elif event.axis == JOY_AXIS_LEFT_Y:
		dir = _stick_y.feed(event.axis_value, SimulationWorld.DIR_DOWN, SimulationWorld.DIR_UP)
	if dir != -1:
		direction_queued.emit(dir)
		get_viewport().set_input_as_handled()

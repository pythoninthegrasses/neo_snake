class_name GameScreen
extends Control

## Top-level orchestrator (TASK-036): instantiates SimulationWorld and every
## previously-standalone piece (TickDriver, BoardView, InputRouter,
## AppLifecycle, SaveStore, ContentLoader) and wires them into the actual
## running game reference/snake.html's own frame()/queueDir()/togglePause()
## bootstrap tail (snake.html:620-628) assembles by hand. No new game-rule
## logic lives here -- it calls SimulationWorld/TickDriver/GameScreenState
## and applies their results to real Control nodes.
##
## Board size mirrors the oracle's fixed COLS/ROWS = 24 (no shared constant
## exists in game/ yet -- game/tests/test_tick_driver.gd and
## test_corpus_replay.gd both pass the literal 24, 24, so this follows the
## same convention rather than introducing a new one).
##
## Pause: reference/snake.html's togglePause() actually flips S.status to
## "paused" (snake.html:559-566). The live GDExtension ABI never reaches
## NS_STATUS_PAUSED -- no export function ever calls core/world.zig's
## togglePause() -- so pause instead lives entirely at this layer, as an
## independent _paused flag gating TickDriver's gate parameter (the sim's
## own status never leaves .playing while paused). See
## backlog/decisions/ for the full writeup, including the resulting
## board_view.gd PAUSED-status branch that stays permanently unreachable.
##
## Win vs. Game Over: distinguished via the already-built NS_EVENT_WIN /
## NS_EVENT_DIE event kinds core/abi.zig's stepOneTick() synthesizes (it
## diffs pre/post score and status around each tick), drained here via
## SimulationWorld.event_drain() -- not a derived full-board check.

const COLS := 24
const ROWS := 24

## Set before add_child() to redirect SaveStore off real user:// data --
## mirrors test_save_store.gd's own temp-base-dir isolation convention, the
## only seam GameScreen needs since ContentLoader's tuning/palette/modes
## JSON are checked-in fixtures, safe to read for real in a test.
var save_dir_override := ""

var world: SimulationWorld
var board_view: BoardView
var hud: Hud
var overlay: OverlayPanel
var input_router: InputRouter
var app_lifecycle: AppLifecycle
var save_store: SaveStore

var _tuning: Dictionary
var _palette: Dictionary
var _modes: Array
var _current_mode_id := ""
var _paused := false
var _is_win := false
var _save_data: Dictionary

func _ready() -> void:
	var content := ContentLoader.load_all()
	if not content.ok:
		push_error(content.error)
		return
	_tuning = content.tuning
	_palette = content.palette
	_modes = content.modes.modes

	save_store = SaveStore.new(save_dir_override) if save_dir_override != "" else SaveStore.new()
	_save_data = save_store.load_or_default()
	if OS.has_feature("web"):
		var imported: Variant = save_store.import_web_legacy_best()
		if imported != null:
			_save_data = imported
	_current_mode_id = _save_data.last_mode if _has_mode(_save_data.last_mode) else content.modes.default_mode

	world = SimulationWorld.new()
	world.init(COLS, ROWS, 1, _wrap_for(_current_mode_id), SeedSource.fresh(), SimulationWorld.SPEED_SOURCE_SCORE_TABLE)

	board_view = BoardView.new()
	board_view.custom_minimum_size = Vector2(520, 520)
	board_view.size = Vector2(520, 520)
	board_view.setup(world, _tuning, _palette)
	add_child(board_view)

	hud = Hud.new()
	add_child(hud)

	overlay = OverlayPanel.new()
	add_child(overlay)
	overlay.set_modes(_modes, _current_mode_id)
	overlay.action_pressed.connect(_on_overlay_action_pressed)
	overlay.mode_selected.connect(_on_mode_selected)

	input_router = InputRouter.new()
	input_router.direction_queued.connect(_on_direction_queued)
	input_router.pause_requested.connect(_on_pause_requested)
	input_router.restart_requested.connect(_on_restart_requested)
	add_child(input_router)

	app_lifecycle = AppLifecycle.new()
	app_lifecycle.focus_lost.connect(_on_focus_lost)
	add_child(app_lifecycle)

	_refresh_screen()

func _process(delta: float) -> void:
	var pre_food_x := BoardGeometry.NO_CELL_COORD
	var pre_food_y := BoardGeometry.NO_CELL_COORD
	var pre := world.serialize()
	if pre.result == SimulationWorld.OK:
		var header := BoardGeometry.decode_canon_header(pre.bytes)
		pre_food_x = header.food_x
		pre_food_y = header.food_y

	TickDriver.advance_frame(world, delta * 1000.0, true, not _paused)

	var drain := world.event_drain(16)
	if drain.result == SimulationWorld.OK:
		for event in drain.events:
			match event.kind:
				SimulationWorld.EVENT_EAT:
					if pre_food_x != BoardGeometry.NO_CELL_COORD:
						board_view.notify_eat(pre_food_x, pre_food_y)
				SimulationWorld.EVENT_DIE:
					_is_win = false
					board_view.fx.flash = 1.0
				SimulationWorld.EVENT_WIN:
					_is_win = true

	_refresh_screen()

func _refresh_screen() -> void:
	var view := world.player_view_get(0)
	if view.result != SimulationWorld.OK:
		return
	var screen := GameScreenState.screen_for(view.status, _paused)
	var best: int = _save_data.best_scores.get(_current_mode_id, 0)
	if view.score > best:
		best = view.score
		_save_data.best_scores[_current_mode_id] = best
		_save_data.last_mode = _current_mode_id
		save_store.save(_save_data)

	hud.update(view.score, best, screen.capitalize())

	if screen == GameScreenState.SCREEN_PLAYING:
		overlay.configure({})
		return
	var body := world.body_copy(0)
	var snake_len: int = body.cells.size() if body.result == SimulationWorld.OK else 0
	overlay.configure(GameScreenState.overlay_content(screen, view.score, best, snake_len, _is_win))

func _has_mode(mode_id: String) -> bool:
	for mode in _modes:
		if mode.id == mode_id:
			return true
	return false

func _wrap_for(mode_id: String) -> bool:
	for mode in _modes:
		if mode.id == mode_id:
			return bool(mode.wrap)
	return false

## Space (pause_requested): starts from menu/dead, exactly like queueDir()
## does for any direction (snake.html:576); toggles the app-level pause
## flag otherwise, mirroring togglePause() (snake.html:559-566) without
## ever touching the sim's own (unreachable) paused status.
func _on_pause_requested() -> void:
	var view := world.player_view_get(0)
	if view.result != SimulationWorld.OK:
		return
	if view.status == BoardGeometry.STATUS_MENU or view.status == BoardGeometry.STATUS_DEAD:
		_start_or_restart()
	else:
		_paused = not _paused
		_refresh_screen()

## R (restart_requested): reference/snake.html's R handler always calls
## start() unconditionally (snake.html:584). Since this port's mode
## selector is menu-only (see the class doc), a live world's wrap can never
## have changed once playing/dead, so a plain world.reset() here is
## behaviorally identical to a full re-init for every reachable case.
func _on_restart_requested() -> void:
	var view := world.player_view_get(0)
	if view.result != SimulationWorld.OK:
		return
	if view.status == BoardGeometry.STATUS_MENU or view.status == BoardGeometry.STATUS_DEAD:
		_start_or_restart()
	else:
		world.reset()
		_paused = false
		_refresh_screen()

## The overlay's single action button: "Start" (menu), "Resume" (paused),
## or "Play again" (dead) -- mirrors el.start's click handler, which
## dispatches on status the same way (snake.html:588-590).
func _on_overlay_action_pressed() -> void:
	var view := world.player_view_get(0)
	if view.result != SimulationWorld.OK:
		return
	if view.status == BoardGeometry.STATUS_PLAYING and _paused:
		_paused = false
		_refresh_screen()
	else:
		_start_or_restart()

func _start_or_restart() -> void:
	var view := world.player_view_get(0)
	if view.result == SimulationWorld.OK and view.status == BoardGeometry.STATUS_MENU:
		world.init(COLS, ROWS, 1, _wrap_for(_current_mode_id), SeedSource.fresh(), SimulationWorld.SPEED_SOURCE_SCORE_TABLE)
	world.queue_dir(0, SimulationWorld.DIR_RIGHT)
	_paused = false
	_is_win = false
	_refresh_screen()

## Mirrors queueDir()'s own auto-start branch (snake.html:576): any
## direction input from menu/dead starts/restarts the run. Faithfully
## reproduces the oracle's own quirk where that direction is then
## discarded rather than applied -- start() calls reset(), which
## unconditionally sets S.dir = S.nextDir = right (snake.html:312) AFTER
## queueDir() already set nextDir to the pressed key, clobbering it. So the
## keypress that starts a run never steers it; only the run itself.
func _on_direction_queued(dir: int) -> void:
	var view := world.player_view_get(0)
	if view.result == SimulationWorld.OK and (view.status == BoardGeometry.STATUS_MENU or view.status == BoardGeometry.STATUS_DEAD):
		_start_or_restart()
		return
	world.queue_dir(0, dir)

func _on_mode_selected(mode_id: String) -> void:
	_current_mode_id = mode_id

## Mirrors reference/snake.html's blur auto-pause (snake.html:620), which
## only fires while actually playing.
func _on_focus_lost() -> void:
	var view := world.player_view_get(0)
	if view.result == SimulationWorld.OK and view.status == BoardGeometry.STATUS_PLAYING and not _paused:
		_paused = true
		_refresh_screen()

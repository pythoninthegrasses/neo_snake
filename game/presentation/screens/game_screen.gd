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
##
## Audio (TASK-039): sfx is a single SfxPlayer child, the only thing here
## that knows chiptune cues exist -- core/*.zig carries no audio symbol.
## See docs/build-layout.md's TASK-039 section for the full cue-to-event
## wiring map.
##
## Music (TASK-040): music is a single MusicPlayer child, started once here
## and looping continuously on the "Music" bus -- reference/snake.html has
## no music, so there's no oracle-driven start/stop cue point to match.

const COLS := 24
const ROWS := 24

## core/world.zig's reset() spawns a 3-cell snake.
const SNAKE_LEN := 3

const EVENT_DRAIN_CAPACITY := 16

## Set before add_child() to redirect SaveStore off real user:// data --
## mirrors test_save_store.gd's own temp-base-dir isolation convention, the
## only seam GameScreen needs since ContentLoader's tuning/palette/modes
## JSON are checked-in fixtures, safe to read for real in a test.
var save_dir_override := ""

var world: SimulationWorld
var board_view: BoardView
var board_view_p2: BoardView
var hud: Hud
var overlay: OverlayPanel
var settings_panel: SettingsPanel
var input_router: InputRouter
var app_lifecycle: AppLifecycle
var web_checksum_smoke_test: WebChecksumSmokeTest
var save_store: SaveStore
var sfx: SfxPlayer
var music: MusicPlayer

## Chosen on the menu screen, then fixed for the run (the overlay's
## 1/2-player buttons only exist on the menu). The menu itself idles on a
## 1-player world; picking "2 Player Game" re-inits with player_count 2.
## Every per-player surface -- board_view_p2, the HUD's P2 row, player 1's
## keyboard input -- is gated on this, because the ABI rejects any call
## naming a player the world doesn't have (core/abi.zig's
## `player >= storage.player_count` guard).
var _player_count := 1

## Cleared only by the TASK-037 parity capture harness: its whole job is
## producing screenshots comparable against reference/snake.html's own, and
## the oracle always spawns facing right.
var _randomize_start := true

var _tuning: Dictionary
var _palette: Dictionary
var _modes: Array
var _current_mode_id := ""
var _paused := false
var _is_win := false
var _save_data: Dictionary
var _settings_open := false

func _ready() -> void:
	## project.godot's viewport_width/height (520x545) is only the design
	## canvas that canvas_items/keep stretch scales up to fill the window --
	## it's also the actual initial OS window size unless overridden here,
	## since window_width_override/height_override (the project-settings
	## knob for this) only affects the editor's own Play-button preview, not
	## a direct `godot main.tscn` run or an exported build. Open larger by
	## default and cap growth at the largest size that still fits under
	## 1080p at the board's own aspect ratio, so a maximized window on a
	## QHD/4K display doesn't blow the board up past a sane on-screen size.
	## Window.size is in physical pixels, not the OS window manager's points
	## -- on a Retina/hiDPI display (screen_get_scale() > 1) an unscaled
	## Vector2i(780, 817.5) here nets a window that visually measures half
	## that on screen, so the target size must be scaled up to compensate.
	var screen := DisplayServer.window_get_current_screen()
	var display_scale := DisplayServer.screen_get_scale(screen)
	get_window().size = Vector2i(Vector2(780, 817.5) * display_scale)
	get_window().max_size = Vector2i(Vector2(936, 981) * display_scale)

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
	world.init(COLS, ROWS, _player_count, _wrap_for(_current_mode_id), SeedSource.fresh(), SimulationWorld.SPEED_SOURCE_SCORE_TABLE)

	## board_view only paints the board's own COLS*cell x ROWS*cell rect
	## (0,0 to 520,520); without this, the HUD strip below it (520-600) had
	## nothing drawn behind it and showed the Viewport's default grey clear
	## color instead of the theme's own background.
	var background := ColorRect.new()
	background.color = Color(_palette.board.background)
	background.size = size
	background.position = Vector2.ZERO
	add_child(background)

	board_view = BoardView.new()
	board_view.custom_minimum_size = Vector2(520, 520)
	board_view.size = Vector2(520, 520)
	board_view.position = Vector2(0, 0)
	board_view.setup(world, _tuning, _palette, 0)
	add_child(board_view)

	## TASK-051: board_view.gd is already generic over `player` -- a second
	## instance, sharing the same world/board geometry, renders player 1's
	## snake on top of the same shared board/food/grid. Hidden entirely for
	## a 1-player game (see _apply_player_count).
	board_view_p2 = BoardView.new()
	board_view_p2.custom_minimum_size = Vector2(520, 520)
	board_view_p2.size = Vector2(520, 520)
	board_view_p2.position = Vector2(0, 0)
	board_view_p2.setup(world, _tuning, _palette, 1)
	board_view_p2.draws_shared_board = false
	add_child(board_view_p2)
	_apply_settings(_save_data.settings)

	hud = Hud.new()
	hud.position = Vector2(0, board_view.size.y)
	add_child(hud)

	overlay = OverlayPanel.new()
	overlay.position = board_view.position
	overlay.size = board_view.size
	add_child(overlay)
	overlay.set_modes(_modes, _current_mode_id)
	overlay.action_pressed.connect(_on_overlay_action_pressed)
	overlay.player_count_selected.connect(_on_player_count_selected)
	overlay.return_to_title_requested.connect(_on_return_to_title_requested)
	overlay.mode_selected.connect(_on_mode_selected)
	overlay.settings_requested.connect(_on_settings_requested)
	overlay.set_quit_available(not OS.has_feature("web"))
	overlay.quit_requested.connect(_quit_game)

	settings_panel = SettingsPanel.new()
	settings_panel.position = board_view.position
	settings_panel.size = board_view.size
	settings_panel.visible = false
	add_child(settings_panel)
	settings_panel.set_settings(_save_data.settings)
	settings_panel.volume_changed.connect(_on_volume_changed)
	settings_panel.reduce_flash_changed.connect(_on_reduce_flash_changed)
	settings_panel.keybind_changed.connect(_on_keybind_changed)
	settings_panel.closed.connect(_on_settings_closed)

	input_router = InputRouter.new()
	input_router.direction_queued.connect(func(player: int, dir: int) -> void: _on_direction_queued(dir, player))
	input_router.pause_requested.connect(_on_pause_requested)
	input_router.restart_requested.connect(_on_restart_requested)
	add_child(input_router)

	app_lifecycle = AppLifecycle.new()
	app_lifecycle.focus_lost.connect(_on_focus_lost)
	add_child(app_lifecycle)

	web_checksum_smoke_test = WebChecksumSmokeTest.new()
	add_child(web_checksum_smoke_test)

	sfx = SfxPlayer.new()
	add_child(sfx)

	music = MusicPlayer.new()
	add_child(music)
	music.play()

	_apply_player_count()
	_refresh_screen()
	_maybe_drive_capture_state()

## TASK-037 capture tooling only: real OS-level key injection via wtype does
## not reach Godot's action map under headless sway (see
## backlog/decisions/ for the writeup), so the parity capture harness drives
## GameScreen straight through its own already-tested handlers instead of
## simulating input events. Guarded behind an explicit --capture-state= CLI
## arg that normal play never passes -- inert for every real player.
func _maybe_drive_capture_state() -> void:
	var state := _capture_state_arg()
	if state == "" or state == "menu":
		return
	_randomize_start = false
	set_process(false)
	_on_direction_queued(SimulationWorld.DIR_UP)
	if state == "playing":
		return
	if state == "paused":
		_on_pause_requested()
		return
	if state == "dead":
		var guard := 0
		while _shared_status() != BoardGeometry.STATUS_DEAD and guard < 100000:
			_process(0.05)
			guard += 1

func _capture_state_arg() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-state="):
			return arg.substr("--capture-state=".length())
	return ""

## NOTIFICATION_WM_CLOSE_REQUEST fires for both a window close and a
## terminal SIGINT, so routing it through _quit_game() covers both.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit_game()

## A still-looping AudioStreamOggVorbis at process exit leaks its playback
## objects (AudioStreamPlaybackOggVorbis/OggPacketSequencePlayback) --
## Godot only releases them cleanly once AudioStreamPlayer.stop() has run,
## not merely on the node being freed. Shared by the window-close path
## above and the title screen's own Quit button.
func _quit_game() -> void:
	if music != null:
		music.stop()
	get_tree().quit()

func _process(delta: float) -> void:
	var pre_food_x := BoardGeometry.NO_CELL_COORD
	var pre_food_y := BoardGeometry.NO_CELL_COORD
	var pre := world.serialize()
	if pre.result == SimulationWorld.OK:
		var header := BoardGeometry.decode_canon_header(pre.bytes)
		pre_food_x = header.food_x
		pre_food_y = header.food_y

	TickDriver.advance_frame(world, delta * 1000.0, true, not _paused)

	var drain := world.event_drain(EVENT_DRAIN_CAPACITY)
	if drain.result == SimulationWorld.OK:
		for event in drain.events:
			var event_board_view: BoardView = board_view if event.player == 0 else board_view_p2
			match event.kind:
				SimulationWorld.EVENT_EAT:
					if pre_food_x != BoardGeometry.NO_CELL_COORD:
						event_board_view.notify_eat(pre_food_x, pre_food_y)
				SimulationWorld.EVENT_DIE:
					_is_win = false
					event_board_view.fx.trigger_flash()
				SimulationWorld.EVENT_WIN:
					_is_win = true
		# Catch-up coalescing is presentation policy, not simulation policy
		# (TASK-041 AC#2): a hitch can drive several ticks in this one call,
		# and each eating tick pushed its own EVENT_EAT, so decide cues once
		# per frame here instead of once per drained event.
		var cues := AudioEventCoalescer.cues_for(drain.events)
		if cues["eat"]:
			sfx.play("eat")
		if cues["die"]:
			sfx.play("die")
		if cues["win"]:
			sfx.play("win")

	_refresh_screen()

## Recovers the true shared world status from only per-player ABI calls (no
## new header/ABI function is permitted -- TASK-051 AC#1). A player's own
## projected status is DEAD whenever it is not alive (core/abi.zig's
## playerStatus); the shared world only ever becomes DEAD once every player
## is simultaneously eliminated (backlog/decisions/decision-034). So player
## 0's own status already IS the shared status unless player 0 individually
## died first, in which case player 1's status settles it.
func _shared_status() -> int:
	var v0: int = world.player_view_get(0).status
	if _player_count < 2 or v0 != BoardGeometry.STATUS_DEAD:
		return v0
	return world.player_view_get(1).status

func _refresh_screen() -> void:
	var view0 := world.player_view_get(0)
	if view0.result != SimulationWorld.OK:
		return
	var screen := GameScreenState.screen_for(_shared_status(), _paused)
	var best: int = _save_data.best_scores.get(_current_mode_id, 0)
	if view0.score > best:
		best = view0.score
		_save_data.best_scores[_current_mode_id] = best
		_save_data.last_mode = _current_mode_id
		save_store.save(_save_data)

	hud.update(view0.score, best, GameScreenState.screen_for(view0.status, _paused).capitalize())
	if _player_count >= 2:
		var view1 := world.player_view_get(1)
		if view1.result == SimulationWorld.OK:
			hud.update_p2(view1.score, GameScreenState.screen_for(view1.status, _paused).capitalize())

	if _settings_open:
		return
	if screen == GameScreenState.SCREEN_PLAYING:
		overlay.configure({})
		return
	var body := world.body_copy(0)
	var snake_len: int = body.cells.size() if body.result == SimulationWorld.OK else 0
	overlay.configure(GameScreenState.overlay_content(screen, view0.score, best, snake_len, _is_win))

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

## Space (pause_requested) is pause-only: it toggles the app-level pause
## flag while playing and does nothing at all on the menu/dead screens.
## reference/snake.html's Space handler also started a run from those two
## screens (snake.html:584-591); Enter/Kp Enter -- Godot's own ui_accept on
## the overlay's focused button -- is this port's select key instead, so
## Space no longer carries two meanings. Mirrors togglePause()
## (snake.html:559-566) without ever touching the sim's own (unreachable)
## paused status.
##
## Pause is an app-level flag, so the sim's status stays PLAYING while
## paused -- one status check therefore covers both pausing and resuming.
func _on_pause_requested() -> void:
	var view := world.player_view_get(0)
	if view.result != SimulationWorld.OK:
		return
	if _shared_status() != BoardGeometry.STATUS_PLAYING:
		return
	_paused = not _paused
	if _paused:
		sfx.play("pause")
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
	var status := _shared_status()
	if status == BoardGeometry.STATUS_MENU or status == BoardGeometry.STATUS_DEAD:
		_start_or_restart()
	else:
		## reset() forces every player back to the sim's own fixed
		## right-facing spawn, so this path needs the same reroll
		## _start_or_restart() does -- without it, restarting mid-run always
		## heads east.
		world.reset()
		_apply_start_directions()
		_paused = false
		_refresh_screen()

## The overlay's single action button: "Start" (menu), "Resume" (paused),
## or "Play Again" (dead) -- mirrors el.start's click handler, which
## dispatches on status the same way (snake.html:588-590).
func _on_overlay_action_pressed() -> void:
	var view := world.player_view_get(0)
	if view.result != SimulationWorld.OK:
		return
	sfx.play("ui_confirm")
	var status := _shared_status()
	if status == BoardGeometry.STATUS_PLAYING and _paused:
		_paused = false
		_refresh_screen()
	else:
		_start_or_restart()

## The dead screen's "Return to Title". A fresh world.init() is what puts
## the status back to menu -- world.reset() only restarts a run, and no ABI
## call moves a live world backwards into .menu. Keeps the current player
## count so the menu comes up on whatever was last played; picking a
## different one there re-inits again anyway.
func _on_return_to_title_requested() -> void:
	sfx.play("ui_confirm")
	world.init(COLS, ROWS, _player_count, _wrap_for(_current_mode_id), SeedSource.fresh(), SimulationWorld.SPEED_SOURCE_SCORE_TABLE)
	_paused = false
	_is_win = false
	_refresh_screen()

## Queues each player's drawn heading against an already-playing world, so
## every path that puts a snake back on the sim's fixed right-facing spawn
## -- _start_or_restart()'s init/reset, and R's mid-run reset() -- rerolls
## through here rather than each re-deriving it.
##
## queue_dir alone only sets next_dir; the heading wouldn't commit until the
## first pumped tick, so the snake would render facing east for a frame and
## then visibly pivot. Stepping the sim here, before anything is drawn,
## makes the drawn heading the starting one. It takes SNAKE_LEN - 1 ticks to
## walk every segment out of the east-west spawn layout and onto the new
## axis -- one tick alone would leave an elbow behind the head.
##
## ns_step is the exact-one-tick primitive (include/neo_snake.h calls
## queue_dir/pump the local-play conveniences layered on top of it), so this
## consumes no accumulator time and can't overshoot.
func _apply_start_directions() -> void:
	if not _randomize_start:
		return
	var dirs := StartDirections.pick(_player_count)
	var inputs := []
	for player in dirs.size():
		inputs.append({"player": player, "dir": dirs[player]})
	for i in SNAKE_LEN - 1:
		world.step(inputs)
	## A pellet can land in the handful of cells stepped over here. Draining
	## keeps _process from firing an eat cue and a particle burst for a bite
	## the player never saw -- the score it earned still stands.
	world.event_drain(EVENT_DRAIN_CAPACITY)

## The menu's "1 Player Game" / "2 Player Game" buttons. The count is fixed
## for the run: re-initializing mid-game would reset both snakes anyway, and
## the buttons only exist on the menu screen.
func _on_player_count_selected(count: int) -> void:
	_player_count = count
	_apply_player_count()
	sfx.play("ui_confirm")
	_start_or_restart()

## Gates every surface that names player 1 on whether player 1 exists.
func _apply_player_count() -> void:
	board_view_p2.visible = _player_count >= 2
	hud.set_p2_row_visible(_player_count >= 2)

func _start_or_restart() -> void:
	var view := world.player_view_get(0)
	var status := _shared_status()
	if view.result == SimulationWorld.OK and status == BoardGeometry.STATUS_MENU:
		world.init(COLS, ROWS, _player_count, _wrap_for(_current_mode_id), SeedSource.fresh(), SimulationWorld.SPEED_SOURCE_SCORE_TABLE)
	elif status == BoardGeometry.STATUS_DEAD:
		## core/world.zig's queueDir (byte-for-byte matching the oracle's
		## own queueDir, snake.html:569-576) checks a queued direction
		## against next_dir whenever status isn't "playing" -- including
		## "dead", where next_dir is just whatever a player was moving
		## when they died. Queuing DIR_RIGHT below with no reset first
		## means a player who died moving left gets silently rejected as
		## an illegal 180 (the very check that's supposed to only guard
		## a live run), so status never flips back to playing and every
		## later restart attempt -- any key, or "Play Again" by mouse --
		## fails the identical way. world.reset() unconditionally sets
		## every player's next_dir back to .right first, so the
		## queue_dir call below can never collide.
		world.reset()
	## This first queue_dir is what flips the world out of menu/dead: core's
	## queueDir calls start() -> reset(), which re-forces every player's
	## dir back to .right, clobbering whatever was queued (the oracle quirk
	## documented on _on_direction_queued). So the randomized headings can
	## only be applied afterwards, against an already-playing world -- where
	## the 180 guard reads dir == .right and accepts every direction in
	## StartDirections.LEGAL. They commit on the first tick.
	world.queue_dir(0, SimulationWorld.DIR_RIGHT)
	_apply_start_directions()
	_paused = false
	_is_win = false
	sfx.play("start")
	_refresh_screen()

## Mirrors queueDir()'s own auto-start branch (snake.html:576): any
## direction input from menu/dead starts/restarts the run. Faithfully
## reproduces the oracle's own quirk where that direction is then
## discarded rather than applied -- start() calls reset(), which
## unconditionally sets S.dir = S.nextDir = right (snake.html:312) AFTER
## queueDir() already set nextDir to the pressed key, clobbering it. So the
## keypress that starts a run never steers it; only the run itself.
##
## On desktop this branch is normally unreachable from the keyboard: while
## the menu/dead overlay is showing, its action button holds real Control
## focus (overlay_panel.gd), so a keyboard arrow gets consumed there first
## (Godot's own ui_up/ui_down focus navigation) and never reaches
## input_router.gd's _unhandled_input at all -- Enter/Space "choose the
## selection" instead, per Lance's desktop-menu spec. This still matters
## for touch swipe and joypad direction input, neither of which goes
## through Control focus, so both keep the oracle's original
## press-any-direction-to-start convenience -- starting whatever player
## count the menu is currently sitting on.
##
## A direction for a player this world doesn't have (WASD in a 1-player
## game) is dropped here rather than in input_router.gd: the router is a
## pure translation layer with no game-state knowledge, and the player
## count is game state.
func _on_direction_queued(dir: int, player: int = 0) -> void:
	if player >= _player_count:
		return
	var status := _shared_status()
	if status == BoardGeometry.STATUS_MENU or status == BoardGeometry.STATUS_DEAD:
		_start_or_restart()
		return
	sfx.play("turn")
	world.queue_dir(player, dir)

func _on_mode_selected(mode_id: String) -> void:
	sfx.play("ui_move")
	_current_mode_id = mode_id

## Mirrors reference/snake.html's blur auto-pause (snake.html:620), which
## only fires while actually playing.
func _on_focus_lost() -> void:
	var view := world.player_view_get(0)
	if view.result == SimulationWorld.OK and _shared_status() == BoardGeometry.STATUS_PLAYING and not _paused:
		_paused = true
		_refresh_screen()

## Applies a loaded settings dict (TASK-042) to the live systems it governs
## -- AudioServer bus volume, the fx reduce-flash gate, and the InputMap --
## called once at startup and again whenever settings_panel emits a change,
## so the running game always reflects what SaveStore has on disk.
func _apply_settings(settings: Dictionary) -> void:
	for bus: String in SaveStore.AUDIO_BUSES:
		var bus_idx := AudioServer.get_bus_index(bus)
		if bus_idx >= 0:
			AudioServer.set_bus_volume_db(bus_idx, settings.volume_db[bus])
	board_view.fx.reduce_flash = settings.reduce_flash
	board_view_p2.fx.reduce_flash = settings.reduce_flash
	KeybindCodec.apply_to_input_map(settings.keybinds)

func _on_settings_requested() -> void:
	_settings_open = true
	overlay.visible = false
	settings_panel.visible = true

func _on_settings_closed() -> void:
	_settings_open = false
	settings_panel.visible = false
	_refresh_screen()

func _on_volume_changed(bus: String, db: float) -> void:
	_save_data.settings.volume_db[bus] = db
	_apply_settings(_save_data.settings)
	save_store.save(_save_data)

func _on_reduce_flash_changed(enabled: bool) -> void:
	_save_data.settings.reduce_flash = enabled
	_apply_settings(_save_data.settings)
	save_store.save(_save_data)

func _on_keybind_changed(action: String, encoded: String) -> void:
	_save_data.settings.keybinds[action] = [encoded]
	_apply_settings(_save_data.settings)
	save_store.save(_save_data)

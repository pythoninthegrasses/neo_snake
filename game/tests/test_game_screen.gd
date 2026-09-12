extends GdUnitTestSuite

## Exercises GameScreen (TASK-036 AC#1-3) end to end through the real wired
## Node objects, following test_app_lifecycle.gd's add_child()-then-call
## convention. Isolates SaveStore under a temp user:// dir the same way
## test_save_store.gd does, so no real player save data is ever touched.

const BASE_DIR := "user://game_screen_test"

var _screen: GameScreen


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(BASE_DIR)
	_screen = GameScreen.new()
	_screen.save_dir_override = BASE_DIR
	add_child(_screen)


func after_test() -> void:
	_screen.queue_free()
	var dir := DirAccess.open(BASE_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			DirAccess.remove_absolute(BASE_DIR.path_join(name))
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(BASE_DIR)


func test_ready_starts_on_the_menu_screen() -> void:
	var view := _screen.world.player_view_get(0)
	assert_int(view.status).is_equal(BoardGeometry.STATUS_MENU)
	assert_bool(_screen.overlay.visible).is_true()


func test_direction_input_from_menu_starts_the_game() -> void:
	_screen._on_direction_queued(SimulationWorld.DIR_UP)
	var view := _screen.world.player_view_get(0)
	assert_int(view.status).is_equal(BoardGeometry.STATUS_PLAYING)
	assert_bool(_screen.overlay.visible).is_false()


func test_pause_requested_while_playing_shows_the_paused_overlay() -> void:
	_screen._start_or_restart()
	_screen._on_pause_requested()
	assert_bool(_screen._paused).is_true()
	assert_bool(_screen.overlay.visible).is_true()


func test_pause_requested_again_resumes_and_hides_the_overlay() -> void:
	_screen._start_or_restart()
	_screen._on_pause_requested()
	_screen._on_pause_requested()
	assert_bool(_screen._paused).is_false()
	assert_bool(_screen.overlay.visible).is_false()


func test_restart_requested_while_playing_resets_without_touching_menu() -> void:
	_screen._start_or_restart()
	_screen._on_restart_requested()
	var view := _screen.world.player_view_get(0)
	assert_int(view.status).is_equal(BoardGeometry.STATUS_PLAYING)
	assert_bool(_screen._paused).is_false()


func test_overlay_action_pressed_from_menu_starts_the_game() -> void:
	_screen._on_overlay_action_pressed()
	var view := _screen.world.player_view_get(0)
	assert_int(view.status).is_equal(BoardGeometry.STATUS_PLAYING)


func test_overlay_action_pressed_while_paused_resumes() -> void:
	_screen._start_or_restart()
	_screen._on_pause_requested()
	_screen._on_overlay_action_pressed()
	assert_bool(_screen._paused).is_false()


func test_focus_lost_while_playing_pauses() -> void:
	_screen._start_or_restart()
	_screen._on_focus_lost()
	assert_bool(_screen._paused).is_true()


func test_focus_lost_while_already_paused_stays_paused() -> void:
	_screen._start_or_restart()
	_screen._on_pause_requested()
	_screen._on_focus_lost()
	assert_bool(_screen._paused).is_true()


func test_hud_reflects_score_and_status_after_start() -> void:
	_screen._start_or_restart()
	_screen._refresh_screen()
	assert_str(_screen.hud._status_label.text).is_equal(GameScreenState.SCREEN_PLAYING.capitalize())

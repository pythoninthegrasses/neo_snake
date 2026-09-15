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


## Space is pause-only: it never starts or restarts a run. Enter/Kp Enter
## (Godot's ui_accept) confirm the overlay's focused button instead.

func test_pause_requested_from_the_menu_does_nothing() -> void:
	_screen._on_pause_requested()
	var view := _screen.world.player_view_get(0)
	assert_int(view.status).is_equal(BoardGeometry.STATUS_MENU)
	assert_bool(_screen._paused).is_false()
	assert_bool(_screen.overlay.visible).is_true()


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


func test_start_or_restart_plays_the_start_cue() -> void:
	_screen._start_or_restart()
	assert_bool(_screen.sfx._players["start"].playing).is_true()


func test_pause_requested_while_playing_plays_the_pause_cue() -> void:
	_screen._start_or_restart()
	_screen._on_pause_requested()
	assert_bool(_screen.sfx._players["pause"].playing).is_true()


func test_direction_input_while_playing_plays_the_turn_cue() -> void:
	_screen._start_or_restart()
	_screen._on_direction_queued(SimulationWorld.DIR_UP)
	assert_bool(_screen.sfx._players["turn"].playing).is_true()


func test_overlay_action_pressed_plays_the_ui_confirm_cue() -> void:
	_screen._on_overlay_action_pressed()
	assert_bool(_screen.sfx._players["ui_confirm"].playing).is_true()


func test_mode_selected_plays_the_ui_move_cue() -> void:
	_screen._on_mode_selected("classic")
	assert_bool(_screen.sfx._players["ui_move"].playing).is_true()


## TASK-051 AC#2: two locally-controlled players, independent input routing.

func test_game_screen_wires_a_second_board_view_for_player_1() -> void:
	assert_object(_screen.board_view_p2).is_not_null()
	assert_int(_screen.board_view_p2.player).is_equal(1)


## TASK-055: board_view_p2 is stacked on top of board_view, so if it also
## painted the shared board layers (opaque background/checkerboard/grid, and
## food) it would erase player 0's snake every frame -- player 0 then looks
## unsteerable because it is simply invisible.

func test_only_the_bottom_board_view_paints_the_shared_board() -> void:
	assert_bool(_screen.board_view.draws_shared_board).is_true()
	assert_bool(_screen.board_view_p2.draws_shared_board).is_false()


func test_player_1_direction_input_steers_player_1_without_touching_player_0() -> void:
	_screen._start_or_restart()
	_screen._on_direction_queued(SimulationWorld.DIR_DOWN, 1)
	var p0 := _screen.world.player_view_get(0)
	var p1 := _screen.world.player_view_get(1)
	assert_int(p0.next_dir).is_equal(SimulationWorld.DIR_RIGHT)
	assert_int(p1.next_dir).is_equal(SimulationWorld.DIR_DOWN)


func test_player_0_direction_input_still_defaults_to_player_0() -> void:
	_screen._start_or_restart()
	_screen._on_direction_queued(SimulationWorld.DIR_UP)
	var p0 := _screen.world.player_view_get(0)
	var p1 := _screen.world.player_view_get(1)
	assert_int(p0.next_dir).is_equal(SimulationWorld.DIR_UP)
	assert_int(p1.next_dir).is_equal(SimulationWorld.DIR_RIGHT)


## TASK-051 AC#3: per-player score/status HUD elements both update.

func test_hud_reflects_both_players_score_and_status_after_start() -> void:
	_screen._start_or_restart()
	_screen._refresh_screen()
	assert_str(_screen.hud._status_label.text).is_equal(GameScreenState.SCREEN_PLAYING.capitalize())
	assert_str(_screen.hud._p2_status_label.text).is_equal(GameScreenState.SCREEN_PLAYING.capitalize())
	assert_str(_screen.hud._p2_score_label.text).is_equal("P2 Score 0")

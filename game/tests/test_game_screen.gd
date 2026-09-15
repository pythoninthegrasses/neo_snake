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


## A run now begins on a randomized heading, so a test that wants a turn
## accepted has to pick one perpendicular to it -- a hardcoded direction
## would be a rejected 180 whenever the draw came up opposite.
func _a_legal_turn_for(player: int) -> int:
	var dir: int = _screen.world.player_view_get(player).dir
	var vertical := dir == SimulationWorld.DIR_UP or dir == SimulationWorld.DIR_DOWN
	return SimulationWorld.DIR_RIGHT if vertical else SimulationWorld.DIR_UP


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


## A started run gets a randomized heading rather than the sim's own fixed
## spawn direction, and two players never start facing each other.

func test_a_started_run_gets_a_legal_randomized_heading() -> void:
	var seen := {}
	for i in 60:
		_screen._on_player_count_selected(1)
		var dir: int = _screen.world.player_view_get(0).next_dir
		assert_array(StartDirections.LEGAL).contains([dir])
		seen[dir] = true
		_screen._on_return_to_title_requested()
	## Membership alone would pass on a heading that never actually varies.
	assert_int(seen.size()).is_greater(1)


## The heading has to be committed and the body laid out along it before the
## first frame is drawn -- otherwise the snake spawns facing east and visibly
## pivots one tick later.

func test_the_snake_is_already_facing_its_heading_when_play_begins() -> void:
	for count in [1, 2]:
		for i in 20:
			_screen._on_player_count_selected(count)
			for player in count:
				var view := _screen.world.player_view_get(player)
				assert_int(view.dir).is_equal(view.next_dir)
				var cells: PackedVector2Array = _screen.world.body_copy(player).cells
				## Every segment steps the same way, i.e. no elbow left over
				## from the spawn's east-west layout.
				assert_vector(cells[0] - cells[1]).is_equal(cells[1] - cells[2])
			_screen._on_return_to_title_requested()


func test_starting_play_never_fires_a_stale_eat_cue() -> void:
	for i in 40:
		_screen._on_player_count_selected(1)
		assert_int(_screen.world.event_count()).is_equal(0)
		_screen._on_return_to_title_requested()


## R mid-run restarts through world.reset(), not through the menu/dead
## branch, and must reroll the heading the same way -- reset() itself always
## forces the sim's own fixed right-facing spawn back.

func test_restarting_while_playing_also_rerolls_the_heading() -> void:
	_screen._on_player_count_selected(1)
	var seen := {}
	for i in 60:
		_screen._on_restart_requested()
		var dir: int = _screen.world.player_view_get(0).next_dir
		assert_array(StartDirections.LEGAL).contains([dir])
		seen[dir] = true
	assert_int(seen.size()).is_greater(1)


func test_restarting_two_players_while_playing_keeps_them_off_each_other() -> void:
	_screen._on_player_count_selected(2)
	for i in 60:
		_screen._on_restart_requested()
		var p0: int = _screen.world.player_view_get(0).next_dir
		var p1: int = _screen.world.player_view_get(1).next_dir
		var head_on: bool = p0 == SimulationWorld.DIR_DOWN and p1 == SimulationWorld.DIR_UP
		assert_bool(head_on).is_false()


func test_two_players_never_start_facing_each_other() -> void:
	for i in 60:
		_screen._on_player_count_selected(2)
		var p0: int = _screen.world.player_view_get(0).next_dir
		var p1: int = _screen.world.player_view_get(1).next_dir
		var head_on: bool = p0 == SimulationWorld.DIR_DOWN and p1 == SimulationWorld.DIR_UP
		assert_bool(head_on).is_false()
		_screen._on_return_to_title_requested()


func test_return_to_title_puts_the_world_back_on_the_menu() -> void:
	_screen._on_player_count_selected(2)
	_screen._on_return_to_title_requested()
	assert_int(_screen._shared_status()).is_equal(BoardGeometry.STATUS_MENU)
	assert_bool(_screen._paused).is_false()
	assert_bool(_screen.overlay.visible).is_true()


## The menu chooses the player count; a 1-player game must not render, score
## or accept input for a player the world doesn't have.

func test_choosing_a_one_player_game_starts_a_single_player_world() -> void:
	_screen._on_player_count_selected(1)
	assert_int(_screen.world.player_view_get(0).status).is_equal(BoardGeometry.STATUS_PLAYING)
	assert_int(_screen.world.player_view_get(1).result).is_not_equal(SimulationWorld.OK)
	assert_bool(_screen.board_view_p2.visible).is_false()
	assert_bool(_screen.hud.p2_row_visible()).is_false()


func test_choosing_a_two_player_game_starts_a_two_player_world() -> void:
	_screen._on_player_count_selected(2)
	assert_int(_screen.world.player_view_get(0).status).is_equal(BoardGeometry.STATUS_PLAYING)
	assert_int(_screen.world.player_view_get(1).result).is_equal(SimulationWorld.OK)
	assert_bool(_screen.board_view_p2.visible).is_true()
	assert_bool(_screen.hud.p2_row_visible()).is_true()


func test_player_1_input_is_inert_in_a_one_player_game() -> void:
	_screen._on_player_count_selected(1)
	var before: int = _screen.world.player_view_get(0).next_dir
	_screen._on_direction_queued(SimulationWorld.DIR_DOWN, 1)
	assert_int(_screen.world.player_view_get(0).next_dir).is_equal(before)
	assert_int(_screen._shared_status()).is_equal(BoardGeometry.STATUS_PLAYING)


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
	_screen._on_player_count_selected(2)
	var p0_before: int = _screen.world.player_view_get(0).next_dir
	var turn := _a_legal_turn_for(1)
	_screen._on_direction_queued(turn, 1)
	assert_int(_screen.world.player_view_get(0).next_dir).is_equal(p0_before)
	assert_int(_screen.world.player_view_get(1).next_dir).is_equal(turn)


func test_player_0_direction_input_still_defaults_to_player_0() -> void:
	_screen._on_player_count_selected(2)
	var p1_before: int = _screen.world.player_view_get(1).next_dir
	var turn := _a_legal_turn_for(0)
	_screen._on_direction_queued(turn)
	assert_int(_screen.world.player_view_get(0).next_dir).is_equal(turn)
	assert_int(_screen.world.player_view_get(1).next_dir).is_equal(p1_before)


## TASK-051 AC#3: per-player score/status HUD elements both update.

func test_hud_reflects_both_players_score_and_status_after_start() -> void:
	_screen._on_player_count_selected(2)
	_screen._refresh_screen()
	assert_str(_screen.hud._status_label.text).is_equal(GameScreenState.SCREEN_PLAYING.capitalize())
	assert_str(_screen.hud._p2_status_label.text).is_equal(GameScreenState.SCREEN_PLAYING.capitalize())
	assert_str(_screen.hud._p2_score_label.text).is_equal("P2 Score 0")

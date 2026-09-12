extends GdUnitTestSuite

## Exercises GameScreenState (TASK-036 AC#3) against every S.status-equivalent
## transition reference/snake.html's showOverlay() call sites cover:
## menu, playing (no overlay), paused, dead (Game Over), and dead (You Win).

func test_screen_for_menu_status_is_menu() -> void:
	assert_str(GameScreenState.screen_for(BoardGeometry.STATUS_MENU, false)).is_equal(GameScreenState.SCREEN_MENU)


func test_screen_for_playing_status_not_app_paused_is_playing() -> void:
	assert_str(GameScreenState.screen_for(BoardGeometry.STATUS_PLAYING, false)).is_equal(GameScreenState.SCREEN_PLAYING)


func test_screen_for_playing_status_app_paused_is_paused() -> void:
	assert_str(GameScreenState.screen_for(BoardGeometry.STATUS_PLAYING, true)).is_equal(GameScreenState.SCREEN_PAUSED)


func test_screen_for_dead_status_is_dead_regardless_of_app_paused() -> void:
	assert_str(GameScreenState.screen_for(BoardGeometry.STATUS_DEAD, false)).is_equal(GameScreenState.SCREEN_DEAD)
	assert_str(GameScreenState.screen_for(BoardGeometry.STATUS_DEAD, true)).is_equal(GameScreenState.SCREEN_DEAD)


func test_overlay_content_menu_matches_the_oracles_static_markup() -> void:
	var content := GameScreenState.overlay_content(GameScreenState.SCREEN_MENU, 0, 0, 3, false)
	assert_str(content.title).is_equal("Ready?")
	assert_str(content.button_label).is_equal("Start")
	assert_bool(content.show_mode_select).is_true()


func test_overlay_content_paused_matches_togglepauses_showoverlay_call() -> void:
	var content := GameScreenState.overlay_content(GameScreenState.SCREEN_PAUSED, 40, 90, 7, false)
	assert_str(content.title).is_equal("Paused")
	assert_str(content.sub).contains("Score 40")
	assert_str(content.sub).contains("Length 7")
	assert_str(content.button_label).is_equal("Resume")
	assert_bool(content.show_mode_select).is_false()


func test_overlay_content_dead_not_win_matches_dies_showoverlay_call() -> void:
	var content := GameScreenState.overlay_content(GameScreenState.SCREEN_DEAD, 30, 90, 4, false)
	assert_str(content.title).is_equal("Game Over")
	assert_str(content.sub).contains("Score 30")
	assert_str(content.sub).contains("Best 90")
	assert_str(content.button_label).is_equal("Play again")
	assert_bool(content.show_mode_select).is_false()


func test_overlay_content_dead_win_matches_wins_showoverlay_call() -> void:
	var content := GameScreenState.overlay_content(GameScreenState.SCREEN_DEAD, 570, 570, 24, true)
	assert_str(content.title).is_equal("You Win")
	assert_str(content.sub).contains("Score 570")
	assert_str(content.button_label).is_equal("Play again")
	assert_bool(content.show_mode_select).is_false()

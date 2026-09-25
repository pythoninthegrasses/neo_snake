extends GdUnitTestSuite

## Exercises OverlayPanel's configure()-driven visibility directly against
## the real Control tree (no GameScreen needed), the way test_hud.gd would
## if it existed -- the Quit button (added for the title-screen quit
## option) is the only piece of overlay wiring this repo tests in
## isolation rather than through test_game_screen.gd's end-to-end flow.

var _overlay: OverlayPanel


func before_test() -> void:
	_overlay = OverlayPanel.new()
	add_child(_overlay)


func _menu_content() -> Dictionary:
	return GameScreenState.overlay_content(GameScreenState.SCREEN_MENU, 0, 0, 3, false)


func _paused_content() -> Dictionary:
	return GameScreenState.overlay_content(GameScreenState.SCREEN_PAUSED, 0, 0, 3, false)


func test_quit_button_is_visible_on_the_menu_by_default() -> void:
	_overlay.configure(_menu_content())
	assert_bool(_overlay._quit_button.visible).is_true()


func test_quit_button_is_hidden_on_paused() -> void:
	_overlay.configure(_paused_content())
	assert_bool(_overlay._quit_button.visible).is_false()


## A browser tab can't quit itself -- get_tree().quit() is a no-op there --
## so game_screen.gd tells the overlay quit isn't available on web, and the
## button must stay hidden even on the menu.
func test_quit_button_stays_hidden_when_quit_is_unavailable() -> void:
	_overlay.set_quit_available(false)
	_overlay.configure(_menu_content())
	assert_bool(_overlay._quit_button.visible).is_false()

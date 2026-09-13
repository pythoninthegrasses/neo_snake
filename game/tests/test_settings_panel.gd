extends GdUnitTestSuite

## SettingsPanel (TASK-042): confirms volume sliders/reduce-flash checkbox/
## keybind buttons initialize from a loaded settings dict (set_settings),
## and that editing each control emits the change signal GameScreen wires
## up to apply it live and persist it via SaveStore.

var _panel: SettingsPanel


func before_test() -> void:
	_panel = SettingsPanel.new()
	add_child(_panel)


func after_test() -> void:
	_panel.queue_free()


func _default_settings() -> Dictionary:
	var volume_db := {}
	for bus in SaveStore.AUDIO_BUSES:
		volume_db[bus] = 0.0
	return {
		"volume_db": volume_db,
		"reduce_flash": false,
		"keybinds": KeybindCodec.default_keybinds(),
	}


func test_set_settings_initializes_volume_sliders() -> void:
	var settings := _default_settings()
	settings.volume_db.Master = -6.0
	_panel.set_settings(settings)
	assert_float(_panel._volume_sliders.Master.value).is_equal_approx(-6.0, 0.0001)


func test_set_settings_initializes_reduce_flash_checkbox() -> void:
	var settings := _default_settings()
	settings.reduce_flash = true
	_panel.set_settings(settings)
	assert_bool(_panel._reduce_flash_check.button_pressed).is_true()


func test_set_settings_initializes_keybind_button_labels() -> void:
	_panel.set_settings(_default_settings())
	assert_str(_panel._keybind_buttons[InputDefaults.ACTION_PAUSE].text).is_equal(OS.get_keycode_string(KEY_SPACE))


func test_moving_a_volume_slider_emits_volume_changed() -> void:
	_panel.set_settings(_default_settings())
	var received := []
	_panel.volume_changed.connect(func(bus: String, db: float) -> void: received.append([bus, db]))
	_panel._volume_sliders.SFX.value = -12.0
	assert_array(received).contains_exactly([["SFX", -12.0]])


func test_toggling_reduce_flash_emits_reduce_flash_changed() -> void:
	_panel.set_settings(_default_settings())
	var received := []
	_panel.reduce_flash_changed.connect(func(enabled: bool) -> void: received.append(enabled))
	_panel._reduce_flash_check.button_pressed = true
	assert_array(received).contains_exactly([true])


func test_rebinding_an_action_emits_keybind_changed_and_updates_the_button_label() -> void:
	_panel.set_settings(_default_settings())
	var received := []
	_panel.keybind_changed.connect(func(action: String, encoded: String) -> void: received.append([action, encoded]))
	_panel._on_rebind_pressed(InputDefaults.ACTION_MOVE_UP)
	assert_str(_panel._keybind_buttons[InputDefaults.ACTION_MOVE_UP].text).is_equal("Press a key...")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_I
	event.pressed = true
	_panel._capture_key(event)
	assert_array(received).contains_exactly([[InputDefaults.ACTION_MOVE_UP, KeybindCodec.encode(KEY_I)]])
	assert_str(_panel._keybind_buttons[InputDefaults.ACTION_MOVE_UP].text).is_equal(OS.get_keycode_string(KEY_I))


func test_closing_emits_closed() -> void:
	## GDScript lambdas capture locals by value, not by reference -- an Array
	## is captured by reference instead, the same pattern the other emit
	## assertions in this file already rely on.
	var received := []
	_panel.closed.connect(func() -> void: received.append(true))
	_panel._close_button.pressed.emit()
	assert_array(received).contains_exactly([true])

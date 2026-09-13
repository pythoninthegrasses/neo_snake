extends GdUnitTestSuite

## KeybindCodec (TASK-042 AC#3): confirms the encode/decode round trip is
## stable (not raw InputEvent serialization), that default_keybinds()
## mirrors InputDefaults.ACTION_PHYSICAL_KEYCODES exactly, and that
## apply_to_input_map() actually rebinds the project's live InputMap.

func after_test() -> void:
	## Restore the project's real InputMap bindings so a rebind test never
	## leaks into a later test (e.g. test_input_defaults.gd).
	KeybindCodec.apply_to_input_map(KeybindCodec.default_keybinds())


func test_encode_round_trips_through_decode() -> void:
	for code: Array in [[KEY_UP], [KEY_W], [KEY_SPACE], [KEY_R]]:
		var keycode: Key = code[0]
		assert_int(KeybindCodec.decode(KeybindCodec.encode(keycode))).is_equal(keycode)


func test_decode_of_a_malformed_string_returns_key_none() -> void:
	assert_int(KeybindCodec.decode("not-a-key")).is_equal(KEY_NONE)
	assert_int(KeybindCodec.decode("")).is_equal(KEY_NONE)


func test_default_keybinds_mirrors_input_defaults() -> void:
	var defaults := KeybindCodec.default_keybinds()
	for action: String in InputDefaults.ACTION_PHYSICAL_KEYCODES:
		var expected: Array = InputDefaults.ACTION_PHYSICAL_KEYCODES[action]
		var decoded: Array = []
		for encoded in defaults[action]:
			decoded.append(KeybindCodec.decode(encoded))
		assert_array(decoded).contains_exactly_in_any_order(expected)


func test_apply_to_input_map_rebinds_an_action() -> void:
	KeybindCodec.apply_to_input_map({InputDefaults.ACTION_MOVE_UP: [KeybindCodec.encode(KEY_I)]})
	var events := InputMap.action_get_events(InputDefaults.ACTION_MOVE_UP)
	assert_int(events.size()).is_equal(1)
	assert_int((events[0] as InputEventKey).physical_keycode).is_equal(KEY_I)


func test_apply_to_input_map_skips_unknown_actions_and_undecodable_strings() -> void:
	KeybindCodec.apply_to_input_map({"not_a_real_action": ["key:Up"]})
	KeybindCodec.apply_to_input_map({InputDefaults.ACTION_MOVE_UP: ["garbage"]})
	assert_int(InputMap.action_get_events(InputDefaults.ACTION_MOVE_UP).size()).is_equal(0)

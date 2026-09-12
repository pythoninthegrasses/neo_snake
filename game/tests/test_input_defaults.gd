extends GdUnitTestSuite

## TASK-033 AC#1: InputMap actions are declared in project.godot itself,
## not constructed at runtime -- so this asserts the *project's actual
## loaded InputMap* (populated from project.godot before any test runs)
## matches InputDefaults.ACTION_PHYSICAL_KEYCODES exactly, catching drift
## in either direction (a project.godot edit that forgets to update
## InputDefaults, or vice versa).

func test_every_expected_action_is_declared_with_its_expected_keycodes() -> void:
	for action: String in InputDefaults.ACTION_PHYSICAL_KEYCODES:
		assert_bool(InputMap.has_action(action)).is_true()
		var expected: Array = InputDefaults.ACTION_PHYSICAL_KEYCODES[action]
		var actual_keycodes: Array = []
		for event in InputMap.action_get_events(action):
			assert_object(event).is_instanceof(InputEventKey)
			actual_keycodes.append((event as InputEventKey).physical_keycode)
		assert_array(actual_keycodes).contains_exactly_in_any_order(expected)

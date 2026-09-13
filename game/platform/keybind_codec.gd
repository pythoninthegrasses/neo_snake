class_name KeybindCodec
extends RefCounted

## Stable, engine-version-tolerant text encoding for physical-keyboard
## keybinds (TASK-042 AC#3): built on Godot's own OS.get_keycode_string()/
## find_keycode_from_string() round trip rather than raw InputEvent
## serialization, so a save file survives a Godot engine/input-system
## version bump. Every encoded value is prefixed "key:" so a future non-key
## input kind (joypad button, etc.) can be added later without an
## ambiguous bare string.

const KEY_PREFIX := "key:"

static func encode(keycode: Key) -> String:
	return KEY_PREFIX + OS.get_keycode_string(keycode)

## Returns KEY_NONE (0) for a malformed or unrecognized string -- callers
## treat that as "no binding", never as a crash.
static func decode(text: String) -> Key:
	if not text.begins_with(KEY_PREFIX):
		return KEY_NONE
	return OS.find_keycode_from_string(text.substr(KEY_PREFIX.length())) as Key

## action name -> Array[String] of encode()'d keys, derived from
## InputDefaults.ACTION_PHYSICAL_KEYCODES -- the fresh-install default every
## save file's settings.keybinds section starts from.
static func default_keybinds() -> Dictionary:
	var result := {}
	for action: String in InputDefaults.ACTION_PHYSICAL_KEYCODES:
		var codes: Array = InputDefaults.ACTION_PHYSICAL_KEYCODES[action]
		var encoded: Array[String] = []
		for code in codes:
			encoded.append(encode(code))
		result[action] = encoded
	return result

## Rebuilds project.godot's InputMap action bindings from encoded keybinds
## (physical keycodes only, matching how InputDefaults itself declares
## every default binding) -- callers apply this once at startup, after
## SaveStore.load_or_default(). Unknown actions/undecodable strings are
## skipped rather than raising, since a save file can be hand-edited or
## carried over from an older schema version.
static func apply_to_input_map(keybinds: Dictionary) -> void:
	for action: String in keybinds:
		if not InputMap.has_action(action):
			continue
		InputMap.action_erase_events(action)
		for encoded in keybinds[action]:
			var keycode := decode(encoded)
			if keycode == KEY_NONE:
				continue
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			InputMap.action_add_event(action, event)

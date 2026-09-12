class_name ContentLoader
extends RefCounted

## Loads and schema-validates game/content/*.json (TASK-030) so gameplay
## tuning, palette colors, and mode definitions are data instead of magic
## numbers/hardcoded colors baked into presentation code
## (backlog/decisions/decision-010). See docs/build-layout.md's
## "game/content/{tuning,palette,modes}.json + game/content/loader.gd"
## section for the field-by-field schema and the decisions each field
## traces back to.

const TUNING_PATH := "res://content/tuning.json"
const PALETTE_PATH := "res://content/palette.json"
const MODES_PATH := "res://content/modes.json"

## Schema values are one of: a nested Dictionary (recurse), the string
## "number" (JSON numbers always decode as TYPE_FLOAT in Godot, so this
## accepts either), ["array_of", <element schema>] (a TYPE_ARRAY whose every
## element must match the element schema), or a Variant.Type constant
## (exact typeof() match).
const TUNING_SCHEMA := {
	"version": "number",
	"particles": {
		"burst_count": "number",
		"speed_min": "number",
		"speed_max": "number",
		"drag_per_tick": "number",
		"life_decay_per_ms": "number",
	},
	"flash": {
		"decay_per_ms": "number",
		"dead_alpha_factor": "number",
		"eat_alpha_factor": "number",
	},
	"food": {
		"pulse_period_ms": "number",
		"pulse_pad_base_fraction": "number",
		"pulse_pad_amplitude_fraction": "number",
		"shadow_blur_base_fraction": "number",
		"shadow_blur_amplitude_fraction": "number",
		"corner_radius_fraction": "number",
	},
	"snake": {
		"head_shadow_blur_fraction": "number",
		"body_pad_base_fraction": "number",
		"body_pad_amplitude_fraction": "number",
		"corner_radius_fraction": "number",
		"eye_side_offset_fraction": "number",
		"eye_forward_offset_fraction": "number",
		"eye_radius_fraction": "number",
		"eye_radius_min_px": "number",
	},
	"render": {
		"checkerboard_alpha": "number",
		"grid_line_alpha": "number",
		"device_pixel_ratio_cap": "number",
	},
	"input": {
		"swipe_threshold_cell_fraction": "number",
	},
	"scoring": {
		"best_score_defaults": TYPE_DICTIONARY,
	},
}

const PALETTE_SCHEMA := {
	"version": "number",
	"ui": {
		"bg": TYPE_STRING,
		"panel": TYPE_STRING,
		"grid_a": TYPE_STRING,
		"grid_b": TYPE_STRING,
		"snake": TYPE_STRING,
		"snake_head": TYPE_STRING,
		"food": TYPE_STRING,
		"text": TYPE_STRING,
		"muted": TYPE_STRING,
		"accent": TYPE_STRING,
	},
	"board": {
		"background": TYPE_STRING,
		"checkerboard_tile": TYPE_STRING,
		"grid_line": TYPE_STRING,
		"food_fill": TYPE_STRING,
		"food_shadow": TYPE_STRING,
		"snake_head_fill": TYPE_STRING,
		"snake_head_shadow": TYPE_STRING,
		"snake_body_base_rgb": TYPE_ARRAY,
		"snake_body_rgb_delta": TYPE_ARRAY,
		"eye_fill": TYPE_STRING,
		"particle_hues": TYPE_ARRAY,
		"flash_dead": TYPE_STRING,
		"flash_eat": TYPE_STRING,
		"pause_vignette": TYPE_STRING,
	},
}

const MODES_SCHEMA := {
	"version": "number",
	"default_mode": TYPE_STRING,
	"modes": ["array_of", {
		"id": TYPE_STRING,
		"label": TYPE_STRING,
		"wrap": TYPE_BOOL,
	}],
}

static func load_tuning(path: String = TUNING_PATH) -> Dictionary:
	return _load(path, TUNING_SCHEMA)

static func load_palette(path: String = PALETTE_PATH) -> Dictionary:
	return _load(path, PALETTE_SCHEMA)

static func load_modes(path: String = MODES_PATH) -> Dictionary:
	return _load(path, MODES_SCHEMA)

## Loads all three content files and additionally cross-validates that
## tuning.json's scoring.best_score_defaults (decision-009) has exactly one
## entry per mode declared in modes.json -- neither missing an id nor
## carrying a stale one.
static func load_all(tuning_path: String = TUNING_PATH, palette_path: String = PALETTE_PATH, modes_path: String = MODES_PATH) -> Dictionary:
	var tuning := load_tuning(tuning_path)
	if not tuning.ok:
		return {"ok": false, "error": tuning.error}
	var palette := load_palette(palette_path)
	if not palette.ok:
		return {"ok": false, "error": palette.error}
	var modes := load_modes(modes_path)
	if not modes.ok:
		return {"ok": false, "error": modes.error}

	var mode_ids: Array = []
	for mode in modes.data.modes:
		mode_ids.append(mode.id)
	var defaults: Dictionary = tuning.data.scoring.best_score_defaults
	for mode_id in defaults.keys():
		if not mode_ids.has(mode_id):
			return {"ok": false, "error": "%s: scoring.best_score_defaults has mode id '%s' not declared in %s" % [tuning_path, mode_id, modes_path]}
	for mode_id in mode_ids:
		if not defaults.has(mode_id):
			return {"ok": false, "error": "%s: scoring.best_score_defaults is missing an entry for mode '%s' declared in %s" % [tuning_path, mode_id, modes_path]}

	return {"ok": true, "error": "", "tuning": tuning.data, "palette": palette.data, "modes": modes.data}

static func _load(path: String, schema: Dictionary) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "%s: file not found" % path, "data": {}}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "%s: could not open file (%s)" % [path, error_string(FileAccess.get_open_error())], "data": {}}
	var text := file.get_as_text()
	var json := JSON.new()
	var parse_err: Error = json.parse(text)
	if parse_err != OK:
		return {"ok": false, "error": "%s: JSON parse error at line %d: %s" % [path, json.get_error_line(), json.get_error_message()], "data": {}}
	var data: Variant = json.get_data()
	var schema_err := _validate_against_schema(data, schema, path)
	if schema_err != "":
		return {"ok": false, "error": schema_err, "data": {}}
	return {"ok": true, "error": "", "data": data}

static func _validate_against_schema(data: Variant, schema: Dictionary, path: String) -> String:
	if typeof(data) != TYPE_DICTIONARY:
		return "%s: expected an object, got %s" % [path, type_string(typeof(data))]
	for key in schema.keys():
		if not data.has(key):
			return "%s: missing required key '%s'" % [path, key]
		var expected: Variant = schema[key]
		var value: Variant = data[key]
		var field_path := "%s.%s" % [path, key]
		if expected is Dictionary:
			var err := _validate_against_schema(value, expected, field_path)
			if err != "":
				return err
		elif expected is Array and expected.size() == 2 and expected[0] == "array_of":
			if typeof(value) != TYPE_ARRAY:
				return "%s: expected an array, got %s" % [field_path, type_string(typeof(value))]
			var elem_schema: Dictionary = expected[1]
			for i in value.size():
				var elem_err := _validate_against_schema(value[i], elem_schema, "%s[%d]" % [field_path, i])
				if elem_err != "":
					return elem_err
		elif expected is String and expected == "number":
			if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
				return "%s: expected a number, got %s" % [field_path, type_string(typeof(value))]
		else:
			if typeof(value) != expected:
				return "%s: expected %s, got %s" % [field_path, type_string(expected), type_string(typeof(value))]
	return ""

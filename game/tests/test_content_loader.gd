extends GdUnitTestSuite

## Exercises ContentLoader (TASK-030) against the real game/content/*.json
## files, and against deliberately malformed temp files to confirm AC#2
## ("loader.gd validates the content files and reports a clear error for a
## malformed file") actually holds.

const ContentLoaderScript := preload("res://content/loader.gd")

var _temp_paths: Array[String] = []


func after_test() -> void:
	for path in _temp_paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_temp_paths.clear()


func _write_temp(name: String, contents: String) -> String:
	var path := "user://%s" % name
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(contents)
	file.close()
	_temp_paths.append(path)
	return path


func test_load_tuning_from_the_real_content_file_succeeds() -> void:
	var result := ContentLoaderScript.load_tuning()
	assert_bool(result.ok).is_true()
	assert_str(result.error).is_equal("")
	assert_int(int(result.data.particles.burst_count)).is_equal(14)
	assert_int(int(result.data.scoring.best_score_defaults.wall)).is_equal(0)


func test_load_palette_from_the_real_content_file_succeeds() -> void:
	var result := ContentLoaderScript.load_palette()
	assert_bool(result.ok).is_true()
	assert_str(result.data.ui.snake).is_equal("#4ade80")


func test_load_modes_from_the_real_content_file_succeeds() -> void:
	var result := ContentLoaderScript.load_modes()
	assert_bool(result.ok).is_true()
	assert_int(result.data.modes.size()).is_equal(2)
	assert_str(result.data.modes[0].id).is_equal("wall")


func test_load_all_cross_validates_best_score_defaults_against_modes() -> void:
	var result := ContentLoaderScript.load_all()
	assert_bool(result.ok).is_true()
	assert_str(result.error).is_equal("")
	assert_bool(result.tuning.scoring.best_score_defaults.has("wrap")).is_true()


func test_malformed_json_syntax_reports_a_clear_error() -> void:
	var path := _write_temp("bad_syntax.json", "{ this is not valid json")
	var result := ContentLoaderScript.load_tuning(path)
	assert_bool(result.ok).is_false()
	assert_str(result.error).contains("JSON parse error")


func test_missing_required_key_reports_a_clear_error() -> void:
	var path := _write_temp("missing_key.json", '{"version": 1}')
	var result := ContentLoaderScript.load_tuning(path)
	assert_bool(result.ok).is_false()
	assert_str(result.error).contains("missing required key 'particles'")


func test_wrong_field_type_reports_a_clear_error() -> void:
	var path := _write_temp("wrong_type.json", '{"version": 1, "modes": "not-an-array", "default_mode": "wall"}')
	var result := ContentLoaderScript.load_modes(path)
	assert_bool(result.ok).is_false()
	assert_str(result.error).contains("modes")
	assert_str(result.error).contains("expected an array")


func test_missing_file_reports_a_clear_error() -> void:
	var result := ContentLoaderScript.load_tuning("res://content/does_not_exist.json")
	assert_bool(result.ok).is_false()
	assert_str(result.error).contains("file not found")


func test_best_score_defaults_mismatched_with_modes_reports_a_clear_error() -> void:
	var tuning_path := _write_temp("tuning_mismatch.json", JSON.stringify({
		"version": 1,
		"particles": {"burst_count": 14, "speed_min": 0.02, "speed_max": 0.06, "drag_per_tick": 0.94, "life_decay_per_ms": 0.001},
		"flash": {"decay_per_ms": 0.004, "dead_alpha_factor": 0.28, "eat_alpha_factor": 0.12},
		"food": {"pulse_period_ms": 260, "pulse_pad_base_fraction": 0.2, "pulse_pad_amplitude_fraction": 0.04, "shadow_blur_base_fraction": 0.7, "shadow_blur_amplitude_fraction": 0.6, "corner_radius_fraction": 0.28},
		"snake": {"head_shadow_blur_fraction": 0.75, "body_pad_base_fraction": 0.12, "body_pad_amplitude_fraction": 0.16, "corner_radius_fraction": 0.3, "eye_side_offset_fraction": 0.19, "eye_forward_offset_fraction": 0.16, "eye_radius_fraction": 0.072, "eye_radius_min_px": 1.4},
		"render": {"checkerboard_alpha": 0.019, "grid_line_alpha": 0.055, "device_pixel_ratio_cap": 2},
		"input": {"swipe_threshold_cell_fraction": 0.5},
		"scoring": {"best_score_defaults": {"wall": 0, "extra_mode": 0}},
	}))
	var result := ContentLoaderScript.load_all(tuning_path)
	assert_bool(result.ok).is_false()
	assert_str(result.error).contains("extra_mode")

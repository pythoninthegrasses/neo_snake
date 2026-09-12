extends GdUnitTestSuite

## Exercises SaveStore (TASK-034) against a temp base dir under user:// so no
## real player save data is ever touched (AC#2). Mirrors test_content_loader.gd's
## _write_temp/after_test cleanup convention.

const SaveStoreScript := preload("res://platform/save_store.gd")

const BASE_DIR := "user://save_store_test"


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(BASE_DIR)


func after_test() -> void:
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


func _store() -> SaveStore:
	return SaveStoreScript.new(BASE_DIR)


func test_load_or_default_with_no_existing_file_returns_the_v2_default() -> void:
	var data := _store().load_or_default()
	assert_int(data.version).is_equal(2)
	assert_int(data.best_scores.wall).is_equal(0)
	assert_int(data.best_scores.wrap).is_equal(0)
	assert_str(data.last_mode).is_equal("wall")


func test_save_then_load_round_trips_the_data() -> void:
	var store := _store()
	var written := {"version": 2, "best_scores": {"wall": 7, "wrap": 3}, "last_mode": "wrap"}
	assert_int(store.save(written)).is_equal(OK)
	var read := store.load_or_default()
	assert_int(read.best_scores.wall).is_equal(7)
	assert_int(read.best_scores.wrap).is_equal(3)
	assert_str(read.last_mode).is_equal("wrap")


func test_load_migrates_a_v1_legacy_shape_assigning_the_score_to_wall_mode() -> void:
	var store := _store()
	assert_int(store.save({"version": 1, "best": 12})).is_equal(OK)
	var data := store.load_or_default()
	assert_int(data.version).is_equal(2)
	assert_int(data.best_scores.wall).is_equal(12)
	assert_int(data.best_scores.wrap).is_equal(0)
	assert_str(data.last_mode).is_equal("wall")


func test_a_second_save_rotates_the_prior_dst_into_bak() -> void:
	var store := _store()
	store.save({"version": 2, "best_scores": {"wall": 1, "wrap": 0}, "last_mode": "wall"})
	store.save({"version": 2, "best_scores": {"wall": 2, "wrap": 0}, "last_mode": "wall"})
	assert_bool(FileAccess.file_exists(BASE_DIR.path_join("save.json.bak"))).is_true()
	var bak_text := FileAccess.get_file_as_string(BASE_DIR.path_join("save.json.bak"))
	var bak_json := JSON.new()
	bak_json.parse(bak_text)
	assert_int(int(bak_json.data.best_scores.wall)).is_equal(1)


func test_load_falls_back_to_bak_when_dst_is_missing() -> void:
	## Fabricates the exact filesystem state a crash between the dst rename
	## and the tmp->dst promotion in save() would leave behind (AC#3),
	## bypassing SaveStore's own API entirely so the recovery path is
	## genuinely exercised rather than assumed.
	var store := _store()
	var bak_data := {"version": 2, "best_scores": {"wall": 9, "wrap": 0}, "last_mode": "wall"}
	var file := FileAccess.open(BASE_DIR.path_join("save.json.bak"), FileAccess.WRITE)
	file.store_string(JSON.stringify(bak_data))
	file.close()
	var read := store.load_or_default()
	assert_int(read.best_scores.wall).is_equal(9)


func test_load_falls_back_to_bak_when_dst_is_corrupt() -> void:
	var store := _store()
	var bak_data := {"version": 2, "best_scores": {"wall": 5, "wrap": 0}, "last_mode": "wall"}
	var bak_file := FileAccess.open(BASE_DIR.path_join("save.json.bak"), FileAccess.WRITE)
	bak_file.store_string(JSON.stringify(bak_data))
	bak_file.close()
	var dst_file := FileAccess.open(BASE_DIR.path_join("save.json"), FileAccess.WRITE)
	dst_file.store_string("{ not valid json")
	dst_file.close()
	var read := store.load_or_default()
	assert_int(read.best_scores.wall).is_equal(5)


func test_parse_legacy_best_matches_the_oracles_number_or_zero_fallback() -> void:
	assert_int(SaveStoreScript.parse_legacy_best("42").best).is_equal(42)
	assert_int(SaveStoreScript.parse_legacy_best("").best).is_equal(0)
	assert_int(SaveStoreScript.parse_legacy_best("not-a-number").best).is_equal(0)
	assert_int(SaveStoreScript.parse_legacy_best("0").best).is_equal(0)


func test_parse_legacy_best_returns_a_v1_shaped_dict() -> void:
	var data := SaveStoreScript.parse_legacy_best("17")
	assert_int(data.version).is_equal(1)
	assert_int(data.best).is_equal(17)

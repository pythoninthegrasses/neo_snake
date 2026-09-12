class_name SaveStore
extends RefCounted

## Persists best-score/mode state to disk with an injected base directory
## (AC#1) so tests point it at a temp dir instead of the real user://
## profile. Mirrors reference/snake.html's localStorage["snake.best"]
## (snake.html:294, 389) but in a richer, versioned on-disk shape per
## backlog/decisions/decision-009 (per-mode best score + persisted last
## mode, not one shared scalar) and decision-013 (writes are the caller's
## responsibility to debounce -- this class does not decide when to save,
## only how).

const FILE_NAME := "save.json"
const SCHEMA_VERSION := 2

## v2 defaults mirror content/tuning.json's scoring.best_score_defaults
## and content/modes.json's default_mode. Hardcoded rather than loaded via
## ContentLoader so a missing/corrupt content file can never break a
## save/load -- this is deliberately a self-contained file-I/O primitive.
const DEFAULT_BEST_SCORES := {"wall": 0, "wrap": 0}
const DEFAULT_MODE := "wall"

var _base_dir: String
## version -> Callable(Dictionary) -> Dictionary, taking that version's
## data and returning the next version's. Applied in a loop until
## SCHEMA_VERSION is reached.
var _migrations: Dictionary

func _init(base_dir: String = "user://") -> void:
	_base_dir = base_dir
	_migrations = {1: Callable(self, "_migrate_v1_to_v2")}

func _dst_path() -> String:
	return _base_dir.path_join(FILE_NAME)

func _tmp_path() -> String:
	return _dst_path() + ".tmp"

func _bak_path() -> String:
	return _dst_path() + ".bak"

static func _default_v2() -> Dictionary:
	return {
		"version": SCHEMA_VERSION,
		"best_scores": DEFAULT_BEST_SCORES.duplicate(),
		"last_mode": DEFAULT_MODE,
	}

func _migrate_v1_to_v2(data: Dictionary) -> Dictionary:
	var best_scores: Dictionary = DEFAULT_BEST_SCORES.duplicate()
	best_scores[DEFAULT_MODE] = int(data.get("best", 0))
	return {
		"version": 2,
		"best_scores": best_scores,
		"last_mode": DEFAULT_MODE,
	}

func _migrate(data: Dictionary) -> Dictionary:
	var version: int = int(data.get("version", 0))
	while version < SCHEMA_VERSION:
		if not _migrations.has(version):
			return _default_v2()
		data = _migrations[version].call(data)
		version = int(data.get("version", 0))
	return _normalize_v2(data)

## JSON numbers always decode as TYPE_FLOAT in Godot (same caveat
## content/loader.gd documents), but best_scores are conceptually ints --
## normalize on the way out so callers never have to re-cast.
static func _normalize_v2(data: Dictionary) -> Dictionary:
	var best_scores: Dictionary = data.get("best_scores", DEFAULT_BEST_SCORES.duplicate())
	var normalized_scores := {}
	for mode: String in best_scores:
		normalized_scores[mode] = int(best_scores[mode])
	return {
		"version": 2,
		"best_scores": normalized_scores,
		"last_mode": str(data.get("last_mode", DEFAULT_MODE)),
	}

static func _read_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var text := file.get_as_text()
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var parsed: Variant = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

## Reads the on-disk save, falling back to the .bak rotation copy if the
## primary file is missing or unparsable (an interrupted tmp -> bak -> dst
## write can leave dst absent with .bak holding the last-known-good save),
## then migrates it up to SCHEMA_VERSION. Never touches the network/web
## import path -- call import_web_legacy_best() first if this returns the
## fresh-install default and a web legacy score might exist.
func load_or_default() -> Dictionary:
	var data := _read_json_file(_dst_path())
	if data.is_empty():
		data = _read_json_file(_bak_path())
	if data.is_empty():
		return _default_v2()
	return _migrate(data)

## Atomic tmp -> bak -> dst rotation (three steps, not a direct
## overwrite): DirAccess.rename_absolute's overwrite-destination behavior
## on Windows is unconfirmed, so the previous dst is moved aside to .bak
## before the new tmp is promoted, rather than relying on rename to
## replace dst in place.
func save(data: Dictionary) -> Error:
	var dir := _base_dir.get_base_dir() if _base_dir.ends_with(FILE_NAME) else _base_dir
	if not DirAccess.dir_exists_absolute(_base_dir):
		var err := DirAccess.make_dir_recursive_absolute(_base_dir)
		if err != OK:
			return err
	var file := FileAccess.open(_tmp_path(), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	if FileAccess.file_exists(_dst_path()):
		if FileAccess.file_exists(_bak_path()):
			DirAccess.remove_absolute(_bak_path())
		var rename_err := DirAccess.rename_absolute(_dst_path(), _bak_path())
		if rename_err != OK:
			return rename_err
	return DirAccess.rename_absolute(_tmp_path(), _dst_path())

## Converts reference/snake.html's raw localStorage["snake.best"] string
## into a v1-shaped dict, matching the oracle's `Number(x) || 0` fallback
## on anything that doesn't parse as a finite number (snake.html:294).
## Pure and Node-free so it's directly unit-testable (AC#4) without a
## JavaScriptBridge/web export available.
static func parse_legacy_best(raw: String) -> Dictionary:
	var value := raw.to_float()
	if is_nan(value) or is_inf(value):
		value = 0.0
	return {"version": 1, "best": int(value)}

## Web-only: reads localStorage["snake.best"] via JavaScriptBridge.eval
## and folds it through the same v1 -> v2 migration used for on-disk
## saves, so a player's existing best score survives the port. No-ops
## (returns null) off the web platform. Manual verification: export a web
## build, set localStorage["snake.best"] via the browser devtools console
## before first load, then confirm the imported value appears as the
## "wall" mode's best score.
func import_web_legacy_best() -> Variant:
	if not OS.has_feature("web"):
		return null
	var raw: Variant = JavaScriptBridge.eval("localStorage.getItem('snake.best') || ''", true)
	return _migrate(parse_legacy_best(str(raw)))

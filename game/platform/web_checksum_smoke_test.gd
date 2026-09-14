class_name WebChecksumSmokeTest
extends Node

## TASK-048 AC#2: proves the Zig-SHA-256-via-C-ABI checksum chain
## (core/canon.zig's checksum() -> core/abi.zig's ns_checksum ->
## extension/src/neo_snake_world.cpp's NeoSnakeWorld.checksum(), the same
## chain game/tests/test_corpus_replay.gd already exercises natively as
## Tier-D) also produces correct output once core/ and the GDExtension are
## cross-compiled to wasm32-emscripten and actually running inside a real
## browser -- not just that the build artifact loads.
##
## Only runs under a web export (OS.has_feature("web")); a no-op everywhere
## else, since Tier-D's gdUnit4 suite already covers every corpus trace
## natively and re-running one here on desktop would just be redundant.
## Replays the same "one-turn-per-tick" trace test_corpus_replay.gd uses for
## its own corrupted-checksum negative case (a short, single-player,
## ABI-representable trace) tick-by-tick through SimulationWorld, exactly as
## test_corpus_replay.gd's _replay() does -- this is a deliberately smaller
## duplicate of that logic (one hardcoded trace, no gdUnit assertions)
## rather than a shared refactor, so it can run standalone at boot without
## depending on gdUnit4's test-runner machinery being present in an exported
## build.
##
## Prints one line to the browser console: "WEB_CHECKSUM_SMOKE_TEST: PASS"
## on success, or "WEB_CHECKSUM_SMOKE_TEST: FAIL <reason>" on the first
## mismatch -- this is what a Playwright-driven browser check (AC#3) reads
## to confirm the extension's checksum path is genuinely correct on web, not
## just that it didn't crash.

const TRACE_PATH := "res://tests/corpus/one-turn-per-tick.jsonl"


func _ready() -> void:
	if not OS.has_feature("web"):
		return
	var result := _replay()
	if result["ok"]:
		print("WEB_CHECKSUM_SMOKE_TEST: PASS")
	else:
		print("WEB_CHECKSUM_SMOKE_TEST: FAIL ", result["message"])


func _replay() -> Dictionary:
	var f := FileAccess.open(TRACE_PATH, FileAccess.READ)
	if f == null:
		return {"ok": false, "message": "could not open %s" % TRACE_PATH}
	var lines := f.get_as_text().split("\n")

	var header: Dictionary = JSON.parse_string(lines[0])
	var world := SimulationWorld.new()
	var init_result: int = world.init(
		int(header["cols"]), int(header["rows"]), int(header["players"]), bool(header["wrap"]),
		PackedInt32Array(header["seed"]), SimulationWorld.SPEED_SOURCE_SCORE_TABLE
	)
	if init_result != SimulationWorld.OK:
		return {"ok": false, "message": "init failed (result %d)" % init_result}

	var expected_tick := 0
	for line_text in lines.slice(1):
		if line_text.is_empty():
			continue
		var line: Dictionary = JSON.parse_string(line_text)
		var t: int = line["t"]
		if t != expected_tick:
			return {"ok": false, "message": "tick %d out of order (expected %d)" % [t, expected_tick]}

		if t == 0:
			var anchor_hex: String = line.get("s", "")
			if anchor_hex.is_empty():
				return {"ok": false, "message": "tick 0 has no \"s\" anchor"}
			var deser_result: int = world.deserialize(_hex_decode(anchor_hex))
			if deser_result != SimulationWorld.OK:
				return {"ok": false, "message": "tick 0 deserialize failed (result %d)" % deser_result}
		else:
			var inputs: Array = []
			for ev in line["in"]:
				var dir := _dir_from_name(String(ev["dir"]))
				if dir == -1:
					return {"ok": false, "message": "tick %d: unknown direction \"%s\"" % [t, ev["dir"]]}
				inputs.append({"player": int(ev["p"]), "dir": dir})
			var step_result: int = world.step(inputs)
			if step_result != SimulationWorld.OK:
				return {"ok": false, "message": "tick %d: step failed (result %d)" % [t, step_result]}

		var record: Dictionary = world.serialize()
		if record["result"] != SimulationWorld.OK:
			return {"ok": false, "message": "tick %d: serialize failed (result %d)" % [t, record["result"]]}
		var bytes: PackedByteArray = record["bytes"]

		var checksum_result: Dictionary = SimulationWorld.checksum(bytes)
		if checksum_result["result"] != SimulationWorld.OK:
			return {"ok": false, "message": "tick %d: checksum call failed (result %d)" % [t, checksum_result["result"]]}
		if not _checksum_matches(checksum_result["checksum"], String(line["c"])):
			return {"ok": false, "message": "tick %d: checksum mismatch" % t}

		expected_tick += 1

	return {"ok": true, "message": ""}


func _dir_from_name(dir_name: String) -> int:
	match dir_name:
		"up":
			return SimulationWorld.DIR_UP
		"down":
			return SimulationWorld.DIR_DOWN
		"left":
			return SimulationWorld.DIR_LEFT
		"right":
			return SimulationWorld.DIR_RIGHT
		_:
			return -1


func _hex_decode(hex: String) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(hex.length() / 2)
	for i in range(out.size()):
		out[i] = ("0x" + hex.substr(i * 2, 2)).hex_to_int()
	return out


## Splits a (possibly negative, bit-reinterpreted) int64 into its high/low
## 32-bit halves via well-defined bitwise ops only -- see test_corpus_replay.gd.
func _u64_hi_lo(v: int) -> Array:
	return [(v >> 32) & 0xFFFFFFFF, v & 0xFFFFFFFF]


func _parse_decimal_hi_lo(s: String) -> Array:
	var hi := 0
	var lo := 0
	for i in range(s.length()):
		var digit: int = s.unicode_at(i) - 48
		var lo_wide: int = lo * 10 + digit
		var carry: int = lo_wide >> 32
		lo = lo_wide & 0xFFFFFFFF
		hi = (hi * 10 + carry) & 0xFFFFFFFF
	return [hi, lo]


func _checksum_matches(ext_checksum: int, decimal: String) -> bool:
	var a := _u64_hi_lo(ext_checksum)
	var b := _parse_decimal_hi_lo(decimal)
	return a[0] == b[0] and a[1] == b[1]

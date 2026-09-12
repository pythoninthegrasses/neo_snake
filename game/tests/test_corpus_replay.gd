extends GdUnitTestSuite

## Tier-D corpus replay (TASK-028): drives every committed corpus trace
## entirely through SimulationWorld -> NeoSnakeWorld -> the C ABI ->
## core/world.zig, mirroring core/abitest.zig's Tier-C replay one layer up.
## This is the fourth independent computation of the same per-tick checksum
## (node oracle, Zig-internal Tier-B, Zig-via-C-ABI Tier-C, and now
## GDScript-via-GDExtension Tier-D) that must all agree on one committed
## constant per trace.
##
## Every trace was recorded starting already .playing (regen_corpus.mjs),
## while a fresh NeoSnakeWorld always starts in .menu (decision-015), so
## tick 0 is never reached via step() -- it is reached by deserializing its
## own committed "s" anchor directly, exactly as abitest.zig's Tier-C pass
## does at the C-ABI layer. docs/corpus-format.md and the empirical scan
## behind this task both confirm every trace's tick-0 line carries an "s"
## anchor and an empty "in" array, so this precondition always holds.
##
## Checksums are u64 but NeoSnakeWorld.checksum() bit-reinterprets them into
## a signed int64 (extension/src/neo_snake_world.cpp), and a corpus "c"
## field is a decimal string specifically because such values can exceed
## Number.MAX_SAFE_INTEGER / GDScript's signed range. _checksum_matches()
## compares the two 32-bit halves instead of the raw integers so nothing
## here depends on how GDScript handles 64-bit overflow.

const CORPUS_DIR := "res://tests/corpus/"
const MANIFEST_PATH := CORPUS_DIR + "manifest.json"

## win-full-board's cols=3 board can never be represented over the C ABI:
## ns_world_init rejects any cols<=8 config outright (it unconditionally
## calls reset(), whose fixed x=8/7/6 snake placement needs cols>8), and
## ns_deserialize separately refuses to rehydrate a record whose cols/rows
## differ from the world's init-time cols/rows -- so there is no sequence of
## ABI calls that can reach this trace's tick-0 anchor. See
## backlog/decisions/decision-021 for the full analysis; this is a Tier-D
## ABI-boundary coverage gap, not a reference/snake.html deviation, and not
## a bug this test file can fix.
const ABI_UNREPRESENTABLE_TRACES := ["win-full-board"]


func test_every_corpus_trace_replays_with_matching_checksums_and_anchors() -> void:
	var manifest: Dictionary = JSON.parse_string(_read_file(MANIFEST_PATH))
	for entry in manifest["files"]:
		var name := String(entry["name"])
		if ABI_UNREPRESENTABLE_TRACES.has(name):
			continue
		var text := _read_file(CORPUS_DIR + String(entry["file"]))
		var result := _replay(text, name)
		if not result["ok"]:
			fail(result["message"])


## Guards decision-021's exclusion against silently going stale: if a future
## ABI change ever lets win-full-board's board size init successfully, this
## fails loudly and is the signal to remove the exclusion above and replay
## the trace for real instead of continuing to skip it.
func test_win_full_board_still_cannot_be_represented_over_the_abi() -> void:
	var text := _read_file(CORPUS_DIR + "win-full-board.jsonl")
	var header: Dictionary = JSON.parse_string(text.split("\n")[0])
	var world := SimulationWorld.new()
	var init_result: int = world.init(
		int(header["cols"]), int(header["rows"]), int(header["players"]), bool(header["wrap"]),
		PackedInt32Array(header["seed"]), SimulationWorld.SPEED_SOURCE_SCORE_TABLE
	)
	assert_int(init_result).is_not_equal(SimulationWorld.OK)


func test_a_corrupted_committed_checksum_fails_replay() -> void:
	var text := _read_file(CORPUS_DIR + "one-turn-per-tick.jsonl")
	var corrupted := _corrupt_one_checksum(text)
	var result := _replay(corrupted, "one-turn-per-tick (corrupted)")
	assert_bool(result["ok"]).is_false()
	assert_str(result["message"]).contains("checksum mismatch")


# --- replay driver -------------------------------------------------------


func _replay(text: String, name: String) -> Dictionary:
	var lines := text.split("\n")
	var header: Dictionary = JSON.parse_string(lines[0])
	var players: int = header["players"]
	if players != 1:
		return {"ok": false, "message": "%s: %d-player trace; Tier-D only drives single-player traces" % [name, players]}

	var world := SimulationWorld.new()
	var seed := PackedInt32Array(header["seed"])
	var init_result: int = world.init(
		int(header["cols"]), int(header["rows"]), players, bool(header["wrap"]),
		seed, SimulationWorld.SPEED_SOURCE_SCORE_TABLE
	)
	if init_result != SimulationWorld.OK:
		return {"ok": false, "message": "%s: init failed (result %d)" % [name, init_result]}

	var expected_tick := 0
	for line_text in lines.slice(1):
		if line_text.is_empty():
			continue
		var line: Dictionary = JSON.parse_string(line_text)
		var t: int = line["t"]
		if t != expected_tick:
			return {"ok": false, "message": "%s: tick %d out of order (expected %d)" % [name, t, expected_tick]}

		if t == 0:
			# Every committed trace starts already .playing; jump straight
			# there via deserialize instead of step()ing a fresh .menu world.
			var anchor_hex: String = line.get("s", "")
			if anchor_hex.is_empty():
				return {"ok": false, "message": "%s: tick 0 has no \"s\" anchor" % name}
			var deser_result: int = world.deserialize(_hex_decode(anchor_hex))
			if deser_result != SimulationWorld.OK:
				return {"ok": false, "message": "%s: tick 0 deserialize failed (result %d)" % [name, deser_result]}
		else:
			var inputs: Array = []
			for ev in line["in"]:
				var dir := _dir_from_name(String(ev["dir"]))
				if dir == -1:
					return {"ok": false, "message": "%s: tick %d: unknown direction \"%s\"" % [name, t, ev["dir"]]}
				inputs.append({"player": int(ev["p"]), "dir": dir})
			var step_result: int = world.step(inputs)
			if step_result != SimulationWorld.OK:
				return {"ok": false, "message": "%s: tick %d: step failed (result %d)" % [name, t, step_result]}

		var record: Dictionary = world.serialize()
		if record["result"] != SimulationWorld.OK:
			return {"ok": false, "message": "%s: tick %d: serialize failed (result %d)" % [name, t, record["result"]]}
		var bytes: PackedByteArray = record["bytes"]

		var checksum_result: Dictionary = SimulationWorld.checksum(bytes)
		if checksum_result["result"] != SimulationWorld.OK:
			return {"ok": false, "message": "%s: tick %d: checksum call failed (result %d)" % [name, t, checksum_result["result"]]}
		if not _checksum_matches(checksum_result["checksum"], String(line["c"])):
			return {"ok": false, "message": "%s: tick %d: checksum mismatch" % [name, t]}

		if line.has("s"):
			var anchor_bytes := _hex_decode(String(line["s"]))
			if bytes != anchor_bytes:
				return {"ok": false, "message": "%s: tick %d: full-state anchor mismatch" % [name, t]}

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


func _corrupt_one_checksum(text: String) -> String:
	var lines := text.split("\n")
	# lines[0] is the header, lines[1] is tick 0 (anchor-only, no checksum
	# to meaningfully corrupt against a step() call) -- corrupt tick 1's
	# plain checksum instead so the failure is unambiguously a checksum
	# mismatch reached via the normal step() path, not an anchor mismatch.
	var line: Dictionary = JSON.parse_string(lines[2])
	var c: String = line["c"]
	var last_digit := c.substr(c.length() - 1, 1)
	line["c"] = c.left(c.length() - 1) + ("1" if last_digit != "1" else "2")
	lines[2] = JSON.stringify(line)
	return "\n".join(lines)


# --- file + checksum helpers ---------------------------------------------


func _read_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text()


func _hex_decode(hex: String) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(hex.length() / 2)
	for i in range(out.size()):
		out[i] = ("0x" + hex.substr(i * 2, 2)).hex_to_int()
	return out


## Splits a (possibly negative, bit-reinterpreted) int64 into its high/low
## 32-bit halves via well-defined bitwise ops only -- see the file header.
func _u64_hi_lo(v: int) -> Array:
	return [(v >> 32) & 0xFFFFFFFF, v & 0xFFFFFFFF]


## Parses a u64 decimal string into the same [hi, lo] shape by accumulating
## digit-by-digit in 32-bit halves, so no intermediate value ever needs more
## than 33 bits and overflow is never a concern.
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

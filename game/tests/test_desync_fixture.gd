extends GdUnitTestSuite

## TASK-054: a lockstep checksum mismatch is captured as a committed
## regression fixture, the same "promote a one-off failure into a permanent
## fixture" pattern task oracle:fuzz's promotion step uses for the JS-oracle
## corpus (docs/corpus-format.md "Promoting a fuzz failure") -- adapted here
## because a lockstep desync is inherently a two-replica artifact (peer_a's
## and peer_b's diverging world states), which the single-actor oracle
## corpus format has no room for. See backlog/decisions/decision-037.
##
## The deliberately-corrupted-peer scenario reuses the exact injection
## technique test_lockstep_session.gd's corrupted-input test already proved
## produces a genuine, detected mismatch (AC#2's "e.g." is explicit that any
## concrete corruption suffices) -- introducing a second, novel corruption
## method here would only be new surface to get wrong for no added coverage.
##
## Regeneration is deliberately manual and opt-in (DESYNC_FIXTURE_REGEN=1),
## never a side effect of a normal `task game:test` run -- mirroring
## reference/oracle/fuzz.mjs's promotion step, which never runs unattended
## either. Every ordinary run instead re-derives the fixture live and diffs
## it against the committed file field-by-field; if a future change to
## core/world.zig, the checksum algorithm, or the lockstep layer itself ever
## alters the recorded checksums/state/input log, this test fails until
## that's accounted for -- the same regression contract test_corpus_replay.gd
## enforces for the single-actor corpus (AC#2's "fails ... until the
## underlying bug is fixed").

const FIXTURE_PATH := "res://tests/desync_fixtures/corrupted_player0_input.json"
const REGEN_ENV_VAR := "DESYNC_FIXTURE_REGEN"

const COLS := 24
const ROWS := 24
const CHECKSUM_INTERVAL := LockstepSession.CHECKSUM_INTERVAL
const INPUT_DELAY := LockstepPeer.INPUT_DELAY

const DIR_UP := SimulationWorld.DIR_UP
const DIR_DOWN := SimulationWorld.DIR_DOWN
const DIR_RIGHT := SimulationWorld.DIR_RIGHT

func test_corrupted_peer_scenario_matches_the_committed_desync_fixture() -> void:
	var fixture := _run_corrupted_peer_scenario()

	if OS.get_environment(REGEN_ENV_VAR) == "1":
		_write_fixture(fixture)

	if not FileAccess.file_exists(FIXTURE_PATH):
		fail("%s does not exist -- regenerate it once with %s=1" % [FIXTURE_PATH, REGEN_ENV_VAR])
		return

	var committed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_PATH))
	if not _values_equal(fixture, committed):
		fail("live desync capture no longer matches the committed fixture at %s" % FIXTURE_PATH)

func _run_corrupted_peer_scenario() -> Dictionary:
	var config := {
		"cols": COLS,
		"rows": ROWS,
		"player_count": 2,
		"wrap": false,
		"rng_seed": [1, 2, 3, 4],
		"speed_source": SimulationWorld.SPEED_SOURCE_SCORE_TABLE,
		"input_delay": INPUT_DELAY,
		"checksum_interval": CHECKSUM_INTERVAL,
	}

	# link_latency=1 both ways: peer_a's round-R send over link_a_to_b
	# delivers at round R+1 -- identical setup to
	# test_lockstep_session.gd's corrupted-input test.
	var link_latency := 1
	var session := LockstepSession.new(_make_world(), _make_world(), link_latency, link_latency)

	var mismatch := {"tick": -1, "checksum_a": 0, "checksum_b": 0}
	session.desync_detected.connect(func(tick: int, checksum_a: int, checksum_b: int) -> void:
		if mismatch["tick"] == -1:
			mismatch["tick"] = tick
			mismatch["checksum_a"] = checksum_a
			mismatch["checksum_b"] = checksum_b
	)

	var injection_round := 10
	for i in range(injection_round):
		session.advance_round()

	var corrupt_for_tick := injection_round + INPUT_DELAY
	session.advance_round()
	_inject_conflicting_player0_direction(session, injection_round, corrupt_for_tick)

	var target_tick := ((corrupt_for_tick / CHECKSUM_INTERVAL) + 2) * CHECKSUM_INTERVAL
	while mismatch["tick"] == -1 and (session.peer_a.tick() < target_tick or session.peer_b.tick() < target_tick):
		session.advance_round()

	assert_int(mismatch["tick"]).is_greater(-1)

	var fixture := session.capture_fixture(mismatch["tick"], mismatch["checksum_a"], mismatch["checksum_b"])
	fixture["config"] = config
	return fixture

static func _make_world() -> SimulationWorld:
	var world := SimulationWorld.new()
	var result := world.init(COLS, ROWS, 2, false, PackedInt32Array([1, 2, 3, 4]), SimulationWorld.SPEED_SOURCE_SCORE_TABLE)
	assert(result == SimulationWorld.OK)
	return world

## Same corruption as test_lockstep_session.gd's
## test_a_corrupted_remote_input_produces_a_checksum_mismatch_and_emits_desync_detected --
## see that test for why the ordering makes the bogus message win.
static func _inject_conflicting_player0_direction(session: LockstepSession, sent_at_step: int, for_tick: int) -> void:
	var bogus_dir := DIR_UP if DIR_UP != DIR_RIGHT else DIR_DOWN
	session.link_a_to_b.send(sent_at_step, for_tick, bogus_dir)

func _write_fixture(fixture: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FIXTURE_PATH.get_base_dir()))
	var file := FileAccess.open(FIXTURE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(fixture, "\t"))
	file.close()

## Recursive equality that treats any two numeric leaves (int or float) as
## equal by value -- Godot's JSON parser always produces float for JSON
## numbers (no integer type in JSON), while the freshly-computed fixture's
## leaves are native GDScript int, so a plain `==` would risk depending on
## exactly how Dictionary/Array equality handles that cross-type case.
## Comparing by explicit float() cast sidesteps the question entirely.
static func _values_equal(a, b) -> bool:
	if a is Dictionary and b is Dictionary:
		if a.keys().size() != b.keys().size():
			return false
		for k in a.keys():
			if not b.has(k) or not _values_equal(a[k], b[k]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in range(a.size()):
			if not _values_equal(a[i], b[i]):
				return false
		return true
	if (a is int or a is float) and (b is int or b is float):
		return float(a) == float(b)
	return a == b

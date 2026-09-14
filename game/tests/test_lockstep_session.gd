extends GdUnitTestSuite

## TASK-053: proves LockstepSession/LockstepPeer/LockstepLink actually
## deliver AC#1 (fixed INPUT_DELAY=3 driving ns_step), AC#2 (a checksum
## exchanged/compared every 30 ticks), and AC#3 (two networked instances
## with simulated latency stay checksum-identical over a multi-minute
## session).
##
## No randi()/randomize() -- game/tests/ is not exempt from
## tools/validate_simulation_boundary.py's global-rng ban, so direction
## choices are driven by a hand-rolled xorshift32 PRNG (pure arithmetic).
##
## "Multi-minute" (AC#3): core/world.zig ticks at BASE_MS=130ms down to
## MIN_MS=55ms as score rises (docs/architecture.md). NUM_TICKS_LONG=6000
## ticks spans 6000*0.055s=330s (5.5min) at the fastest rate and
## 6000*0.130s=780s (13min) at the slowest -- "multi-minute" under either
## bound.

const COLS := 24
const ROWS := 24
const NUM_TICKS_LONG := 6000
const CHECKSUM_INTERVAL := LockstepSession.CHECKSUM_INTERVAL
const INPUT_DELAY := LockstepPeer.INPUT_DELAY

const DIR_UP := SimulationWorld.DIR_UP
const DIR_DOWN := SimulationWorld.DIR_DOWN
const DIR_RIGHT := SimulationWorld.DIR_RIGHT

static func _xorshift32(state: int) -> int:
	state ^= (state << 13) & 0xFFFFFFFF
	state ^= (state >> 17)
	state ^= (state << 5) & 0xFFFFFFFF
	return state & 0xFFFFFFFF

## UP/DOWN (0/1) and LEFT/RIGHT (2/3) are opposite pairs -- XORing with 1
## flips within a pair, matching core/world.zig's DIR_VEC layout.
static func _opposite(dir: int) -> int:
	return dir ^ 1

## Picks a pseudo-random direction that is never the exact reverse of
## current_dir (World.queueDir's only illegal input) -- falls back to
## repeating current_dir, always legal and harmless (LockstepPeer's
## heartbeat design relies on exactly this).
static func _next_legal_dir(rng_value: int, current_dir: int) -> int:
	var candidate := rng_value % 4
	if candidate == _opposite(current_dir):
		return current_dir
	return candidate

static func _make_world() -> SimulationWorld:
	var world := SimulationWorld.new()
	var result := world.init(COLS, ROWS, 2, false, PackedInt32Array([1, 2, 3, 4]), SimulationWorld.SPEED_SOURCE_SCORE_TABLE)
	assert(result == SimulationWorld.OK)
	return world

func test_two_peers_with_bounded_latency_stay_checksum_identical_over_a_long_session() -> void:
	var session := LockstepSession.new(_make_world(), _make_world(), 2, 1)

	var rng_a := 0x1234abcd
	var rng_b := 0x87654321
	var dir_a := DIR_RIGHT
	var dir_b := DIR_RIGHT
	var checks_performed := 0

	for i in range(NUM_TICKS_LONG):
		rng_a = _xorshift32(rng_a)
		rng_b = _xorshift32(rng_b)
		# Only redirect occasionally -- most real play is a long straight
		# run punctuated by turns, and this also exercises plenty of
		# heartbeat-repeats-of-the-current-direction ticks.
		if rng_a % 5 == 0:
			dir_a = _next_legal_dir(rng_a, dir_a)
			session.queue_direction(0, dir_a)
		if rng_b % 7 == 0:
			dir_b = _next_legal_dir(rng_b, dir_b)
			session.queue_direction(1, dir_b)

		var result := session.advance_round()
		if result["checked"]:
			checks_performed += 1
			assert_bool(result["match"]).is_true()

	# Asymmetric latency (2 vs 1) means the two peers' tick counts can be
	# transiently offset by a tick at any given round -- that's not a
	# desync, only a boundary artifact of when each side's last message
	# happened to land, and advance_round() already only compares checksums once
	# tick_a == tick_b. What actually proves AC#3 is the per-iteration
	# assertion above: never once did a comparison see a real mismatch.
	assert_int(checks_performed).is_greater(0)

func test_latency_at_the_input_delay_budget_never_permanently_stalls() -> void:
	var session := LockstepSession.new(_make_world(), _make_world(), INPUT_DELAY, INPUT_DELAY)
	var num_rounds := 50

	for i in range(num_rounds):
		session.advance_round()

	assert_int(session.peer_a.tick()).is_equal(num_rounds)
	assert_int(session.peer_b.tick()).is_equal(num_rounds)

func test_latency_over_the_input_delay_budget_stalls_but_recovers() -> void:
	var over_budget_latency := INPUT_DELAY + 2
	var session := LockstepSession.new(_make_world(), _make_world(), over_budget_latency, over_budget_latency)
	var num_rounds := 60

	var tick_before_tail := 0
	for i in range(num_rounds):
		session.advance_round()
		if i == num_rounds - 11:
			tick_before_tail = session.peer_a.tick()

	# Falls behind the round count (latency exceeds the hidden budget)...
	assert_int(session.peer_a.tick()).is_less(num_rounds)
	# ...but the two peers never desync from each other...
	assert_int(session.peer_a.tick()).is_equal(session.peer_b.tick())
	# ...and once the pipeline is full, it proceeds at a steady 1 tick per
	# round rather than stalling forever: the last 10 rounds gained exactly
	# 10 ticks.
	assert_int(session.peer_a.tick() - tick_before_tail).is_equal(10)

func test_a_corrupted_remote_input_produces_a_checksum_mismatch_and_emits_desync_detected() -> void:
	# latency 1 both ways: peer_a's round-R send over link_a_to_b delivers
	# at round R+1.
	var link_latency := 1
	var session := LockstepSession.new(_make_world(), _make_world(), link_latency, link_latency)

	# A Dictionary, not scalar locals: GDScript lambdas capture enclosing
	# locals by value at creation time, so reassigning a captured scalar
	# inside the lambda would never be visible out here -- mutating a
	# captured container's contents is what actually propagates.
	var received := {"tick": -1, "a": 0, "b": 0}
	session.desync_detected.connect(func(tick: int, a: int, b: int) -> void:
		received["tick"] = tick
		received["a"] = a
		received["b"] = b
	)

	var injection_round := 10
	for i in range(injection_round):
		session.advance_round()

	# peer_a's advance_round() at round `injection_round` (about to run) will
	# heartbeat-send player 0's real (unchanged) direction for
	# for_tick = injection_round + INPUT_DELAY, arriving at peer_b via
	# link_a_to_b at round injection_round + link_latency. Appending a
	# second, wrong-direction message for the SAME for_tick with the SAME
	# delivery round -- but appended to the link's queue after peer_a's own
	# real send happens this round -- makes it win the last-write-wins
	# overwrite in LockstepPeer._remote_input once both are ingested
	# together, corrupting only peer_b's replica of player 0's input
	# without touching peer_a's own (authoritative) copy.
	var corrupt_for_tick := injection_round + INPUT_DELAY
	session.advance_round()
	_inject_conflicting_player0_direction(session, injection_round, corrupt_for_tick)

	# Run comfortably past the next CHECKSUM_INTERVAL boundary so the now-
	# diverged tick actually gets compared.
	var target_tick := ((corrupt_for_tick / CHECKSUM_INTERVAL) + 2) * CHECKSUM_INTERVAL
	var saw_mismatch := false
	while session.peer_a.tick() < target_tick or session.peer_b.tick() < target_tick:
		var result := session.advance_round()
		if result["checked"] and not result["match"]:
			saw_mismatch = true

	assert_bool(saw_mismatch).is_true()
	assert_int(received["tick"]).is_greater(-1)
	assert_bool(received["a"] != received["b"]).is_true()

## Appends a second, wrong-direction message for a for_tick peer_a's real
## heartbeat already targeted this same round -- see the comment above this
## test for why the ordering here makes it win.
static func _inject_conflicting_player0_direction(session: LockstepSession, sent_at_step: int, for_tick: int) -> void:
	var bogus_dir := DIR_UP if DIR_UP != DIR_RIGHT else DIR_DOWN
	session.link_a_to_b.send(sent_at_step, for_tick, bogus_dir)

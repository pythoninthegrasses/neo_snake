extends GdUnitTestSuite

## TASK-031: tick_driver.gd never reads a clock or inspects world state --
## advance_frame is a pure forwarding call onto SimulationWorld.pump (which
## itself forwards to ns_pump, core/world.zig's already-tested accumulator).
## These numbers are chosen to cross-check directly against
## core/world.zig's own "pump clamps to MAX_STEPS per call and carries the
## remainder over" test: a fresh world's score is 0, so its tick period is
## TICK_PERIOD_US[0] = 130000 us, and ns_pump's MAX_DT_US clamp is 64000 us.

const SOURCE_PATH := "res://simulation/tick_driver.gd"


func test_advance_frame_never_reads_a_clock() -> void:
	var source := FileAccess.get_file_as_string(SOURCE_PATH)
	assert_str(source).not_contains("OS.get_ticks")
	assert_str(source).not_contains("Time.get_ticks")
	assert_str(source).not_contains("Time.get_unix_time")


## Feeds a synthetic per-frame dt sequence -- including a 200ms hitch well
## past ns_pump's 64ms MAX_DT_US clamp, and two frames gated closed -- and
## asserts the exact resulting tick count at every step, matching ns_pump's
## documented clamp-and-carry behavior with no additional catch-up logic
## layered on top by tick_driver itself (AC#3).
func test_advance_frame_matches_ns_pumps_clamp_behavior_across_a_hitch() -> void:
	var world := SimulationWorld.new()
	var init_result: int = world.init(24, 24, 1, false, PackedInt32Array([1, 2, 3, 4]), SimulationWorld.SPEED_SOURCE_SCORE_TABLE)
	assert_int(init_result).is_equal(SimulationWorld.OK)

	# menu -> playing without consuming a tick (queueDir never itself
	# advances, docs/abi-header.md); .right is the fresh snake's own
	# direction, so this isn't a reversal the guard would reject.
	var queue_result: int = world.queue_dir(0, SimulationWorld.DIR_RIGHT)
	assert_int(queue_result).is_equal(SimulationWorld.OK)

	# acc 0 -> 64000 (no clamp needed, exactly at MAX_DT_US) -> 0/130000 ticks
	_assert_steps(world, 64.0, true, true, 0)
	# acc 64000 -> 128000 -> still short of one 130000us tick
	_assert_steps(world, 64.0, true, true, 0)
	# 200ms hitch clamped to 64000us: acc 128000+64000=192000 -> 1 tick,
	# 62000us remainder carried (matches core/world.zig's own worked
	# carry-over example for this exact period).
	_assert_steps(world, 200.0, true, true, 1)

	# Gated closed: dt must be discarded outright, not banked.
	_assert_steps(world, 100.0, false, true, 0)
	_assert_steps(world, 100.0, true, false, 0)

	# If the two gated-closed frames above had leaked into the accumulator,
	# these two frames would together produce far more than exactly one
	# more tick with a zero remainder.
	_assert_steps(world, 64.0, true, true, 0) # acc 62000 -> 126000
	_assert_steps(world, 4.0, true, true, 1) # acc 126000 -> 130000 -> 1 tick, remainder 0

	var view: Dictionary = world.player_view_get(0)
	assert_int(view["result"]).is_equal(SimulationWorld.OK)
	assert_int(view["score"]).is_equal(0)


func _assert_steps(world: SimulationWorld, raw_frame_ms: float, running: bool, gate: bool, expected_steps: int) -> void:
	var result := TickDriver.advance_frame(world, raw_frame_ms, running, gate)
	assert_int(result["result"]).is_equal(SimulationWorld.OK)
	assert_int(result["steps"]).is_equal(expected_steps)

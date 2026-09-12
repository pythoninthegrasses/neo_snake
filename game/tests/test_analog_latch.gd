extends GdUnitTestSuite

## TASK-033 AC#3: confirms the 0.55 fire / 0.35 release hysteresis and,
## specifically, that jitter sitting anywhere between the two thresholds
## never produces a second fire for the same push.

func test_crossing_fire_threshold_fires_once() -> void:
	var latch := AnalogLatch.new()
	assert_int(latch.feed(0.6, 1, 2)).is_equal(1)


func test_jitter_between_release_and_fire_thresholds_does_not_refire() -> void:
	var latch := AnalogLatch.new()
	assert_int(latch.feed(0.6, 1, 2)).is_equal(1)
	# Still above RELEASE_THRESHOLD (0.35) on every subsequent sample, so
	# the latch never releases and none of these may fire again.
	assert_int(latch.feed(0.58, 1, 2)).is_equal(-1)
	assert_int(latch.feed(0.4, 1, 2)).is_equal(-1)
	assert_int(latch.feed(0.9, 1, 2)).is_equal(-1)
	assert_int(latch.feed(0.36, 1, 2)).is_equal(-1)


func test_dropping_below_release_threshold_allows_a_fresh_fire() -> void:
	var latch := AnalogLatch.new()
	assert_int(latch.feed(0.6, 1, 2)).is_equal(1)
	assert_int(latch.feed(0.2, 1, 2)).is_equal(-1)
	assert_int(latch.feed(0.6, 1, 2)).is_equal(1)


func test_negative_direction_uses_its_own_latch_independently() -> void:
	var latch := AnalogLatch.new()
	assert_int(latch.feed(-0.6, 1, 2)).is_equal(2)
	assert_int(latch.feed(-0.5, 1, 2)).is_equal(-1)
	assert_int(latch.feed(0.0, 1, 2)).is_equal(-1)
	assert_int(latch.feed(-0.6, 1, 2)).is_equal(2)


func test_values_below_fire_threshold_never_fire() -> void:
	var latch := AnalogLatch.new()
	assert_int(latch.feed(0.1, 1, 2)).is_equal(-1)
	assert_int(latch.feed(-0.5, 1, 2)).is_equal(-1)
	assert_int(latch.feed(0.54, 1, 2)).is_equal(-1)

extends GdUnitTestSuite

## TASK-033 AC#4: SwipeGesture is pure logic (no Node dependency, exercised
## here with no scene tree at all) and its board-scaled threshold formula
## is covered directly.

func test_threshold_scales_with_cell_size_above_the_oracle_floor() -> void:
	# cell_px * fraction (40.0 * 0.5 = 20.0) is below the oracle's original
	# 24px minimum (snake.html:613), so the floor wins.
	assert_float(SwipeGesture.threshold_px(40.0, 0.5)).is_equal_approx(24.0, 0.0001)
	# cell_px * fraction (60.0 * 0.5 = 30.0) exceeds the floor, so the
	# board-scaled value wins.
	assert_float(SwipeGesture.threshold_px(60.0, 0.5)).is_equal_approx(30.0, 0.0001)


func test_update_does_not_fire_below_threshold_on_either_axis() -> void:
	var gesture := SwipeGesture.new()
	gesture.start(Vector2(100.0, 100.0))
	assert_int(gesture.update(Vector2(110.0, 105.0), 40.0, 0.5)).is_equal(-1)


func test_update_fires_dominant_axis_direction_matching_the_oracles_sign_convention() -> void:
	var right := SwipeGesture.new()
	right.start(Vector2(100.0, 100.0))
	assert_int(right.update(Vector2(140.0, 105.0), 40.0, 0.5)).is_equal(SimulationWorld.DIR_RIGHT)

	var left := SwipeGesture.new()
	left.start(Vector2(100.0, 100.0))
	assert_int(left.update(Vector2(60.0, 95.0), 40.0, 0.5)).is_equal(SimulationWorld.DIR_LEFT)

	var down := SwipeGesture.new()
	down.start(Vector2(100.0, 100.0))
	assert_int(down.update(Vector2(105.0, 140.0), 40.0, 0.5)).is_equal(SimulationWorld.DIR_DOWN)

	var up := SwipeGesture.new()
	up.start(Vector2(100.0, 100.0))
	assert_int(up.update(Vector2(95.0, 60.0), 40.0, 0.5)).is_equal(SimulationWorld.DIR_UP)


func test_firing_consumes_the_gesture_so_further_movement_does_not_refire() -> void:
	var gesture := SwipeGesture.new()
	gesture.start(Vector2(100.0, 100.0))
	assert_int(gesture.update(Vector2(140.0, 100.0), 40.0, 0.5)).is_equal(SimulationWorld.DIR_RIGHT)
	assert_int(gesture.update(Vector2(200.0, 100.0), 40.0, 0.5)).is_equal(-1)


func test_touchend_resets_tracking_without_firing() -> void:
	var gesture := SwipeGesture.new()
	gesture.start(Vector2(100.0, 100.0))
	gesture.end()
	assert_int(gesture.update(Vector2(200.0, 100.0), 40.0, 0.5)).is_equal(-1)

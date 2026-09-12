class_name AnalogLatch
extends RefCounted

## Hysteresis latch for one analog stick axis, converting a continuous
## [-1, 1] axis value into discrete direction fires without double-firing
## while the stick jitters around a single threshold (TASK-033 AC#3).
## reference/snake.html has no gamepad support at all (its `KEY` table and
## touch handling are the only input paths, snake.html:578-618) -- this is
## a wholly new capability with no oracle behavior to deviate from, so it
## needs no backlog/decisions/ entry per DoD#2 (nothing to record a
## deviation *from*).
##
## Fire threshold (0.55) and release threshold (0.35) are deliberately far
## apart: once latched, the axis must fall all the way back under 0.35
## before a fresh push past 0.55 can fire again, so noise sitting anywhere
## between the two thresholds never produces a second fire.

const FIRE_THRESHOLD := 0.55
const RELEASE_THRESHOLD := 0.35

var _latched_positive := false
var _latched_negative := false

## Feeds one new axis sample and returns the direction to fire
## (positive_dir or negative_dir, caller-supplied so this stays direction-
## agnostic across the X and Y stick axes), or -1 if this sample doesn't
## cross into a fresh fire.
func feed(value: float, positive_dir: int, negative_dir: int) -> int:
	if _latched_positive:
		if value < RELEASE_THRESHOLD:
			_latched_positive = false
		return -1
	if _latched_negative:
		if value > -RELEASE_THRESHOLD:
			_latched_negative = false
		return -1
	if value >= FIRE_THRESHOLD:
		_latched_positive = true
		return positive_dir
	if value <= -FIRE_THRESHOLD:
		_latched_negative = true
		return negative_dir
	return -1

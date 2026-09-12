class_name SwipeGesture
extends RefCounted

## Pure port of reference/snake.html's swipe handling (touchstart/touchmove/
## touchend, snake.html:603-618) -- no Node dependency (AC#4), so it can be
## unit-tested without a scene tree. The oracle's fixed 24 CSS-pixel
## threshold becomes board-scaled per backlog/decisions/decision-011: a
## fraction of the board's current cell size (content/tuning.json's
## input.swipe_threshold_cell_fraction, already 0.5), floored at the
## oracle's original 24px so the swipe never reads as too sensitive on a
## low-density screen. This reuses tuning.json's already-wired cell-
## fraction field rather than a second, conflicting board-pixel formula.

const ORACLE_MIN_THRESHOLD_PX := 24.0

var _start := Vector2.ZERO
var _tracking := false

static func threshold_px(cell_px: float, cell_fraction: float) -> float:
	return maxf(ORACLE_MIN_THRESHOLD_PX, cell_px * cell_fraction)

## touchstart (snake.html:605-608): record the gesture's origin and start
## tracking.
func start(pos: Vector2) -> void:
	_start = pos
	_tracking = true

## touchmove (snake.html:609-617): returns one of SimulationWorld.DIR_*
## once the drag from start() has crossed threshold_px on its dominant
## axis, or -1 if still below threshold or no gesture is being tracked.
## Firing consumes the gesture (mirrors the oracle's `sating = false`) so
## a single swipe cannot re-fire on further movement -- call start() again
## to begin a new one.
func update(pos: Vector2, cell_px: float, cell_fraction: float) -> int:
	if not _tracking:
		return -1
	var delta := pos - _start
	var threshold := threshold_px(cell_px, cell_fraction)
	if absf(delta.x) < threshold and absf(delta.y) < threshold:
		return -1
	_tracking = false
	if absf(delta.x) > absf(delta.y):
		return SimulationWorld.DIR_RIGHT if delta.x > 0 else SimulationWorld.DIR_LEFT
	return SimulationWorld.DIR_DOWN if delta.y > 0 else SimulationWorld.DIR_UP

## touchend (snake.html:618): abandon the current gesture without firing.
func end() -> void:
	_tracking = false

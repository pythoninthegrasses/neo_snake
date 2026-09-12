class_name TickDriver
extends RefCounted

## Deliberately not a Node: no _physics_process (variable step re-read after
## each tick, engine-owned catch-up cap, forces the sim onto the tree) and no
## Timer (fires on a fixed interval with no accumulator, so it discards the
## remainder instead of carrying it -- a hitch loses ticks the oracle's own
## accumulator would still run). advance_frame never reads a clock or
## inspects world/game state itself: raw_frame_ms, running, and gate are all
## caller-supplied so this stays a pure forwarding call onto
## SimulationWorld.pump / ns_pump (AC#3). application/run/delta_smoothing
## must stay false (decision-014) or raw_frame_ms itself would already be an
## averaged number by the time it gets here, defeating ns_pump's own
## MAX_DT_US clamp math.

## running: whether the app/scene tree is currently processing frames at all
## (false while engine-paused, e.g. a modal settings/quit overlay).
## gate: whether the game's own state currently permits ticking (e.g. the
## world status is playing). Either being false discards this frame's dt
## outright -- it is never banked for a later call, matching ns_pump's own
## "not playing" no-op rather than silently accumulating backlog time.
static func advance_frame(world: SimulationWorld, raw_frame_ms: float, running: bool, gate: bool) -> Dictionary:
	if not running or not gate:
		return {"result": SimulationWorld.OK, "steps": 0}
	var dt_us := int(round(raw_frame_ms * 1000.0))
	return world.pump(dt_us)

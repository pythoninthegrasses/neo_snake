class_name LockstepSession
extends RefCounted

## Owns both sides of a 2-player lockstep match end-to-end (TASK-053): two
## LockstepPeer instances, each wrapping its own SimulationWorld, connected
## by two LockstepLinks (one per direction) that simulate network latency.
##
## Call advance_round() once per simulated real-time step to drive both peers.
## Whenever both peers have reached the same tick and a CHECKSUM_INTERVAL
## boundary has been crossed since the last comparison, their checksums are
## compared; a mismatch emits desync_detected -- the single named seam
## TASK-054's desync-capture fixture hooks, rather than something inlined
## ad hoc at each call site.
##
## Comparison triggers on "crossed a boundary", not "landed exactly on a
## multiple of CHECKSUM_INTERVAL": a peer that stalls (remote input for its
## next tick hasn't arrived, latency_ticks > LockstepPeer.INPUT_DELAY) and
## then catches up can simulate several ticks in one advance_round() call,
## jumping straight past an exact multiple. Checking at the first
## opportunity after a boundary is crossed still satisfies "every 30 ticks"
## without requiring an exact-alignment guarantee this design doesn't make.

signal desync_detected(tick: int, peer_a_checksum: int, peer_b_checksum: int)

const CHECKSUM_INTERVAL := 30

var peer_a: LockstepPeer
var peer_b: LockstepPeer

## Exposed so a fixture (this task's own desync test, or TASK-054's capture
## harness) can inject a message directly -- e.g. a duplicate/corrupted
## entry for a for_tick already in flight -- without reaching into a
## peer's underscore-prefixed internals.
var link_a_to_b: LockstepLink
var link_b_to_a: LockstepLink

var _last_interval_checked: int = -1

func _init(world_a: SimulationWorld, world_b: SimulationWorld, latency_a_to_b: int, latency_b_to_a: int) -> void:
	link_a_to_b = LockstepLink.new(latency_a_to_b)
	link_b_to_a = LockstepLink.new(latency_b_to_a)
	peer_a = LockstepPeer.new(world_a, 0, 1, link_a_to_b, link_b_to_a)
	peer_b = LockstepPeer.new(world_b, 1, 0, link_b_to_a, link_a_to_b)

	# Both worlds start .menu (decision-015); the first legal queue_dir
	# transitions straight to .playing without consuming a tick
	# (core/world.zig's queueDir -> start()), so both peers begin
	# simulating from tick 0 in lockstep, matching each other exactly.
	world_a.queue_dir(0, SimulationWorld.DIR_RIGHT)
	world_b.queue_dir(0, SimulationWorld.DIR_RIGHT)

func queue_direction(player: int, dir: int) -> void:
	if player == peer_a.local_player:
		peer_a.queue_local_direction(dir)
	else:
		peer_b.queue_local_direction(dir)

## Advances one real-time step on both peers, then compares checksums if a
## CHECKSUM_INTERVAL boundary was just crossed on a tick both peers share.
## Returns {"tick": int, "checked": bool, "match": bool} -- "checked" is
## false when no comparison happened this call (peers not yet realigned,
## or no boundary crossed since the last check).
func advance_round() -> Dictionary:
	peer_a.advance_round()
	peer_b.advance_round()

	var tick_a := peer_a.tick()
	var tick_b := peer_b.tick()
	if tick_a == tick_b and tick_a > 0:
		var interval := tick_a / CHECKSUM_INTERVAL
		if interval > _last_interval_checked:
			_last_interval_checked = interval
			var checksum_a := peer_a.checksum()
			var checksum_b := peer_b.checksum()
			var checksums_match := checksum_a == checksum_b
			if not checksums_match:
				desync_detected.emit(tick_a, checksum_a, checksum_b)
			return {"tick": tick_a, "checked": true, "match": checksums_match}

	return {"tick": tick_a, "checked": false, "match": true}

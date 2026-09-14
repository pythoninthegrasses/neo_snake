class_name LockstepLink
extends RefCounted

## In-process stand-in for a real network transport (TASK-053): delivers a
## message only after `latency_ticks` local steps have elapsed since it was
## sent, modeling network latency deterministically for testing -- no real
## sockets involved. One LockstepLink is one direction only; a
## LockstepSession wires up two (one per peer-to-peer direction).
##
## Both peers call LockstepPeer.advance_round() the same number of times, in
## lockstep with each other (one real-time step per call), so "step S" means
## the same wall-clock moment on both sides -- that shared step counter is
## what latency_ticks is measured in, not real time.

var _latency_ticks: int
var _inbox: Array[Dictionary] = []

func _init(latency_ticks: int) -> void:
	_latency_ticks = latency_ticks

## sent_at_step: the sender's own step counter when this was decided.
## for_tick: the simulation tick this input takes effect at (the sender's
## for_tick = sent_at_step + LockstepPeer.INPUT_DELAY).
func send(sent_at_step: int, for_tick: int, dir: int) -> void:
	_inbox.append({"deliver_at_step": sent_at_step + _latency_ticks, "for_tick": for_tick, "dir": dir})

## Returns (and removes) every message deliverable at or before
## current_step, in send order -- a reliable, ordered channel; the only
## unreliability this models is delay, never loss or reordering.
func receive_ready(current_step: int) -> Array[Dictionary]:
	var ready: Array[Dictionary] = []
	var remaining: Array[Dictionary] = []
	for entry in _inbox:
		if entry["deliver_at_step"] <= current_step:
			ready.append(entry)
		else:
			remaining.append(entry)
	_inbox = remaining
	return ready

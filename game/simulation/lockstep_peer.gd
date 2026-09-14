class_name LockstepPeer
extends RefCounted

## Drives one side of a lockstep match by calling SimulationWorld.step()
## directly (TASK-053) -- never queue_dir()/pump(), which
## include/neo_snake.h documents as local-play conveniences layered on top
## of ns_step, the frozen lockstep primitive (decision-020) a netcode layer
## must drive itself, one call per confirmed tick.
##
## INPUT_DELAY ticks: a direction decided at real-time step S does not take
## effect until tick S + INPUT_DELAY, not immediately -- this is what lets a
## bounded amount of network latency get hidden without rollback (rollback
## is deliberately out of scope here: docs/rng.md's single shared RNG
## stream, drawn in ascending player-index order, cannot be replayed from an
## arbitrary mid-point the way a per-player stream could, so this codebase
## commits to lockstep only, per decision-034). As long as a link's
## latency_ticks <= INPUT_DELAY, the remote input for a given tick always
## arrives before that tick is due to simulate and advance_round() never stalls.
##
## Every local decision is resent every step as a heartbeat, whether or not
## the direction actually changed, so a receiver can always tell "no message
## yet" (network still catching up) apart from "no change decided".
## Resending an unchanged direction is always legal: World.queueDir's
## reversal-reject only rejects the exact opposite of the current direction,
## never a repeat of it (core/world.zig).

const INPUT_DELAY := 3
const DEFAULT_DIR := SimulationWorld.DIR_RIGHT

var world: SimulationWorld
var local_player: int
var remote_player: int

var _outgoing: LockstepLink
var _incoming: LockstepLink

var _step: int = 0
var _next_sim_tick: int = 0
var _pending_direction: int = DEFAULT_DIR
var _local_input: Dictionary = {}   # tick -> dir
var _remote_input: Dictionary = {}  # tick -> dir
var _input_log: Array[Dictionary] = []  # {tick, player, dir}, in application order

func _init(world: SimulationWorld, local_player: int, remote_player: int, outgoing: LockstepLink, incoming: LockstepLink) -> void:
	self.world = world
	self.local_player = local_player
	self.remote_player = remote_player
	_outgoing = outgoing
	_incoming = incoming
	# Bootstrap: for_tick = step + INPUT_DELAY means the first INPUT_DELAY
	# ticks (0 ..< INPUT_DELAY) are never assigned by either side's own
	# decisions. Both peers seed the same default here, matching
	# core/world.zig's own reset default (dir = .right), so no network
	# round trip is needed to agree on it.
	for t in range(INPUT_DELAY):
		_local_input[t] = DEFAULT_DIR
		_remote_input[t] = DEFAULT_DIR

## Records the local player's desired direction; takes effect INPUT_DELAY
## ticks after the next advance_round() call, not immediately. Persists until
## changed again -- advance_round() resends it every step regardless.
func queue_local_direction(dir: int) -> void:
	_pending_direction = dir

## The highest simulation tick this peer's world has actually reached.
func tick() -> int:
	return _next_sim_tick

func checksum() -> int:
	var record: Dictionary = world.serialize()
	return SimulationWorld.checksum(record["bytes"])["checksum"]

func input_log() -> Array[Dictionary]:
	return _input_log.duplicate(true)

## Advances exactly one real-time step:
## 1. ingests any remote messages the network has delivered by now,
## 2. decides and sends this step's own local input (INPUT_DELAY ticks
##    ahead of this step),
## 3. simulates every tick whose local AND remote input are now both known
##    -- zero, one, or (after a stall clears) several ticks at once.
func advance_round() -> void:
	for entry in _incoming.receive_ready(_step):
		_remote_input[entry["for_tick"]] = entry["dir"]

	var for_tick := _step + INPUT_DELAY
	_local_input[for_tick] = _pending_direction
	_outgoing.send(_step, for_tick, _pending_direction)

	while _local_input.has(_next_sim_tick) and _remote_input.has(_next_sim_tick):
		var local_dir: int = _local_input[_next_sim_tick]
		var remote_dir: int = _remote_input[_next_sim_tick]
		world.step([
			{"player": local_player, "dir": local_dir},
			{"player": remote_player, "dir": remote_dir},
		])
		_input_log.append({"tick": _next_sim_tick, "player": local_player, "dir": local_dir})
		_input_log.append({"tick": _next_sim_tick, "player": remote_player, "dir": remote_dir})
		_local_input.erase(_next_sim_tick)
		_remote_input.erase(_next_sim_tick)
		_next_sim_tick += 1

	_step += 1

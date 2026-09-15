class_name StartDirections
extends RefCounted

## Picks each player's heading for a fresh run (a Godot-layer choice, not a
## simulation rule -- see below). Draws from its own
## RandomNumberGenerator rather than the engine's global RNG: a private
## stream can be pinned to a seed, which is what lets a test assert an exact
## sequence instead of only asserting distribution over many draws.
## RandomNumberGenerator.new() seeds itself unpredictably, so live play
## still varies per launch with no randomize() call.
##
## Lives inside game/simulation/ because seeding an RNG at all is something
## tools/validate_simulation_boundary.py's global-rng rule only allows here
## -- same reason seed_source.gd does.
##
## This RNG is independent of the simulation's own seeded stream
## (core/rng.zig, docs/rng.md), which stays reserved for food placement and
## must not be perturbed: the committed corpus pins it byte-for-byte.
##
## LEFT is absent from LEGAL, and that is a spawn-geometry fact rather than
## a preference. core/world.zig's reset() lays every snake out horizontally
## head-first -- cells (8, cy), (7, cy), (6, cy) -- so a snake told to go
## left would move its head onto its own neck and die on tick one.
## core/world.zig's queueDir rejects it for exactly that reason (the
## "no instant 180" guard, reading dir == .right at spawn). Randomizing over
## all four directions would mean laying the body out along the chosen
## heading, which is a core/world.zig change, and core's spawn is pinned
## byte-for-byte against reference/oracle/sim.mjs by the committed corpus
## (docs/corpus-format.md). So "fully random" here means uniform over the
## three headings a freshly spawned snake can actually survive.
const LEGAL: Array[int] = [
	SimulationWorld.DIR_UP,
	SimulationWorld.DIR_DOWN,
	SimulationWorld.DIR_RIGHT,
]

## Both players spawn in the same column (x = 8) with player 0 above player
## 1 -- decision-034's `cy(i) = rows * (i + 1) / (player_count + 1)`. So the
## single way two snakes can start pointed at each other is player 0 heading
## down into player 1 heading up; every other pairing is parallel or facing
## away. Nothing else needs excluding.
static func choices_for(player: int, p0_dir: int) -> Array[int]:
	if player == 0 or p0_dir != SimulationWorld.DIR_DOWN:
		return LEGAL.duplicate()
	var choices := LEGAL.duplicate()
	choices.erase(SimulationWorld.DIR_UP)
	return choices

static var _rng := RandomNumberGenerator.new()

## Pins the draw sequence. Tests only -- live play leaves the generator on
## its own unpredictable startup seed.
static func set_seed(value: int) -> void:
	_rng.seed = value

## One heading per player, indexed by player number.
static func pick(player_count: int) -> Array[int]:
	var dirs: Array[int] = []
	for player in player_count:
		var choices := choices_for(player, dirs[0] if player > 0 else -1)
		dirs.append(choices[_rng.randi() % choices.size()])
	return dirs

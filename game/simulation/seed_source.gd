class_name SeedSource
extends RefCounted

## Generates a fresh rng_seed for live play (SimulationWorld.init's
## rng_seed parameter, a 4-word PackedInt32Array per docs/rng.md). Calls
## randi() itself so it must live inside game/simulation/ --
## tools/validate_simulation_boundary.py's global-rng rule bans any
## randi()/randf()/randomize()/seed() call outside this directory. Retries
## on an all-zero draw: docs/rng.md documents an all-zero seed as a
## degenerate splitmix64 state.

static func fresh() -> PackedInt32Array:
	var words: PackedInt32Array
	while true:
		words = PackedInt32Array([randi(), randi(), randi(), randi()])
		if words[0] != 0 or words[1] != 0 or words[2] != 0 or words[3] != 0:
			break
	return words

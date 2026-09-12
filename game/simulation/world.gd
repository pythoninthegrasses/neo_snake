class_name SimulationWorld
extends RefCounted

## The only .gd file in the repo allowed to reference NeoSnakeWorld (TASK-027)
## -- every other script goes through this wrapper instead. Each method here
## forwards to exactly one NeoSnakeWorld method; no simulation logic is
## reimplemented here.

## Re-exported NeoSnakeWorld result/enum constants, so callers outside this
## file (e.g. game/tests/test_corpus_replay.gd) never need to reference
## NeoSnakeWorld directly just to check a result code or build an input.
const OK := NeoSnakeWorld.NS_OK
const DIR_UP := NeoSnakeWorld.NS_DIR_UP
const DIR_DOWN := NeoSnakeWorld.NS_DIR_DOWN
const DIR_LEFT := NeoSnakeWorld.NS_DIR_LEFT
const DIR_RIGHT := NeoSnakeWorld.NS_DIR_RIGHT
const SPEED_SOURCE_SCORE_TABLE := NeoSnakeWorld.NS_SPEED_SOURCE_SCORE_TABLE

var _world: NeoSnakeWorld = NeoSnakeWorld.new()

func init(cols: int, rows: int, player_count: int, wrap: bool, rng_seed: PackedInt32Array, speed_source: int) -> int:
	return _world.init(cols, rows, player_count, wrap, rng_seed, speed_source)

func reset() -> int:
	return _world.reset()

func queue_dir(player: int, dir: int) -> int:
	return _world.queue_dir(player, dir)

func step(inputs: Array) -> int:
	return _world.step(inputs)

func pump(dt_us: int) -> Dictionary:
	return _world.pump(dt_us)

func player_view_get(player: int) -> Dictionary:
	return _world.player_view_get(player)

func body_copy(player: int) -> Dictionary:
	return _world.body_copy(player)

func canon_len() -> int:
	return _world.canon_len()

func serialize() -> Dictionary:
	return _world.serialize()

func deserialize(bytes: PackedByteArray) -> int:
	return _world.deserialize(bytes)

static func checksum(bytes: PackedByteArray) -> Dictionary:
	return NeoSnakeWorld.checksum(bytes)

func event_count() -> int:
	return _world.event_count()

func event_drain(capacity: int) -> Dictionary:
	return _world.event_drain(capacity)

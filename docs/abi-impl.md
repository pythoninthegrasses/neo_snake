# `core/abi.zig` implementation notes

`docs/abi-header.md` explains what `include/neo_snake.h` (TASK-023) declares and why. This doc
covers the judgment calls `core/abi.zig` (TASK-024) makes filling that contract in — places the
header deliberately left open, or that only became concrete once real `core/world.zig`,
`core/rng.zig`, and `core/canon.zig` code had to be wired behind it.

## `player_count` supports up to 2 (TASK-051)

`core/world.zig`'s `World` originally had no per-player dimension — `dir`, `next_dir`, `score`, the
cell buffer, were all scalar, genuinely single-player. `include/neo_snake.h` had always anticipated
multiplayer (`ns_config.player_count`, every per-player-indexed function), and freeze #1
(`docs/abi-decisions.md`) fixed what a multiplayer ABI must look like once real per-player state
existed, but didn't require building it until something needed it. `backlog/decisions/decision-020`
was the interim precedent: a minimal two-player primitive scoped narrowly to one Tier-B fuzz
invariant, explicitly not touching `core/world.zig` and explicitly not a preview of the real
multiplayer design.

TASK-051 (m-8, local 2-player) is that "something" — `core/world.zig` now carries a real
per-player dimension (`PlayerState`, `MAX_PLAYERS = 2`), and `core/abi.zig` defines
`MAX_SUPPORTED_PLAYERS: u8 = world.MAX_PLAYERS` (currently 2, not N — YAGNI, matching the only AC
that has ever needed a number). `ns_world_init` rejects any `player_count` outside `1..=
MAX_SUPPORTED_PLAYERS` with `NS_ERR_INVALID_ARGUMENT`, the same "additive later, not a rewrite"
shape as the header's own `speed_source` field, and additionally rejects `player_count > 1` on a
board with `rows <= 8` (too short for two players' starting snakes to avoid overlapping under the
starting-row spacing formula). Every player-index bounds check (`ns_queue_dir`, `ns_step`,
`ns_player_view_get`, `ns_body_copy`) compares against `WorldStorage.player_count`, a value stored
at init time, not a literal `1` — loosening the cap further only changes what `ns_world_init`
accepts, not any call site. The actual collision/status/win semantics for `player_count == 2` are
`backlog/decisions/decision-034`, not this doc — this section only covers the ABI-boundary
plumbing. `fuzz_seeds.zig`'s `decision-020` primitive is untouched and remains a separate, narrower
fixture.

## Telling win from die apart

`core/world.zig`'s `win()` and `die()` both just set `status = .dead` — identical, no signal in the
resulting state distinguishes them. But `win()` is only ever reached through the eating branch
(after `score += 10`), so "the world became dead this call AND its score changed this call" is
exactly winning; anything else that becomes dead didn't win. `stepOneTick` captures `pre_score` and
`pre_status` immediately before calling `world.advance`, computes `ate = score != pre_score`, and
classifies a `.playing -> .dead` transition as `NS_EVENT_WIN` if `ate` else `NS_EVENT_DIE`. Both
`ns_step` and `ns_pump` route every tick through this one helper, so the classification can't drift
between the two entry points.

## Event queue: fixed capacity, drop-oldest overflow

`docs/abi-decisions.md` freeze #2 forbids allocating, so the event queue is a fixed-size ring
(`EVENT_QUEUE_CAP = 64`) embedded directly in `WorldStorage`, not a growable list. An undrained
caller that lets more than 64 events accumulate loses the oldest ones — a deliberate, documented
choice, distinct from `ns_event_drain`'s own contract ("nothing is dropped by a too-small [output]
buffer", which is about the *caller's* drain buffer, not this queue). The world's live state stays
fully queryable via `ns_player_view_get`/`ns_body_copy` regardless of whether events were dropped;
only history is lost, never current truth. 64 is generous headroom for any real per-frame drain
cadence — a caller falling 64 events behind has a design problem this ABI can't fix for them.

## `WorldStorage` layout

The caller-owned buffer (`ns_world_size(config)` bytes, aligned to `ns_world_align()`) is carved
into a fixed-size `WorldStorage` header — `world.World`, `player_count`, and the event ring/head/len
— immediately followed by the variable-length snake cell buffer at byte offset
`@sizeOf(WorldStorage)`. A `comptime` assert (`@alignOf(WorldStorage) % @alignOf(world.Cell) == 0`)
guards that this offset always lands sufficiently aligned for the cell slice `ns_world_init` hands
to `world.initWorld`.

## `ns_pump` reimplements, doesn't call, `world.zig`'s accumulator loop

Calling `world.pump()` directly and diffing before/after snapshots to guess how many eats/deaths
happened would reintroduce exactly the ambiguity the event-drain feature exists to remove
(`docs/abi-header.md`). So `ns_pump` reproduces the same clamp-and-loop shape (`world.MAX_DT_US`,
`world.MAX_STEPS`, `world.tickPeriodUs`) — those two constants were changed from private to `pub`
in `core/world.zig` for exactly this reason (a pure visibility change; `zig build test` still
passes unmodified) — calling `stepOneTick` once per advance instead of `world.advance` directly, so
every individual tick gets its event recorded.

## `ns_deserialize`: direct RNG reconstruction, board-size rejection

`canon.verify` is checked before `canon.decode` (decode alone only validates magic/version/length,
not the checksum). The rebuilt `World`'s RNG state is assigned via a direct `rng.Rng` struct
literal, not `rng.Rng.init` — `init` asserts a non-all-zero seed, a real-gameplay precondition that
must not become a panic when handed an adversarially-crafted (but checksum-valid) record. A record
whose `cols`/`rows` don't match the world's own (fixed at `ns_world_init` time, since that's what
sized the cell buffer) is rejected with `NS_ERR_DECODE_FAILED` rather than attempting a resize the
caller-owned-memory model has no room for. `acc_us` is reset to 0 on load (presentation-timing
state, not part of the canonical snapshot per `docs/canonical-state.md`), and the event queue is
cleared — a freshly loaded world owes nothing to the events of the session that produced the
record it just replaced.

## `ns_world_reset` clears the event queue

Not specified by the header, but consistent with its documented contract that `reset` discards the
old body/score/tick: a fresh game discards stale events from the game it replaced too.

## `core/abi.zig` is not bound by the no-libc/no-allocator constraint

`docs/build-layout.md`'s "No allocator, no libc" section names only `core/rng.zig`, `core/canon.zig`,
and `core/world.zig` — future freestanding/WASM targets (TASK-047). `core/abi.zig` is the ABI
boundary layer, expected to be linked into a host that already links libc (the GDExtension shim via
godot-cpp; TASK-025's C conformance harness), so the `getauxval`/`memcpy`/`memmove`/`__divti3`/
`__modti3` undefined references it transitively pulls in (`std.debug`'s panic/backtrace machinery,
compiled in under the default Debug optimize mode) are expected, not a violation.

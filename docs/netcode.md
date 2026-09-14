# Lockstep netcode (TASK-053, TASK-054)

Two-peer lockstep netcode driving `ns_step` directly, one call per confirmed tick --
`include/neo_snake.h` documents `ns_step` as the frozen primitive a netcode layer must call itself,
never `ns_queue_dir`/`ns_pump` (local-play conveniences). Rollback is out of scope: `docs/rng.md`'s
single shared RNG stream, drawn in ascending player-index order, cannot be replayed from an
arbitrary mid-point the way a per-player stream could -- see `backlog/decisions/decision-034`. See
`backlog/decisions/decision-036` for the design rationale; this document is the implementation
spec.

Three files under `game/simulation/` (the one directory permitted to reference `NeoSnakeWorld` /
raw sim internals -- `tools/validate_simulation_boundary.py`):

- `lockstep_link.gd` -- `LockstepLink`, an in-process stand-in for a network transport.
- `lockstep_peer.gd` -- `LockstepPeer`, one side of a match.
- `lockstep_session.gd` -- `LockstepSession`, both peers plus both links.

## `LockstepPeer`

Wraps one `SimulationWorld`, `local_player`/`remote_player` indices, and a fixed
`INPUT_DELAY := 3`. A direction decided at real-time step `S` (via `queue_local_direction(dir)`)
takes effect at simulation tick `for_tick = S + INPUT_DELAY`, not immediately -- this is what hides
latency without rollback: as long as a link's `latency_ticks <= INPUT_DELAY`, the remote input for
a given tick always arrives before that tick is due to simulate.

`advance_round()` does exactly three things, in order, once per real-time step:

1. **Ingest** every message the incoming `LockstepLink` has delivered by now into `_remote_input`.
2. **Decide and send** this step's own local input: `_local_input[S + INPUT_DELAY] = pending_dir`,
   and send it on the outgoing link -- resent every round whether or not it changed (a heartbeat),
   so "no message yet" is never ambiguous with "no change decided". This relies on
   `core/world.zig`'s `queueDir` rejecting only the exact reverse of the current direction, never a
   repeat of it.
3. **Simulate** every tick whose local *and* remote input are both now known, in a loop -- zero,
   one, or (after a stall clears) several `world.step()` calls in one round. This decoupling (send
   cadence advances unconditionally; simulate cadence catches up whenever it can) is what avoids
   deadlock between two peers that are each waiting on the other.

**Bootstrap:** `for_tick = step + INPUT_DELAY` leaves ticks `0 ..< INPUT_DELAY` never assigned by
either side's real decisions. `LockstepPeer._init` seeds both `_local_input` and `_remote_input`
for those ticks with `DEFAULT_DIR := SimulationWorld.DIR_RIGHT` (`core/world.zig`'s own reset
default) -- both peers compute the same default independently, no round-trip required.

`tick()` returns `_next_sim_tick`, the highest tick this peer's world has actually reached.
`checksum()` returns `SimulationWorld.checksum(world.serialize()["bytes"])["checksum"]`.
`input_log()` returns every applied `{tick, player, dir}` in application order -- intended as
TASK-054's serialization source for a captured desync fixture.

## `LockstepLink`

A one-directional FIFO: `send(sent_at_step, for_tick, dir)` enqueues a message deliverable at
`sent_at_step + latency_ticks`; `receive_ready(current_step)` returns and removes every message
deliverable at or before `current_step`, in send order. Models delay only -- never loss or
reordering. `LockstepSession` wires up two (one per direction) between its two peers.

## `LockstepSession`

Owns both `LockstepPeer`s and both `LockstepLink`s, and bootstraps both worlds from `.menu` to
`.playing` via `queue_dir(0, DIR_RIGHT)` at construction (the first legal `queue_dir` starts a match
without consuming a tick, so both peers begin simulating from tick 0 in lockstep).

`advance_round()` drives both peers once, then compares checksums when a `CHECKSUM_INTERVAL := 30`
boundary has just been crossed on a tick both peers share:

```
tick_a, tick_b = peer_a.tick(), peer_b.tick()
if tick_a == tick_b and tick_a / CHECKSUM_INTERVAL > last_interval_checked:
    last_interval_checked = tick_a / CHECKSUM_INTERVAL
    compare peer_a.checksum() vs peer_b.checksum()
```

Comparing on "crossed a boundary" rather than "landed exactly on a multiple" matters because a
peer that stalls and then catches up can simulate several ticks in one `advance_round()` call,
jumping straight past an exact multiple of 30. A mismatch emits
`desync_detected(tick, peer_a_checksum, peer_b_checksum)` -- the one named signal seam TASK-054's
desync-capture fixture hooks.

Tick-count offsets between the two peers at an arbitrary stopping point (under asymmetric link
latency) are a normal timing artifact, not a desync -- `advance_round()` only ever compares when
`tick_a == tick_b`, so this never produces a false mismatch.

`capture_fixture(tick, checksum_a, checksum_b)` builds a JSON-safe snapshot of both peers at a
mismatch tick -- see "Desync capture" below.

## Desync capture (TASK-054)

`LockstepSession.capture_fixture(tick, checksum_a, checksum_b) -> Dictionary` builds
`{tick, latency_a_to_b, latency_b_to_a, peer_a, peer_b}`, where each peer's entry is
`{checksum, input_log, state_bytes}` (checksum stringified -- Godot's `JSON` parser produces `float`
for every JSON number, and a `u64` checksum can exceed 2^53, so a string sidesteps precision loss
the same way `docs/corpus-format.md`'s `"c"` field does). It only knows peer/session-level data; the
board-construction `config` (cols/rows/player_count/wrap/rng_seed/speed_source) is supplied
separately by whichever caller built the worlds, since `LockstepSession` never sees their `init()`
arguments. See `backlog/decisions/decision-037` for the full format and the rationale for a new
fixture type rather than extending the single-actor oracle-corpus JSONL schema.

`game/tests/test_desync_fixture.gd` is both the fixture's (manual, opt-in) generator and its
(automatic, every-run) regression check:

- Reruns the exact corrupted-peer scenario from `test_lockstep_session.gd`'s corrupted-input test,
  captures the fixture at the first `desync_detected` mismatch, and deep-compares it against
  `game/tests/desync_fixtures/corrupted_player0_input.json`.
- Only rewrites that committed file when `DESYNC_FIXTURE_REGEN=1` is set -- never as a side effect
  of a normal `task game:test` run, the same posture `reference/oracle/fuzz.mjs`'s promotion step
  takes toward the oracle corpus.
- A future change to `core/world.zig`, the checksum algorithm, or the lockstep protocol that alters
  the recorded checksums/state/input log fails this test until the committed fixture is regenerated
  (or the regression is fixed) -- verified directly by hand-corrupting one field of the committed
  file and confirming `task game:test` fails, then restoring it and confirming it passes again.

## Testing (`game/tests/test_lockstep_session.gd`)

`game/tests/` is not exempt from `tools/validate_simulation_boundary.py`'s global-RNG ban, so
direction choices in the long-session test are driven by a hand-rolled xorshift32 PRNG (pure
arithmetic, no `randi()`/`randomize()`). Four cases:

- Bounded asymmetric latency (2 vs. 1 tick) stays checksum-identical over 6000 ticks (AC#3).
- Latency exactly at the `INPUT_DELAY` budget never permanently stalls.
- Latency over the budget stalls but recovers to a steady one tick per round once the pipeline is
  full, rather than stalling forever.
- A corrupted remote input (a second, conflicting message injected for the same `for_tick`,
  landing after the legitimate one) produces a real checksum mismatch and fires
  `desync_detected` -- proving AC#2's comparison path actually detects a real divergence, not only
  that it agrees when nothing is wrong.

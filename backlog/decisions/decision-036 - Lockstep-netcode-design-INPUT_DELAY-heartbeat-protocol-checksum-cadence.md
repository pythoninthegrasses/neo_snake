---
id: decision-036
title: Lockstep netcode design -- INPUT_DELAY bootstrap, heartbeat protocol, boundary-crossing checksum cadence
date: '2026-09-14 00:00'
status: Accepted
---
## Context

TASK-053's Description and AC pin down three numbers -- `INPUT_DELAY = 3`, a checksum every 30
ticks, multi-minute checksum-identical operation -- but say nothing about the actual protocol: how
a peer's locally-decided direction reaches the other side, what happens to the first `INPUT_DELAY`
ticks before either side has sent anything, or what "every 30 ticks" means when two peers' tick
counters aren't always exactly aligned. `reference/snake.html` has no networked mode at all, so
none of this is a parity question -- it is new design, same as `decision-034` was for two-player
core semantics. `include/neo_snake.h` and `decision-020` already froze `ns_step` as the primitive a
netcode layer must drive directly, one call per confirmed tick, and `decision-034`'s single shared
RNG stream (drawn in ascending player-index order) rules out rollback: a per-tick draw can't be
replayed from an arbitrary mid-point the way a per-player stream could. This decision records the
lockstep-only protocol built on top of that constraint.

## Decision

**Delayed-input, not rollback.** A direction decided at real-time step `S` takes effect at
simulation tick `S + INPUT_DELAY`, not immediately. As long as a link's latency in ticks is `<=
INPUT_DELAY`, the remote input for a given tick always arrives before that tick is due to simulate,
and `advance_round()` never stalls. This is the entire mechanism by which latency is hidden --
there is no speculative execution and no re-simulation of a corrected past tick, since the shared
RNG stream (`decision-034`, `docs/rng.md`) makes that unsound here.

**Decoupled send-schedule vs. simulate-schedule.** A peer's own local-decision-and-send cadence
advances every real-time step regardless of whether its world has caught up in simulation.
Separately, the simulate step greedily consumes every tick whose local *and* remote input are both
already known -- zero, one, or (after a stall clears) several ticks in one call. This is what
avoids deadlock: a peer that is temporarily behind still keeps transmitting on schedule, so the
other side is never starved waiting on a peer that is itself waiting.

**Heartbeat-every-tick, not change-only.** Every local decision is resent every real-time step
whether or not it changed, so "no message yet" (network still catching up) is never ambiguous with
"no change decided." This relies on `core/world.zig`'s `queueDir` only rejecting the exact reverse
of the current direction, never a repeat of it -- resending an unchanged direction is always legal.

**Bootstrap seeding for the first `INPUT_DELAY` ticks.** Because `for_tick = step + INPUT_DELAY`,
ticks `0 ..< INPUT_DELAY` are never assigned by either side's own real decisions -- there is no
step `-3..-1` to have decided them. Both peers independently pre-seed their local and remote input
maps for those ticks with the same default direction (`SimulationWorld.DIR_RIGHT`, matching
`core/world.zig`'s own reset default) at construction time. Both sides compute the same default
independently, so no network round-trip is needed to agree on it.

**Checksum comparison triggers on crossing a `CHECKSUM_INTERVAL` (30-tick) boundary, not on landing
exactly on a multiple of it.** A peer that stalls (remote input late, catching up) can simulate
several ticks in one `advance_round()` call and jump straight past an exact multiple of 30.
Comparing at the first opportunity after a boundary has been crossed still satisfies "every 30
ticks" (AC#2) without requiring an exact-alignment guarantee the decoupled-schedule design above
doesn't make. A comparison only ever happens when both peers' tick counters are equal to begin
with -- transient tick-count offsets between peers under asymmetric latency are a normal artifact
of when each side's last message happened to land, not a desync, and are never compared against
each other.

**In-process simulated transport (`LockstepLink`), not real sockets, for this task's own tests.**
A `LockstepLink` is a one-directional FIFO queue keyed by a local step counter shared between both
peers (`session.advance_round()` calls both peers once per round, so "step S" means the same
wall-clock moment on both sides); `latency_ticks` delays delivery deterministically. This models
delay only, never loss or reordering -- sufficient to prove AC#3 (bounded latency stays
checksum-identical) and to construct a deterministic corrupted-input fixture (AC#2's mismatch
path) without any real network dependency in the test suite. A real transport is out of scope for
this task; `LockstepPeer`/`LockstepSession` depend only on the `LockstepLink` interface
(`send`/`receive_ready`), so swapping in a real transport later does not require touching either.

## Consequences

- A netcode consumer must guarantee `latency_ticks <= INPUT_DELAY` per link for `advance_round()`
  to make forward progress every round; exceeding the budget degrades to a bounded steady-state lag
  (proven by `test_latency_over_the_input_delay_budget_stalls_but_recovers`), not permanent stall,
  but is not "hidden" the way in-budget latency is.
- `LockstepSession.desync_detected(tick, peer_a_checksum, peer_b_checksum)` is the one named signal
  seam for TASK-054's desync-capture fixture; there is no other checksum-mismatch path.
- `LockstepPeer.input_log()` records every applied `{tick, player, dir}` in application order,
  intended as TASK-054's serialization source for a captured desync fixture.

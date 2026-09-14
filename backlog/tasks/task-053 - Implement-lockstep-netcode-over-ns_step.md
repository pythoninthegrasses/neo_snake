---
id: TASK-053
title: Implement lockstep netcode over ns_step
status: Done
assignee: []
created_date: '2026-09-09 22:16'
labels: []
milestone: m-8
dependencies:
  - TASK-052
priority: low
type: feature
ordinal: 53000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement lockstep netcode (not rollback) built on top of ns_step, the lockstep primitive the ABI carried from day one. Use INPUT_DELAY = 3 ticks to hide network latency, and exchange a checksum every 30 ticks between peers so desyncs are detected quickly rather than silently compounding for minutes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Lockstep netcode drives ns_step with a fixed INPUT_DELAY of 3 ticks
- [x] #2 Peers exchange and compare a checksum every 30 ticks
- [x] #3 Two networked instances with simulated latency stay checksum-identical over a multi-minute session
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 task check is green
- [x] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [x] #3 Docs touched by the change are updated in the same commit
- [x] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

## Notes

Implemented as three new files under `game/simulation/` (the one directory
`tools/validate_simulation_boundary.py` permits to reach raw sim internals):
`lockstep_link.gd` (`LockstepLink`, an in-process simulated-latency FIFO
transport), `lockstep_peer.gd` (`LockstepPeer`, one side of a match, owning
a `SimulationWorld` and driving `ns_step` via `world.step()` directly per
`include/neo_snake.h`'s frozen contract), and `lockstep_session.gd`
(`LockstepSession`, both peers plus both links, exposing the
`desync_detected` signal). Four new gdUnit4 tests in
`game/tests/test_lockstep_session.gd` cover AC#1-#3 plus a corrupted-input
fixture proving the checksum-mismatch path actually detects a real
divergence, not only that it agrees when nothing is wrong. Full design
(INPUT_DELAY-delayed input instead of rollback, decoupled send/simulate
scheduling, heartbeat-every-tick protocol, bootstrap seeding of the first
INPUT_DELAY ticks, boundary-crossing checksum cadence) is recorded in
`backlog/decisions/decision-036` and specced in the new `docs/netcode.md`.

The lockstep driving method was originally named `advance()`, colliding
with `tools/validate_simulation_boundary.py`'s `sim-verb` ban (`advance` is
one of `reference/snake.html`'s own internal simulation-loop function
names) once called from `game/tests/`, which is not exempt from that
check. Renamed to `advance_round()` throughout — the gating tooling was
not touched; the method's own name was the thing that needed to change.

### DoD#2 — backlog/decisions/decision-036

Every mechanism here (delayed-input over rollback, heartbeat protocol,
bootstrap seeding, boundary-crossing checksum cadence, in-process
simulated transport) is new design, not a `reference/snake.html` parity
question — the oracle has no networked mode to diverge from. Recorded in
full in `decision-036`.

### DoD#3 — docs/netcode.md added

No existing doc asserted anything this change falsifies; `docs/rng.md`
and `docs/abi-decisions.md` already referenced "lockstep netcode" only as
a forward-looking justification for the shared-RNG-stream design, and
needed no edits. A new `docs/netcode.md` specs the implementation this
task actually adds.

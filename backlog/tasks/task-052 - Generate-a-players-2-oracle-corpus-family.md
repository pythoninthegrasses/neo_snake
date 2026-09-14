---
id: TASK-052
title: 'Generate a players:2 oracle corpus family'
status: Done
assignee: []
created_date: '2026-09-09 22:16'
labels: []
milestone: m-8
dependencies:
  - TASK-051
priority: low
type: feature
ordinal: 52000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Extend the JS oracle and corpus generator to produce a players: 2 corpus family (analogous to the existing 1-player corpus from Phase 2), then replay it through all four test tiers (A/B/C/D) to prove two-player determinism holds identically to the single-player case, including the shared-RNG-stream property from the ABI decisions doc.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 reference/oracle regenerates a players:2 corpus family alongside the existing 1-player family
- [x] #2 The players:2 corpus replays and checksum-matches through Tier-B, Tier-C, and Tier-D
- [x] #3 The shared single RNG stream (not per-player streams) is exercised and asserted by at least one 2-player trace
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 task check is green
- [x] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [x] #3 Docs touched by the change are updated in the same commit
- [x] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

## Notes

Added two new committed corpus fixtures — `two-player-shared-rng-stream` and
`two-player-head-to-head` — via genuinely new command logs under
`reference/oracle/corpus/commands/`, then a real `regen_corpus.mjs` run (not
hand-authored traces) alongside the existing 1-player family. `sim.mjs`,
`canon.mjs`, and `regen_corpus.mjs`/`regen_corpus-check.mjs` were already
N-player-generic from TASK-051's core-layer work; only the check script's
stale single-player-only assertions needed relaxing to 2-player-aware
equivalents, plus a new corpus-level assertion (decoding the committed
trace's anchor bytes via `canon.mjs`) that proves AC#3 directly against
committed bytes, not just the in-memory `sim-check.mjs` unit test.

`core/difftest.zig` (Tier-B) and `core/abitest.zig` (Tier-C) were both
still hardcoded to `player_count == 1`; generalized both to loop over
`1..MAX_PLAYERS` the same way `core/world.zig` already does, replicating
`core/abi.zig`'s `playerStatus()` canonical-status convention (a live
player's status is the shared `World.status`; an eliminated player's is
always `.dead`) via a locally-duplicated helper in `difftest.zig` per that
file's own hermeticity rule. `abitest.zig`'s fixed `[4096]u8` scratch
buffer was too small for a 24x24 two-player board and was bumped to
`[8192]u8`. `game/tests/test_corpus_replay.gd` (Tier-D) had an artificial
`players != 1` guard predating TASK-051; removed after confirming (by
reading `extension/src/neo_snake_world.cpp`) that `NeoSnakeWorld` was
already fully player-count-generic underneath — no engine-layer change
was needed to lift it.

A third fixture (an opponent-body-collision corpus trace) was considered
and rejected as redundant scope: since both players move at the same fixed
speed, a perpendicular chaser's offset to a moving snake's body stays
constant once matched, so a corpus-level fixture can't exercise anything
`core/world.zig`'s own inline unit tests and `sim-check.mjs` don't already
cover directly.

### DoD#2 — no backlog/decisions/ entry

Not needed. Every semantic choice here (shared status projection, shared
RNG stream draw order, two-phase collision) was already frozen by
decision-034 during TASK-051; this task only proves those same rules hold
at the corpus/replay layer across all four test tiers. No new deviation
from `reference/snake.html` was introduced — `reference/snake.html` itself
has no multiplayer mode to diverge from in the first place.

### DoD#3 — no docs updates needed

`docs/rng.md` and `docs/abi-decisions.md` already documented the shared-
single-RNG-stream rule generically (not scoped to "single-player only");
`docs/corpus-format.md` and `docs/canonical-state.md` already describe the
wire format in player-count-generic terms (explicit `p` field, `player_count`
byte). Nothing in the docs asserted "the corpus is single-player only" as
an invariant this change would falsify, so no doc file needed editing.

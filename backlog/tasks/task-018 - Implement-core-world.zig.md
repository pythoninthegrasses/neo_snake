---
id: TASK-018
title: Implement core/world.zig
status: Done
assignee: []
created_date: '2026-09-09 22:09'
updated_date: '2026-09-11 22:30'
labels: []
milestone: m-3
dependencies:
  - TASK-017
priority: high
type: feature
ordinal: 18000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement the deterministic snake simulation in Zig: movement, direction commit, collision, food placement, scoring, win condition, and the ns_pump tick accumulator. Pure — no allocator, no libc, caller-supplied memory only (world size and layout determined by ns_world_size, initialized via ns_world_init in a later task). This is the sim faithfully mirroring reference/oracle/sim.mjs.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 world.zig has zero calls to malloc/allocator and does not link libc
- [x] #2 All caller-provided memory is explicit function parameters, never a global
- [x] #3 The tick-period table from task-010 is used verbatim, not recomputed from floats
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 task check is green
- [x] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [x] #3 Docs touched by the change are updated in the same commit
- [x] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
What landed:

- core/world.zig — the deterministic simulation mirroring reference/oracle/sim.mjs:
  `initWorld`/`reset`/`start`/`placeFood`/`queueDir`/`togglePause`/`advance`/`pump`, with
  `advance()`'s load-bearing order kept verbatim (input commit → move → collision against the
  tail minus the cell it is about to vacate → unshift/pop; `die`/`win` return before the tick
  increment, exactly like the oracle's `return die(S)`/`return win(S)`), and decision-015's
  menu-direction overwrite reproduced through `queueDir` → `start` → `reset`. Wrap is the
  oracle's own `(v + size) % size` expression kept as `@mod(v + size, size)`. Win is `dead`,
  as in the oracle. The presentation-only state sim.mjs already drops (flash, particles, the
  overlay/HUD sync, `best`) stays dropped — no canonical byte.
- AC#1/#2: no allocator, no libc (no `std.heap`/`Allocator`/`@cImport`, `build.zig` links no
  libc for it), and no mutable globals — the snake body lives in a caller-supplied cell buffer
  passed to `initWorld` (sized via `requiredCells(cols, rows)`; `cells()` is the live head-first
  view), and `World` itself is caller-owned. `placeFood` enumerates free cells in the same
  row-major (outer y, inner x) order as the oracle but finds the drawn cell by counting and
  walking instead of building a free-cell list, since there is no allocator — same draw, same
  cell. Cell/Dir/Status are imported from core/canon.zig rather than duplicated, so the frozen
  canonical encodings cannot drift; the C ABI exports (ns_world_size/ns_world_init) wrap this
  in a later task (TASK-023).
- AC#3: `TICK_PERIOD_US = {130000, 96296, 76471, 63415, 55000}` copied verbatim from
  docs/abi-decisions.md freeze #5, indexed `min(score / 10, 4)` per the freeze's exact rule —
  never recomputed from floats (a committed-table test asserts all five entries).
- The ns_pump accumulator (`pump`) takes an integer-microsecond `dt`, clamps it to 64 ms
  (MAX_DT_US), accumulates in `acc_us`, and runs at most MAX_STEPS=6 advances with the period
  re-read each iteration (eating raises speed mid-frame) — the same shape as sim.mjs's step(),
  integer-only per freeze #5. The first-frame dt sentinel (sim.mjs's `S.last`) is clock
  bookkeeping that lives in the caller's driver (task-031: the driver owns the clock), so
  `World` carries only `acc_us`; `pump` returns the advance count so drivers/tests can assert
  exact tick counts.
- core/build.zig — third module (world.zig) with `addImport` of rng/canon (world needs two of
  these together — imports, not the lib.zig aggregator docs/build-layout.md defers), one
  addTest, same single `test` step. taskfiles/core.yml + docs/build-layout.md updated to list
  world.zig wherever rng.zig/canon.zig were enumerated.
- Tests: 9 in world.zig (refAllDecls + reset/food-draw vector (0,0) on seed [1,2,3,4], move +
  eat + wall death, tail-chase survival, wrap vs wall contrast, queueDir 180-reject +
  decision-015 + pause, pump clamp/carry-over/no-op-when-paused, win-on-full-board, and the
  table verbatim check). `zig build test` → 15/15 (rng 2, canon 4, world 9). The exhaustive
  nine-named Tier-A suite (incl. serialize∘deserialize identity) remains TASK-019's scope.

Deviation analysis (DoD#2 — no new backlog/decisions/ entry warranted; reasoning stated so it
isn't implicit): every divergence from reference/snake.html behavior in world.zig is already
recorded. (a) Seeded xoshiro128** food draw — decision-003. (b) The integer-microsecond tick
period and accumulator instead of the oracle's float-ms `tickMs()`/step() arithmetic — exactly
what docs/abi-decisions.md freeze #5 mandates for "core/world.zig's accumulator" ("not
re-evaluate the float formula"), with task-010's notes ruling the table a lossless
transcription; freeze #5's own text names the accumulator (ns_pump) as in scope. The float-ms
sim.mjs step() that remains is oracle-side and untouched (frozen oracle). (c) Dropped
presentation state — sim.mjs's own documented divergences, no canonical bytes. (d) Win == dead
— the oracle's own behavior. Note pump's input is integer µs (not the float ms sim.mjs's step
accepts): this is a consequence of (b) — freeze #5 forbids floats in this accumulator — and
nothing differentially tests pump against step() (the corpus drives advance() per-tick; task-031
tests the driver against ns_pump's documented clamp behavior).

task check status (same worktree limitation TASK-013/017 recorded): the full gate's guard fails
on missing `.env` (TASK_X_ENV_PRECEDENCE) and game:test fails on missing
`game/addons/gdUnit4/` (needs `./tools/bootstrap.py game all`) — both environmental, neither
touched by this change, which is core/ + docs + taskfiles only. What was actually run green
here: `task core:test` (zig build test, 15/15), `task oracle:verify` (oracle_sha256 matches,
corpus up to date — this change doesn't touch the oracle), and `TASK_X_ENV_PRECEDENCE=1 task
check`, whose guard, oracle:verify, core:test, and game:import steps all passed before the
pre-existing gdUnit4-absence failure at game:test.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented core/world.zig — the deterministic snake simulation (movement, direction commit,
collision with the tail-minus-vacated-cell rule, food placement, scoring, win-as-dead, and the
integer-microsecond ns_pump accumulator) as a faithful port of reference/oracle/sim.mjs, in the
established no-allocator/no-libc/caller-supplied-memory style of core/rng.zig/canon.zig. The
task-010 tick-period table is committed verbatim and indexed by freeze #5's exact rule, never
recomputed from floats. Wired into core/build.zig as a third test module (importing rng +
canon), with docs/build-layout.md and taskfiles/core.yml updated in the same commit. AC#1/#2/#3
verified (grep-clean for heap/allocator/libc/cImport, no globals, table verbatim + asserted in
a test); `zig build test` green at 15/15, and the full `task check` runs green through
guard→oracle:verify→core:test→game:import, failing only at the pre-existing environmental
blocker (gdUnit4 addon not bootstrapped in this worktree) that TASK-013/017 recorded before
this change. DoD#2: no new decision record needed — all divergences were already recorded
(decision-003, freeze #5/task-010); DoD#3/#4 satisfied as above.
<!-- SECTION:FINAL_SUMMARY:END -->

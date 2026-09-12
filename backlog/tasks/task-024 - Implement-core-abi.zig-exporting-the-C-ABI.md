---
id: TASK-024
title: Implement core/abi.zig exporting the C ABI
status: Done
assignee: []
created_date: '2026-09-09 22:10'
updated_date: '2026-09-12 20:10'
labels: []
milestone: m-4
dependencies:
  - TASK-023
priority: high
type: feature
ordinal: 24000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement core/abi.zig as the only Zig file in the project containing `export` symbols, wrapping core/world.zig, core/rng.zig, and core/canon.zig behind exactly the surface declared in include/neo_snake.h.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 nm on the built .a shows only ns_* symbols and compiler-rt intrinsics — no other exported symbols
- [x] #2 No file other than core/abi.zig contains an export keyword
- [x] #3 Every function declared in include/neo_snake.h has a corresponding export in abi.zig with a matching signature
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
core/abi.zig implements all 15 functions declared in include/neo_snake.h, wrapping core/world.zig, core/rng.zig, and core/canon.zig. Verified end to end with a standalone C program linked against zig-out/lib/libneo_snake.a (ns_world_init through a full play/pump/serialize/deserialize/event-drain cycle), not just by inspection.

Key implementation decisions (full rationale in docs/abi-impl.md):
- ns_config.player_count is restricted to exactly 1 for now (MAX_SUPPORTED_PLAYERS), rejecting anything else with NS_ERR_INVALID_ARGUMENT. core/world.zig has no per-player dimension today; backlog/decisions/decision-020 already establishes that full multiplayer is milestone m-8, not m-4 (this task). Every bounds check compares against a stored player_count, not a literal 0, so loosening this later is additive.
- Win vs. die: core/world.zig's win() and die() both just set status = .dead. stepOneTick (shared by ns_step and ns_pump) captures score/status immediately before world.advance() and classifies a .playing -> .dead transition as NS_EVENT_WIN if score changed this tick, else NS_EVENT_DIE — win() is only ever reached through the eating branch, so this is exact, not a heuristic.
- Event queue is a fixed 64-entry ring embedded in the caller-owned WorldStorage (no allocation, per docs/abi-decisions.md freeze #2); overflow drops the oldest event, distinct from ns_event_drain's own no-drop contract for its output buffer.
- ns_pump reimplements (does not call) world.zig's accumulator loop so each individual advance can have its event recorded — delegating and diffing snapshots would reintroduce the exact ambiguity event-drain exists to avoid. This required making world.zig's MAX_DT_US/MAX_STEPS pub (pure visibility change, zig build test unaffected).
- ns_deserialize rebuilds the RNG via a direct struct literal (not rng.Rng.init, which asserts non-zero seed) so an adversarial-but-checksum-valid record can't panic across the ABI boundary; rejects any record whose cols/rows don't match the world's own (fixed at ns_world_init time).

AC#1 (nm) and AC#2 (no stray export) are now mechanically enforced by a new `core:abi-symbols` task (taskfiles/core.yml), wired into `task check` right after core:abi-header-check: builds libneo_snake.a and asserts every defined global symbol matches ^ns_. AC#3 was cross-checked function-by-function against include/neo_snake.h (all 15 match) and exercised live via the C smoke test above.

DoD#2: no new backlog/decisions/ entry — every choice here is a new-ABI-surface implementation decision with no analogue in reference/snake.html (documented in docs/abi-impl.md instead, same pattern as docs/abi-header.md/docs/abi-decisions.md), not a deviation from the oracle's own behavior.

Docs updated: docs/abi-impl.md (new), docs/build-layout.md (zig build abi section, core:abi-symbols wiring, no-libc/no-allocator exemption for abi.zig).
<!-- SECTION:NOTES:END -->

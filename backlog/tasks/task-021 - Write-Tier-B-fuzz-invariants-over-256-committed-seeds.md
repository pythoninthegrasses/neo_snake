---
id: TASK-021
title: Write Tier-B fuzz invariants over 256 committed seeds
status: Done
assignee: []
created_date: '2026-09-09 22:10'
updated_date: '2026-09-12 19:22'
labels: []
milestone: m-3
dependencies:
  - TASK-020
priority: high
type: feature
ordinal: 21000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Create core/fuzz_seeds.zig with 256 committed [4]u32 seeds, checked against structural invariants rather than the oracle (since the oracle is a checksum, not an invariant checker): body_len == 3 + score/10; no duplicate body cells; food never placed on a body cell; serialize∘deserialize == identity; checksum stable across a serialize/deserialize round trip; and ns_step with permuted input-application order yields identical checksums (the netcode-critical property for lockstep, since network input can arrive interleaved).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All 256 committed seeds pass all six invariants under zig build test
- [x] #2 The permuted-input-order invariant test is explicit about what 'permuted' means (e.g. reordering independent per-player inputs within a tick)
- [x] #3 This suite is part of task check
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
core/fuzz_seeds.zig: 256 committed [4]u32 seeds (splitmix64 codegen from a fixed master constant, guarded against an all-zero seed), wired into core/build.zig's test_step alongside rng/canon/world. Invariants 1-5 drive core/world.zig directly via initWorld/queueDir/advance over 60 ticks per seed, checking body_len==3+score/10, no duplicate body cells, food never on a body cell (all three checked every tick, not just at the end), and serialize∘deserialize identity + checksum stability via core/canon.zig's encode/decode/checksum/verify.

Invariant 6 (permuted input-application order) needed a multiplayer step, which core/world.zig doesn't model. Added a private, non-ABI, test-only two-player primitive inside fuzz_seeds.zig (not named ns_step, not in world.zig) scoped only to prove permutation invariance — decision recorded in backlog/decisions/decision-020. Two-phase tick: phase 1 (the permuted order under test) computes each player's move/self-collision read-only against the tick's starting food; phase 2 (always fixed ascending player-index order) applies body mutations, resolves food consumption, and draws the one shared-RNG replacement food — making permutation-invariance structural, satisfying AC#2's 'be explicit about what permuted means'.

docs/build-layout.md updated: new 'Tier-B fuzz invariants' section plus a Module layout mention. task check is green end-to-end in this worktree (core:test, core:difftest, game:import, game:test all pass; game/addons/gdUnit4 needed tools/bootstrap.py game gdunit4 first, same as TASK-020's worktree).
<!-- SECTION:NOTES:END -->

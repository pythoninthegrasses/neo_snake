---
id: TASK-008
title: Write docs/rng.md
status: To Do
assignee: []
created_date: '2026-09-09 22:08'
labels: []
milestone: m-1
dependencies:
  - TASK-001
documentation:
  - docs/rng.md
priority: high
type: docs
ordinal: 8000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Document the xoshiro128** PRNG choice and the JS-exactness argument: its operations (xor, shift, rotate, multiply by 5 and 9) produce products under 2^35, far below JS's 2^53 exact-integer boundary, so no Math.imul or BigInt is needed. Document literal 4×u32 seeding (never a u64 splitmix expansion, since any expander constant overflows JS exactness), the multiply-high bounded draw (r*n)>>32, row-major free-cell enumeration for food placement, and food placement order in ascending player index for multiplayer.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The doc states the JS-exactness argument (product bound vs 2^53) explicitly
- [ ] #2 The doc states the accepted modulo-bias divergence from Math.random() as a documented, deliberate divergence
- [ ] #3 Seeding and bounded-draw formulas are precise enough to implement identically in Zig, JS, and GDScript
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

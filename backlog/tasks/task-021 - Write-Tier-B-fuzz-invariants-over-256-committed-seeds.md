---
id: TASK-021
title: Write Tier-B fuzz invariants over 256 committed seeds
status: To Do
assignee: []
created_date: '2026-09-09 22:10'
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
- [ ] #1 All 256 committed seeds pass all six invariants under zig build test
- [ ] #2 The permuted-input-order invariant test is explicit about what 'permuted' means (e.g. reordering independent per-player inputs within a tick)
- [ ] #3 This suite is part of task check
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

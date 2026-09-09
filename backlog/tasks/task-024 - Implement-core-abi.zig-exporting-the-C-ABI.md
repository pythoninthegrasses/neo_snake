---
id: TASK-024
title: Implement core/abi.zig exporting the C ABI
status: To Do
assignee: []
created_date: '2026-09-09 22:10'
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
- [ ] #1 nm on the built .a shows only ns_* symbols and compiler-rt intrinsics — no other exported symbols
- [ ] #2 No file other than core/abi.zig contains an export keyword
- [ ] #3 Every function declared in include/neo_snake.h has a corresponding export in abi.zig with a matching signature
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

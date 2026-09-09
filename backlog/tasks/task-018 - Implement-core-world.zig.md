---
id: TASK-018
title: Implement core/world.zig
status: To Do
assignee: []
created_date: '2026-09-09 22:09'
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
- [ ] #1 world.zig has zero calls to malloc/allocator and does not link libc
- [ ] #2 All caller-provided memory is explicit function parameters, never a global
- [ ] #3 The tick-period table from task-010 is used verbatim, not recomputed from floats
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

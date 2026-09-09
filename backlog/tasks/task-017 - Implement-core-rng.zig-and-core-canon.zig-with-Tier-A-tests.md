---
id: TASK-017
title: Implement core/rng.zig and core/canon.zig with Tier-A tests
status: To Do
assignee: []
created_date: '2026-09-09 22:09'
labels: []
milestone: m-3
dependencies:
  - TASK-006
  - TASK-016
references:
  - ~/git/zelda3/build.zig
priority: high
type: feature
ordinal: 17000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement the Zig xoshiro128** RNG and canonical-state serialization per docs/rng.md and docs/canonical-state.md, with Tier-A unit tests (zig build test). This is the first Zig code in the project — no allocator, no libc dependency.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The worked example from docs/canonical-state.md round-trips to the same checksum node produced in task-012
- [ ] #2 core/rng.zig produces the identical sequence as reference/oracle/rng.mjs for the same seed
- [ ] #3 zig build test passes with no allocator and no libc linkage
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

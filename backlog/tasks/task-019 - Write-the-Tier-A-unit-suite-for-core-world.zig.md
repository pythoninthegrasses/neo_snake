---
id: TASK-019
title: Write the Tier-A unit suite for core/world.zig
status: To Do
assignee: []
created_date: '2026-09-09 22:09'
labels: []
milestone: m-3
dependencies:
  - TASK-018
priority: high
type: feature
ordinal: 19000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Write zig build test coverage for world.zig with one named test each for: direction commit-before-move ordering; negative wrap using @mod vs raw %; tail-chase legality (head moving onto its own current tail cell survives if not eating, dies if eating — the single most likely thing to get wrong in a port); out-of-bounds death occurring after the direction commit, not before; score += 10 followed by food placement followed by win-on-full-board ordering; both 180-degree-reject references (dir while playing, nextDir otherwise); the ns_pump clamp (max ticks per pump call) and accumulator carry-over; and serialize∘deserialize == identity.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 zig build test runs all nine named tests and they pass
- [ ] #2 The tail-chase test explicitly covers both the surviving and dying case
- [ ] #3 The ns_pump clamp test asserts the maximum tick count per call and that leftover time carries to the next call
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

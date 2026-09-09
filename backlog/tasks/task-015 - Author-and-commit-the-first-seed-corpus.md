---
id: TASK-015
title: Author and commit the first seed corpus
status: To Do
assignee: []
created_date: '2026-09-09 22:09'
labels: []
milestone: m-2
dependencies:
  - TASK-014
priority: high
type: feature
ordinal: 15000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design and commit ~12 hand-designed traces covering the Phase 3 edge cases (tail-chase legality, negative wrap, out-of-bounds death after direction commit, score/placement/win-on-full-board ordering, both 180-reject references, accumulator clamp/carry) plus ~20 random traces for broader coverage. Format: one header line, then per-tick {"t","in","c"} records with full canonical state "s" on tick 0, every 64 ticks, and the last tick. Use JSONL, not a binary blob — these are review artifacts, and a binary format turns every corpus change into an unreviewable diff. A 2000-tick trace should be roughly 60 KB.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 At least 12 hand-designed traces exist, each named for the edge case it covers, plus ~20 random traces
- [ ] #2 Every trace file is JSONL with periodic full-state anchors as specified
- [ ] #3 The corpus is generated via task oracle:regen, not hand-edited
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

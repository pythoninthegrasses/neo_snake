---
id: TASK-010
title: Derive and commit the integer tick-period table
status: To Do
assignee: []
created_date: '2026-09-09 22:08'
labels: []
milestone: m-1
dependencies:
  - TASK-009
documentation:
  - docs/abi-decisions.md
priority: high
type: docs
ordinal: 10000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Derive the five-entry integer microsecond tick-period table from the original snake.html formula max(55, 130 / (1 + min(score,40) * 0.035)), evaluated once at score thresholds 0/10/20/30/40+ and committed as a constant (in docs/abi-decisions.md and as literal values in both the oracle and the Zig core). Without this table as a committed integer constant, a float reaches the canonical state and the accumulator (ns_pump) stops being differentially testable between JS, Zig, and GDScript.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A test asserts each of the five table entries equals round(max(55, 130/(1+min(s,40)*0.035)) * 1000) for s in {0,10,20,30,40+}
- [ ] #2 The table is committed as a named constant, not recomputed from floats at runtime
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

---
id: TASK-022
title: 'Build the nightly oracle:fuzz discovery job'
status: To Do
assignee: []
created_date: '2026-09-09 22:10'
labels: []
milestone: m-3
dependencies:
  - TASK-021
priority: medium
type: feature
ordinal: 22000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement task oracle:fuzz -- --count N: generate fresh random seeds, run them through both the JS oracle and the Zig core (both must be live — node and zig — unlike the hermetic Tier-B difftest), and diff results. This is discovery, not regression, so it is deliberately NOT part of task check; it runs nightly in CI. Any failing seed found this way is promoted into the permanent committed corpus (task-015's files) as a new regression test — that promotion path is how the regression suite grows over time.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 task oracle:fuzz -- --count N runs N fresh seeds through both oracle and core and reports any mismatch
- [ ] #2 task oracle:fuzz is NOT part of task check
- [ ] #3 A documented procedure exists for promoting a failing seed into the committed corpus
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

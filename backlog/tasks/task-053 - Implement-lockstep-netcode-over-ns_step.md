---
id: TASK-053
title: Implement lockstep netcode over ns_step
status: To Do
assignee: []
created_date: '2026-09-09 22:16'
labels: []
milestone: m-8
dependencies:
  - TASK-052
priority: low
type: feature
ordinal: 53000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement lockstep netcode (not rollback) built on top of ns_step, the lockstep primitive the ABI carried from day one. Use INPUT_DELAY = 3 ticks to hide network latency, and exchange a checksum every 30 ticks between peers so desyncs are detected quickly rather than silently compounding for minutes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Lockstep netcode drives ns_step with a fixed INPUT_DELAY of 3 ticks
- [ ] #2 Peers exchange and compare a checksum every 30 ticks
- [ ] #3 Two networked instances with simulated latency stay checksum-identical over a multi-minute session
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

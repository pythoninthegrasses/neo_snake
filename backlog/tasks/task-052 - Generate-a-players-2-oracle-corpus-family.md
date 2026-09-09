---
id: TASK-052
title: 'Generate a players:2 oracle corpus family'
status: To Do
assignee: []
created_date: '2026-09-09 22:16'
labels: []
milestone: m-8
dependencies:
  - TASK-051
priority: low
type: feature
ordinal: 52000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Extend the JS oracle and corpus generator to produce a players: 2 corpus family (analogous to the existing 1-player corpus from Phase 2), then replay it through all four test tiers (A/B/C/D) to prove two-player determinism holds identically to the single-player case, including the shared-RNG-stream property from the ABI decisions doc.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 reference/oracle regenerates a players:2 corpus family alongside the existing 1-player family
- [ ] #2 The players:2 corpus replays and checksum-matches through Tier-B, Tier-C, and Tier-D
- [ ] #3 The shared single RNG stream (not per-player streams) is exercised and asserted by at least one 2-player trace
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

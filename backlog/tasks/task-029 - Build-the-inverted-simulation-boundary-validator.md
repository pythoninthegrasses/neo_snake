---
id: TASK-029
title: Build the inverted simulation-boundary validator
status: To Do
assignee: []
created_date: '2026-09-09 22:11'
labels: []
milestone: m-4
dependencies:
  - TASK-027
references:
  - ~/git/azure-dreams-remake/tools/validate_simulation_boundary.py
priority: high
type: feature
ordinal: 29000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Write the inverted boundary validator (mirroring azure-dreams' validate_simulation_boundary.py but with the failure direction flipped, since the sim here is not in GDScript at all). Fail on: any NeoSnakeWorld reference outside game/simulation/; sim-verb names (advance, place_food, tick_ms, speed_mul, etc.) appearing outside game/simulation/; and global RNG usage anywhere near the sim path. Also add a non-regex check that parses game/bin/neo_snake.gdextension and asserts every platform key it claims to support is actually present — a dropped line there is a silent ship-it-broken failure that nothing else in the suite catches. Wire both checks into task game:boundary-check.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A deliberately introduced NeoSnakeWorld reference outside game/simulation/ fails the validator
- [ ] #2 A deliberately introduced sim-verb name (e.g. advance()) outside game/simulation/ fails the validator
- [ ] #3 Deliberately removing a platform key from neo_snake.gdextension while the binary still exists on disk fails the validator
- [ ] #4 task game:boundary-check runs both checks and is part of task check
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

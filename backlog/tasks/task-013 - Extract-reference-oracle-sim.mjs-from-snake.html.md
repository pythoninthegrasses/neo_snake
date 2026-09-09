---
id: TASK-013
title: Extract reference/oracle/sim.mjs from snake.html
status: To Do
assignee: []
created_date: '2026-09-09 22:09'
labels: []
milestone: m-2
dependencies:
  - TASK-012
references:
  - reference/snake.html
priority: high
type: feature
ordinal: 13000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Faithfully extract snake.html's advance()/placeFood()/queueDir()/frame() logic into a headless, DOM-free sim.mjs, using the oracle rng.mjs and canon.mjs from the previous task. This is the pre-port reference the Zig core will be differentially tested against, so faithfulness to the original (including its bugs/quirks registered in backlog/decisions/) matters more than "clean" code.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A named test covers the tail-chase split: eating ? snake : snake.slice(0,-1)
- [ ] #2 A named test covers the +COLS wrap using JS remainder semantics, not true modulo
- [ ] #3 A named test covers the 180-degree-reject reference: dir while playing, nextDir otherwise
- [ ] #4 The menu-direction-overwrite quirk from backlog/decisions/ reproduces exactly (Up from menu results in rightward movement)
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

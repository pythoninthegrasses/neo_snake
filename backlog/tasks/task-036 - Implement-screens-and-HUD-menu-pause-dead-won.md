---
id: TASK-036
title: 'Implement screens and HUD (menu, pause, dead, won)'
status: To Do
assignee: []
created_date: '2026-09-09 22:15'
labels: []
milestone: m-5
dependencies:
  - TASK-035
references:
  - reference/snake.html
priority: medium
type: feature
ordinal: 36000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement the presentation screens and HUD: menu, pause, dead, and won states. Port reference/snake.html's showOverlay() content and layout without its innerHTML-based construction (showOverlay() uses innerHTML, which is a documented XSS-shaped hazard in the original — the Godot port uses real Control nodes/scenes instead, never string-built markup). HUD reflects score, best score (per active mode, per the corresponding backlog/decisions/ entry), and status text matching S.status transitions.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Menu, pause, dead, and won screens exist as real scenes/Control nodes, not string-built markup
- [ ] #2 HUD score and per-mode best score update on the same transitions reference/snake.html uses
- [ ] #3 Screen visibility follows S.status equivalent transitions (menu/playing/paused/dead) with a test or documented manual check per transition
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

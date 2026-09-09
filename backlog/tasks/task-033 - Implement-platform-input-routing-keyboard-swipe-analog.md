---
id: TASK-033
title: 'Implement platform input routing (keyboard, swipe, analog)'
status: To Do
assignee: []
created_date: '2026-09-09 22:11'
labels: []
milestone: m-5
dependencies:
  - TASK-030
priority: medium
type: feature
ordinal: 33000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement platform/{input_router,input_defaults,swipe_gesture,analog_latch}.gd. Declare the InputMap in project.godot (not built up in code) so bindings are reviewable in a diff. Use _unhandled_input, not _input, so focused UI controls get first refusal of an event. analog_latch.gd implements 0.55 fire / 0.35 release hysteresis to avoid stick-drift double-fires. swipe_gesture.gd is pure logic with a board-scaled threshold max(24, board_px*24/520), matching the corresponding backlog/decisions/ entry.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 InputMap actions are declared in project.godot, not constructed at runtime in code
- [ ] #2 input_router.gd uses _unhandled_input, not _input
- [ ] #3 analog_latch.gd tests confirm 0.55 fire / 0.35 release hysteresis with no double-fire under stick jitter
- [ ] #4 swipe_gesture.gd is pure (no Node dependency) and its threshold formula is covered by a test
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

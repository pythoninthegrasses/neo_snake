---
id: TASK-035
title: Implement app_lifecycle.gd focus-pause handling
status: To Do
assignee: []
created_date: '2026-09-09 22:14'
labels: []
milestone: m-5
dependencies:
  - TASK-034
priority: medium
type: feature
ordinal: 35000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement platform/app_lifecycle.gd, handling focus-out auto-pause. Defensively handle all four of NOTIFICATION_APPLICATION_FOCUS_OUT / NOTIFICATION_WM_WINDOW_FOCUS_OUT and their _IN counterparts, since which of these actually fire on Godot 4.7 across desktop, mobile, and web is unconfirmed at design time. This mirrors reference/snake.html's original focus-out pause behavior, extended to cover Android per the corresponding backlog/decisions/ entry.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 app_lifecycle.gd listens for both NOTIFICATION_APPLICATION_FOCUS_OUT/_IN and NOTIFICATION_WM_WINDOW_FOCUS_OUT/_IN
- [ ] #2 A focus-out notification pauses gameplay exactly once, not once per notification type that happens to fire
- [ ] #3 Behavior is verified on desktop via a test or documented manual check; Android/web coverage is documented if it cannot be automated
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

---
id: TASK-051
title: Add local 2-player support
status: To Do
assignee: []
created_date: '2026-09-09 22:16'
labels: []
milestone: m-8
dependencies:
  - TASK-050
priority: low
type: feature
ordinal: 51000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add local 2-player support to the Godot presentation and input layers. This should be nearly free — the C ABI carried a player index and player_count from day one specifically so this milestone would not require an ABI change. This task must NOT modify include/neo_snake.h: if it turns out to require a change there, the multiplayer-shaped-ABI freeze from m2/m5 failed, and that failure is exactly what this acceptance criterion exists to catch.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 This task does not modify include/neo_snake.h — verified by git diff on the PR containing this work
- [ ] #2 Two locally-controlled players can play simultaneously on one board with independent input routing
- [ ] #3 Per-player score/status HUD elements both update correctly using ns_player_view_get
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

---
id: TASK-005
title: Empty Godot project with gdUnit4 bootstrapped
status: To Do
assignee: []
created_date: '2026-09-09 22:08'
labels: []
milestone: m-0
dependencies:
  - TASK-003
references:
  - ~/git/azure-dreams-remake/taskfiles/game.yml
priority: high
type: chore
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Create game/project.godot with application/run/delta_smoothing = false. Bootstrap gdUnit4 6.2.1 into game/addons/gdUnit4 via task game:bootstrap (checksum-verified download, not committed to git). Run it headlessly and confirm a trivial passing suite executes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A trivial passing gdUnit4 suite runs headless via GdUnitCmdTool.gd --ignoreHeadlessMode
- [ ] #2 gdUnit4 is NOT listed under [editor_plugins] in project.godot
- [ ] #3 application/run/delta_smoothing is false in project.godot
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

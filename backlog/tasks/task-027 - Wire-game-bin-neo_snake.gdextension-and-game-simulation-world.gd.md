---
id: TASK-027
title: Wire game/bin/neo_snake.gdextension and game/simulation/world.gd
status: To Do
assignee: []
created_date: '2026-09-09 22:10'
labels: []
milestone: m-4
dependencies:
  - TASK-026
  - TASK-005
priority: high
type: feature
ordinal: 27000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Commit game/bin/neo_snake.gdextension (the built binaries themselves stay gitignored) and write game/simulation/world.gd as the sole GDScript file allowed to reference the NeoSnakeWorld class name — every other file in the game must go through it. Add test_gdextension_present.gd asserting the extension actually loaded, since a silently-unloaded GDExtension would otherwise make every other test skip rather than fail, hiding the real problem.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 test_gdextension_present.gd asserts ClassDB.class_exists("NeoSnakeWorld") and fails loudly (not skip) when the extension is absent
- [ ] #2 game/simulation/world.gd is the only .gd file in the repo referencing NeoSnakeWorld
- [ ] #3 game/bin/neo_snake.gdextension is committed; the platform binaries it points to are gitignored
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

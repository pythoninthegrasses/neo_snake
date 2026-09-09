---
id: TASK-034
title: Implement save_store.gd with injected base dir and schema migrations
status: To Do
assignee: []
created_date: '2026-09-09 22:14'
labels: []
milestone: m-5
dependencies:
  - TASK-033
priority: medium
type: feature
ordinal: 34000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement platform/save_store.gd. Base directory is injected (constructor/setter), not hardcoded to user://, so tests can point it at a temp dir without touching real user data. Carries a SCHEMA_VERSION and a MIGRATIONS dict keyed by version. Writes go through an atomic tmp -> bak -> dst rotation (three steps, because it is unconfirmed whether DirAccess.rename_absolute overwrites the destination on Windows). The _v1_to_v2 migration also doubles as the HTML5 localStorage["snake.best"] import path via JavaScriptBridge.eval, so a player's existing best score on the web build survives the port.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 save_store.gd accepts an injected base directory rather than hardcoding user://
- [ ] #2 A test writes/reads/migrates a save file against a temp base dir with no real user data touched
- [ ] #3 The tmp -> bak -> dst rotation is exercised by a test that simulates an interrupted write
- [ ] #4 The v1->v2 migration path imports localStorage["snake.best"] on web via JavaScriptBridge.eval, covered by a test or documented manual check
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

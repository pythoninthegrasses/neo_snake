---
id: TASK-042
title: 'Add settings and accessibility (volume, reduce-flash, keybind rebinding)'
status: To Do
assignee: []
created_date: '2026-09-09 22:15'
labels: []
milestone: m-6
dependencies:
  - TASK-041
priority: medium
type: feature
ordinal: 42000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Add a settings screen and accessibility features: volume controls per bus (Master/Music/SFX/UI), a reduce-flash accessibility gate (per the corresponding backlog/decisions/ entry, guarding the particle/flash effects), persisted mode selection, and keybind rebinding. Rebound keys are stored as stable strings (e.g. "key:KEY_UP"), not raw InputEvent serialization, so save files survive Godot engine/input-system version changes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Per-bus volume sliders exist and persist across restarts via save_store.gd
- [ ] #2 A reduce-flash toggle exists and, when enabled, suppresses the flash/particle effects gated by it
- [ ] #3 Keybind rebinding is stored as stable strings (e.g. "key:KEY_UP"), not raw InputEvent serialization, and round-trips through save/load
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

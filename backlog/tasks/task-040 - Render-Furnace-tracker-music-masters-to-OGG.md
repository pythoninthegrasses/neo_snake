---
id: TASK-040
title: Render Furnace tracker music masters to OGG
status: To Do
assignee: []
created_date: '2026-09-09 22:15'
labels: []
milestone: m-6
dependencies:
  - TASK-039
priority: medium
type: feature
ordinal: 40000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Author chiptune music masters as Furnace (.fur) trackers and render them offline to OGG for use as Godot audio streams. Furnace version is pinned in tools/game_toolchain.lock, matching the pattern already used for the Godot binary and export templates so the rendering is reproducible across machines. Wire the rendered tracks into an audio bus layout of Master -> Music / SFX / UI.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Furnace version is pinned in tools/game_toolchain.lock
- [ ] #2 At least one .fur master exists under audio/src/music/ and renders to a committed OGG
- [ ] #3 The Master -> Music / SFX / UI bus layout exists in the Godot project and each SFX/music stream routes to the correct bus
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

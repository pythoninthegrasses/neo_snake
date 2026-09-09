---
id: TASK-039
title: 'Author SFX patches (eat, die, turn, start, pause, win, UI move/confirm)'
status: To Do
assignee: []
created_date: '2026-09-09 22:15'
labels: []
milestone: m-6
dependencies:
  - TASK-038
priority: medium
type: feature
ordinal: 39000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Author the text-source SFX patches under audio/src/sfx/*.chip.json for: eat, die, turn, start, pause, win, and the two UI sounds (move, confirm). Each patch is reviewable as text (per azure-dreams' "source must be reviewable without opening a scene" rule) and rendered offline to WAV by tools/render_audio.py — no runtime AudioStreamGenerator synthesis, per the corresponding backlog/decisions/ entry.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All 8 SFX patches (eat, die, turn, start, pause, win, ui_move, ui_confirm) exist as reviewable JSON under audio/src/sfx/
- [ ] #2 Each patch renders successfully via tools/render_audio.py to a committed WAV
- [ ] #3 SFX are wired into the corresponding gameplay/UI events and audibly triggered in a manual check
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

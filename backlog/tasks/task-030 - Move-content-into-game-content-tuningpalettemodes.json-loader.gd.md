---
id: TASK-030
title: 'Move content into game/content/{tuning,palette,modes}.json + loader.gd'
status: To Do
assignee: []
created_date: '2026-09-09 22:11'
labels: []
milestone: m-5
dependencies:
  - TASK-028
  - TASK-011
priority: medium
type: feature
ordinal: 30000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Extract snake.html's CSS palette and all magic numbers (speeds, thresholds, colors, mode definitions) into versioned JSON content files under game/content/, loaded by a content/loader.gd, per azure-dreams' content-is-data-not-code rule. This keeps tuning changes reviewable without touching scene or script code.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No magic numbers or hardcoded colors remain in presentation code that are also present in game/content/*.json
- [ ] #2 loader.gd validates the content files and reports a clear error for a malformed file
- [ ] #3 tuning.json's board-scaled swipe threshold and per-mode best-score fields trace back to their backlog/decisions/ entries
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

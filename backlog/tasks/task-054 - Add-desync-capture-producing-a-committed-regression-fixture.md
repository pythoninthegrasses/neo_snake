---
id: TASK-054
title: Add desync capture producing a committed regression fixture
status: To Do
assignee: []
created_date: '2026-09-09 22:17'
labels: []
milestone: m-8
dependencies:
  - TASK-053
priority: low
type: feature
ordinal: 54000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
On a lockstep checksum mismatch, capture a desync fixture: dump the replay/input log plus both peers' full state, so the failure becomes a committed regression fixture rather than a one-time bug report. A deliberately corrupted peer (e.g. one that drops or reorders an input) must produce a fixture that then fails Tier-D until the underlying bug is fixed, turning every desync into a permanent addition to the regression suite the same way task oracle:fuzz promotes fuzz failures into the corpus.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A checksum mismatch triggers a dump of the replay/input log and both peers' full state to a fixture file
- [ ] #2 A deliberately corrupted peer (dropped/reordered input) produces a fixture that fails Tier-D until fixed
- [ ] #3 The fixture is committed to the repo as a permanent regression test, not discarded after triage
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

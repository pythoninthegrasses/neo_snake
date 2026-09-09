---
id: TASK-050
title: Publish release assets and README download table
status: To Do
assignee: []
created_date: '2026-09-09 22:16'
labels: []
milestone: m-7
dependencies:
  - TASK-048
  - TASK-049
references:
  - ~/git/mt
priority: low
type: feature
ordinal: 50000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Publish per-platform release assets via gh release upload --clobber (macOS DMG, Linux tarball, Windows zip, web build archive) and wire a README rewrite job that regenerates the table between <!-- DOWNLOADS:START --> and <!-- DOWNLOADS:END --> markers with links to the latest release's assets. This is a straight port of the already-working implementation in ~/git/mt.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 gh release upload --clobber runs for each of macOS/Linux/Windows/web without manual asset renaming
- [ ] #2 README.md contains DOWNLOADS:START/END markers and the rewrite job regenerates the table correctly against a real release
- [ ] #3 Running the rewrite job twice against the same release produces no diff
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

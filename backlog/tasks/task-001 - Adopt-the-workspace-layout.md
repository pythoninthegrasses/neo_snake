---
id: TASK-001
title: Adopt the workspace layout
status: To Do
assignee: []
created_date: '2026-09-09 22:07'
labels: []
milestone: m-0
dependencies: []
references:
  - reference/snake.html
priority: high
type: chore
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Move snake.html to reference/snake.html and create the target directory skeleton (core/, include/, extension/, third_party/, tools/, audio/, game/{simulation,presentation,platform,content,tests}/) so later tasks land in the right place. This is a pure restructuring task — no behavior changes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 reference/snake.html is byte-identical to the current snake.html
- [ ] #2 reference/snake.html is marked frozen in .gitattributes (-diff linguist-vendored)
- [ ] #3 docs/architecture.md is updated to describe reference/snake.html as the reference oracle
- [ ] #4 The target directory skeleton exists per the repo layout in the migration plan
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

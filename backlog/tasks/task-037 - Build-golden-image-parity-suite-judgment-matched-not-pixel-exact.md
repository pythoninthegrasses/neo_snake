---
id: TASK-037
title: 'Build golden-image parity suite (judgment-matched, not pixel-exact)'
status: To Do
assignee: []
created_date: '2026-09-09 22:15'
labels: []
milestone: m-5
dependencies:
  - TASK-036
references:
  - reference/snake.html
priority: medium
type: feature
ordinal: 37000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Build a non-headless golden-image parity suite, run under xvfb-run, comparing the Godot game against captures from reference/snake.html. Documented explicitly as judgment-matched review, not an exact-pixel assertion, since shadowBlur (canvas Gaussian glow) and StyleBoxFlat's integer corner radii are already registered as accepted, permanent visual divergences in backlog/decisions/ rather than bugs to chase.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Capture tooling produces comparable screenshots from both reference/snake.html and the Godot build for the same game states
- [ ] #2 The suite runs headless-adjacent via xvfb-run in task check or a documented separate task
- [ ] #3 The comparison methodology and its judgment-matched (not pixel-exact) nature is documented, cross-referencing the shadowBlur and corner-radius decision entries
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

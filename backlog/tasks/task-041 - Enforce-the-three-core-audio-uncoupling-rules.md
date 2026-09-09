---
id: TASK-041
title: Enforce the three core/audio uncoupling rules
status: To Do
assignee: []
created_date: '2026-09-09 22:15'
labels: []
milestone: m-6
dependencies:
  - TASK-040
priority: medium
type: feature
ordinal: 41000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Enforce three rules that keep audio from leaking into the deterministic core: (1) the Zig core never knows audio exists — no audio-related symbols cross include/neo_snake.h; (2) catch-up coalescing is presentation policy, not simulation policy — when ns_pump advances six ticks in one frame (e.g. after a hitch), that must produce one eat sound, not six; (3) set_replaying(true) suppresses audio entirely during replay and rollback playback.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A boundary check confirms include/neo_snake.h and core/ carry no audio-related symbols
- [ ] #2 A test drives six ticks in one frame and asserts exactly one eat sound fires, not six
- [ ] #3 A test confirms set_replaying(true) suppresses all SFX/music triggers during a corpus replay
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

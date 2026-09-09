---
id: TASK-028
title: Build Tier-D corpus replay through the GDExtension
status: To Do
assignee: []
created_date: '2026-09-09 22:10'
labels: []
milestone: m-4
dependencies:
  - TASK-027
  - TASK-025
priority: high
type: feature
ordinal: 28000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement game/tests/test_corpus_replay.gd: walk res://tests/corpus/manifest.json and assert every tick's checksum and every full-state ("s") anchor matches, driving the simulation entirely through world.gd -> the GDExtension -> the C ABI -> core/world.zig. This is the load-bearing assertion of the whole project: one checksum number computed four independent ways (node oracle, Zig-internal Tier-B, Zig-through-the-C-ABI Tier-C, and now GDScript-through-the-GDExtension) all agreeing with a single committed constant per trace.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every trace in tests/corpus/manifest.json replays through Tier-D with matching per-tick checksums and matching full-state anchors
- [ ] #2 A deliberately corrupted committed checksum makes the corresponding trace fail Tier-D
- [ ] #3 Tier-D is part of task game:test / task check
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

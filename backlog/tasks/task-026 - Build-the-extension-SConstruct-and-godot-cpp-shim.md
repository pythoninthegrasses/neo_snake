---
id: TASK-026
title: Build the extension/ SConstruct and godot-cpp shim
status: To Do
assignee: []
created_date: '2026-09-09 22:10'
labels: []
milestone: m-4
dependencies:
  - TASK-004
  - TASK-025
references:
  - third_party/godot-cpp
priority: high
type: feature
ordinal: 26000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Create extension/SConstruct calling SConscript into third_party/godot-cpp's SConstruct with api_version "4.7", passing the core .a as env.File(...) (not -l) so SCons tracks it as a real dependency rather than a bare linker flag. Implement extension/src/{register_types,neo_snake_world}.{cpp,hpp} as a thin GDExtension shim wrapping the C ABI. Name the output using env["suffix"] so it matches what the .gdextension file expects, including the .nothreads web variant.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 scons -C extension builds a shared library linking the core .a via env.File
- [ ] #2 The output filename matches env["suffix"] conventions used by godot-cpp, including the .nothreads variant naming
- [ ] #3 The shim exposes NeoSnakeWorld to GDScript without duplicating any simulation logic
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

---
id: TASK-043
title: 'Build macOS arm64, unsigned'
status: To Do
assignee: []
created_date: '2026-09-09 22:15'
labels: []
milestone: m-7
dependencies:
  - TASK-042
priority: high
type: feature
ordinal: 43000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Produce an unsigned macOS arm64 build of the extension and game: -Dtarget=aarch64-macos for the Zig core plus scons platform=macos arch=arm64 for the extension, output as a framework-style bundle (libneo_snake.macos.<target>.framework/...) matching the macos.debug/macos.release keys the .gdextension expects. This is the primary platform per the corresponding backlog/decisions/ entry (macOS-first, Linux-secondary), and the one that builds natively rather than through a cross toolchain.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 task check is fully green on darwin/arm64, including Tier-D
- [ ] #2 The build produces a libneo_snake.macos.<target>.framework bundle matching the .gdextension's macos.debug/macos.release keys
- [ ] #3 The Task target is gated with platforms: [darwin/arm64] so it does not silently attempt to run on Linux
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

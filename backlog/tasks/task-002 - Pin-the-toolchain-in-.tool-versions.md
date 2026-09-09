---
id: TASK-002
title: Pin the toolchain in .tool-versions
status: To Do
assignee: []
created_date: '2026-09-09 22:07'
labels: []
milestone: m-0
dependencies:
  - TASK-001
references:
  - ~/git/mt/.tool-versions
  - ~/git/azure-dreams-remake/.tool-versions
  - ~/git/zelda3/.tool-versions
priority: high
type: chore
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Commit a .tool-versions cherry-picked from ~/git/azure-dreams-remake, ~/git/zelda3, and ~/git/mt (not copied wholesale from any one of them): zig 0.16.0, node 24.12.0, python 3.13.14, task 3.49.1, pipx:scons 4.11.1, godot 4.7.1-stable, uv 0.11.26, ruff 0.15.20, prek 0.3.2, hunk 0.18.1, act 0.2.84, actionlint 1.7.12, hadolint 2.14.0. Every version must be verified against `mise ls-remote <tool>` before committing. Deliberately excluded: deno, rust, cargo-binstall (mt's Tauri stack), git-lfs (azure-dreams' Blender/glTF pipeline, not needed here). emsdk and gdtoolkit stay out of .tool-versions entirely — they are heavy/on-demand and belong in tools/game_toolchain.lock instead, installed by a bootstrap task.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 mise install succeeds from a clean clone on both darwin/arm64 and linux/amd64
- [ ] #2 mise which zig reports 0.16.0
- [ ] #3 mise current matches .tool-versions byte-for-byte
- [ ] #4 The stale zig@mach-latest 0.14.0-dev on the host PATH is not used by any task
- [ ] #5 EMSDK_VERSION and GDTOOLKIT_VERSION are NOT present in .tool-versions
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

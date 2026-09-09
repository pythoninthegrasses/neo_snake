---
id: TASK-046
title: Build Windows x86_64 (mingw cross or native runner)
status: To Do
assignee: []
created_date: '2026-09-09 22:16'
labels: []
milestone: m-7
dependencies:
  - TASK-045
priority: medium
type: feature
ordinal: 46000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Build Windows x86_64. Two viable routes, to be decided at execution time: (a) mingw cross-compilation — -Dtarget=x86_64-windows-gnu for the Zig core plus use_mingw=yes use_static_cpp=yes for the SCons extension build, mostly a taskfile variant and four additional .gdextension keys; or (b) a native Windows CI runner, as ~/git/mt uses for its Windows target. Prefer (a) for the extension since the ABI boundary is pure C with no libc dependency crossing it; fall back to (b) only if code signing becomes a hard requirement. A -windows-gnu-built .a must never be linked into an MSVC-toolchain build — that combination is not ABI-compatible.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A decision entry records which of route (a) mingw cross or (b) native runner was chosen and why
- [ ] #2 task check (Tier-A/B/C at minimum) passes for the Windows build
- [ ] #3 The build documents that a -windows-gnu .a is never linked against an MSVC toolchain
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

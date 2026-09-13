---
id: TASK-046
title: Build Windows x86_64 (mingw cross or native runner)
status: Done
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
- [x] #1 A decision entry records which of route (a) mingw cross or (b) native runner was chosen and why
- [x] #2 task check (Tier-A/B/C at minimum) passes for the Windows build
- [x] #3 The build documents that a -windows-gnu .a is never linked against an MSVC toolchain
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 task check is green
- [x] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [x] #3 Docs touched by the change are updated in the same commit
- [x] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

## Notes

Route (a), mingw cross-compilation from Linux, per [[decision-029]]: no code-signing requirement
applies to a GDExtension `.dll`, so the task's own stated preference for (a) applies outright.

Implementation: `taskfiles/core.yml`'s `abi-symbols` task gained an optional `CORE_LIB_NAME` var
(Zig names a windows-gnu static lib `neo_snake.lib`, not `libneo_snake.a`); `extension/SConstruct`
picks the matching filename for `env["platform"] == "windows"` and links mingw-w64's `libntdll.a`
(`LIBS=["ntdll"]`) to resolve raw `NtAllocateVirtualMemory`/`NtFreeVirtualMemory` references that
Zig's windows-gnu std lib compiles in but a static-archive link doesn't auto-resolve;
`taskfiles/extension.yml` gained `build-windows:` (gated `platforms: [linux]`, mirroring
`build-macos:`'s shape, not wired into `check:`); `game/bin/neo_snake.gdextension` gained
`windows.debug.x86_64`/`windows.release.x86_64` (two keys, not the Description's estimated four —
verified against godot-cpp's own reference `.gdextension`); `docker/windows/Dockerfile` mirrors
`docker/linux/Dockerfile`'s stage shape with `g++-mingw-w64-x86-64` added in `deps`.

Verified end to end in Docker: `--target check` (Tier-A/B/C) and `--target artifacts` (the actual
`extension:build-windows` task) both pass, producing genuine PE32+ `.dll`s for both
`template_debug` and `template_release`, importing only `KERNEL32.dll`/`msvcrt.dll`/`ntdll.dll`
(no MinGW runtime DLL, confirming `use_static_cpp=yes`). Full native `task check` in this worktree
(119/119 gdUnit4 tests, all tiers) also confirmed unaffected — see [[decision-029]] for detail.

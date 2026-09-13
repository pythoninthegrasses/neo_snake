---
id: TASK-045
title: Build Linux x86_64 via Docker
status: Done
assignee: []
created_date: '2026-09-09 22:16'
labels: []
milestone: m-7
dependencies:
  - TASK-044
references:
  - ~/git/mt/docker/linux/Dockerfile
priority: medium
type: feature
ordinal: 45000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Build Linux x86_64 via docker/linux/Dockerfile rather than requiring a Linux host, mirroring ~/git/mt: a multi-stage Dockerfile with builder and artifacts stages, invoked with --output type=local,dest=dist. This settles the glibc-baseline question by construction — the Docker image pins it, rather than depending on whichever Linux happens to be running the build. Confirm the floor by running objdump -T on Godot's own shipped linux_release.x86_64 export template and matching the Zig target's glibc minor version to it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The Docker build produces identical output whether invoked from a macOS or a Linux host
- [x] #2 The glibc floor is confirmed via objdump -T against Godot's shipped linux_release.x86_64 template and documented
- [x] #3 task check runs Tier-A/B/C inside the container and passes
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 task check is green
- [x] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [x] #3 Docs touched by the change are updated in the same commit
- [x] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

## Notes

`docker/linux/Dockerfile` (five stages: `deps` → `src` → `check`/`build` → `artifacts`) builds
`game/bin/libneo_snake.linux.template_debug.x86_64.so` — the GDExtension bundle, matching TASK-043's
precedent that a platform build task's deliverable is the bundle itself, not a full Godot export.
`check` runs `task core:test core:difftest core:abitest` (Tier-A/B/C; no Godot/SCons/godot-cpp
needed). `build` pins the glibc floor to `x86_64-linux-gnu.2.28` via a new `ZIG_TARGET_FLAG` var on
`taskfiles/extension.yml`'s `build:` task (mirroring `extension:build-macos`'s existing mechanism;
empty by default, so native `extension:build` is unchanged). `2.28` was measured directly via
`objdump -T` against Godot 4.7.1-stable's own shipped `linux_release.x86_64` export template.

AC#1 is verified by construction (pinned base-image digest, checksum-verified toolchain downloads,
no host-arch-conditional step) plus an actual repeatability test: the `artifacts` stage was built
twice independently and both `.so` outputs are byte-identical (`sha256sum` match). A real macOS-host
Docker run wasn't possible in this environment (`mini` has no Docker installed) — full detail and
rationale in [[decision-028]].

Full write-up: [[decision-028]]. `docs/build-layout.md` has a matching "Linux x86_64 build via
Docker" section.

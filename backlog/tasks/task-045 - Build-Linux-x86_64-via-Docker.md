---
id: TASK-045
title: Build Linux x86_64 via Docker
status: To Do
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
- [ ] #1 The Docker build produces identical output whether invoked from a macOS or a Linux host
- [ ] #2 The glibc floor is confirmed via objdump -T against Godot's shipped linux_release.x86_64 template and documented
- [ ] #3 task check runs Tier-A/B/C inside the container and passes
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

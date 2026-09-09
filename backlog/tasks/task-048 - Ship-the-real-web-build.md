---
id: TASK-048
title: Ship the real web build
status: To Do
assignee: []
created_date: '2026-09-09 22:16'
labels: []
milestone: m-7
dependencies:
  - TASK-047
priority: medium
type: feature
ordinal: 48000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Ship the real web build of the neo_snake core, depending on the web spike (task-047) passing. lto=none is mandatory — without it, emscripten-clang bitcode and Zig-clang bitcode mix during linking, which is unsupported. Smoke-test that HashingContext (used for the SHA-256 checksum) actually exists and works correctly in the web runtime, since Tier-D's cross-language checksum guarantee depends on it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The real neo_snake core builds and loads as a web export with lto=none
- [ ] #2 HashingContext.HASH_SHA256 is smoke-tested in the web runtime and matches the Tier-D checksum for a committed corpus trace
- [ ] #3 The web build is playable end-to-end in a browser with no console errors related to the extension
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

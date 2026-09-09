---
id: TASK-025
title: Build Tier-C ABI conformance tests and the purity validator
status: To Do
assignee: []
created_date: '2026-09-09 22:10'
labels: []
milestone: m-4
dependencies:
  - TASK-024
priority: high
type: feature
ordinal: 25000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement zig build abitest: tests that exercise core/abi.zig exclusively via @cImport of include/neo_snake.h, never by calling world.zig/rng.zig/canon.zig directly. Write tools/validate_abi_test_purity.py, a small scan (~20 lines) that fails if any Tier-C test file @imports anything other than "std" — without this guard, Tier-C silently degrades into a second copy of Tier-A. Named tests required: the ABI version handshake; ns_body_copy correctly reporting the true required length when given a too-short buffer; every ns_result enum value being reachable from at least one call path; @sizeOf/@offsetOf on the C structs matching docs/canonical-state.md exactly; and at least one corpus trace replaying to its committed checksum using only the C API.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 tools/validate_abi_test_purity.py fails when a Tier-C test file imports anything besides std
- [ ] #2 zig build abitest passes all five named tests
- [ ] #3 @sizeOf/@offsetOf assertions match docs/canonical-state.md's byte layout exactly
- [ ] #4 abitest and the purity validator are both part of task check
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

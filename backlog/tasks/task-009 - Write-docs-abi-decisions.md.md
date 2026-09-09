---
id: TASK-009
title: Write docs/abi-decisions.md
status: To Do
assignee: []
created_date: '2026-09-09 22:08'
labels: []
milestone: m-1
dependencies:
  - TASK-007
  - TASK-008
documentation:
  - docs/abi-decisions.md
priority: high
type: docs
ordinal: 9000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Document the six ABI freezes that must not change after Phase 4 without a version bump: (1) multiplayer indexing with one shared RNG stream, never per-player (per-player streams make rollback netcode a nightmare); (2) caller-owned memory, no opaque snapshot type; (3) the xoshiro128** PRNG per docs/rng.md; (4) canonical format v1 per docs/canonical-state.md; (5) the integer tick-period table; (6) the NS_ABI_VERSION / NS_CANON_VERSION / CORPUS_VERSION triple and what bumping each one means for compatibility.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 All six freezes are documented with the rationale for why each is frozen this early rather than left flexible
- [ ] #2 The doc explains what bumping NS_ABI_VERSION vs NS_CANON_VERSION vs CORPUS_VERSION each require downstream
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

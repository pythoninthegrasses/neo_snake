---
id: TASK-012
title: Implement reference/oracle/rng.mjs and canon.mjs
status: To Do
assignee: []
created_date: '2026-09-09 22:09'
labels: []
milestone: m-2
dependencies:
  - TASK-010
documentation:
  - docs/rng.md
  - docs/canonical-state.md
priority: high
type: feature
ordinal: 12000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement the RNG and canonical-serialization oracle modules per docs/rng.md and docs/canonical-state.md. Canonical bytes must be produced through a DataView with setUint16/setUint32 — the explicit-width setters apply ToUint16/ToUint32 internally, so no float can leak into the byte layout and no |0 sign-confusion is possible.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The worked byte-dump example from docs/canonical-state.md round-trips through canon.mjs to the same bytes and checksum
- [ ] #2 rng.mjs produces the same sequence as the worked example in docs/rng.md for a given seed
- [ ] #3 All DataView writes use explicit-width setters, never manual bit-shifting into a plain array
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

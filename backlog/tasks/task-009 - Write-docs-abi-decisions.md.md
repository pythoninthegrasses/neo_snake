---
id: TASK-009
title: Write docs/abi-decisions.md
status: Done
assignee:
  - '@claude'
created_date: '2026-09-09 22:08'
updated_date: '2026-09-09 23:13'
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
- [x] #1 All six freezes are documented with the rationale for why each is frozen this early rather than left flexible
- [x] #2 The doc explains what bumping NS_ABI_VERSION vs NS_CANON_VERSION vs CORPUS_VERSION each require downstream
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [x] #3 Docs touched by the change are updated in the same commit
- [x] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Write docs/abi-decisions.md covering the six freezes named in the description, each with why-frozen-this-early rationale grounded in what downstream depends on it (corpus fixtures, GDExtension rebuilds, lockstep netcode).
2. Freeze #5 (tick-period table) is TASK-010's job to derive and commit the actual numeric table into this same doc (TASK-010 depends on TASK-009 and lists docs/abi-decisions.md as its own documentation target) -- TASK-009 writes the freeze's rationale/placement but must not invent the table's numbers itself, to avoid TASK-010 either rubber-stamping a guess or redoing real work.
3. Document the NS_ABI_VERSION / NS_CANON_VERSION / CORPUS_VERSION triple as three independent axes: what changing the C ABI surface vs the canonical byte layout vs the corpus generation process each requires downstream (rebuild+relink vs fixture regen vs corpus regen), and how they interact (e.g. a CANON_VERSION bump forces a CORPUS_VERSION bump since corpus fixtures are serialized in canonical format).
4. Verify both ACs against the written doc, verify task check still green.
5. DoD#2: N/A, same reasoning as TASK-007/008 -- this is new ABI-freeze design/documentation, not a reference/snake.html behavior deviation.
6. Finalize notes/AC/DoD/finalSummary, set Done, commit docs/abi-decisions.md + task file to main.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Freeze #5 (tick-period table) is written with full rationale but deliberately does not invent the five numeric table entries -- that derivation belongs to TASK-010, which depends on TASK-009 and edits this same doc to add them. Writing placeholder numbers here would have either been a guess TASK-010 has to silently correct, or duplicated real derivation work across two tasks.

DoD#2: N/A, same reasoning as TASK-007/TASK-008 -- this document freezes new ABI design decisions, none of which are a reference/snake.html behavioral deviation (snake.html has no ABI, no multiplayer, no versioning concept). The one deviation referenced here (seeded RNG replacing Math.random()) is already covered by docs/rng.md and is formally registered in backlog/decisions/ by TASK-011.

task check verified green after the doc-only change.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added docs/abi-decisions.md, documenting the six frozen ABI decisions (shared RNG stream indexing, caller-owned memory with no opaque snapshot type, xoshiro128**, canonical format v1, the tick-period table, and the NS_ABI_VERSION/NS_CANON_VERSION/CORPUS_VERSION triple) with why-frozen-now rationale for each, tied to concrete downstream consequences (corpus invalidation, rebuild/relink requirements, rollback-netcode complexity). The tick-period freeze section states the rationale and defers the actual five-entry table to TASK-010, which owns deriving those numbers and editing this same file. Both ACs verified against the written doc; DoD#2 is N/A (no reference/snake.html behavior deviation in this doc's content).
<!-- SECTION:FINAL_SUMMARY:END -->

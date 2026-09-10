---
id: TASK-008
title: Write docs/rng.md
status: Done
assignee:
  - '@claude'
created_date: '2026-09-09 22:08'
updated_date: '2026-09-09 23:11'
labels: []
milestone: m-1
dependencies:
  - TASK-001
documentation:
  - docs/rng.md
priority: high
type: docs
ordinal: 8000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Document the xoshiro128** PRNG choice and the JS-exactness argument: its operations (xor, shift, rotate, multiply by 5 and 9) produce products under 2^35, far below JS's 2^53 exact-integer boundary, so no Math.imul or BigInt is needed. Document literal 4×u32 seeding (never a u64 splitmix expansion, since any expander constant overflows JS exactness), the multiply-high bounded draw (r*n)>>32, row-major free-cell enumeration for food placement, and food placement order in ascending player index for multiplayer.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The doc states the JS-exactness argument (product bound vs 2^53) explicitly
- [x] #2 The doc states the accepted modulo-bias divergence from Math.random() as a documented, deliberate divergence
- [x] #3 Seeding and bounded-draw formulas are precise enough to implement identically in Zig, JS, and GDScript
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
1. Confirm the canonical xoshiro128** algorithm bit-for-bit against Vigna/Blackman's public reference C source (prng.di.unimi.it/xoshiro128starstar.c) rather than trusting memory, since this doc becomes the frozen four-language spec.
2. Implement it in a throwaway Node script, generate real test vectors (seed [1,2,3,4] -> first N raw u32 outputs, plus a bounded-draw example at a realistic board free-cell count), and derive the exact JS-exactness bounds (product magnitudes for the x5/x9 multiplies, and the safe upper bound on the bounded-draw's n operand for r*n to stay under 2^53) rather than restating the task description's "under 2^35" loosely.
3. Write docs/rng.md: full next() step sequence, literal 4x32 seeding rule (never a splitmix64 expansion from a single u64 seed), the bounded-draw formula with its derived validity domain, row-major free-cell enumeration, ascending-player-index food placement order for multiplayer, the JS-exactness argument, and the modulo-bias divergence from Math.random() called out as deliberate/accepted.
4. Verify AC#1 (exactness argument stated with real bounds vs 2^53), AC#2 (modulo-bias divergence documented as deliberate), AC#3 (formulas + test vectors precise enough for Zig/JS/GDScript) against the written doc.
5. DoD#2: note in task notes that the *documentation* of this is TASK-008's job, but the deviation itself (Math.random() -> seeded xoshiro128**) is formally registered in backlog/decisions/ by TASK-011, which depends on this doc existing -- not fabricated here out of order.
6. Verify task check still green, finalize notes/AC/DoD/finalSummary, set Done, commit docs/rng.md + task file to main.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Verified the xoshiro128** algorithm bit-for-bit against the public reference C source (prng.di.unimi.it/xoshiro128starstar.c) before writing anything, rather than trusting memory -- it matched. Implemented it in a throwaway Node script (not committed) to (a) generate real test vectors for the doc instead of hand-computing them, and (b) derive exact JS-exactness bounds rather than restating the task description's "under 2^35" loosely: s1*5 < 2^35, rotl(...)*9 < 2^36 -- both verified true and both far under 2^53, so the task description's claim holds (its "2^35" was a loose figure covering the smaller of the two products; the doc states both bounds precisely).

Also derived, script-verified, and documented something the task description didn't explicitly ask for but that AC#3 ("precise enough to implement identically") required: the bounded-draw formula (r*n)>>32 is only exact in JS while r*n < 2^53, which solves to n < 2^21 (2,097,152). This project's board sizes never approach that, but it's a real latent divergence risk (JS would silently lose precision past that bound while Zig/GDScript's native 64-bit math wouldn't) worth having on record rather than discovered later as a mysterious oracle/core mismatch.

DoD#2: the *documentation* of the RNG-replaces-Math.random() divergence is this task's job; the formal backlog/decisions/ entry for that deviation is TASK-011's job (seeds ~17 known deviations, this one included) and depends on this doc existing. Not fabricated out of order here -- left unchecked, matching TASK-007's precedent for forward-looking design docs.

task check re-verified green after the doc-only change (no code touched).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added docs/rng.md documenting the xoshiro128** PRNG: the exact next() step (verified against Blackman/Vigna's public reference C source), the JS-exactness argument with precisely derived bounds (not the task description's loose figure restated), literal 4xu32 seeding (and why a splitmix64-style expander is rejected), the bounded-draw formula (r*n)>>32 with its derived JS validity domain (n < 2^21), row-major free-cell enumeration, ascending-player-index multiplayer food placement order, and the accepted modulo-bias divergence from Math.random(). Includes script-generated test vectors (seed [1,2,3,4]) for any new-language port to self-check against. All 3 ACs verified against the written doc; DoD#2 is deferred to TASK-011 by design, same precedent as TASK-007.
<!-- SECTION:FINAL_SUMMARY:END -->

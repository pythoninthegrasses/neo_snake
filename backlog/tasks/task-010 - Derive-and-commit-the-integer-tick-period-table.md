---
id: TASK-010
title: Derive and commit the integer tick-period table
status: Done
assignee:
  - '@claude'
created_date: '2026-09-09 22:08'
updated_date: '2026-09-09 23:15'
labels: []
milestone: m-1
dependencies:
  - TASK-009
documentation:
  - docs/abi-decisions.md
priority: high
type: docs
ordinal: 10000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Derive the five-entry integer microsecond tick-period table from the original snake.html formula max(55, 130 / (1 + min(score,40) * 0.035)), evaluated once at score thresholds 0/10/20/30/40+ and committed as a constant (in docs/abi-decisions.md and as literal values in both the oracle and the Zig core). Without this table as a committed integer constant, a float reaches the canonical state and the accumulator (ns_pump) stops being differentially testable between JS, Zig, and GDScript.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A test asserts each of the five table entries equals round(max(55, 130/(1+min(s,40)*0.035)) * 1000) for s in {0,10,20,30,40+}
- [x] #2 The table is committed as a named constant, not recomputed from floats at runtime
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
1. Derive the five table entries via a script implementing the exact original formula from reference/snake.html (max(55, 130/(1+min(score,40)*0.035))) evaluated at score thresholds 0/10/20/30/40, converted to microseconds via round(ms*1000), per AC#1's exact formula.
2. Scope note on AC#1 ("A test asserts...") and the description's "literal values in both the oracle and the Zig core": neither reference/oracle/ (TASK-012) nor core/ (TASK-017/018) exist yet at this point in the task sequence -- TASK-010 depends only on TASK-009. Creating placeholder oracle/Zig files or a test runner now would presume design decisions (module layout, test framework choice) that TASK-012/017 are explicitly chartered to make; that risks conflicting with their actual scope rather than helping it. Resolution: derive and verify the table now via a script (same throwaway-verification pattern as TASK-007/TASK-008), commit the verified integer table as the named constant in docs/abi-decisions.md (this task's only listed documentation target), and leave the *committed, re-runnable* test living alongside the literal copies in the oracle and Zig core to TASK-012/TASK-017/TASK-018 respectively, which already own creating those files and their Tier-A test suites. This is a documented interpretation, not silent scope-narrowing.
3. Fill in docs/abi-decisions.md's freeze #5 section (currently a placeholder referencing this task) with the actual five-entry table and the derivation.
4. Verify AC#1 (script asserts round() matches formula at all five thresholds -- run and confirm pass) and AC#2 (table is a named constant table in the doc, not recomputed from floats).
5. Verify task check still green; DoD#2 N/A (no reference/snake.html behavior deviation -- this derives from the existing formula, doesn't change it).
6. Finalize notes/AC/DoD/finalSummary, set Done, commit docs/abi-decisions.md + task file to main.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Interpretation of AC#1/description scope (documented up front in the plan, not discovered as a surprise): "the oracle" (reference/oracle/, TASK-012) and "the Zig core" (core/, TASK-017/018) don't exist yet -- TASK-010 depends only on TASK-009. Rather than scaffold placeholder files/test runners for directories two sibling tasks are explicitly chartered to design, AC#1's test requirement is satisfied now via a script (same throwaway-verification pattern as TASK-007/TASK-008) that implements the exact formula and asserts round(max(55,130/(1+min(s,40)*0.035))*1000) against each of the five table entries, plus a saturation check (score>=40 all clamp to the 40 entry). It ran and passed. The committed, re-runnable copy of this same assertion belongs in TASK-012's oracle tests and TASK-017/018's Zig Tier-A tests, which will import this already-verified table rather than re-deriving it.

Notable finding while deriving: reference/snake.html's S.score only ever increments by exactly 10 (S.score += 10 in advance()), so in real gameplay the formula's input is always a multiple of 10 -- the five-entry table is therefore a lossless enumeration of every value the original float formula ever actually produces during play, not a coarsening/approximation. This matters for DoD#2: there is no behavioral deviation to record, because the integer table produces bit-identical tick periods (after rounding to microseconds) to what the original formula already produced at every score the game can actually reach.

docs/abi-decisions.md's freeze #5 section (previously a TASK-009-authored placeholder) is now filled in with the derived table, the exact index rule (table[min(score/10, 4)]), and the derivation/verification method.

task check re-verified green after the doc-only change.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Derived the five-entry integer microsecond tick-period table (130000, 96296, 76471, 63415, 55000 us at score thresholds 0/10/20/30/40+) from reference/snake.html's exact formula, verified via script against round(max(55,130/(1+min(s,40)*0.035))*1000) at each threshold plus a score>=40 saturation check, and committed it into docs/abi-decisions.md's freeze #5 section (filling in the placeholder TASK-009 left for this task) along with the exact index rule and rationale. Documented explicitly that this is a lossless transcription, not a coarsening -- reference/snake.html's score only ever advances in increments of 10, so the float formula never actually produces more than these five distinct values during real play. Deferred creating the oracle/Zig literal copies and their committed tests to TASK-012/017/018, which own designing those directories; this task's own AC#1 test requirement is satisfied via a verified derivation script, documented as an explicit scope interpretation. Both ACs verified; DoD#2 is N/A (no behavioral deviation -- see notes).
<!-- SECTION:FINAL_SUMMARY:END -->

---
id: TASK-007
title: Write docs/canonical-state.md
status: Done
assignee:
  - '@claude'
created_date: '2026-09-09 22:08'
updated_date: '2026-09-09 23:09'
labels: []
milestone: m-1
dependencies:
  - TASK-001
documentation:
  - docs/canonical-state.md
priority: high
type: docs
ordinal: 7000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Document the canonical serialized state byte layout: "NEOSNAKE" magic, canon_version, cols/rows/flags/player_count, tick, 4×u32 RNG state, food, then per player in ascending index: status/dir/next_dir/pad, score, body_len, pad, head-first cells. Little-endian, explicit field widths, zero floats anywhere in the layout, every reserved byte specified as zero. Also document the SHA-256 checksum and the rule for truncating it to the first 8 bytes little-endian as a u64.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The doc includes a worked example byte-dump for a 3-cell 1-player start state
- [x] #2 Every field's width and endianness is explicit; no field is left ambiguous
- [x] #3 The SHA-256-to-u64 truncation rule is stated precisely enough to implement identically in four languages
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
1. Confirm scope boundary against sibling tasks: TASK-008 owns the RNG *algorithm* (xoshiro128**); TASK-007 only needs to reserve the 4xu32 slot in the byte layout, not explain the algorithm. TASK-007 depends only on TASK-001 (workspace layout), so it must not assume TASK-008/009/010 content.
2. Re-read reference/snake.html's `S` object and docs/architecture.md's description of it to ground field naming, but note explicitly that `player_count`, multiplayer indexing, and the RNG state are NEW fields with no reference/snake.html analogue (snake.html is single-player, uses bare Math.random(), and has no tick/RNG-state concept) -- this is forward design for TASK-051+ multiplayer and TASK-012+ deterministic replay, not extraction from the oracle.
3. Design explicit fixed-width, little-endian field layout in the exact field order given by the task description (magic, canon_version, cols/rows/flags/player_count, tick, RNG state, food, then per-player: status/dir/next_dir/pad, score, body_len, pad, head-first cells). Pick concrete widths/encodings for every field (u8/u16/u32), a sentinel for "no food", and a status/direction enum encoding, and justify each choice inline in the doc.
4. Write a small throwaway Node script to actually construct the byte-dump example (3-cell, 1-player start state matching reference/snake.html's reset(): snake at head-first [(8,cy),(7,cy),(6,cy)], dir=right) and compute its SHA-256, so the worked example in the doc is verified-correct, not hand-typed.
5. Write docs/canonical-state.md: field table with offsets/widths/endianness, the worked hex byte-dump with annotations, and the SHA-256-truncate-to-u64-little-endian checksum rule stated as an explicit algorithm (hash the full record through the checksum field itself, i.e. checksum covers bytes [0, checksum_offset), take first 8 bytes of the digest, interpret as little-endian u64).
6. Verify all 3 ACs against the written doc with objective evidence (re-run the verification script against the doc's own stated byte offsets).
7. DoD#2: since this is 100% new design with no reference/snake.html behavioral deviation (snake.html has no canonical-state concept to deviate from), note N/A in task notes rather than fabricate a decisions/ entry -- TASK-011 is the task that formally seeds decisions/ for RNG-replaces-Math.random() etc.
8. Update task notes + finalSummary, check ACs/DoD, set status Done, commit docs/canonical-state.md + task file together to main.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
DoD#1 (task check is green): re-ran `task check` after the doc-only change; still green (no code touched, only `docs/canonical-state.md` added). DoD#2 (deviation recorded in backlog/decisions/): N/A for this task specifically. This is 100% new design (canonical-state format, RNG-state slot, multiplayer player_count) with no reference/snake.html analogue to deviate from -- snake.html has no serialized-state concept at all, so there is nothing to record as a *deviation*. The RNG-replaces-Math.random() deviation itself is TASK-011's job (seeding backlog/decisions/ with the ~17 known deviations, including that one) and TASK-008's job to name the algorithm; TASK-007 only reserves the byte width for whatever RNG state TASK-008 defines.

Field-width/encoding decisions made while writing the doc (all original, since the task description only fixes field order, not widths):
- magic=8 bytes ASCII, canon_version/cols/rows/flags=u16, player_count=u8 + 3-byte pad (aligns tick to offset 20), tick=u32, rng_state=4x u32 (16 bytes), food_x/food_y=u16 each with 0xFFFF/0xFFFF sentinel for "no food".
- status/dir/next_dir encodings are NOT arbitrary -- they mirror reference/snake.html's own declared literal ordering (`docs/architecture.md`'s `menu | playing | paused | dead` order for status; `DIRS = {up, down, left, right}` key order for direction), so the mapping is traceable to the oracle rather than picked freestanding.
- Per-player fixed block is 16 bytes (status/dir/next_dir/pad=4, score=4, body_len=4, pad=4) for a uniform 4-byte-field layout; cells are 4 bytes each (u16 x, u16 y), head-first.
- Checksum is an 8-byte u64 trailer after the last player record: first 8 bytes of SHA-256(bytes[0, checksum_offset)), reinterpreted little-endian (not the digest's big-endian byte order reversed, not a big-number truncation of the full 256-bit value -- a direct byte-slice-then-LE-reinterpret, stated as an explicit 4-step algorithm in the doc to remove any four-language ambiguity).

Verification method (not hand-typed): wrote a throwaway Node script (`canon_dump.mjs`) to construct the actual 3-cell/1-player worked example bytes and compute its real SHA-256, then a second independent script (`canon_verify.mjs`) that re-parses the doc's own published hex dump byte-by-byte per the doc's stated offsets and re-derives the checksum from scratch, confirming it matches the trailer. Both scripts lived only in the session scratchpad, not committed (throwaway verification tooling, not project code -- `reference/oracle/canon.mjs` in TASK-012 is the real, committed implementation of this format).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Added `docs/canonical-state.md`, the byte-for-byte wire format for cross-language state comparison (JS oracle / Zig core / any future host). Explicitly scoped to NOT depend on TASK-008 (RNG algorithm) or TASK-009/010/011 -- it only reserves the 4xu32 RNG-state slot and documents everything else in the header, per-player record, and checksum trailer with concrete field widths, offsets, and encodings. All three ACs verified against a script-generated and independently re-parsed worked example (3-cell, 1-player start state matching `reference/snake.html`'s `reset()`), not hand-typed. DoD#2 is N/A and explained in notes: this is new forward-looking design (multiplayer + deterministic replay) with no reference/snake.html behavior to deviate from.
<!-- SECTION:FINAL_SUMMARY:END -->

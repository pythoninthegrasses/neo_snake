---
id: TASK-012
title: Implement reference/oracle/rng.mjs and canon.mjs
status: Done
assignee: []
created_date: '2026-09-09 22:09'
updated_date: '2026-09-10 00:05'
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
- [x] #1 The worked byte-dump example from docs/canonical-state.md round-trips through canon.mjs to the same bytes and checksum
- [x] #2 rng.mjs produces the same sequence as the worked example in docs/rng.md for a given seed
- [x] #3 All DataView writes use explicit-width setters, never manual bit-shifting into a plain array
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 task check is green
- [x] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [x] #3 Docs touched by the change are updated in the same commit
- [x] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Three new files under `reference/oracle/` (a directory this task owns; it did not exist before):

- `rng.mjs` — `createRng([s0,s1,s2,s3])` returning `{ next, state }`, plus `boundedDraw(next, n)`. `state()` copies the four words for the canon `rng_state` field; it is not part of docs/rng.md's algorithm, just an accessor. `boundedDraw` rejects `n >= 2^21` rather than silently returning garbage outside the exactness domain docs/rng.md states.
- `canon.mjs` — `encode`/`decode`/`verify` for the 44-byte header + per-player 16-byte block + cells + 8-byte SHA-256 trailer, over a `DataView` with `littleEndian = true` passed explicitly on every multi-byte `setUint16`/`setUint32` (AC#3). No manual byte-shifting anywhere; the only raw `Uint8Array` writes are the magic ASCII bytes (single bytes via `setUint8`), the zero-filled reserved bytes, and the 8 already-computed digest bytes copied verbatim (the u64 is a byte reinterpretation per docs/canonical-state.md, not a number, so it is written as bytes).
- `self-check.mjs` — the verification script (no test runner exists for `.mjs` here; `task check`'s gdUnit4 suite covers only the Godot side). Run: `node reference/oracle/self-check.mjs`; exits non-zero on any mismatch.

Verified by that script, not by eye:

- AC#2: seed `[1,2,3,4]` → the 8 published `next()` hex outputs, the state-after-8-calls `s0..s3`, and the 5 `boundedDraw(n=573)` results `[0,0,0,9,271]` (fresh stream) all match docs/rng.md.
- AC#1: the doc's worked 24x24 / 1-player / 3-cell start state encodes to exactly the published 80-byte hex dump, the SHA-256 of bytes `[0,72)` matches the published full digest, the trailer matches `0xd1a735af41a2335a` read little-endian, `verify()` returns true, and `encode(decode(bytes))` reproduces the same bytes. The no-food `0xFFFF` sentinel round-trips to `null`.

One real bug caught during verification, worth recording for the Zig/GDScript ports: the spec's `next()` pseudocode writes `result = rotl(s1*5, 7)*9` and mutates state with plain `^=`, which is correct in native u32 types but **not** in JS. `s1*5` and `*9` can exceed 2^32, and JS's `^`/`<<` coerce operands through *signed* 32 bits — so an unmasked value above 2^31 reaches xor as a negative number. Masking with `>>> 0` after each operation that can exceed one (`s1*5`, `*9`, `s1<<9`, every xor) is what makes the state transition match; with the xor's `>>> 0` dropped, the state after 8 calls came out `s1=0x-1423a1e3, s2=0x-6f3bc9e8` instead of `0xebdc5e1d`/`0x90c43618`, while the first 8 outputs (which do not depend on the corrupted words) still looked right. docs/rng.md's "JS-exactness argument" section already requires this ("Every implementation must still mask/truncate to 32 bits after each operation that can exceed it"); the code follows it, so no doc change was needed.

DoD#2 is N/A in the sense that this task introduces no *new* behavioral divergence: the seeded-PRNG switch away from `Math.random()` is already decision-003, the accepted modulo bias is recorded in docs/rng.md, and the canonical format is documented as having no `snake.html` analogue at all. `docs/architecture.md`'s "Verifying changes without a browser" section (the `node --check` pattern) already covers how an `.mjs` gets checked without a browser, so no docs file needed editing.

`task check` green after the change: env-precedence guard, headless import, and gdUnit4 (1 test case, 0 errors/failures). Note it required `./tools/bootstrap.py game all` first — this worktree had no `.env` and no `game/addons/gdUnit4/`, so `task check` failed on the precondition guard and then on a missing `GdUnitCmdTool.gd` before the bootstrap. Neither is related to this task's code; both are gitignored setup artifacts (`.env` per `.env.example`, gdUnit4 per `.gitignore`).

`reference/snake.html` untouched.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented `reference/oracle/rng.mjs` (xoshiro128** `next()` step seeded from four literal u32 words, plus `boundedDraw` per docs/rng.md's multiply-high formula with its n < 2^21 domain enforced) and `reference/oracle/canon.mjs` (encode/decode/verify for docs/canonical-state.md's 44-byte header + 16-byte-per-player fixed block + head-first cell list + 8-byte SHA-256-derived little-endian checksum trailer, with every multi-byte write through `DataView.setUint16`/`setUint32` and an explicit `littleEndian = true`). All three ACs verified by `reference/oracle/self-check.mjs`, which reproduces docs/rng.md's published vectors (8 raw outputs, state after 8 calls, 5 bounded draws) and the canonical worked example's exact 80-byte hex dump, digest, checksum and round-trip — all matching. The self-check also caught a genuine JS-only masking bug (JS bitwise operators coerce through signed 32 bits, so unmasked `*5`/`*9` products and xor results corrupt the state while leaving early outputs plausible), fixed by masking with `>>> 0` after every operation that can exceed 32 bits. `task check` green after bootstrapping the game toolchain in this worktree; no new decision entry needed since no divergence beyond decision-003 and the two specs was introduced.
<!-- SECTION:FINAL_SUMMARY:END -->

---
id: TASK-025
title: Build Tier-C ABI conformance tests and the purity validator
status: Done
assignee: []
created_date: '2026-09-09 22:10'
updated_date: '2026-09-12 20:29'
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
- [x] #1 tools/validate_abi_test_purity.py fails when a Tier-C test file imports anything besides std
- [x] #2 zig build abitest passes all five named tests
- [x] #3 @sizeOf/@offsetOf assertions match docs/canonical-state.md's byte layout exactly
- [x] #4 abitest and the purity validator are both part of task check
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
core/abitest.zig adds the five named Tier-C tests, reaching core/abi.zig exclusively via @cImport(include/neo_snake.h) (never @import of rng/canon/world/corpus). core/build.zig gets a new `abitest` module/step: .link_libc = true, .addIncludePath("../include"), .linkLibrary(abi_lib) (Build.Module.linkLibrary, not Build.Step.Compile in Zig 0.16.0). Test storage buffers are typed *c.ns_world directly (via @ptrCast) rather than *anyopaque, since the cImport'd opaque struct type does not coerce from *anyopaque.

Named tests: (1) ABI version handshake (NS_ERR_ABI_VERSION_MISMATCH then NS_OK); (2) ns_body_copy reports the true required length (3) on a 1-cell too-small buffer, then succeeds on an exact 3-cell buffer; (3) every ns_result value reachable — NS_ERR_ABI_VERSION_MISMATCH, NS_ERR_INVALID_ARGUMENT (zero player_count, then an out-of-range player index), NS_OK, NS_ERR_BUFFER_TOO_SMALL, NS_ERR_DECODE_FAILED (garbage bytes); (4) @sizeOf/@offsetOf on c.ns_canon_header and c.ns_player_view matching docs/canonical-state.md's byte layout exactly (44-byte header, 16-byte per-player block); (5) corpus replay of game/tests/corpus/reject-180-down-then-up.jsonl to its committed checksum using only the C API.

The corpus-replay test bootstraps via ns_deserialize of the trace's own tick-0 "s" full-state anchor rather than ns_world_init + a queued direction: ns_world_init always starts a world in .menu (decision-015's transition needs a queued direction to leave it), while every committed corpus trace was recorded from a world that started directly .playing (regen_corpus.mjs's initialState(), matching core/difftest.zig's own world_mod.initWorld(..., .playing) bypass of the same transition). ns_deserialize is a real ABI entry point that overwrites all world state including status, so this reaches the same starting point without reimplementing reset/RNG logic in the test file.

Bug fixed during implementation: ns_checksum(bytes, len, ...) takes the *whole* already-encoded record (header + player records + the trailer ns_serialize just wrote), not a pre-trimmed slice — it hashes only the prefix up to but not including the trailer's own bytes (core/canon.zig's checksum() does its own bytes.len - CHECKSUM_BYTES slicing internally). Passing written - 8 caused it to strip an extra 8 bytes and hash 16 bytes too few; the fix was to pass the full written length. Verified against core/difftest.zig's own calling convention (canon.checksum(got) where got is the full encoded record) and empirically via two standalone debug programs before applying the fix.

tools/validate_abi_test_purity.py (uv-script convention, ~30 lines with docstring) regexes core/abitest.zig for every @import("...") argument and fails if anything besides "std" appears. Verified it both passes on the real file and fails when a throwaway `@import("world")` line is appended.

Wired into taskfiles/core.yml as two new tasks: core:abitest-purity (runs the validator) and core:abitest (deps: [abitest-purity], then zig build abitest), both added to the top-level check task between core:abi-symbols and core:difftest. docs/build-layout.md documents the new build.zig step, the five named tests, the ns_deserialize bootstrap rationale, the ns_checksum calling convention, and the purity validator, plus an addition to the existing "task check wiring" section.

No backlog/decisions/ entry needed: Tier-C test infrastructure and its purity validator have no analogue in reference/snake.html's behavior (same reasoning as TASK-024's abi.zig implementation, which also added none) — this is build/test tooling, not a behavioral deviation from the oracle.

Full `task check` run green end-to-end in the task-025 worktree (oracle:verify, core:test, core:abi-header-check, core:abi-symbols, core:abitest-purity, core:abitest, core:difftest, game:import, game:test).
<!-- SECTION:NOTES:END -->

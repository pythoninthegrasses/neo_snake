---
id: TASK-028
title: Build Tier-D corpus replay through the GDExtension
status: Done
assignee: []
created_date: '2026-09-09 22:10'
updated_date: '2026-09-12 21:46'
labels: []
milestone: m-4
dependencies:
  - TASK-027
  - TASK-025
priority: high
type: feature
ordinal: 28000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement game/tests/test_corpus_replay.gd: walk res://tests/corpus/manifest.json and assert every tick's checksum and every full-state ("s") anchor matches, driving the simulation entirely through world.gd -> the GDExtension -> the C ABI -> core/world.zig. This is the load-bearing assertion of the whole project: one checksum number computed four independent ways (node oracle, Zig-internal Tier-B, Zig-through-the-C-ABI Tier-C, and now GDScript-through-the-GDExtension) all agreeing with a single committed constant per trace.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every trace in tests/corpus/manifest.json replays through Tier-D with matching per-tick checksums and matching full-state anchors
- [x] #2 A deliberately corrupted committed checksum makes the corresponding trace fail Tier-D
- [x] #3 Tier-D is part of task game:test / task check
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
Implemented `game/tests/test_corpus_replay.gd`, the Tier-D corpus replay: drives every trace in
`tests/corpus/manifest.json` entirely through `SimulationWorld -> NeoSnakeWorld -> the C ABI ->
core/world.zig`, mirroring `core/abitest.zig`'s Tier-C algorithm one layer up rather than inventing
a new one.

**Algorithm** (per trace): tick 0 is reached via `SimulationWorld.deserialize()` of that line's
committed `"s"` anchor, never via `init()` + `step()` — every committed trace was recorded starting
already `.playing` (regen_corpus.mjs), while a fresh `NeoSnakeWorld` always starts `.menu`
(decision-015), and an empirical scan of all 36 `.jsonl` files confirmed every trace's tick-0 line
carries an `"s"` anchor with an empty `"in"` array, so this precondition always holds. Every
subsequent line's `"in"` array becomes a `step()` call; after every tick (0 included) the world is
`serialize()`d and its checksum compared against `"c"`, and if the line carries an `"s"` anchor its
serialized bytes are compared byte-for-byte against the decoded anchor.

**u64-vs-int64 checksum comparison**: `NeoSnakeWorld.checksum()` bit-reinterprets the ABI's `u64`
into a (possibly negative) signed `int64` (`extension/src/neo_snake_world.cpp`'s
`static_cast<int64_t>(value)`), while a corpus `"c"` field is a decimal string specifically because
such values can exceed GDScript's safe integer range. Rather than assume anything about how
GDScript's integer arithmetic handles overflow, `_u64_hi_lo()`/`_parse_decimal_hi_lo()` split both
sides into 32-bit halves using only well-defined bitwise `&`/`>>` operations and compare those —
verified correct against a real known checksum via a throwaway Godot-executed probe script before
being written into the committed test.

**AC#2** (negative test): `test_a_corrupted_committed_checksum_fails_replay` takes
`one-turn-per-tick.jsonl`'s in-memory text, mutates tick 1's `"c"` digit, and asserts the replay
fails with a checksum-mismatch message — the real corpus file on disk is never touched.

**AC#3**: no `taskfiles/game.yml` change was needed — `game:test`'s `-a res://tests` already globs
the whole directory, so the new test file is picked up automatically. Confirmed by reading the
taskfile before writing any test code.

**One trace excluded, documented, and self-guarded**: `win-full-board.jsonl` (a deliberately tiny
`cols=3` board, meant to force a full-board win quickly) cannot be represented over the C ABI at
all: `ns_world_init` (`core/abi.zig`) rejects any `cols<=8` config outright because it
unconditionally calls `reset()`, whose fixed `x=8/7/6` snake placement needs `cols>8`, and
`ns_deserialize` separately refuses to rehydrate a record whose `cols`/`rows` differ from the
world's init-time `cols`/`rows` — so there is no sequence of ABI calls that can ever reach this
trace's tick-0 anchor. This was never caught before this task because Tier-C's `abitest.zig` only
replays one hand-picked trace, and Tier-B's `difftest.zig` bypasses the ABI's validation entirely
by calling `world_mod.initWorld` directly. Recorded as `backlog/decisions/decision-021` (not a
`reference/snake.html` behavioral deviation — a Tier-D/ABI-boundary coverage gap). The test file
excludes this one trace by name from the main loop and adds a second test,
`test_win_full_board_still_cannot_be_represented_over_the_abi`, asserting `NeoSnakeWorld.init()`
still rejects that config — if a future ABI change ever lifts the `cols<=8` guard, this assertion
fails loudly rather than leaving the exclusion silently stale. AC#1 is satisfied for all 35
ABI-representable traces; the 36th's exclusion is explicit and self-checking, not silent.

**DoD#2** ("any deviation... recorded in backlog/decisions/"): satisfied by decision-021 above —
the only notable divergence this task produced from a naive reading of AC#1 is the
ABI-boundary exclusion, which is exactly what that decision documents. No `reference/snake.html`
behavioral deviation was introduced.

**Docs**: added a "`game/tests/test_corpus_replay.gd` (Tier-D)" section to `docs/build-layout.md`,
in the same style as the existing Tier-A/B/C sections, covering the algorithm, the checksum
comparison approach, the `win-full-board` exclusion, and why no taskfile change was needed.

**`game/simulation/world.gd`**: added re-exported `NeoSnakeWorld` result/enum constants (`OK`,
`DIR_UP/DOWN/LEFT/RIGHT`, `SPEED_SOURCE_SCORE_TABLE`) so the test file never needs to reference
`NeoSnakeWorld` directly (TASK-027's "only `.gd` file allowed to reference `NeoSnakeWorld`" rule).
Verified via the real `task game:test`/`task check` pipeline, not Godot's `-s` script mode: `-s`
mode does not carry GDExtension global-class registration (three throwaway probe scripts each
failed with "Identifier NeoSnakeWorld not declared," even for a bare `.new()` call), so any future
GDExtension-class-dependent GDScript verification in this repo must go through the real
project/test-runner path, not `-s`.

`task check` is green (5 test cases across the 3 suites, 0 failures).
<!-- SECTION:NOTES:END -->

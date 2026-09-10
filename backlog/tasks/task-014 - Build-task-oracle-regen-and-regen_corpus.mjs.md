---
id: TASK-014
title: 'Build task oracle:regen and regen_corpus.mjs'
status: Done
assignee: []
created_date: '2026-09-09 22:09'
labels: []
milestone: m-2
dependencies:
  - TASK-013
priority: high
type: feature
ordinal: 14000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement regen_corpus.mjs, which drives sim.mjs through committed command logs and emits the JSONL seed corpus, manifest.json, CORPUS_VERSION, and a generated-but-committed core/corpus.zig file listing (needed because Zig's build graph cannot read JSON at graph-construction time). Wire task oracle:regen to run it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Running task oracle:regen twice in a row produces byte-identical output (JSONL, manifest.json, core/corpus.zig)
- [x] #2 manifest.json lists every corpus file with its CORPUS_VERSION
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
Four new source files plus committed generated output. Plain Node ESM, no new dependency, no test framework — same shape as `rng.mjs`/`canon.mjs`/`self-check.mjs` and `sim.mjs`/`sim-check.mjs`.

- `reference/oracle/regen_corpus.mjs` — `parseCommandLog` (line-1 header + `t`-sorted events), `renderTrace` (drive `sim.mjs` one `advance()` per tick, serialize via `canon.mjs`'s existing `encode()`), `renderManifest`, `renderCorpusZig`, and `generate(root)`. No RNG, canonical-encoding or simulation logic of its own; the whole file is parsing, driving and formatting. Exports are pure (string in / string out) so the check script can exercise them without touching the repo. `--check` regenerates in memory and diffs against what is on disk, exiting non-zero on drift instead of writing — the shape the later `oracle:verify` task will want.
- `reference/oracle/regen_corpus-check.mjs` — 93 named checks (`check(label, actual, expected)`, same as the other two check scripts). Run: `node reference/oracle/regen_corpus-check.mjs`.
- `taskfiles/oracle.yml` (included as the `oracle:` namespace by the one `includes:` line added to `taskfile.yml`): `task oracle:regen` runs the generator; `task oracle:check` runs `--check` plus the check script. `oracle:regen` is deliberately **not** a dependency of the existing `check` task (that wiring belongs to `oracle:verify`, a later task).
- Four fixture command logs under `reference/oracle/corpus/commands/` and their generated output: `game/tests/corpus/{wall-right-edge,wall-serpentine-death,win-full-board,wrap-serpentine}.jsonl`, `game/tests/corpus/manifest.json`, `core/corpus.zig`.

Fixtures cover the four shapes asked for: wall death with no input at all (`wall-right-edge`, 16 ticks then an early stop at x=23), an out-of-bounds death after a direction commit (`wall-serpentine-death`, one lap, dying at (0,0) on tick 22 out of a 400 cap), win-on-full-board (`win-full-board`, 3x2 wrap, the snake fills all 6 cells, `placeFood` yields null, `dead` with score 30), and a wrap trace that survives to its cap so the cap — not a death — ends it and spans several 64-tick anchor blocks (`wrap-serpentine`, 150 ticks). Multiplayer is *not* covered: `sim.mjs` simulates exactly one snake (`initialState` builds a single `snake`), so a `players: 2` log would describe a game nothing in the repo simulates. Every trace therefore carries `players: 1` with `p` still explicit on every event, asserted by the check script; the multi-player fixture arrives with whatever task gives the sim a second snake.

AC#1 verified three ways, all actually run: `generate(ROOT)` twice with every file compared byte-for-byte; `task oracle:regen` twice back to back with `sha256sum` over all six generated files diffed (`0 file(s) changed` on the second run, identical hashes); and a copy of the worktree with the generated output deleted outright, regenerated from the command logs alone, byte-identical to this worktree on all six files. Ordering is deterministic by construction, not by luck: command logs are discovered by a sorted recursive scan, and both `manifest.json`'s `files` and `core/corpus.zig`'s `entries` are sorted lexicographically by name, so no directory-listing order reaches the output.

AC#2 verified against the files rather than against `generate()`'s own return value (a manifest graded against the thing that wrote it proves nothing): `manifest.files` equals a fresh `readdirSync` of `game/tests/corpus/` filtered to `.jsonl`, every entry repeats `corpus_version` and matches the trace header's own `corpus_version`, each entry's `ticks` equals its file's line count minus the header, and `core/corpus.zig`'s entries are the same names in the same order with the same `CORPUS_VERSION: u32` constant.

Three real defects were caught by the check script while it was being written, all fixed in the generator: (a) the 64-tick anchor rule was implemented as `t % 64 === 0`, which puts the 64th recorded tick at t=64 rather than t=63 and left t=63 unanchored — the rule is `(t + 1) % 64`; (b) `last` was referenced inside `traceLine` without being passed, a `ReferenceError` that only fired once the last-tick anchor was actually asserted; (c) the last tick was not anchored at all when it was neither t=0 nor a multiple of 64, so traces ended with no full-state record to restart from. The anchor rule is now `t === 0 || (t + 1) % 64 === 0 || last`, with `last` computed in the loop rather than patched onto the emitted line afterwards.

Two deliberate choices worth recording. `docs/canonical-state.md` defines the trailer as a `u64` and its worked example prints it as a decimal string (`15107102501874316122`), but `DataView`/`JSON` have no u64: the checksum is therefore read with `getBigUint64` and emitted as `BigInt.prototype.toString()`, using `BigInt` only for that width. That is not a departure from `docs/rng.md`'s "no BigInt" rule, which is about keeping the xoshiro128** stream bit-exact in float64 — the sim path never sees a BigInt. Second, two command logs reducing to the same trace name (e.g. `a.commands.jsonl` and `a.b.commands.jsonl`, whose extra dot the name slice cannot distinguish) would silently overwrite one another, so `findCommandLogs` rejects the collision by name at discovery time with both file names in the message. A `.jsonl` in `game/tests/corpus/` that no command log produces is stale corpus output rather than part of the corpus, so `regen` removes it and `--check` reports it.

DoD#2: no `backlog/decisions/` entry added. This task has no `reference/snake.html` analogue at all — `docs/corpus-format.md` says so in its first line, as do `docs/canonical-state.md` and `docs/rng.md` for the layers underneath — and the generator reproduces no oracle behavior of its own; it drives `sim.mjs`, whose one quirk is decision-015 and whose PRNG substitution is decision-003. No new divergence was introduced, so there is nothing to record rather than a manufactured entry.

DoD#3: no `docs/*.md` file needed editing. `docs/corpus-format.md` is the frozen spec and is implemented as written; `docs/architecture.md` documents the `reference/snake.html` IIFE and its `node --check`/stubbed-DOM technique, which this change does not touch. The generator's and the task's own comments carry the format decisions.

DoD#1: `task check` run green in this worktree after `cp .env.example .env && ./tools/bootstrap.py game all` (gitignored setup): env-precedence guard, headless Godot import, gdUnit4 1 test case / 0 errors / 0 failures. `oracle:regen` was **not** added to it. Also run green: `node --check` on both new `.mjs` files, `biome lint reference/oracle/*.mjs` (clean), `self-check.mjs` and `sim-check.mjs` (TASK-012/013 regressions, still passing), `task oracle:check`, and `regen_corpus.mjs --check` on the committed output.

`reference/snake.html`, `rng.mjs`, `canon.mjs`, `sim.mjs`, their check scripts, `docs/`, `taskfiles/game.yml` and every other task file untouched.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented `reference/oracle/regen_corpus.mjs` per `docs/corpus-format.md`: it parses every command log under `reference/oracle/corpus/commands/`, drives each through `sim.mjs` one `advance()` per tick, and rewrites the JSONL traces under `game/tests/corpus/`, `game/tests/corpus/manifest.json` and `core/corpus.zig` from scratch at `CORPUS_VERSION` 1, with no RNG, canonical-encoding or simulation logic of its own. Wired `task oracle:regen` (plus a read-only `task oracle:check`) through a new `taskfiles/oracle.yml` included under the `oracle:` namespace; the existing `check` task is unchanged. Four committed fixture command logs cover wall death, out-of-bounds death after a direction commit, win-on-full-board, and a wrap trace that runs to its `ticks` cap across several full-state anchor blocks; multiplayer is skipped because `sim.mjs` simulates one snake, so every trace is `players: 1` with `p` explicit. AC#1 verified by two in-process regens, two back-to-back `task oracle:regen` runs with `sha256sum` diffs, and a regen from scratch in a copy with the generated output deleted — all byte-identical on all six files, with sorted discovery and sorted listings so no filesystem order can leak. AC#2 verified against `readdirSync` of the corpus directory plus each trace's own header and `core/corpus.zig`, not against the manifest's own generator. `reference/oracle/regen_corpus-check.mjs` (93 named checks) re-derives every recorded checksum, anchor state and input from `sim.mjs` + `canon.mjs` and asserts the spec's loud rejections (duplicate `(t, p)`, unsorted events, out-of-range fields); it caught three genuine generator bugs (the 64-tick anchor off-by-one, an unpassed `last`, and the last tick not being anchored at all) before anything was committed. `task check` green; no new decision entry, since nothing here diverges from `reference/snake.html` (the corpus layer has no oracle analogue) and no doc required editing.
<!-- SECTION:FINAL_SUMMARY:END -->

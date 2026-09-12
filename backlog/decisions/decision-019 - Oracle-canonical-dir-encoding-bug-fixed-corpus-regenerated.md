---
id: decision-019
title: Oracle canonical dir/nextDir encoding bug fixed, corpus regenerated
date: '2026-09-12 13:14'
status: Accepted
---
## Context

This is not a deviation from `reference/snake.html` behavior — it is a defect in the headless
oracle *tooling* that generates the committed differential-test corpus, discovered while
implementing TASK-020 (`zig build difftest`).

`reference/oracle/sim.mjs` stores `S.dir`/`S.nextDir` as `DIRS` vector objects (`{x,y}`), not
strings. `reference/oracle/canon.mjs`'s `encode()` (`docs/canonical-state.md`'s wire format)
expects a direction *name string* (or an already-numeric code) for its `dir`/`next_dir` bytes —
documented in `encode()`'s own doc comment and exercised correctly by `self-check.mjs`.
`reference/oracle/regen_corpus.mjs`'s `canonical(S)` helper — the function that builds the object
handed to `encode()` for every tick of every trace — passed `S.dir`/`S.nextDir` straight through
untranslated. `DIR[vectorObject]` (where `DIR = {up:0,down:1,left:2,right:3}`) always evaluated to
`undefined`, silently coerced to `0` by `DataView.setUint8`. Because the checksum trailer is a
SHA-256 over the entire canonical record, this forced `dir`/`next_dir` to `0` (up) in **every
tick's checksum and every full-state anchor of every one of the 35/36 committed
`game/tests/corpus/*.jsonl` trace files**, regardless of the snake's actual direction.

This went uncaught because `reference/oracle/regen_corpus-check.mjs`'s own "independent"
verification loop had a hand-rolled duplicate of the identical bug (it also passed raw
`S.dir`/`S.nextDir` into its own local `encode({...})` call), so the generator and its own check
always agreed with each other.

## Decision

Fixed at the root: added an exported `dirName(d)` reverse-lookup helper to `sim.mjs`, and used it
at both real call sites that build canonical-encode input from live `sim.mjs` state —
`regen_corpus.mjs`'s `canonical()` and `regen_corpus-check.mjs`'s independent verification loop.
`canon.mjs` itself was not touched — its `encode()` was already correct and already documented;
the bug was entirely in its callers. Regenerated the full corpus
(`game/tests/corpus/*.jsonl`, `manifest.json`, `oracle_sha256`) via `task oracle:regen` and
verified it via `task oracle:check`/`task oracle:verify` and `regen_corpus-check.mjs`.

## Consequences

Every committed corpus trace file's bytes changed (dir/next_dir field, and every downstream
checksum/anchor derived from it) even though the underlying simulated gameplay did not — this is a
tooling-correctness fix, not a gameplay or oracle-behavior change, and no `core/world.zig` or
`core/difftest.zig` code needed to change as a result. Any future oracle helper that serializes
live `sim.mjs` state for `canon.mjs`'s `encode()` must go through `dirName()` rather than passing
`S.dir`/`S.nextDir` directly — `sim.mjs`'s own doc comment on `dirName` now says this explicitly.

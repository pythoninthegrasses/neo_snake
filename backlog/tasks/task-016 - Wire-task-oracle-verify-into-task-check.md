---
id: TASK-016
title: 'Wire task oracle:verify into task check'
status: To Do
assignee: []
created_date: '2026-09-09 22:09'
labels: []
milestone: m-2
dependencies:
  - TASK-015
priority: high
type: feature
ordinal: 16000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement task oracle:verify: regenerate the corpus into a scratch directory, assert byte-identity with the committed corpus, and compute oracle_sha256 (a hash of the concatenated *.mjs oracle source files) so an oracle change with a stale committed corpus fails loudly instead of silently drifting.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 task oracle:verify is part of task check
- [ ] #2 Deliberately editing any oracle/*.mjs file without regenerating the corpus makes task oracle:verify fail
- [ ] #3 The scratch-regenerated corpus is byte-identical to the committed one on a clean run
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

## Format decision (resolved, sign-off given — safe to implement)

`oracle_sha256`'s storage location and comparison target were ambiguous (no prior
mention in `docs/corpus-format.md`, `backlog/decisions/`, or TASK-014/015). Resolved
and already written into `docs/corpus-format.md`'s `manifest.json` section in this same
commit — implement exactly that spec, restated here so it doesn't need re-deriving:

- **Location**: a new top-level `oracle_sha256` field in `game/tests/corpus/manifest.json`,
  sibling to `corpus_version`. Not part of `core/corpus.zig`.
- **Input set**: `reference/oracle/*.mjs`, non-recursive (excludes `reference/oracle/corpus/`).
  Today that's `canon.mjs`, `regen_corpus-check.mjs`, `regen_corpus.mjs`, `rng.mjs`,
  `self-check.mjs`, `sim-check.mjs`, `sim.mjs` — includes the check scripts, matching
  AC#2's literal "any oracle/*.mjs file."
- **Hash construction**: sort filenames ascending, concatenate each file's raw bytes in
  that order with no delimiter between files, SHA-256 the result, lowercase hex string.
- **Writer**: `regen_corpus.mjs` computes and writes `oracle_sha256` into `manifest.json`
  on every `task oracle:regen` run.
- **Verifier**: the new `task oracle:verify` recomputes the same hash from the current
  working tree and compares it to the committed `manifest.json`'s value — mismatch fails
  loudly. Separately (AC#3), it also regenerates the corpus into a scratch directory and
  diffs it byte-for-byte against the committed `game/tests/corpus/`. Both checks must
  pass for `oracle:verify` to pass; either one failing is a real failure, not a warning.
- **Why two checks, not one**: byte-identity alone misses a behaviorally-inert oracle
  edit (e.g. a comment) that doesn't change any trace's output but does mean the source
  no longer matches what's on record — `oracle_sha256` catches that case.

`docs/corpus-format.md` already reflects this — no further design work needed there.

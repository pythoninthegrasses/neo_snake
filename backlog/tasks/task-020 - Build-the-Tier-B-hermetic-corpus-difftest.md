---
id: TASK-020
title: Build the Tier-B hermetic corpus difftest
status: Done
assignee: []
created_date: '2026-09-09 22:09'
updated_date: '2026-09-12 18:15'
labels: []
milestone: m-3
dependencies:
  - TASK-019
references:
  - ~/git/zelda3/build.zig
modified_files:
  - core/difftest.zig
  - core/build.zig
  - taskfiles/core.yml
  - taskfile.yml
  - docs/build-layout.md
  - reference/oracle/sim.mjs
  - reference/oracle/regen_corpus.mjs
  - reference/oracle/regen_corpus-check.mjs
  - game/tests/corpus/*.jsonl
  - game/tests/corpus/manifest.json
  - >-
    backlog/decisions/decision-019 -
    Oracle-canonical-dir-encoding-bug-fixed-corpus-regenerated.md
priority: high
type: feature
ordinal: 20000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement zig build difftest, which replays the committed JSONL corpus (task-015) against core/world.zig and asserts every tick's checksum and every full-state ("s") anchor matches. Must be hermetic — it runs with no node installed on the box, reading only the committed corpus files, which is the entire point of the frozen-output differential-test pattern (zelda3's Tier-B idea, adapted since the reference here is JS rather than C). On a mismatch, it must rewind to the last "s" anchor, re-run from there, and print a field-by-field diff of the first divergent tick.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 zig build difftest passes against the full committed corpus with no node binary present in PATH
- [x] #2 A deliberately introduced divergence (e.g. flipping a comparison operator in world.zig) causes difftest to fail with a field-by-field diff of the first divergent tick
- [x] #3 difftest is part of task check
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
core/difftest.zig implements zig build difftest: iterates core/corpus.zig's committed trace list, JSON-parses each game/tests/corpus/*.jsonl file (header + per-tick lines), replays each tick through core/world.zig (queueDir + advance), and checks the checksum plus any "s" full-state anchor. On a mismatch it finds the last anchor at or before the failing tick and decodes the already-computed failing bytes directly (no re-simulation — replaying the same world.zig code from the same start can only reproduce the bytes already computed in the single forward pass) and prints a field-by-field diff against that anchor. Wired into core/build.zig as a standalone difftest executable/step (reusing the test step's rng/canon/world modules plus a new corpus module), and into task check via a new core:difftest task in taskfiles/core.yml, run immediately after core:test.

Deep pre-existing bug found and fixed in the oracle corpus-generation pipeline while implementing this (see decision-019): reference/oracle/regen_corpus.mjs's canonical() helper passed sim.mjs's raw S.dir/S.nextDir vector objects ({x,y}) straight into canon.mjs's encode(), which expects a direction name string — DIR[vectorObject] silently evaluated to undefined, coerced to 0 by DataView.setUint8. This forced dir/next_dir to 0 (up) in every tick's checksum and every full-state anchor of every committed corpus trace, regardless of the snake's real direction. regen_corpus-check.mjs's own independent verification loop had an identical duplicate of the bug, which is why it was never caught. Fixed by adding sim.mjs's dirName() helper and using it at both real call sites; regenerated the full corpus (all 35/36 trace files + manifest.json + oracle_sha256) via task oracle:regen and reverified via oracle:check/oracle:verify.

AC#1 verified with PATH scrubbed to exclude any node binary (env -i with only zig's directory on PATH) — difftest reads only committed corpus files via std.Io.Dir, no shell-out. AC#2 verified by temporarily flipping world.zig's non-wrap bounds check (nx >= w.cols -> nx > w.cols) and confirming difftest fails with a clear field-by-field diff (status .dead vs .playing, cells off by one past the wall) before reverting. Full task check (oracle:verify, core:test, core:difftest, game:import, game:test) is green.
<!-- SECTION:NOTES:END -->

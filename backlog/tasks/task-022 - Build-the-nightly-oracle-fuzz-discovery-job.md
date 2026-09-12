---
id: TASK-022
title: 'Build the nightly oracle:fuzz discovery job'
status: Done
assignee: []
created_date: '2026-09-09 22:10'
updated_date: '2026-09-12 19:34'
labels: []
milestone: m-3
dependencies:
  - TASK-021
priority: medium
type: feature
ordinal: 22000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement task oracle:fuzz -- --count N: generate fresh random seeds, run them through both the JS oracle and the Zig core (both must be live — node and zig — unlike the hermetic Tier-B difftest), and diff results. This is discovery, not regression, so it is deliberately NOT part of task check; it runs nightly in CI. Any failing seed found this way is promoted into the permanent committed corpus (task-015's files) as a new regression test — that promotion path is how the regression suite grows over time.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 task oracle:fuzz -- --count N runs N fresh seeds through both oracle and core and reports any mismatch
- [x] #2 task oracle:fuzz is NOT part of task check
- [x] #3 A documented procedure exists for promoting a failing seed into the committed corpus
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
Implementation: `reference/oracle/fuzz.mjs` generates N fresh command logs (real node:crypto randomness for the meta-level seed/wrap/input choices — not the sim's own seeded stream, which stays fully deterministic per generated seed) and drives each through reference/oracle/sim.mjs by reusing regen_corpus.mjs's own exported parseCommandLog()/renderTrace() — the identical machinery that already produces the committed corpus, so there is no second JS implementation to keep in sync.

Zig side: `core/fuzzrun.zig`, a new standalone executable (wired into core/build.zig as its own `fuzzrun` step, addInstallArtifact'd but deliberately NOT attached to the default install step) that takes a command-log path as a runtime CLI argument, drives core/world.zig the same way renderTrace() drives sim.mjs (queue this tick's events, advance(), stop at first non-playing status or the ticks cap), and prints "<tick>\t<checksum>" per tick to stderr (this codebase's established std.debug.print convention, verified to land on stderr not stdout). fuzz.mjs spawns the built zig-out/bin/fuzzrun binary once per generated seed and diffs its output against the JS oracle's own checksums tick-by-tick. Verified end-to-end with a hand-written command log (both sides produced byte-identical checksums) and with `task oracle:fuzz -- --count 20 --ticks 400` (20/20 fresh seeds matched, mixing wrap on/off and both early-death and full-length runs).

Wired as taskfiles/oracle.yml's `fuzz` task (`zig build fuzzrun` then `node reference/oracle/fuzz.mjs {{.CLI_ARGS}}`) — confirmed NOT part of the root `check` task (AC#2): taskfile.yml's `check` task list is unchanged by this task.

AC#3 (promotion procedure): documented in docs/corpus-format.md's new "Promoting a fuzz failure" section — copy the preserved command log (fuzz.mjs keeps the temp directory only when a run has mismatches) into reference/oracle/corpus/commands/ under a descriptive name, run task oracle:regen (task-015's existing machinery, never invoked by oracle:fuzz itself), fix whichever side is wrong, commit the new trace and the fix together.

docs/build-layout.md updated: Module layout list now mentions core/fuzzrun.zig, and a new "zig build fuzzrun" section mirrors the existing "zig build difftest" section, explaining why fuzzrun takes a runtime path instead of enumerating a committed list and why it's excluded from the default install step.

No new backlog/decisions/ entry: adding reference/oracle/fuzz.mjs to reference/oracle/ changed oracle_sha256 (docs/corpus-format.md's hash covers every *.mjs file in that directory, source or not), so task oracle:regen was re-run to update game/tests/corpus/manifest.json's oracle_sha256 field alone — confirmed via git diff that no trace file or core/corpus.zig changed, only that one field. This is new discovery tooling with no reference/snake.html analogue, the same precedent TASK-015/020/021 already established for corpus/build tooling.

task check: green in a fresh worktree after the same one-time `./tools/bootstrap.py game gdunit4` step every prior worktree has needed (gdUnit4 isn't committed) and a `.env` copied from `.env.example` for TASK_X_ENV_PRECEDENCE=1 (also gitignored, not previously needed to be created by hand in earlier task worktrees' recorded notes, but required here since this worktree had none).
<!-- SECTION:NOTES:END -->

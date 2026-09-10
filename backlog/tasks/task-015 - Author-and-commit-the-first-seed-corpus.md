---
id: TASK-015
title: Author and commit the first seed corpus
status: Done
assignee: []
created_date: '2026-09-09 22:09'
labels: []
milestone: m-2
dependencies:
  - TASK-014
priority: high
type: feature
ordinal: 15000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Design and commit ~12 hand-designed traces covering the Phase 3 edge cases (tail-chase legality, negative wrap, out-of-bounds death after direction commit, score/placement/win-on-full-board ordering, both 180-reject references, accumulator clamp/carry) plus ~20 random traces for broader coverage. Format: one header line, then per-tick {"t","in","c"} records with full canonical state "s" on tick 0, every 64 ticks, and the last tick. Use JSONL, not a binary blob — these are review artifacts, and a binary format turns every corpus change into an unreviewable diff. A 2000-tick trace should be roughly 60 KB.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 At least 12 hand-designed traces exist, each named for the edge case it covers, plus ~20 random traces
- [x] #2 Every trace file is JSONL with periodic full-state anchors as specified
- [x] #3 The corpus is generated via task oracle:regen, not hand-edited
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 task check is green
- [x] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [x] #3 Docs touched by the change are updated in the same commit
- [x] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

## Implementation Notes

36 command logs under `reference/oracle/corpus/commands/`: 16 hand-designed (named for
the edge case each covers) + 20 random (`random-01`..`random-20`, varying seed, board
size, wrap, and length). All output (`game/tests/corpus/*.jsonl`, `manifest.json`,
`core/corpus.zig`) generated via `task oracle:regen` — never hand-edited.

Coverage of the 6 named edge-case categories:
- **Tail-chase legality**: `tail-chase-vacating-tail` — verified by decoding its last
  canonical-state anchor: reaches its full 199-tick cap (`status: playing`, never dies),
  confirming the snake repeatedly re-enters cells its own tail is vacating without a
  false self-collision.
- **Negative wrap**: `negative-wrap-y10-col9a`, `negative-wrap-y12-col9`,
  `negative-wrap-y16-col15` — three board-size variants exercising `(ny + ROWS) % ROWS`
  at `y=0` moving up.
- **Out-of-bounds death after direction commit**: `wall-corner-death`, `wall-right-edge`,
  `wall-right-edge16x16`, `wall-serpentine-death`, `wall-top-edge-death10`,
  `wall-turn-bottom-edge-death`.
- **Score/placement/win-on-full-board ordering**: `win-full-board` — verified by decoding
  its last anchor: 3x2 board, snake length 6 (== board cells), `food: null`,
  `status: dead`, `score: 30`. Genuinely fills the board rather than just being named for it.
- **Both 180-reject references**: only the `dir`-while-playing reference is
  representable — verified behaviorally (`reject-180-down-then-up`,
  `reject-180-opposite-then-perpendicular`, `reject-180-right-then-left`: each queues an
  opposite-of-current-`dir` input and confirms `nextDir` does not change). The
  `nextDir`-otherwise reference (menu/paused/dead) is **not representable in the current
  corpus format**: `docs/corpus-format.md`'s command-log header has no field to set a
  non-`playing` initial status, there is no "pause" input primitive, and
  `regen_corpus.mjs` hardcodes `initialState({..., status: 'playing'})`. This mirrors the
  accumulator-clamp/carry exception already called out for this task — the `nextDir`
  reference is already covered at the unit level by `TASK-013`'s `sim-check.mjs`. Making
  it representable would mean extending `docs/corpus-format.md` and `regen_corpus.mjs`,
  both out of scope here (frozen inputs for this task) — worth a follow-up task if
  corpus-level coverage of this reference is wanted later. Because of this, the 3
  `reject-180-*` traces all cover the same reference case (with different direction
  pairs/wrap settings) rather than "both" — flagged here rather than left implicit.
- **Accumulator clamp/carry**: not representable as a corpus trace — `regen_corpus.mjs`
  drives `sim.mjs` only via `advance()` (one tick per command-log tick), never via the
  wall-clock-driven `step(S, now)` that owns clamp/carry behavior. Already covered by
  `sim-check.mjs`'s unit assertions, per the same reasoning as the 180-reject exception
  above.

Also present: `one-turn-per-tick` (single-direction-change-per-tick mechanics),
`tail-blocked-by-middle-segment` (self-collision against a non-tail body segment). The
4 TASK-014 fixtures were reduced to 3: `wall-right-edge`, `wall-serpentine-death`, and
`win-full-board` were kept/reused as-is; `wrap-serpentine` was superseded by the 3
`negative-wrap-y-*` traces (which exercise the same wrap arithmetic more specifically)
and removed via `task oracle:regen`'s stale-output cleanup, not by hand.

**Run history**: delegated to `pi` via the `gnhf` skill. The run stalled for ~48 minutes
(08:51–09:39) on a runaway self-authored `/tmp` verification script — a `cap`-vs-`ticks`
field-name bug in its own throwaway script caused an infinite loop while checking the
`tail-chase-vacating-tail` trace, pegging one `node` subprocess at ~99% CPU and blocking
`pi`'s bash tool call from ever returning (confirmed via Aperture gateway session logs:
the last real model request completed normally at 08:51:19 with `finish_reason:
tool_calls`; nothing was sent afterward because `pi` was blocked waiting on the local
subprocess, not on the network/backend). The user killed the runaway process manually;
`pi` resumed immediately and continued authoring traces normally. It was then killed by
its own bounding `timeout 10800` (3-hour cap) at ~11:41, before reaching its FINISH
PROTOCOL (no commit, task file untouched) — the earlier stall had consumed enough of the
budget that the remaining authoring work didn't finish in time. All of `pi`'s authored
command logs and outputs survived uncommitted in the worktree; the mechanical last mile
(a `task oracle:regen` pass to fill 3 files `pi` hadn't regenerated yet and purge 2 stale
outputs from renamed traces, `regen_corpus-check.mjs`, a byte-identical double-regen
check, targeted behavioral verification of the fidelity-critical traces above, `task
check`, and this task file's own sync) was completed independently rather than
relaunching `pi` for what was by that point pure verification/wrap-up.

No formatting drift this run (unlike TASK-012/013/014's recurring cosmetic
biome-reformatting) — the diff was clean.

No new `backlog/decisions/` entry: no new divergence from `reference/snake.html` was
found: the corpus layer has no `snake.html` analogue, and the one design gap found (the
180-reject `nextDir` reference not being representable) is a corpus-format limitation,
not a simulation-behavior divergence.

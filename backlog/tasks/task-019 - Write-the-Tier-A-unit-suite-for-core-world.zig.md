---
id: TASK-019
title: Write the Tier-A unit suite for core/world.zig
status: Done
assignee: []
created_date: '2026-09-09 22:09'
updated_date: '2026-09-11 23:30'
labels: []
milestone: m-3
dependencies:
  - TASK-018
priority: high
type: feature
ordinal: 19000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Write zig build test coverage for world.zig with one named test each for: direction commit-before-move ordering; negative wrap using @mod vs raw %; tail-chase legality (head moving onto its own current tail cell survives if not eating, dies if eating — the single most likely thing to get wrong in a port); out-of-bounds death occurring after the direction commit, not before; score += 10 followed by food placement followed by win-on-full-board ordering; both 180-degree-reject references (dir while playing, nextDir otherwise); the ns_pump clamp (max ticks per pump call) and accumulator carry-over; and serialize∘deserialize == identity.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 zig build test runs all nine named tests and they pass
- [x] #2 The tail-chase test explicitly covers both the surviving and dying case
- [x] #3 The ns_pump clamp test asserts the maximum tick count per call and that leftover time carries to the next call
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
What landed:

- core/world.zig — replaced TASK-018's ad hoc "Tier-A smoke tests" placeholder section with
  the authoritative named Tier-A suite: `refAllDecls` (kept) plus exactly nine named tests, one
  per load-bearing behavior, each mapping onto a single Acceptance Criterion:
  1. `advance commits next_dir into dir before the head moves` — commit-before-move ordering
     (docs/architecture.md "Simulation" step 1): the queued turn is reflected in both `dir` and
     the head position on the very same `advance`, not one tick later.
  2. `wrap uses @mod on the (+size) offset, not raw signed %` — pins the arithmetic identity the
     Zig port relies on (Zig's `%` truncates toward zero, so `-1 % 24 == -1`); head at x=0 moving
     left and y=0 moving up must land on cols-1/rows-1, which a naive raw `%` (or `%` without the
     `+ size` offset) gets wrong. Distinct from test 3 (the identity, not "wrap works").
  3. `tail-chase survives entering the vacating tail cell when not eating` — collision checked
     against the body minus the vacating tail cell (the oracle's `eating ? S.snake :
     S.snake.slice(0, -1)`), ported from the placeholder.
  4. `tail-chase dies entering the tail cell when eating` — the AC's "single most likely thing to
     get wrong in a port": the identical layout but with food on the tail cell, so the move is a
     scoring move that pins the tail (grow, no vacate) and the same move becomes a fatal
     self-collision. Tests 3+4 are the survive/die pair AC#2 requires.
  5. `out-of-bounds death happens after the direction commit` — a wall-mode fatal turn still
     commits `dir` before the bounds check runs (commit is unconditional, not skipped when fatal).
  6. `advance scores 10 before placeFood and wins only after the increment` — the eating branch's
     score += 10 lands (asserted == 10) before placeFood finds no free cell and the win (dead)
     fires; the increment is neither skipped nor ordered after the win.
  7. `queueDir reads dir while playing and next_dir in every other status` — both branches of the
     180-guard ternary exercised with `dir` and `next_dir` deliberately made to differ, so a guard
     reading the wrong field rejects/accepts wrongly (playing reads dir; paused reads next_dir).
  8. `pump clamps to MAX_STEPS per call and carries the remainder over` — AC#3: a pump handed
     more accumulated time than MAX_STEPS ticks (acc preloaded to 10 ticks at the fastest period)
     returns exactly MAX_STEPS with the rest left in acc_us (not discarded), and a sub-tick
     remainder (64+64+64 ms vs the 130000 us first period) carries into and is consumed by the
     next pump. Includes the frozen tickPeriodUs table lookups so the pump math stays pinned.
  9. `serialize then deserialize round-trips a driven World` — the World is driven through an eat,
     further advances and a pump so tick/score/rng_state/body all diverge, then a canon.State is
     built field-by-field inline (there is no World→canon.State helper in world.zig — TASK-018
     never introduced one and no abi freeze commits to one now), canon.encode/decode'd, and every
     decoded field asserted equal to the world's corresponding field (cols, rows, wrap, tick,
     rng_state, food, status, dir, next_dir, score, cells in order).

Deviation from reference/snake.html: none found. Every behavior these tests pin is already
implemented in core/world.zig and matches reference/oracle/sim.mjs line for line (the
`(nx + cols) % cols` wrap, `eating ? S.snake : S.snake.slice(0,-1)`, the commit at the top of
`advance`, the `dir`/`nextDir` 180-guard ternary, and the `score += 10; placeFood; if (!food) win`
order). decision-015 already records the one known quirk (menu-direction overwrite), which these
tests do not regress. No new backlog/decisions/ entry is warranted.

Docs: no doc change needed. `docs/architecture.md` and `docs/build-layout.md` describe the test
structure and the `zig build test` graph, not the individual ad hoc test names, so nothing
referenced the placeholder names being replaced.

Verification: `task core:test` green (16 tests pass; world module 10/10 = refAllDecls + the nine
named tests). `task check` green (oracle:verify, core:test, game:import, game:test). Note: this
fresh worktree was missing the gitignored local setup (`/game/addons/gdUnit4/` and `.env`); these
were restored via the documented bootstrap (`./tools/bootstrap.py game gdunit4`) and a copy of
`.env` from `.env.example`, both gitignored and outside the commit.
<!-- SECTION:NOTES:END -->

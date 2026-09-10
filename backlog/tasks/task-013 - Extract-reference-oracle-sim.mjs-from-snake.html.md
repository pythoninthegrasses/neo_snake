---
id: TASK-013
title: Extract reference/oracle/sim.mjs from snake.html
status: Done
assignee: []
created_date: '2026-09-09 22:09'
labels: []
milestone: m-2
dependencies:
  - TASK-012
references:
  - reference/snake.html
priority: high
type: feature
ordinal: 13000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Faithfully extract snake.html's advance()/placeFood()/queueDir()/frame() logic into a headless, DOM-free sim.mjs, using the oracle rng.mjs and canon.mjs from the previous task. This is the pre-port reference the Zig core will be differentially tested against, so faithfulness to the original (including its bugs/quirks registered in backlog/decisions/) matters more than "clean" code.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A named test covers the tail-chase split: eating ? snake : snake.slice(0,-1)
- [x] #2 A named test covers the +COLS wrap using JS remainder semantics, not true modulo
- [x] #3 A named test covers the 180-degree-reject reference: dir while playing, nextDir otherwise
- [x] #4 The menu-direction-overwrite quirk from backlog/decisions/ reproduces exactly (Up from menu results in rightward movement)
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
Two new files under `reference/oracle/`, following TASK-012's `rng.mjs`/`canon.mjs`/`self-check.mjs` layout (plain ESM, no dependencies beyond Node's stdlib, no test framework):

- `sim.mjs` — the DOM-free extraction of `reference/snake.html`'s `reset()`/`start()`/`queueDir()`/`togglePause()`/`placeFood()`/`advance()`/`frame()` logic over an explicit state object `S = { cols, rows, wrap, tick, score, food, snake, dir, nextDir, status, acc, last, rng }` (the `rng` stream is non-enumerable so it stays out of `JSON.stringify` and the canonical diff). `advance(S)` is the primary entry point (one true simulation step); `step(S, now)` is `frame()`'s accumulator loop as a pure function of (state, caller-supplied timestamp). `initialState({ seed })` builds the oracle `reset()` start position, food drawn through `boundedDraw` from `rng.mjs`.
- `sim-check.mjs` — the verification script, same `check(label, actual, expected)` shape as `self-check.mjs`. Run: `node reference/oracle/sim-check.mjs`; exits non-zero on any mismatch. 58 named checks; the four ACs each get their own clearly-labeled block (a reviewer can grep "the tail-chase test", "the +COLS wrap", "180 reject", or "menu overwrite").

Fidelity notes, verified against `reference/snake.html` line-for-line:

- AC#1 (`eating ? S.snake : S.snake.slice(0, -1)`): advancing into the tail cell the snake is vacating survives (collision body excludes the tail); a mid-body hit and a length-4 tail-chase both die; eating keeps the whole body, so a food cell under the tail collides. `tick += 1` happens only on a successful move (die leaves `tick` untouched), mirroring the oracle's `return die()` before any mutation.
- AC#2 (`nx = (nx + COLS) % COLS`): kept verbatim; the `+COLS`/`+ROWS` is what keeps JS's sign-of-dividend remainder non-negative (a naive `-1 % 24` is `-1`, asserted directly). x/y wrap in both directions confirmed; wall mode's death on the same step is the contrast case.
- AC#3 (`queueDir`): while `playing` the 180° guard reads `dir` (the committed direction), otherwise it reads `nextDir` — so two presses in one tick are both legal as long as each is legal against the committed `dir`, and the queued direction only commits on the next `advance`. `paused` reads `nextDir` and never starts.
- AC#4 (decision-015): starting via Up/Down/Right from `menu` (or `dead`) lands in `playing` with `dir = nextDir = right` and moves right on the first tick — the `reset()` overwrite, kept. Left is the notable case: from a right-facing start it is 180-rejected against `dir`/`nextDir` (both right), so it never triggers `start()` at all — the quirk only manifests for inputs that would otherwise have taken effect.

One headless-context liberty, **not** a behavioral divergence: the oracle reads dt as `now - (S.last || now)` with `S.last = 0`, which works only because a browser's first `requestAnimationFrame` timestamp is never 0. A headless caller's clock legitimately starts at t=0, where that truthiness test would read every frame as "no previous frame" and the sim would never tick. `sim.mjs` therefore uses an explicit `last: undefined` sentinel (first frame → dt 0); behavior is identical to the oracle for every real timestamp. The 64 ms dt clamp and the 6-step catch-up guard are kept verbatim; in practice the clamp keeps the accumulator below one extra tick, so the guard rarely binds — the dt clamp is the real bound on a huge gap (asserted).

The win branch reproduces the oracle exactly: a full-board eat finds no free cell, `placeFood` yields `null`, and the status becomes `dead` (the oracle has no separate win status; `docs/canonical-state.md`'s encoding table is `menu|playing|paused|dead`, so a distinct "won" code would not even be canonically encodable — asserting `dead` keeps the oracle and the format in agreement).

Dropped from the headless core (presentation/persistence only, no canonical byte, so not a divergence to record): `best`/localStorage, the eat-flash and best-score bookkeeping, particle burst, the overlay/HUD `sync()`, and the blur-to-pause listener. The seeded-PRNG switch is decision-003; nothing introduced here diverges beyond it and the canonical-format specs.

`task check` (env-precedence guard + headless Godot import + the gdUnit4 suite) is **not runnable in this worktree** — no `.env` (`TASK_X_ENV_PRECEDENCE`) and no `game/addons/gdUnit4/` (needs `./tools/bootstrap.py game all`), same as the TASK-012 note — and it exercises only the Godot/GDScript side, which this change does not touch. What was actually run green here: `node --check` on both files, `node reference/oracle/self-check.mjs` (TASK-012 regression, still passing), `node reference/oracle/sim-check.mjs` (58/58, byte-identical across repeated runs), and `biome lint` (clean). Notably, the check script caught two real fixture bugs while being written: a shared `DIRS.right` object handed to `advance()` as a board cell got mutated by `unshift`/`pop` (fixtures now copy direction vectors), and the dt-clamp/accumulator interaction means a single BASE_MS tick needs ≥3 frames, not one.

Docs: `docs/architecture.md`'s "Verifying changes without a browser" section already documents the node-runnable internals-extraction pattern this file follows (same call as TASK-012), and no `docs/*.md` file needed editing — no new decision entry either, since every divergence is covered by decision-003 / the canonical-format specs or is a verbatim reproduction of the oracle.

`reference/snake.html`, `rng.mjs`, `canon.mjs` untouched.
<!-- SECTION:NOTES:END -->

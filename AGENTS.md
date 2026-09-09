# AGENTS.md

This file provides guidance to AI agents when working with code in this repository.

## What this is

A single-file Snake game (`snake.html`) — no build step, no dependencies, no package manager, no
modules. Open it directly in a browser to run it.

## Commands

- Run: open `snake.html` in a browser (e.g. `xdg-open snake.html`).
- Syntax-check the script: extract the contents of the `<script>` tag and run `node --check` on it
  (see `docs/architecture.md` for the exact technique used to unit-test mechanics without a browser
  — there is no test suite or test runner in this repo).
- No lint/format tooling is configured for this repo.

## Architecture

Full details are in `docs/architecture.md` — read it before making non-trivial changes. Key points:

- Everything lives in one IIFE at the bottom of `snake.html`. CSS is in `<style>` in `<head>`; there
  is no other file to keep in sync.
- One mutable state object `S` holds all game state (`snake, dir, nextDir, food, score, best,
  status, wrap, acc, last, flash, particles`). `status` (`menu | playing | paused | dead`) is the
  only state machine — grep `S.status ===` when changing behavior.
- Fixed-timestep simulation via an accumulator (`S.acc`), decoupled from the `requestAnimationFrame`
  render loop. Difficulty is tuned via `BASE_MS` / `MIN_MS`, not framerate.
- `advance()` order is load-bearing (input commit → move → collision check against tail-minus-vacated-cell
  → unshift/pop) — see the doc before touching movement/collision logic.
- `queueDir()` is the single choke point for input legality (reversal rejection); add new input
  sources there, not by branching at call sites.
- `showOverlay()` uses `innerHTML` — never interpolate untrusted strings into it.

## Docs

- `docs/architecture.md` — the primary architecture reference; keep it in sync with any structural
  change to `snake.html`.

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

## Context7

Always use Context7 MCP for library/API documentation, code generation, and setup or configuration steps, without being explicitly asked.

### Libraries

- godotengine/godot-docs
- j178/prek
- mrlesk/backlog.md
- websites/taskfile_dev

<!-- BACKLOG.MD MCP GUIDELINES START -->

<CRITICAL_INSTRUCTION>

## BACKLOG WORKFLOW INSTRUCTIONS

This project uses Backlog.md MCP for all task and project management activities.

**CRITICAL GUIDANCE**

- If your client supports MCP resources, read `backlog://workflow/overview` to understand when and how to use Backlog for this project.
- If your client only supports tools or the above request fails, call `backlog.get_backlog_instructions()` to load the tool-oriented overview. Use the `instruction` selector when you need `task-creation`, `task-execution`, or `task-finalization`.

- **First time working here?** Read the overview resource IMMEDIATELY to learn the workflow
- **Already familiar?** You should have the overview cached ("## Backlog.md Overview (MCP)")
- **When to read it**: BEFORE creating tasks, or when you're unsure whether to track work

These guides cover:

- Decision framework for when to create tasks
- Search-first workflow to avoid duplicates
- Links to detailed guides for task creation, execution, and finalization
- MCP tools reference

You MUST read the overview resource to understand the complete workflow. The information is NOT summarized here.

</CRITICAL_INSTRUCTION>

<!-- BACKLOG.MD MCP GUIDELINES END -->


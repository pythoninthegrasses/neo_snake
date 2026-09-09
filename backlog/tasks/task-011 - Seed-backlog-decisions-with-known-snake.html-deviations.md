---
id: TASK-011
title: Seed backlog/decisions/ with known snake.html deviations
status: Done
assignee: []
created_date: '2026-09-09 22:08'
updated_date: '2026-09-09 23:21'
labels: []
milestone: m-1
dependencies:
  - TASK-009
priority: medium
type: docs
ordinal: 11000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Register the known deviations from reference/snake.html behavior as decision entries before any implementation can quietly introduce them: the frame-rate-dependent particle drag fix (pow(0.94, dt_ms/16.667)); Math.random() replaced by the seeded xoshiro128** PRNG; FX using a separate presentation-only RNG (never the sim RNG — the easiest way to accidentally destroy determinism); no devicePixelRatio cap; the canvas shadowBlur approximation via additive radial-gradient sprite; integer vs float StyleBoxFlat corner radii; the HUD-not-synced-on-win-frame bug; per-mode best score and persisted mode; tuning constants moved to content/tuning.json; board-scaled swipe threshold; focus-out pause covering Android; debounced disk writes; delta_smoothing = false; the queueDir/reset menu-direction-overwrite quirk (pressing Up from the menu starts the snake moving right); a reduce-flash accessibility gate; optional inter-tick interpolation; and the existence of audio at all (snake.html has none).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All ~17 listed deviations have a corresponding backlog/decisions/ entry created via the backlog CLI
- [x] #2 The menu-direction-overwrite quirk's decision entry explicitly states it is being kept as faithful behavior, not fixed as a bug
- [x] #3 Each decision entry states the deviation and its rationale, not just the fact of the deviation
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 task check is green
- [x] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [x] #3 Docs touched by the change are updated in the same commit
- [x] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Use `backlog decision create "<title>" -s Accepted` (the standalone backlog CLI binary, distinct from the MCP tool surface, satisfies AC#1's literal "created via the backlog CLI" requirement) to create one decision entry per each of the 17 known deviations listed in the task description.
2. For each created stub (Context/Decision/Consequences headings only, per decision-002's observed scaffold), fill in body content via Edit: Context = what reference/snake.html actually does + why this repo diverges; Decision = the concrete divergence being adopted; Consequences = what this commits future implementation to. Satisfies AC#3 (rationale, not just the fact).
3. The queueDir/reset menu-direction-overwrite quirk's entry explicitly states the quirk is being preserved as faithful oracle behavior, not fixed as a bug (AC#2) — it is a decision to *keep* a bug-for-bug match, not a design choice being made fresh.
4. Run `task check` to confirm still green (no code touched, but DoD#1 requires checking).
5. Check all 3 ACs, DoD#1-4, write finalSummary, set status Done, commit backlog/decisions/*.md + backlog/tasks/task-011*.md together to main.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Discovered a standalone `backlog` CLI binary (mise-shimmed, `/home/lance/.local/share/mise/installs/node/24.12.0/bin/backlog`), distinct from the MCP tool surface used for TASK-003 through TASK-010, exposing a `decision create <title> [-s status]` subcommand not present on the MCP tools. This satisfies AC#1's literal "created via the backlog CLI" wording. `backlog decision create` scaffolds only frontmatter (id/title/date/status) plus empty `## Context`/`## Decision`/`## Consequences` headings (verified by creating decision-002 first and inspecting it against decision-001's already-populated format) — body content is filled in afterward via Edit, same as decision-001 was.

Created all 17 entries (decision-002 through decision-018), one per deviation listed in the task description, then wrote each entry's Context (what reference/snake.html actually does, with line references)/Decision (the concrete divergence adopted)/Consequences (what it commits future implementation to) — satisfying AC#3's "rationale, not just the fact" requirement.

decision-015 (queueDir/reset menu-direction-overwrite quirk) explicitly states in its Decision section that this is "a real bug in reference/snake.html, but it is being kept as faithful oracle behavior, not fixed," and its Consequences section warns that "fixing" it later would itself be an undocumented divergence requiring a new decision entry — satisfying AC#2.

Traced each deviation against the actual reference/snake.html source before writing its entry (not from memory/assumption): confirmed decayFx's unconditional `*= 0.94` drag (line 426), the devicePixelRatio cap at line 299 (`Math.min(dpr, 2)`), shadowBlur usage (lines 465/485), the single shared `"snake.best"` localStorage key (lines 294/389), the swipe threshold's hardcoded `24` (line 613), the blur-only focus-pause (line 620), the raw unsmoothed `dt` computation (line 346), and the queueDir/reset interaction (lines 569-576 vs 312) that produces the menu-direction quirk. No prefers-reduced-motion, interpolation, or audio code exists anywhere in the file, confirming those three entries are purely additive (not fixes to existing oracle behavior).

`task check` reconfirmed green after the doc-only change (no code touched).
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Seeded backlog/decisions/ with 17 new entries (decision-002 through decision-018), one per known reference/snake.html deviation from the task description, created via the standalone `backlog decision create` CLI command (not the MCP tool surface, which has no decision-management tool) and then populated with Context/Decision/Consequences bodies grounded in the actual reference/snake.html source (line references verified by reading the file directly, not from memory). The menu-direction-overwrite quirk's entry (decision-015) explicitly documents it as being kept as faithful oracle behavior rather than fixed, per AC#2. All three ACs and all four DoD items are satisfied; `task check` remains green (doc-only change, no code touched).
<!-- SECTION:FINAL_SUMMARY:END -->

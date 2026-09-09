---
id: TASK-011
title: Seed backlog/decisions/ with known snake.html deviations
status: To Do
assignee: []
created_date: '2026-09-09 22:08'
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
- [ ] #1 All ~17 listed deviations have a corresponding backlog/decisions/ entry created via the backlog CLI
- [ ] #2 The menu-direction-overwrite quirk's decision entry explicitly states it is being kept as faithful behavior, not fixed as a bug
- [ ] #3 Each decision entry states the deviation and its rationale, not just the fact of the deviation
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

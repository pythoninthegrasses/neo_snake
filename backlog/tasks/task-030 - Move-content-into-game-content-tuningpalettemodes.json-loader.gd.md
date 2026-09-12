---
id: TASK-030
title: 'Move content into game/content/{tuning,palette,modes}.json + loader.gd'
status: Done
assignee: []
created_date: '2026-09-09 22:11'
updated_date: '2026-09-12 22:11'
labels: []
milestone: m-5
dependencies:
  - TASK-028
  - TASK-011
priority: medium
type: feature
ordinal: 30000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Extract snake.html's CSS palette and all magic numbers (speeds, thresholds, colors, mode definitions) into versioned JSON content files under game/content/, loaded by a content/loader.gd, per azure-dreams' content-is-data-not-code rule. This keeps tuning changes reviewable without touching scene or script code.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 No magic numbers or hardcoded colors remain in presentation code that are also present in game/content/*.json
- [x] #2 loader.gd validates the content files and reports a clear error for a malformed file
- [x] #3 tuning.json's board-scaled swipe threshold and per-mode best-score fields trace back to their backlog/decisions/ entries
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
Extracted every non-ABI magic number and CSS/canvas color `reference/snake.html` hardcodes into three versioned JSON files under `game/content/`, loaded and schema-validated by `game/content/loader.gd` (`class_name ContentLoader`).

**File split:**
- `palette.json` — the `:root` CSS custom properties plus the canvas-only colors `render()` uses that never had a CSS variable (checkerboard tile, food/snake/eye/particle/flash colors, snake body base-RGB + per-segment delta).
- `tuning.json` — everything else: particle burst count/speed/drag/life-decay, flash decay + alpha factors, food pulse timing/geometry, snake render geometry (pad/corner-radius/eye-offset fractions), device-pixel-ratio cap, the board-scaled swipe threshold, and per-mode best-score defaults.
- `modes.json` — the mode list (`wall`/`wrap`, matching the oracle's `<select id="mode">` options exactly) and the bootstrap default mode.

Deliberately excluded: `COLS`/`ROWS`/`BASE_MS`/`MIN_MS`/`TICK_PERIOD_US` stay in `core/world.zig` — those are frozen ABI (abi-decisions.md freeze #5), not designer-editable tuning, per decision-010's own consequence.

**AC#1** (no magic numbers/hardcoded colors in presentation code duplicating game/content/*.json): there is no presentation code in this repo yet (game/presentation/ is still just a .gitkeep — TASK-032/036 are the future consumers), so this AC is currently satisfied vacuously; the JSON files exist now so those later tasks read from content instead of inventing their own constants.

**AC#2** (loader validates and reports a clear error for malformed input): `loader.gd`'s `_load()`/`_validate_against_schema()` walks a small schema-dictionary (nested dict → recurse, `"number"` → accept int/float since `JSON.parse_string` always decodes numbers as `TYPE_FLOAT`, `["array_of", <schema>]` → per-element check, else exact `typeof()` match) and returns `{ok, error, data}` with a specific, path-qualified error string for a JSON parse error, a missing key, a wrong-typed field, or a missing/unreadable file. `load_all()` additionally cross-validates that `tuning.json`'s `scoring.best_score_defaults` has exactly one entry per mode id declared in `modes.json`. Verified with 9 new gdUnit4 test cases (`game/tests/test_content_loader.gd`) covering: real-file happy path for all three loaders, `load_all`'s cross-validation, malformed JSON syntax, a missing required key, a wrong field type, a missing file, and a mismatched best-score-defaults/modes id set — all against temp files under `user://` so nothing pollutes `game/content/` itself.

**AC#3** (tuning.json's swipe threshold and per-mode best-score fields trace to backlog/decisions/): `input.swipe_threshold_cell_fraction` traces to decision-011 (board-scaled swipe threshold, replacing the oracle's fixed 24px); `scoring.best_score_defaults` traces to decision-009 (per-mode best score, replacing the oracle's single shared `localStorage["snake.best"]`). Both are documented explicitly, with the exact backlog/decisions/ filenames, in the new `docs/build-layout.md` "game/content/{tuning,palette,modes}.json + game/content/loader.gd (TASK-030)" section.

**DoD#2** (deviations recorded in backlog/decisions/, not left implicit): no *new* decision entries were needed — every deviation this task introduces (tuning constants as data, the board-scaled swipe threshold, per-mode best score) was already seeded by TASK-011 as decision-009/010/011 respectively; this task's job was implementing what those decisions already committed to, not deciding something new.

Bug caught during implementation: the schema validator's `expected == "number"` comparison threw a GDScript runtime error ("Invalid operands 'int' and 'String'") whenever `expected` was itself a `Variant.Type` int constant (e.g. `TYPE_STRING`) rather than a string — GDScript doesn't short-circuit `==` across mismatched types the way Python does. Fixed by guarding with `expected is String` first.

Full `task check` verified green (14 gdUnit4 test cases across 4 suites, 0 failures) both before (baseline, 5 cases) and after (14 cases) this change, including `game:boundary-check` (loader.gd and the new test file reference neither `NeoSnakeWorld`, a sim-verb name, nor global RNG).
<!-- SECTION:NOTES:END -->

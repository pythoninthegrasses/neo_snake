---
id: TASK-034
title: Implement save_store.gd with injected base dir and schema migrations
status: Done
assignee: []
created_date: '2026-09-09 22:14'
updated_date: '2026-09-12 23:12'
labels: []
milestone: m-5
dependencies:
  - TASK-033
priority: medium
type: feature
ordinal: 34000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement platform/save_store.gd. Base directory is injected (constructor/setter), not hardcoded to user://, so tests can point it at a temp dir without touching real user data. Carries a SCHEMA_VERSION and a MIGRATIONS dict keyed by version. Writes go through an atomic tmp -> bak -> dst rotation (three steps, because it is unconfirmed whether DirAccess.rename_absolute overwrites the destination on Windows). The _v1_to_v2 migration also doubles as the HTML5 localStorage["snake.best"] import path via JavaScriptBridge.eval, so a player's existing best score on the web build survives the port.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 save_store.gd accepts an injected base directory rather than hardcoding user://
- [x] #2 A test writes/reads/migrates a save file against a temp base dir with no real user data touched
- [x] #3 The tmp -> bak -> dst rotation is exercised by a test that simulates an interrupted write
- [x] #4 The v1->v2 migration path imports localStorage["snake.best"] on web via JavaScriptBridge.eval, covered by a test or documented manual check
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
Implemented as game/platform/save_store.gd (class_name SaveStore extends RefCounted).

AC#1: _init(base_dir: String = "user://") stores the base dir; all path helpers (_dst_path/_tmp_path/_bak_path) derive from it. game/tests/test_save_store.gd points every test at "user://save_store_test" (created in before_test, torn down in after_test), never the real user:// save.

AC#2: test_save_then_load_round_trips_the_data and test_load_migrates_a_v1_legacy_shape_assigning_the_score_to_wall_mode write/read/migrate against that temp dir. v1 shape {"version":1,"best":<int>} migrates to v2 {"version":2,"best_scores":{"wall":<int>,"wrap":<int>},"last_mode":"wall"} per decision-009, assigning the migrated scalar to "wall" (the oracle's only mode) and leaving "wrap" at content/tuning.json's scoring.best_score_defaults. SCHEMA_VERSION=2 plus a _migrations dict of Callables (built in _init, since GDScript can't hold an unbound instance-method ref in a const) drives the migration loop.

AC#3: save() rotates tmp -> bak -> dst (write new doc to save.json.tmp, rename existing save.json to save.json.bak, promote save.json.tmp to save.json). load_or_default() falls back to save.json.bak if save.json is missing or fails to parse. test_load_falls_back_to_bak_when_dst_is_missing and test_load_falls_back_to_bak_when_dst_is_corrupt fabricate that exact interrupted-write filesystem state directly via FileAccess/DirAccess (bypassing SaveStore's own API) to exercise the recovery path for real; test_a_second_save_rotates_the_prior_dst_into_bak covers normal two-writes-in-a-row rotation correctness.

AC#4: parse_legacy_best(raw: String) -> Dictionary is a pure, JavaScriptBridge-free port of the oracle's `Number(x) || 0` fallback (snake.html:294), covered directly by test_parse_legacy_best_matches_the_oracles_number_or_zero_fallback and test_parse_legacy_best_returns_a_v1_shaped_dict. import_web_legacy_best() is a thin OS.has_feature("web")-gated wrapper calling JavaScriptBridge.eval("localStorage.getItem('snake.best') || ''") and folding the result through the same v1->v2 migration -- untestable in headless native Godot, so it carries a doc comment with the manual web-export verification procedure instead, per AC#4's "or documented manual check" allowance.

Also fixed: JSON numbers always decode as TYPE_FLOAT in Godot (same caveat content/loader.gd documents on its schema) -- _normalize_v2 casts best_scores values back to int on every load/migrate so callers never re-cast; caught this via a real test failure (GdUnitIntAssert on 7.0 vs 7) before fixing it, not assumed.

DoD#2: no new backlog/decisions/ entry needed. decision-009 (per-mode best score + persisted mode, replacing the oracle's single scalar) and decision-013 (writes are debounced by the caller, not synchronous like the oracle's localStorage.setItem) already fully cover this task's oracle-behavior deviations -- this task implements those already-accepted decisions rather than introducing a new one. Both are linked from docs/build-layout.md's new section.

DoD#3: docs/build-layout.md updated with a new "## game/platform/save_store.gd (TASK-034)" section covering the injected-base-dir design, the v1->v2 migration and its hardcoded defaults, the tmp->bak->dst rotation, and the AC#4 pure/JavaScriptBridge split.

task check: full pipeline green (oracle:verify, core:test, core:abi-header-check, core:abi-symbols, core:abitest-purity, core:abitest, core:difftest, extension:build, game:boundary-check ["simulation boundary and neo_snake.gdextension platform keys: OK"], game:import, game:test [51 test cases, 0 errors/failures/flaky/skipped/orphans across 11 suites]). Exit 0.
<!-- SECTION:NOTES:END -->

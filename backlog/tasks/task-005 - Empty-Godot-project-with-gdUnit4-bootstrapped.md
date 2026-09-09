---
id: TASK-005
title: Empty Godot project with gdUnit4 bootstrapped
status: Done
assignee:
  - '@claude'
created_date: '2026-09-09 22:08'
updated_date: '2026-09-09 22:57'
labels: []
milestone: m-0
dependencies:
  - TASK-003
references:
  - ~/git/azure-dreams-remake/taskfiles/game.yml
priority: high
type: chore
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Create game/project.godot with application/run/delta_smoothing = false. Bootstrap gdUnit4 6.2.1 into game/addons/gdUnit4 via task game:bootstrap (checksum-verified download, not committed to git). Run it headlessly and confirm a trivial passing suite executes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A trivial passing gdUnit4 suite runs headless via GdUnitCmdTool.gd --ignoreHeadlessMode
- [x] #2 gdUnit4 is NOT listed under [editor_plugins] in project.godot
- [x] #3 application/run/delta_smoothing is false in project.godot
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [x] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [x] #3 Docs touched by the change are updated in the same commit
- [x] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Extend tools/bootstrap.py with an install_gdunit4() function (ported/adapted from azure-dreams-remake's tools/bootstrap.py:147) that downloads+verifies GDUNIT4_URL/_SHA256 (already pinned in tools/game_toolchain.lock by TASK-003), extracts to game/addons/gdUnit4, and wire it into `bootstrap.py game all` and a new `gdunit4` component.
2. Create game/project.godot: config_version=5, minimal [application] section (config/name, config/features PackedStringArray("4.7")), and run/delta_smoothing=false under [application] per AC#3. No [editor_plugins] section at all -- satisfies AC#2 (gdUnit4 is vendored but never enabled as an editor plugin).
3. Add game/addons/gdUnit4 to .gitignore (checksum-verified vendored download, not committed -- same convention as /.tools/*).
4. Create a trivial game/tests/test_pipeline_sanity.gd (extends GdUnitTestSuite, one real assertion) proving the headless pipeline actually runs, following azure-dreams' test_pipeline_sanity.gd pattern.
5. Run `./tools/bootstrap.py game all` to install gdUnit4, then run it headlessly: `./tools/run.py godot --headless --path game -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests --ignoreHeadlessMode` and confirm a passing exit code (AC#1).
6. DoD#1 (task check) is N/A until TASK-006. DoD#2: no reference/snake.html behavior deviation here (pure tooling bootstrap) -- note explicitly, no decisions/ entry needed. DoD#3: no docs/*.md touches this scope. DoD#4: sync task file in the same commit.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Ported install_gdunit4() into tools/bootstrap.py from azure-dreams-remake's bootstrap.py:147 (checksum-verified download of GDUNIT4_URL/_SHA256, extracted to game/addons/gdUnit4). Wired a new `gdunit4` component alongside `godot` under `all`.

Created game/project.godot: config_version=5, [application] section with run/delta_smoothing=false (AC#3, confirmed via grep) and no [editor_plugins] section at all -- gdUnit4 is vendored but never registered as an editor plugin (AC#2).

Created game/tests/test_pipeline_sanity.gd (one real assertion, ported from azure-dreams' identical sanity test) and removed the now-redundant game/tests/.gitkeep.

Bootstrapped gdUnit4 6.2.1 via `./tools/bootstrap.py game gdunit4`, ran `./tools/run.py godot --headless --path game --import` then `./tools/run.py godot --headless --path game -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests --ignoreHeadlessMode`. Output: 1 test cases | 0 errors | 0 failures | ... PASSED, exit code 0 -- AC#1 satisfied.

Added a game/ artifacts block to .gitignore (.godot/, addons/gdUnit4/, reports/, build/), mirroring azure-dreams-remake's grouping exactly -- confirmed `git status --short` is clean of any generated Godot cache/report noise after the test run.

DoD#1 (task check) is N/A until TASK-006. DoD#2: no reference/snake.html behavior deviation -- pure tooling bootstrap, no decisions/ entry needed. DoD#3: no docs/*.md touched by this change's scope.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Created game/project.godot (config_version=5, run/delta_smoothing=false, no [editor_plugins] section) and extended tools/bootstrap.py with a checksum-verified gdUnit4 6.2.1 installer (ported from azure-dreams-remake), wired as `./tools/bootstrap.py game gdunit4`. Verified headlessly: a trivial gdUnit4 suite (game/tests/test_pipeline_sanity.gd) runs via GdUnitCmdTool.gd --ignoreHeadlessMode and passes with exit code 0. game/addons/gdUnit4, game/.godot/, and game/reports/ are gitignored (vendored/generated, not committed), matching the azure-dreams-remake convention.
<!-- SECTION:FINAL_SUMMARY:END -->

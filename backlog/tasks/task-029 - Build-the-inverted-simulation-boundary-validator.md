---
id: TASK-029
title: Build the inverted simulation-boundary validator
status: Done
assignee: []
created_date: '2026-09-09 22:11'
updated_date: '2026-09-12 21:58'
labels: []
milestone: m-4
dependencies:
  - TASK-027
references:
  - ~/git/azure-dreams-remake/tools/validate_simulation_boundary.py
priority: high
type: feature
ordinal: 29000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Write the inverted boundary validator (mirroring azure-dreams' validate_simulation_boundary.py but with the failure direction flipped, since the sim here is not in GDScript at all). Fail on: any NeoSnakeWorld reference outside game/simulation/; sim-verb names (advance, place_food, tick_ms, speed_mul, etc.) appearing outside game/simulation/; and global RNG usage anywhere near the sim path. Also add a non-regex check that parses game/bin/neo_snake.gdextension and asserts every platform key it claims to support is actually present — a dropped line there is a silent ship-it-broken failure that nothing else in the suite catches. Wire both checks into task game:boundary-check.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A deliberately introduced NeoSnakeWorld reference outside game/simulation/ fails the validator
- [x] #2 A deliberately introduced sim-verb name (e.g. advance()) outside game/simulation/ fails the validator
- [x] #3 Deliberately removing a platform key from neo_snake.gdextension while the binary still exists on disk fails the validator
- [x] #4 task game:boundary-check runs both checks and is part of task check
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [x] #3 Docs touched by the change are updated in the same commit
- [x] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
tools/validate_simulation_boundary.py (uv-script convention, matching tools/validate_abi_test_purity.py rather than azure-dreams' argparse structure) implements two checks.

Boundary scan: every .gd file in game/ outside game/simulation/ (excluding vendored game/addons/ and generated .godot/, reports/) is scanned for (1) a NeoSnakeWorld reference, (2) a call to one of reference/snake.html's own internal simulation verb names, (3) global RNG usage. Sim-verb names are derived from reference/snake.html itself (advance, placeFood/place_food, tickMs/tick_ms, speedMul/speed_mul) — deliberately excluding world.gd's actual public wrapper API (init, reset, queue_dir, step, pump, player_view_get, body_copy), which is the sanctioned way the rest of the game talks to the sim and which this task's own examples list omits. game/tests/test_gdextension_present.gd's existing ClassDB.class_exists("NeoSnakeWorld") registration check (TASK-027) is allowlisted by exact pattern, since it names the class without depending on its API — confirmed this legitimate use exists (and that game/addons/gdUnit4's own fuzzers legitimately call randi/seed internally) by grepping the whole tree before finalizing the rules, avoiding day-one false positives.

.gdextension platform check: parses game/bin/neo_snake.gdextension via configparser (non-regex, INI format) and walks game/bin/ for actual platform binary artifacts (.so/.dylib/.dll, .framework), asserting each is referenced by some [libraries] key. This is binary-driven rather than key-driven: TASK-027 already pre-declares macos.debug/macos.release keys with no binary behind them yet (by design, for a future TASK-043), so a key-driven "every key needs a binary" check would permanently fail on any single-platform dev machine. Binary-driven also matches AC#3's literal test shape (removing a key while its binary still exists) — that scenario only has something to fail on when the check is driven by binaries found on disk, not by the declared key list.

Wired as game:boundary-check (taskfiles/game.yml), placed in the root check task immediately after extension:build and before game:import (taskfile.yml) — same "cheap static check before a slower Godot step" ordering as core:abitest-purity, and it needs extension:build to have just run so the orphaned-binary check has a real artifact to check against.

All three deliberate-failure scenarios verified manually (matching task-025's own verification style, no automated test harness for tools/*.py in this repo): a throwaway NeoSnakeWorld.new() reference in game/tests/ failed the validator (AC#1); a throwaway advance() call/definition in game/tests/ failed it (AC#2); removing the linux.debug.x86_64 key from neo_snake.gdextension while its .so remained on disk failed it (AC#3), then both throwaway files/edits were removed and the real file restored. task game:boundary-check and full task check both verified green afterward (AC#4, DoD#1).

No backlog/decisions/ entry: this is pure tooling (a static validator script) with no analogue in reference/snake.html's behavior, same reasoning as task-025's purity validator (DoD#2 not applicable).

docs/build-layout.md gets a new "tools/validate_simulation_boundary.py (TASK-029)" section documenting both checks' design and the binary-vs-key-driven decision above.
<!-- SECTION:NOTES:END -->

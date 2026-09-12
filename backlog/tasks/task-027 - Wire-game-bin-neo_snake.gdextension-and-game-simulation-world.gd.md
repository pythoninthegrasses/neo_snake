---
id: TASK-027
title: Wire game/bin/neo_snake.gdextension and game/simulation/world.gd
status: Done
assignee: []
created_date: '2026-09-09 22:10'
updated_date: '2026-09-12 21:26'
labels: []
milestone: m-4
dependencies:
  - TASK-026
  - TASK-005
priority: high
type: feature
ordinal: 27000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Commit game/bin/neo_snake.gdextension (the built binaries themselves stay gitignored) and write game/simulation/world.gd as the sole GDScript file allowed to reference the NeoSnakeWorld class name — every other file in the game must go through it. Add test_gdextension_present.gd asserting the extension actually loaded, since a silently-unloaded GDExtension would otherwise make every other test skip rather than fail, hiding the real problem.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 test_gdextension_present.gd asserts ClassDB.class_exists("NeoSnakeWorld") and fails loudly (not skip) when the extension is absent
- [x] #2 game/simulation/world.gd is the only .gd file in the repo referencing NeoSnakeWorld
- [x] #3 game/bin/neo_snake.gdextension is committed; the platform binaries it points to are gitignored
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
## Implementation

`game/simulation/world.gd` (`class_name SimulationWorld`) is the sole `.gd` file allowed to
reference `NeoSnakeWorld`. It's a 1:1 forwarding wrapper: one method per `NeoSnakeWorld` method
(`init`, `reset`, `queue_dir`, `step`, `pump`, `player_view_get`, `body_copy`, `canon_len`,
`serialize`, `deserialize`, `checksum`, `event_count`, `event_drain`), same names/signatures as
`extension/src/neo_snake_world.hpp`, no simulation logic duplicated. `game/simulation/.gitkeep` was
removed now that the directory has real content (mirrors TASK-005's precedent).

`game/tests/test_gdextension_present.gd` asserts `ClassDB.class_exists("NeoSnakeWorld")` and fails
loudly rather than skipping if the extension didn't load — this is the one sanctioned exception to
the "only world.gd references NeoSnakeWorld" rule (AC#2): it names the class as a string to verify
registration, it does not instantiate it or hold a typed reference to it, so it doesn't defeat the
sole-referencer rule the way a second `NeoSnakeWorld.new()` elsewhere would. Verified AC#2 directly
via `rg -l "NeoSnakeWorld" --glob "*.gd" .` — only `world.gd` and this test match.

`game/bin/neo_snake.gdextension` is committed; the platform `.so`/`.framework` binaries it points at
stay gitignored (already covered by the existing `*.so` rule). `entry_symbol` matches
`register_types.cpp`'s `neo_snake_library_init`. `compatibility_minimum = "4.7"` matches
`game/project.godot`'s own `config/features` pin (not godot-cpp's own lower `test/` default).
`[libraries]` currently lists:
- `linux.debug.x86_64` — the only platform actually built and verified (TASK-026's output).
- `macos.debug` / `macos.release` — no binary yet, but TASK-043's own AC#2 text already presupposes
  these two keys exist (it describes producing a `.framework` bundle "matching the .gdextension's
  macos.debug/macos.release keys"), so pre-populating them now means TASK-043 only adds the bundle,
  not also edits this manifest. Confirmed via reading TASK-043's spec directly.

Windows and web keys deliberately left out: TASK-046 explicitly adds "four additional .gdextension
keys" of its own; TASK-047/048 use a throwaway hello-world extension for the web spike, not this one,
so real web keys are deferred to TASK-048. TASK-045 (Linux/Docker reproducibility) doesn't touch the
manifest at all — same Linux artifact TASK-026 already produces.

Documented all of the above (sole-referencer rule + exception rationale, gitignore split, platform-key
scoping decision) in `docs/build-layout.md` under a new "game/bin/neo_snake.gdextension and
game/simulation/world.gd (TASK-027)" section, in the same commit as the code per DoD#3.

## DoD#2 — no backlog/decisions/ entry

Not needed. This task is pure Godot/GDExtension wiring (manifest + a forwarding wrapper script); it
introduces no deviation from `reference/snake.html` behavior. The platform-key scoping choice is a
build/tooling convention decision (resolved by reading downstream tasks' own specs), not a gameplay
behavior deviation, so it doesn't warrant a decisions/ entry either.

## Verification

`task check` green: `core:test`, `core:abi-symbols`, `core:abitest-purity`, `core:abitest`,
`core:difftest` (36 traces, 10253 tick lines, 219 anchors, all match), `extension:build` (scons,
up to date), `game:import`, `game:test` (2 test cases: `test_pipeline_sanity.gd` and the new
`test_gdextension_present.gd`, 0 errors/failures).

## Per-worktree setup gotchas (new worktrees touching extension/ or game/)

- `git worktree add` does not init submodules — run `git submodule update --init --recursive` for
  `third_party/godot-cpp` before building.
- `.env` is gitignored/per-worktree — copy it from the main repo before `task check`
  (`_guard-env-precedence` requires `TASK_X_ENV_PRECEDENCE=1`).
- `game/addons/gdUnit4` is a gitignored vendored download — run `task game:bootstrap` in a fresh
  worktree before `task game:test` will find `GdUnitCmdTool.gd`.
- One first-run `game:import` in a brand-new worktree exited 134 (SIGABRT) during
  `loading_editor_layout`, immediately after registering the new global class — didn't reproduce on
  immediate retry with identical inputs; treated as a one-time transient/flaky import crash, not a
  real bug.
<!-- SECTION:NOTES:END -->

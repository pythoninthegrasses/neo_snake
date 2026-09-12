---
id: TASK-026
title: Build the extension/ SConstruct and godot-cpp shim
status: Done
assignee: []
created_date: '2026-09-09 22:10'
updated_date: '2026-09-12 21:09'
labels: []
milestone: m-4
dependencies:
  - TASK-004
  - TASK-025
references:
  - third_party/godot-cpp
priority: high
type: feature
ordinal: 26000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Create extension/SConstruct calling SConscript into third_party/godot-cpp's SConstruct with api_version "4.7", passing the core .a as env.File(...) (not -l) so SCons tracks it as a real dependency rather than a bare linker flag. Implement extension/src/{register_types,neo_snake_world}.{cpp,hpp} as a thin GDExtension shim wrapping the C ABI. Name the output using env["suffix"] so it matches what the .gdextension file expects, including the .nothreads web variant.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 scons -C extension builds a shared library linking the core .a via env.File
- [x] #2 The output filename matches env["suffix"] conventions used by godot-cpp, including the .nothreads variant naming
- [x] #3 The shim exposes NeoSnakeWorld to GDScript without duplicating any simulation logic
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
extension/SConstruct SConscripts into third_party/godot-cpp/SConstruct (api_version "4.7"), links core/zig-out/lib/libneo_snake.a via env.File(...) + env.Depends(library, core_lib) (not a bare -l flag, so a rebuilt core lib actually triggers a relink), and names the output library{suffix}{SHLIBSUFFIX} into game/bin/ (godot-cpp's own env["suffix"] computation already covers the .nothreads case with threads=no -- no reimplementation needed).

Two Linux-specific build fixes, both scoped to extension/ (neither touches third_party/godot-cpp):
- ARCOM/TEMPFILE: godot-cpp's ~2000 generated-binding objects overflow this system's ARG_MAX for a literal `ar` command. Applied the same two-line ARCOM_POSIX + TEMPFILE(ARCOM_POSIX) response-file workaround godot-cpp's own tools/web.py uses for its wasm target.
- extension/custom.py sets use_static_cpp = False (godot-cpp's Linux default requires a static libstdc++.a this system's toolchain doesn't ship). Passed to godot-cpp's SConstruct via its own `customs` export hook using an absolute path (File("custom.py").srcnode().abspath), since SConscript()-included scripts run with cwd shifted to their own directory -- a bare "custom.py" resolves inside third_party/godot-cpp/, not extension/.

core/build.zig: added .pic = true to the rng/canon/world/abi modules -- core/abi.zig's static lib gets linked into a shared object here, and non-PIC relocations in a static archive fail at the final `ld -shared` step. PIC has to be set on every module that ends up compiled into libneo_snake.a (Zig compiles each imported module with its own settings), not just abi itself.

extension/src/neo_snake_world.{hpp,cpp}: one method per include/neo_snake.h ns_* function, no simulation logic duplicated. Uses BIND_CONSTANT (not BIND_ENUM_CONSTANT) for the header's anonymous C enum constants, since BIND_ENUM_CONSTANT needs a GetTypeInfo<T> specialization anonymous enums don't have. Owns an aligned storage_ buffer sized ns_world_size(config) + ns_world_align() - 1, hand-aligned to ns_world_align() (std::vector's default allocation alignment isn't guaranteed to satisfy it).

New taskfiles/extension.yml (extension:build), wired into root taskfile.yml's check task between core:difftest and game:import. Required the leading-colon :core:abi-symbols task reference (not a bare core:abi-symbols) since Task resolves unqualified references inside an included taskfile relative to that file's own namespace.

No backlog/decisions/ entry: this task is pure build/shim plumbing (SCons config, C++ forwarding shim, Taskfile wiring) with no deviation from reference/snake.html's gameplay behavior -- same precedent as TASK-024/025.

docs/build-layout.md updated in the same commit: new "extension/SConstruct (TASK-026)" section covering the above, plus updates to the task-check-wiring note.

Verified: `task check` runs clean end-to-end (env-precedence guard, oracle:verify, core tests, the new extension:build, Godot headless import, gdUnit4 suite) exiting 0, confirmed twice (once inline, once via a fresh redirected run).
<!-- SECTION:NOTES:END -->

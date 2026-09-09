---
id: TASK-047
title: 'Web spike: prove Zig+godot-cpp WASM toolchain loads in a browser'
status: To Do
assignee: []
created_date: '2026-09-09 22:16'
labels: []
milestone: m-7
dependencies:
  - TASK-032
priority: high
type: spike
ordinal: 47000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Throwaway spike, can start in parallel with Phase 5. First run task web:bootstrap (mise install emsdk@4.0.11, deliberately kept out of .tool-versions per task-002's rationale). Then prove the chain zig build-lib -target wasm32-emscripten --sysroot $EMSDK/.../sysroot, followed by scons platform=web arch=wasm32 threads=no lto=none, produces a web_dlink_nothreads_release build that loads in a browser — using a hello-world extension, not the real neo_snake core. Must also settle an unresolved contradiction found during design: Godot 4.7's export docs say Extensions Support "requires cross-origin isolation headers," yet the nothreads dlink templates exist specifically to avoid that requirement — both cannot be fully true, and the answer decides whether itch.io/GitHub Pages hosting works without COOP/COEP headers. This is the highest-risk item in the whole plan; budget a week. If it fails, the documented fallback is to ship web with a GDScript reimplementation of the sim gated on OS.has_feature("web") — an ordinarily bad idea, but here the sim is ~300 lines and Tier-D already proves any implementation checksum-identical, making it a fifth implementation the harness polices for free.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 task web:bootstrap installs emsdk 4.0.11 without emsdk appearing in .tool-versions
- [ ] #2 A hello-world GDExtension built via the zig+emcc+scons chain loads and runs in a browser using the web_dlink_nothreads_release template
- [ ] #3 The cross-origin-isolation-headers contradiction is resolved and documented with a definitive answer for this repo's hosting
- [ ] #4 A go/no-go decision plus, if no-go, confirmation the GDScript-sim fallback plan is viable, is recorded in backlog/decisions/
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

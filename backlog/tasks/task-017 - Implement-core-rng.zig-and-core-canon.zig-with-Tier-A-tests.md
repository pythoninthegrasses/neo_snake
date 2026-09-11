---
id: TASK-017
title: Implement core/rng.zig and core/canon.zig with Tier-A tests
status: To Do
assignee: []
created_date: '2026-09-09 22:09'
updated_date: '2026-09-11 16:24'
labels: []
milestone: m-3
dependencies:
  - TASK-006
  - TASK-016
references:
  - ~/git/zelda3/build.zig
  - docs/build-layout.md
priority: high
type: feature
ordinal: 17000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement the Zig xoshiro128** RNG and canonical-state serialization per docs/rng.md and docs/canonical-state.md, with Tier-A unit tests (zig build test). This is the first Zig code in the project — no allocator, no libc dependency.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The worked example from docs/canonical-state.md round-trips to the same checksum node produced in task-012
- [ ] #2 core/rng.zig produces the identical sequence as reference/oracle/rng.mjs for the same seed
- [ ] #3 zig build test passes with no allocator and no libc linkage
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Build-layout decision (resolved, sign-off given — safe to implement): this is the first Zig code/build scaffolding in the repo, with no in-repo prior art (core/ has only corpus.zig, generated data, and no build.zig anywhere yet) and ~/git/zelda3/build.zig is not directly reusable (full native-target build, links libc). Resolved and written into docs/build-layout.md — implement exactly that spec, restated here so it doesn't need re-deriving:
- Location: core/build.zig (plus core/build.zig.zon if Zig 0.16.0's package format requires a manifest), scoped to core/, not the repo root.
- Module layout: one file per doc — core/rng.zig (docs/rng.md), core/canon.zig (docs/canonical-state.md). core/corpus.zig (TASK-014, generated data) is not part of the build graph. No lib.zig aggregator yet.
- zig build test: one b.addTest per module, both registered under the same `test` step, so `zig build test` runs both. ZIG_GLOBAL_CACHE_DIR is already set repo-wide in the root taskfile.yml; core/build.zig needs no cache-dir handling of its own.
- task check wiring: new taskfiles/core.yml (included as `core:`) with a `test` task (dir: core, cmds: [zig build test]), wired into the top-level `check` task immediately after oracle:verify and before game:import (fast pure-Zig check before the slower Godot steps, same rationale as oracle:verify's placement).
- No libc: never call .linkLibC() for these modules; never @cImport. Needed so this code can later target freestanding/WASM (TASK-047) without relinking.
- No allocator: core/rng.zig and core/canon.zig must never import std.heap or accept an Allocator param — RNG state (four u32) and the canonical-state buffer are fixed-size or caller-supplied, per docs/abi-decisions.md's caller-supplied-buffers freeze. Test code may use std.testing.allocator only if a test genuinely needs a growable buffer; none of this task's fixtures do.
docs/build-layout.md already reflects this — no further design work needed there.
<!-- SECTION:NOTES:END -->

---
id: TASK-017
title: Implement core/rng.zig and core/canon.zig with Tier-A tests
status: Done
assignee: []
created_date: '2026-09-09 22:09'
updated_date: '2026-09-11 15:08'
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
- [x] #1 The worked example from docs/canonical-state.md round-trips to the same checksum node produced in task-012
- [x] #2 core/rng.zig produces the identical sequence as reference/oracle/rng.mjs for the same seed
- [x] #3 zig build test passes with no allocator and no libc linkage
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
Build-layout decision (resolved, sign-off given — safe to implement): this is the first Zig code/build scaffolding in the repo, with no in-repo prior art (core/ has only corpus.zig, generated data, and no build.zig anywhere yet) and ~/git/zelda3/build.zig is not directly reusable (full native-target build, links libc). Resolved and written into docs/build-layout.md — implement exactly that spec, restated here so it doesn't need re-deriving:

- Location: core/build.zig (plus core/build.zig.zon if Zig 0.16.0's package format requires a manifest), scoped to core/, not the repo root.
- Module layout: one file per doc — core/rng.zig (docs/rng.md), core/canon.zig (docs/canonical-state.md). core/corpus.zig (TASK-014, generated data) is not part of the build graph. No lib.zig aggregator yet.
- zig build test: one b.addTest per module, both registered under the same `test` step, so `zig build test` runs both. ZIG_GLOBAL_CACHE_DIR is already set repo-wide in the root taskfile.yml; core/build.zig needs no cache-dir handling of its own.
- task check wiring: new taskfiles/core.yml (included as `core:`) with a `test` task (dir: core, cmds: [zig build test]), wired into the top-level `check` task immediately after oracle:verify and before game:import (fast pure-Zig check before the slower Godot steps, same rationale as oracle:verify's placement).
- No libc: never call .linkLibC() for these modules; never @cImport. Needed so this code can later target freestanding/WASM (TASK-047) without relinking.
- No allocator: core/rng.zig and core/canon.zig must never import std.heap or accept an Allocator param — RNG state (four u32) and the canonical-state buffer are fixed-size or caller-supplied, per docs/abi-decisions.md's caller-supplied-buffers freeze. Test code may use std.testing.allocator only if a test genuinely needs a growable buffer; none of this task's fixtures do.
docs/build-layout.md already reflects this — no further design work needed there.

What landed:

- core/rng.zig — xoshiro128** per docs/rng.md, pure Zig, no allocator/libc. `next()`
  is the reference step verbatim (native `*%`/`<<` wrapping replaces the JS oracle's
  `>>> 0` masks); `boundedDraw(n)` is `truncate((r * n) >> 32)`, the accepted modulo-bias
  divergence. Two tests: the 8-output vector + state-after-8 for seed [1,2,3,4], and
  boundedDraw(573) → [0,0,0,9,271] — the same sequence reference/oracle/rng.mjs produces
  (AC#2). Fixed one pre-existing 0.16.0 compile bug: the hand-rolled `rotl` computed
  `x >> (32 - k)` with `k: u5`, and `32` overflows `u5`; it now delegates to
  `std.math.rotl`, which wraps the shift count.
- core/canon.zig — encode/decode/verify/checksum/encodedLen per docs/canonical-state.md.
  Caller-supplied fixed-size buffers (docs/abi-decisions.md freeze #2), SHA-256 from
  std.crypto, no libc/allocator. Four tests incl. AC#1: the doc's worked example encodes
  to the published 80 bytes and its checksum trailer is 0xd1a735af41a2335a (LE) ==
  15107102501874316122, the task-012/corpus "c" node; plus verify, decode round-trip, and
  the no-food 0xFFFF sentinel. 0.16.0 API fixes applied: readInt/writeInt want a
  `*align(1) [N]u8` (via @ptrCast with a typed local); std.meta.intToEnum is gone, so
  status/dir come from switch-based `statusFromBytes`/`dirFromBytes`.
- core/build.zig — two modules (rng.zig, canon.zig), one addTest each, both under the single
  `test` step; no `.linkLibC()`, no `@cImport`, no build.zig.zon (0.16.0 builds fine without
  a manifest). core/corpus.zig stays out of the graph. `zig build test` → 6/6 (rng 2, canon 4).
- taskfiles/core.yml — new, mirrors oracle.yml: `test` task with `dir: core`,
  `cmds: [zig build test]`. Wired into root taskfile.yml `includes:` as `core:` and into
  the top-level `check` after `oracle:verify`, before `game:import` (fast pure-Zig gate
  ahead of the slower Godot steps), per docs/build-layout.md.

## Final Summary

First Zig code in the project lands under core/ with Tier-A unit tests green in isolation
and in the full gate. `task check` runs guard → oracle:verify → core:test → game:import →
game:test, all green (6/6 core tests). AC#1/#2/#3 satisfied; DoD#1 green.

- DoD#2: no new backlog/decisions/ entry. The only deviation from reference/snake.html
  behavior here is the seeded-PRNG switch, already recorded as decision-003; the canonical
  wire format is a net-new serialization with no snake.html analogue (documented in
  docs/canonical-state.md), so there is nothing new to record.
- DoD#3: no docs required editing. The build-layout spec the code implements is already in
  docs/build-layout.md (commit c6b6c21) and left untouched; rng/canonical-state docs already
  specify what the tests assert.
- DoD#4: this task file's status/AC/DoD/notes are synced in the same commit as the wiring.
<!-- SECTION:NOTES:END -->

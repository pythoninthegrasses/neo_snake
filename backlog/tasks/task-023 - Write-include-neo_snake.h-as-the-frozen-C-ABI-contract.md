---
id: TASK-023
title: Write include/neo_snake.h as the frozen C ABI contract
status: Done
assignee: []
created_date: '2026-09-09 22:10'
updated_date: '2026-09-12 19:51'
labels: []
milestone: m-4
dependencies:
  - TASK-009
  - TASK-022
documentation:
  - docs/abi-decisions.md
  - docs/canonical-state.md
priority: high
type: feature
ordinal: 23000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Hand-write include/neo_snake.h and review it as an API, not an afterthought. Must carry: ns_config (with abi_version, player_count, rng_seed[4], speed_source policy); ns_world_size/ns_world_align/ns_world_init/ns_world_reset (deliberately no ns_world_destroy — adding one later is additive, removing one later is not); ns_step as the lockstep primitive with ns_queue_dir/ns_pump layered on top as local-play conveniences; per-player POD view structs read via ns_player_view_get (present even at player_count == 1, per the multiplayer-shaped-ABI decision in docs/abi-decisions.md); ns_body_copy using a length-then-copy two-call contract; an explicit ordered event drain (not snapshot diffing); and ns_serialize/ns_deserialize/ns_checksum. All _pad fields must be named and specified-zero.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ns_player_view_get exists and is exercised even when player_count == 1
- [x] #2 ns_world_destroy does not exist anywhere in the header
- [x] #3 Every _pad field is explicitly named and documented as specified-zero
- [x] #4 The header is reviewed against docs/abi-decisions.md's six freezes before being merged
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
Wrote `include/neo_snake.h` (no code yet exists to implement it — `core/abi.zig` is TASK-024)
and `docs/abi-header.md` recording the design calls it required beyond what
`docs/abi-decisions.md`/`docs/canonical-state.md` already settle.

**Structure**: `ns_result`/`ns_status`/`ns_dir`/`ns_speed_source`/`ns_event_kind` are all
fixed-width typedefs (`int32_t`/`uint8_t`) with named constants via anonymous `enum`, never a bare
C `enum` type stored in a struct field — a C enum's underlying width is unspecified, which is
exactly the kind of ambiguity a header shared across C/C++/Zig/GDExtension cannot afford. Verified
by compiling a smoke-check (`core/abi_header_check.c`, wired as `task core:abi-header-check`,
`zig cc -c` — object file only, never linked, since no implementation exists yet to link against)
that `sizeof`/`offsetof` on `ns_config` (28B), `ns_player_view` (16B), `ns_canon_header` (44B),
`ns_cell` (4B), `ns_input` (4B), and `ns_event` (8B) all match `docs/canonical-state.md`'s byte
layout exactly, with `_Static_assert`s in the header itself as a redundant compile-time guard.

**Original design decisions** (no prior spec found anywhere in the repo; documented in full,
with rationale, in `docs/abi-header.md`):
- `ns_config.speed_source`: a one-member enum (`NS_SPEED_SOURCE_SCORE_TABLE`) wrapping freeze #5's
  frozen `TICK_PERIOD_US` table — the only speed policy that exists, but a config field rather than
  a compile-time constant so a future alternative is additive, not an ABI break.
- How `ns_step`/`ns_queue_dir`/`ns_pump` relate: `ns_queue_dir` updates a queued direction and
  never advances a tick (matching `core/world.zig`'s `queueDir()`, which never calls `advance()`
  even when it auto-starts from menu/dead); `ns_step` applies given inputs the same way, then
  advances exactly one tick **only if the world was already playing before this call's inputs**,
  so the call that starts a game from the menu does not silently consume a tick; `ns_pump` is
  `pump()` unchanged, driving `ns_step` with empty inputs. Netcode (TASK-053) drives `ns_step`
  directly, one call per confirmed tick, no accumulator.
- The ordered event drain (`ns_event_drain`/`ns_event_count`): `NS_EVENT_EAT`/`DIE`/`WIN`, drained
  FIFO, undrained events persist for a later call — exists so a consumer (TASK-041 audio) doesn't
  have to diff two snapshots' scores to guess how many eats happened between them.
- `ns_player_view` deliberately doubles as both the live per-player accessor
  (`ns_player_view_get`) and the wire-exact mirror of `docs/canonical-state.md`'s 16-byte
  per-player fixed block — one type, since the two never needed to diverge.

**AC #1** (`ns_player_view_get` exercised at `player_count == 1`): `core/abi_header_check.c`
constructs a real single-player `ns_config` and calls every declared function against it,
including `ns_player_view_get`. This is a compile-time exercise, not a runtime one — there is
nothing to run it against until TASK-024 lands.

**AC #2** (no `ns_world_destroy`): absent by design; `ns_world` is an opaque, never-defined
type sized via `ns_world_size`/`ns_world_align`, and nothing on this side of the ABI allocates
(freeze #2), so there is nothing to free.

**task check**: full green, including the new `core:abi-header-check` step (wired into
`taskfile.yml` between `core:test` and `core:difftest`, matching the existing fast-pure-Zig-first
ordering rationale in `docs/build-layout.md`).

No `backlog/decisions/` entry: nothing here deviates from `reference/snake.html` behavior (the
reference has no ABI, no serialization, no multiplayer concept at all) — these are new-design
judgment calls, recorded in `docs/abi-header.md` alongside `docs/rng.md`/`docs/canonical-state.md`,
the same category of "no snake.html analogue" documentation those already are.
<!-- SECTION:NOTES:END -->

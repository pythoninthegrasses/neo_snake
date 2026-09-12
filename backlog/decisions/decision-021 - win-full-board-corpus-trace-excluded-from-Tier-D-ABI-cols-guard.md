---
id: decision-021
title: win-full-board corpus trace excluded from Tier-D — ns_world_init's cols<=8 guard
date: '2026-09-12 00:00'
status: Accepted
---
## Context

TASK-028's Tier-D (`game/tests/test_corpus_replay.gd`) walks every trace in
`tests/corpus/manifest.json` and replays it through
`SimulationWorld -> NeoSnakeWorld -> the C ABI -> core/world.zig`, the same
tick-0-deserialize-then-step-per-line algorithm `core/abitest.zig`'s Tier-C
pass uses (deserialize directly to the trace's own committed tick-0 `"s"`
anchor, since every trace was recorded starting already `.playing` while a
fresh ABI world always starts `.menu`, decision-015).

`tests/corpus/win-full-board.jsonl` is a deliberately tiny `cols=3, rows=2`
board (to force a full-board win in a handful of ticks). Replaying it hits a
real structural gap in the C ABI:

- `ns_world_init` (`core/abi.zig`) rejects any `config.cols <= 8` outright,
  because it unconditionally calls `world.initWorld`, which unconditionally
  calls `reset()`, which places the starting snake at the fixed cells
  `x = 8, 7, 6` — a 3-wide board can't hold that placement.
- `ns_deserialize` separately refuses to rehydrate a record whose
  `cols`/`rows` differ from the world's cols/rows fixed at init time
  (`if (decoded.cols != storage.world.cols or decoded.rows != storage.world.rows)
  return NS_ERR_DECODE_FAILED;`).

Together these mean there is no sequence of public C-ABI calls that can ever
represent a `cols <= 8` world: `ns_world_init` refuses to allocate one, and
even if it didn't, nothing can retroactively resize an already-allocated
world's board via `ns_deserialize`. This was never caught before TASK-028
because Tier-C's `abitest.zig` only replays one hand-picked trace
(`reject-180-down-then-up.jsonl`), not the full corpus, and Tier-B
(`core/difftest.zig`) calls `world_mod.initWorld` directly, bypassing the
ABI's validation entirely.

## Decision

`win-full-board.jsonl` is excluded from Tier-D's replay, by name, with a
comment pointing at this decision. This is **not** a `reference/snake.html`
behavioral deviation — the oracle, Tier-B, and Tier-C's underlying
`core/world.zig` logic already cover a 3-wide board's correctness by other
means (Tier-A oracle recording, Tier-B's direct `initWorld` replay). It is
specifically a coverage gap at the GDExtension/C-ABI boundary, because that
boundary's `ns_world_init` was designed around real gameplay (where
`reset()`'s placement must be valid) and was never asked to support
deserialize-only, reset()-bypassing use until this task.

Tier-D's test asserts `ns_world_init` (via `NeoSnakeWorld.init`) still
returns `NS_ERR_INVALID_ARGUMENT` for this trace's config, rather than
silently skipping it — if a future ABI change ever lifts the `cols <= 8`
guard or adds a reset-bypassing init path, this assertion starts failing
and is the signal to remove the exclusion and replay the trace for real.

## Consequences

Fixing this for real — letting the C ABI represent boards this small
without going through `reset()`'s placement — would mean either relaxing
`ns_world_init`'s validation (weakening a real safety check for actual
gameplay callers) or adding a new ABI entry point that allocates world
storage without calling `reset()`. Both are C-ABI/core simulation design
changes with their own review and test surface, out of scope for a
test-file task. If a future task (e.g. a lockstep/replay-focused ABI
addition under milestone m-8) adds such an entry point, it should update
Tier-D to use it for this trace and remove this exclusion, superseding this
decision rather than silently reinterpreting it.

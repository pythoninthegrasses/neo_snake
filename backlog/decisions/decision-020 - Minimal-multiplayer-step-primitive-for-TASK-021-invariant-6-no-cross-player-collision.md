---
id: decision-020
title: Minimal multiplayer step primitive for TASK-021 invariant #6 — no cross-player collision
date: '2026-09-12 14:14'
status: Accepted
---
## Context

TASK-021 requires proving "`ns_step` with permuted input-application order yields identical
checksums" — the netcode-critical property that applying multiple players' per-tick inputs in a
different order (as can happen when network input arrives interleaved) must not change the
resulting simulation state. `ns_step` itself is the frozen name for a future C-ABI lockstep
primitive, explicitly scoped to TASK-023 (`include/neo_snake.h`) and TASK-053 (lockstep netcode)
under milestone m-8 "multiplayer (stretch)" — neither exists yet, and `core/world.zig` is
single-player only today (no `player_count`, no per-player array).

Building the full ABI/lockstep stack now would pull all of m-8's design work forward into m-3,
far exceeding this task's scope. The user chose instead to add a minimal, internal (non-ABI, not
named `ns_step`), test-only multiplayer step primitive — scoped only enough to prove permutation
invariance — living entirely in `core/fuzz_seeds.zig`, not `core/world.zig`.

The already-frozen `docs/abi-decisions.md` freeze #1 and `docs/rng.md`'s "Food placement" point 3
specify, for real multiplayer: a single shared `xoshiro128**` stream and shared food placement,
both resolved in ascending player index order when more than one player needs a draw/placement in
the same tick. Neither document specifies what happens when two players' bodies (or a body and
another player's head) occupy the same cell — that is genuinely undecided, and `docs/canonical-
state.md`'s wire format has no field for it either.

## Decision

The new primitive (private to `core/fuzz_seeds.zig`) models exactly two players sharing board
dimensions, a single global food cell, and a single RNG stream — reusing the already-frozen
ascending-index resolution rule for both. It explicitly does **not** model cross-player body
collision: each player's move is checked only against its own body and the walls (identical to
`core/world.zig`'s single-player `advance()` collision logic), never against another player's
cells. If two players' heads land on the same cell in the same tick, both simply occupy it —
no death, no special-cased tie-break beyond food resolution.

Each tick is computed in two phases so that the permutation given to the primitive can only ever
affect phase 1 (dir-commit + move + self-collision, all per-player-local, read-only against the
current shared food value), never phase 2 (body mutation, food consumption, and the one shared RNG
draw for a replacement food, always applied in fixed ascending player-index order regardless of the
permutation). This makes the permutation-invariance property structural rather than incidental: a
future regression that made resolution order-dependent (e.g. "whichever player is visited first
in the loop eats contested food") would fail this test even though it would pass a naive "run it
once and see" check.

Cross-player body collision, and any other real PvP rule, is left entirely to whatever TASK-053/
m-8 designs when the full `ns_step` ABI is built — this primitive does not anticipate or constrain
that design.

## Consequences

`core/world.zig` is untouched by this task. The new primitive is intentionally not exposed outside
`core/fuzz_seeds.zig` and is not named `ns_step` or otherwise implied to be ABI-facing, so it
creates no expectation that TASK-023/TASK-053 must match its shape. When real multiplayer
collision semantics are designed later, they are a new decision, not a continuation of this one —
this entry documents only what invariant #6 needed, not a preview of m-8.

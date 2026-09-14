---
id: decision-034
title: Two-player core semantics -- shared status, per-player alive flag, cross-player collision, mutual kill
date: '2026-09-13 21:57'
status: Accepted
---
## Context

TASK-051 reads as "nearly free, Godot-layer only" ("Add local 2-player support to the Godot
presentation and input layers"), but `core/world.zig` had no `player_count` and no per-player
state at all before this task -- `MAX_SUPPORTED_PLAYERS` in `core/abi.zig` was hardcoded to `1`,
and `World` was a single flat struct. Godot's `world.gd` (TASK-027) already forwards `player`/
`player_count` params through every method to the GDExtension class, and `include/neo_snake.h`'s
`ns_input`/`ns_player_view`/`ns_config.player_count` are already N-player-shaped -- but nothing on
the `core/` side backs any of it for `player_count > 1`. Real two-player local play needs that
support built first.

`decision-020` (TASK-021) explicitly left cross-player collision "genuinely undecided," scoped its
own two-player primitive to `core/fuzz_seeds.zig` only, and said real PvP rules are "left entirely
to whatever TASK-053/m-8 designs" -- deliberately not constraining this decision. `reference/
snake.html` is single-player only and has no oracle behavior to match here; every choice below is a
new design, not a parity check.

## Decision

**`MAX_PLAYERS: u8 = 2`** (in `core/world.zig`, reused by `core/abi.zig`'s
`MAX_SUPPORTED_PLAYERS`) -- capped at exactly 2, not N, matching this task's actual AC ("two
locally-controlled players") and `decision-020`'s own `MULTI_PLAYERS=2` precedent. YAGNI: nothing
in this repo needs more than 2 yet.

**Shared world-level `status` (menu/playing/paused/dead) drives the overall game phase.** Pausing
pauses both players; either player's first direction input (from menu or dead) starts or restarts
the whole shared match for both -- `start()`/`reset()` stay whole-world operations, extending
`decision-015`'s existing single-player "press any direction to begin/restart" quirk to a
same-screen match's natural convention.

**Per-player `alive: bool`, not a full independent `Status` enum.** The per-player status exposed
through the ABI (`ns_player_view_get`, HUD-facing) is a single projection: `if (alive) w.status
else .dead` (`playerStatus` in `core/abi.zig`). A dead player's board keeps rendering as "dead"
even while the match continues for a survivor, without needing two parallel state machines.

**Starting position: `cy(i) = rows * (i+1) / (player_count+1)`** (integer division), spacing
`player_count` players evenly down the board. This is a strict generalization of the oracle's own
`rows/2` formula: at `player_count == 1` it reduces to `rows*1/2 == rows/2` exactly, so
single-player starting position is unchanged byte-for-byte.

**Cross-player collision, two-phase (extending `decision-020`'s phase split):**
- Phase 1 (read-only, order-independent): for each player, compute the candidate new head cell
  and check it against (a) walls/self-body, exactly as single-player already does, and (b) every
  *other* player's full pre-tick body -- with **no tail-vacate exception** granted to opponents.
  An opponent's tail cell is still occupied as far as this tick's move is concerned, since that
  opponent's own tick hasn't resolved yet. This is the simplest, most conservative reading
  available and avoids having to define a cross-player analog of the single-player tail-vacate
  rule that decision-020 never touched.
- Phase 2 (fixed ascending player-index order): mutate bodies, apply deaths, resolve eating/food
  respawn -- same ascending-index rule `decision-020` and `docs/abi-decisions.md` already require
  for the shared RNG stream and food placement.

**Head-to-head mutual kill:** if two surviving players' computed new-head cells coincide, both
die. Symmetric outcome, no arbitrary tie-break by player index -- a same-screen match where two
snakes collide head-on is expected to be a draw for both, not a coin-flip favoring one player.

**Win uses the same "win == dead" sentinel convention as single-player**, per player -- no separate
"won" state was invented.

**A dead player's body is never cleared -- a permanent corpse/obstacle**, exactly matching
single-player's existing behavior of never clearing the body on death. This is a deliberate
divergence from `fuzz_seeds.zig`'s non-canonical `MultiPlayer`/`placeFoodShared` primitive (which
skips dead players when checking occupancy) -- legitimate since `decision-020` explicitly said that
primitive's scope does not anticipate or constrain this design. Corpses remain solid obstacles for
the survivor.

**World-level `tick` increments only if at least one player is alive after the tick resolves** --
an exact generalization of single-player's existing "die()/win() return before `w.tick += 1`"
quirk; at `player_count == 1` it reduces to the original behavior exactly.

**World-level `status` becomes `.dead` only when every player is simultaneously eliminated.**

**Tick period/speed is read from player 0's score only**, not per-player -- a shared-screen match
shares one clock either way, so there is no meaningful per-player speed to derive.

**Wire format:** `canon.decode()`'s cell packing is contiguous/bump-allocator-style (every player's
cells packed back-to-back from offset 0, sized by each player's actual `body_len`), which does not
match `World`'s new fixed-per-player-offset `cells_buf` layout once `player_count > 1`.
`ns_deserialize` reconstructs a flat scratch region (reusing `players[0]`'s own backing buffer,
sized `per_player * player_count`), decodes into it, then relocates each player's decoded cells
into its real per-player buffer via `@memmove` -- safe regardless of processing order, since each
player's real destination offset can never overlap an unread portion of the source range when every
`body_len <= per_player`.

**`ns_world_init` rejects `player_count > 1` when `rows <= 8`** (`NS_ERR_INVALID_ARGUMENT`) --
guards against a board too short for two players' 3-cell starting snakes to avoid immediately
overlapping under the `cy(i)` spacing formula at small row counts.

## Consequences

`core/world.zig`, `core/abi.zig`, and `core/fuzz_seeds.zig` all changed to carry a `player_count`
dimension end to end. Every existing single-player test (Tier-A `core/build.zig test`, Tier-B
`difftest`, Tier-C `abitest`) passes unchanged -- confirming `player_count == 1` behavior is
byte-for-byte preserved under every one of the generalizations above. A new two-player test suite
in `core/world.zig` (starting-row spacing, wall-death-doesn't-stop-survivor, all-players-eliminated
stops the tick counter, opponent-body-collision-is-fatal, head-to-head mutual kill) and a new
`core/abitest.zig` conformance test (two independently-controlled players driven purely through the
C ABI) exercise the new behavior directly. `fuzz_seeds.zig`'s own private `MultiPlayer` primitive
(`decision-020`) is left untouched -- it remains a narrower, non-canonical permutation-invariance
fixture, not a rehearsal of this design, and continues to diverge from it exactly where documented
above (no dead-player occupancy skip). Any future lockstep/netcode work (TASK-053, m-8) inherits
this collision/status model as the real one, rather than re-deciding it from scratch.

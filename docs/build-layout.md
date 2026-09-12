# Zig core build layout

This is new tooling design with **no analogue in `reference/snake.html`** — same category as
`docs/rng.md`/`docs/canonical-state.md`. It exists so TASK-017, the first Zig code in this repo,
has an unambiguous target rather than improvising a build graph from `~/git/zelda3/build.zig` (a
full native game build with libc), whose scope doesn't match this project's constraints.

## Location

`core/build.zig` (plus `core/build.zig.zon` if Zig 0.16.0's package format requires a module
manifest) — scoped to the `core/` directory, not the repo root. `core/` is a standalone Zig
library with its own build/test graph; it does not build the Godot game or the reference oracle,
and the repo root has no reason to look like a Zig project. `extension/` (TASK-026) gets its own
separate SConstruct-based build wrapping the compiled `core/` artifact — the two build systems are
siblings, neither absorbing the other.

## Module layout

One `.zig` file per concern, matching the docs each implements: `core/rng.zig` (`docs/rng.md`),
`core/canon.zig` (`docs/canonical-state.md`), `core/world.zig` (the simulation mirroring
`reference/oracle/sim.mjs` — the accumulator side of `docs/architecture.md`'s fixed-timestep loop,
with the integer tick-period table of `docs/abi-decisions.md` freeze #5). `core/corpus.zig` (already
committed, TASK-014) is generated data — the list of committed `game/tests/corpus/*.jsonl` trace
paths — consumed by `core/difftest.zig` (TASK-020) to enumerate which files to replay; it is not
part of the `test` step's build graph. Each new Zig source this phase adds is exposed as its own
root module in `build.zig` so `zig build test` can run its Tier-A tests independently; there is no
single top-level `lib.zig` aggregator yet — add one only when a later task (e.g. TASK-024's
`core/abi.zig`) actually needs to import more than one of these together.

## `zig build test`

`build.zig` defines one test step per module (`b.addTest` on `rng.zig`, another on `canon.zig`, another on `world.zig`),
all registered under the same `test` step name so `zig build test` runs all of them in one
invocation. `ZIG_GLOBAL_CACHE_DIR` is already set repo-wide in the root `taskfile.yml`
(`{{.ROOT_DIR}}/.cache/zig`) — `core/build.zig` does not need its own cache-dir handling.

## `zig build difftest`

`build.zig` also defines a standalone `difftest` executable (`core/difftest.zig`), built from its
own module (importing `rng`, `canon`, `world`, and `corpus` — the same module objects the `test`
step already builds, reused rather than duplicated for Zig's per-module type identity) and wired to
a named `difftest` step (`b.step("difftest", ...)`), separate from `test` per the
`~/git/zelda3/build.zig` step-naming precedent. It replays every trace `core/corpus.zig` lists
against a fresh `core/world.zig` simulation, asserting each tick's checksum and each `docs/canonical-state.md`
full-state anchor. Hermetic: it reads only the committed `game/tests/corpus/*.jsonl` files via
`std.Io.Dir`, never shells out, and needs no `node` binary on `PATH`. On a mismatch it decodes the
already-computed failing tick's bytes and diffs them field-by-field against the last anchor at or
before it (anchors occur every 64 ticks) — it does not re-simulate from the anchor, since replaying
the same `world.zig` code from the same start can only reproduce the bytes already computed in the
single forward pass; the anchor is the only independent ground truth available between checksums.

## `task check` wiring

New `taskfiles/core.yml`, included in the root `taskfile.yml` as `core:`, with `test` and
`difftest` tasks (`dir: core`, `cmds: [zig build test]` / `[zig build difftest]`). Wired into the
top-level `check` task immediately after `oracle:verify` and before `game:import` — `core:test` and
`core:difftest` are fast and pure-Zig (no Godot/GDExtension involved yet), so they fail before the
slower Godot steps, the same ordering rationale already applied to `oracle:verify`
(`docs/corpus-format.md`). `core:difftest` runs after `core:test` since it exercises the same
`world.zig` the Tier-A suite already validated in isolation.

## No allocator, no libc

Both constraints are properties of the **library code** (`core/rng.zig`, `core/canon.zig`,
`core/world.zig`), not something `build.zig`
can mechanically assert on its own:

- **No libc**: `build.zig` must never call `.linkLibC()` for these modules, and the source files
  must never `@cImport` or otherwise pull in a libc dependency. Required so the same code can
  later target freestanding/WASM (TASK-047) without relinking.
- **No allocator**: `core/rng.zig`, `core/canon.zig`, and `core/world.zig` must never import
  `std.heap`, accept an `Allocator` parameter, or otherwise allocate — the RNG state (four `u32`
  words), the canonical-state buffer (`docs/canonical-state.md`'s fixed header plus a
  caller-supplied cell-list buffer, per `docs/abi-decisions.md`'s "reads from and writes into
  caller-supplied buffers" freeze), and the snake body (a caller-supplied cell buffer) are
  fixed-size or caller-owned. Tier-A test code may use `std.testing.allocator` only if a test
  genuinely needs a growable buffer — prefer stack arrays / caller-supplied buffers even there,
  since none of this task's fixtures actually require dynamic sizing.

Future `core/*.zig` files (TASK-018+) extend this same `build.zig` rather than inventing a second
build graph — add a new `addTest` per module, same pattern.

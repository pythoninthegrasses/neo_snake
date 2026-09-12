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
with the integer tick-period table of `docs/abi-decisions.md` freeze #5), `core/fuzz_seeds.zig`
(TASK-021's Tier-B fuzz invariants over 256 committed seeds, see below), `core/fuzzrun.zig`
(TASK-022's live fuzz-runner for `task oracle:fuzz`, see below). `core/corpus.zig` (already
committed, TASK-014) is generated data — the list of committed `game/tests/corpus/*.jsonl` trace
paths — consumed by `core/difftest.zig` (TASK-020) to enumerate which files to replay; it is not
part of the `test` step's build graph. Each new Zig source this phase adds is exposed as its own
root module in `build.zig` so `zig build test` can run its Tier-A tests independently. `core/abi.zig`
(TASK-024) is the first module that imports more than one of these together (`rng`, `canon`,
`world`) — it is the C ABI boundary layer, not a `lib.zig`-style internal aggregator, and is built
as a static library rather than a test module; see `zig build abi` below.

## `zig build test`

`build.zig` defines one test step per module (`b.addTest` on `rng.zig`, another on `canon.zig`, another on `world.zig`),
all registered under the same `test` step name so `zig build test` runs all of them in one
invocation. `ZIG_GLOBAL_CACHE_DIR` is already set repo-wide in the root `taskfile.yml`
(`{{.ROOT_DIR}}/.cache/zig`) — `core/build.zig` does not need its own cache-dir handling.

## Tier-B fuzz invariants (`core/fuzz_seeds.zig`)

`core/fuzz_seeds.zig` (TASK-021) is a fourth module in the same `test` step, built and imported the
same way `world.zig` is (`.addImport` of `rng`/`canon`/`world` into a fresh `b.createModule`, then
`b.addTest`). Unlike `core/difftest.zig`, it checks 256 committed `[4]u32` seeds (a one-time
splitmix64 codegen expansion, `docs/rng.md`'s "generated and independently re-derived, not
hand-computed" convention for test vectors) against structural invariants — body length tracks
score, no duplicate body cells, food never lands on a body cell, serialize∘deserialize is the
identity, checksum survives a round trip — rather than a recorded oracle trace, since these are
properties that must hold for any legal input sequence, not a fixed expected output. It stays
pure-Zig (no allocator, no libc), so it belongs in `test_step` alongside `rng`/`canon`/`world`, not
in the `difftest`/`corpus` executable below.

One of the six invariants (permutation-invariance of multiplayer input-application order) needs
more than one player moving in the same tick, which `core/world.zig` does not model. Rather than
build the real multiplayer ABI (`docs/abi-decisions.md`, TASK-023/TASK-053, milestone m-8) years
ahead of schedule, `core/fuzz_seeds.zig` adds a private, non-ABI, test-only two-player step
primitive scoped only to prove that property — see `backlog/decisions/decision-020` for the exact
scope (notably: no cross-player body collision) and why it lives here instead of `core/world.zig`.

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

## `zig build abi`

`build.zig` also defines a static library target (`core/abi.zig`, TASK-024): a `b.createModule`
importing `rng`, `canon`, and `world` (the same module objects `test` already builds), built via
`b.addLibrary(.{ .name = "neo_snake", .linkage = .static, .root_module = abi })` — Zig 0.16.0's
static-library API; there is no `b.addStaticLibrary`. Unlike `fuzzrun`, this is attached to the
default `install` step (`b.installArtifact`) as well as its own named `abi` step, since
`libneo_snake.a` is the actual cross-language deliverable (the GDExtension shim, TASK-025's Tier-C
conformance tests link against it), not a dev-only tool. `docs/abi-impl.md` covers what
`core/abi.zig` does that `include/neo_snake.h` and this doc don't already settle.

## `zig build fuzzrun`

`build.zig` also defines a `fuzzrun` executable (`core/fuzzrun.zig`, TASK-022), the live Zig half of
`task oracle:fuzz`. Unlike `difftest`, it takes a command-log path (docs/corpus-format.md's *input*
format) as a runtime argument rather than replaying `core/corpus.zig`'s committed list, because
`oracle:fuzz` drives it with a freshly-generated, non-committed log each time
(`reference/oracle/fuzz.mjs`) — there is nothing for `build.zig` to enumerate at graph-construction
time. Its module reuses `canon` and `world` the same way `difftest`'s does, but its executable is
only `b.addInstallArtifact`-attached to its own `fuzzrun` step (`b.step("fuzzrun", ...)`), not to the
default `install` step, so a plain `zig build`/`zig build install` does not build it — only `zig
build fuzzrun` (or `task oracle:fuzz`, which runs that first) does, leaving a stable
`zig-out/bin/fuzzrun` for `fuzz.mjs` to invoke directly, once per generated seed.

## `task check` wiring

New `taskfiles/core.yml`, included in the root `taskfile.yml` as `core:`, with `test` and
`difftest` tasks (`dir: core`, `cmds: [zig build test]` / `[zig build difftest]`). Wired into the
top-level `check` task immediately after `oracle:verify` and before `game:import` — `core:test` and
`core:difftest` are fast and pure-Zig (no Godot/GDExtension involved yet), so they fail before the
slower Godot steps, the same ordering rationale already applied to `oracle:verify`
(`docs/corpus-format.md`). `core:difftest` runs after `core:test` since it exercises the same
`world.zig` the Tier-A suite already validated in isolation.

`core:abi-header-check` (TASK-023) runs between them: `zig cc -std=c11 -c core/abi_header_check.c
-o /dev/null` against `include/neo_snake.h`, compiled to an object file only and never linked or
run. It exists because `include/neo_snake.h` predates any implementation (`core/abi.zig` is
TASK-024) — there is nothing yet to build a real test against — but the header still needs a check
that every declared type/function is genuinely usable, not just syntactically present. Compiling
without linking is what makes this possible: an unresolved `extern` reference is legal C right up
until something tries to resolve it.

`core:abi-symbols` (TASK-024) runs immediately after: `zig build abi` then `nm -g --defined-only
zig-out/lib/libneo_snake.a`, asserting every defined global symbol name matches `^ns_`. This is the
mechanical form of that task's AC #1 ("no other exported symbols") — `core/abi.zig` is the only Zig
file allowed to `export` (AC #2), and this check is what actually enforces it in `task check` rather
than relying on a one-off manual `nm` read.

## No allocator, no libc

Both constraints are properties of the **library code** (`core/rng.zig`, `core/canon.zig`,
`core/world.zig`), not something `build.zig`
can mechanically assert on its own. `core/abi.zig` (TASK-024) is deliberately not bound by either:
it's the ABI boundary layer, expected to be linked into a host (the GDExtension shim via
godot-cpp, TASK-025's C conformance harness) that already links libc, so the compiler-rt/libc
symbols `std.debug`'s panic machinery pulls in transitively are not a violation — see
`docs/abi-impl.md`.

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

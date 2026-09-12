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

## `zig build abitest`

`build.zig` also defines an `abitest` test module (`core/abitest.zig`, TASK-025): the Tier-C
conformance suite. Unlike every other module here, it never `.addImport`s `rng`/`canon`/`world`/
`corpus` — it reaches `core/abi.zig`'s implementation exclusively through `@cImport(include/
neo_snake.h)`, so its module sets `.link_libc = true` and calls `.addIncludePath(b.path("../
include"))` and `.linkLibrary(abi_lib)` (`Build.Module.linkLibrary`, not `Build.Step.Compile` —
Zig 0.16.0 puts the method on the module, not the compile step). Linking `abi_lib` supplies the
actual `ns_*` symbol implementations behind `@cImport`'s generated declarations; every ABI call in
the test file takes a `?*cimport.struct_ns_world`, the opaque type Zig 0.16.0 generates for the
header's forward-declared, never-defined `typedef struct ns_world ns_world;` — a bare `*anyopaque`
does not coerce to it, so test storage buffers are declared as `*c.ns_world` directly via
`@ptrCast`.

Five named tests, one-for-one with TASK-025's description: the ABI version handshake
(`NS_ERR_ABI_VERSION_MISMATCH` then `NS_OK`), `ns_body_copy` reporting the true required length on
a too-small buffer, every `ns_result` value reachable from at least one call path, `@sizeOf`/
`@offsetOf` on `c.ns_canon_header`/`c.ns_player_view` matching `docs/canonical-state.md`'s byte
layout exactly, and a committed `game/tests/corpus/*.jsonl` trace replaying to its committed
checksum using only the C API. The corpus-replay test bootstraps into the trace's tick-0 state via
`ns_deserialize` of that tick's `"s"` full-state anchor, rather than `ns_world_init` followed by a
queued direction: `ns_world_init` always starts a world in `.menu` (decision-015's menu-to-playing
transition needs a queued direction to leave it), while every committed corpus trace was recorded
from a world that started directly in `.playing` (`regen_corpus.mjs`'s `initialState()`, matching
`core/difftest.zig`'s own `world_mod.initWorld(..., .playing)` bypass of the same transition).
`ns_deserialize` is a real ABI entry point that overwrites all world state including `status`, so
this reaches the same starting point without reimplementing any reset/RNG logic inside the test
file. `ns_checksum(bytes, len, ...)` takes the *whole* already-encoded record (header + player
records + the trailer `ns_serialize` just wrote) — it hashes only the prefix up to but not
including the trailer's own bytes, so callers must pass the full serialized length, not a
pre-trimmed one.

`tools/validate_abi_test_purity.py` is the mechanical guard behind the "exclusively through
`@cImport`" rule: it greps `core/abitest.zig` for every `@import("...")` argument and fails if
anything besides `"std"` appears. Without it, Tier-C could silently degrade into a second copy of
Tier-A by picking up a stray `@import("world")` or similar.

## `game/tests/test_corpus_replay.gd` (Tier-D)

TASK-028's Tier-D pass, a GDScript gdUnit4 suite driving the whole corpus through
`SimulationWorld -> NeoSnakeWorld -> the C ABI -> core/world.zig` — the fourth independent
computation of the same per-tick checksum (node oracle, Zig-internal Tier-B, Zig-via-C-ABI Tier-C,
and now GDScript-via-GDExtension Tier-D). It mirrors Tier-C's own algorithm one layer up rather
than inventing a new one: for each trace, `SimulationWorld.deserialize()` jumps straight to tick
0's committed `"s"` anchor (every trace was recorded already `.playing`, decision-015), then every
subsequent line's `"in"` array becomes a `step()` call, with the resulting `serialize()` output
checked against that tick's `"c"` checksum and, where present, its `"s"` full-state anchor.

Because `NeoSnakeWorld.checksum()` bit-reinterprets the ABI's `u64` into a (possibly negative)
signed `int64` (`extension/src/neo_snake_world.cpp`), while a corpus trace's `"c"` field is a
decimal string specifically because such values can exceed GDScript's safe integer range, the test
file never compares the raw integers directly — `_u64_hi_lo()`/`_parse_decimal_hi_lo()` split both
sides into 32-bit halves via well-defined bitwise ops and compare those, so nothing depends on how
GDScript handles 64-bit overflow.

One committed trace, `win-full-board.jsonl` (a deliberately tiny `cols=3` board), is excluded by
name: `ns_world_init` unconditionally calls `reset()`, whose fixed snake placement needs `cols>8`,
so the C ABI has no way to allocate a board that small in the first place — see
`backlog/decisions/decision-021` for the full analysis. A second test asserts `NeoSnakeWorld.init()`
still rejects that config, so an ABI change that ever lifts this restriction fails the guard loudly
instead of leaving the exclusion stale.

`game/tests/corpus/` (not `reference/oracle/corpus/`) is what Tier-D reads, specifically so it
resolves via `res://tests/corpus/` (`docs/corpus-format.md`); no `taskfiles/game.yml` change was
needed to wire this in; `game:test`'s `-a res://tests` already globs the whole directory.

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

`core:abitest` (TASK-025) runs immediately after `core:abi-symbols` and before `core:difftest`: it
depends on `core:abitest-purity` (`tools/validate_abi_test_purity.py`, run first so a purity
violation is reported before spending time on a `zig build`), then runs `zig build abitest` to
build and run the five named Tier-C conformance tests against the same `libneo_snake.a`
`core:abi-symbols` just verified.

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

## `extension/SConstruct` (TASK-026)

`extension/` is the GDExtension shim's own SCons build, a sibling to `core/build.zig` (see
"Location" above), not folded into it. It `SConscript`s into `third_party/godot-cpp/SConstruct`,
exporting `{"api_version": "4.7"}` — the version `game/project.godot`'s `config/features` already
pins — and gets back godot-cpp's fully-configured `env` (platform detection, `env["suffix"]`,
`env["SHLIBSUFFIX"]`, etc.) rather than reimplementing any of that.

`rng`/`canon`/`world`/`abi` in `core/build.zig` all carry `.pic = true` (added alongside this task):
`core/abi.zig`'s static library gets linked into a shared object here, and non-PIC relocations in a
static archive fail at the final `ld -shared` step (`relocation R_X86_64_32S ... can not be used
when making a shared object`) — PIC has to be set on every module whose code actually ends up in
`libneo_snake.a`, not just on `abi` itself, since Zig's module system compiles each imported module
with its own settings.

`core/zig-out/lib/libneo_snake.a` is linked via `env.File("../core/zig-out/lib/libneo_snake.a")`
appended to `LIBS`, not a bare `-lneo_snake -L...` pair — an `env.File(...)` is a real SCons node, so
`env.Depends(library, core_lib)` makes a rebuilt core library actually trigger a relink; a bare
linker flag carries no such dependency edge and SCons would consider the shim up to date even after
`libneo_snake.a` changed underneath it.

Two Linux-specific build-environment workarounds, both scoped to `extension/`, neither touching
`third_party/godot-cpp` itself:

- **`ARCOM`/`TEMPFILE`**: godot-cpp's own generated-bindings object count (~2000 files under
  `third_party/godot-cpp/gen/`) overflows this system's `ARG_MAX` for a literal `ar` command line
  ("Argument list too long"). godot-cpp's own `tools/web.py` hits the identical wall for its
  wasm/emscripten target and works around it with `env["ARCOM_POSIX"] = env["ARCOM"]...` followed by
  `env["ARCOM"] = "${TEMPFILE(ARCOM_POSIX)}"` (SCons' response-file mechanism) — `extension/SConstruct`
  applies the same two-line pair to the Linux `env` it gets back. Both lines are required: setting
  only the second (`TEMPFILE(ARCOM_POSIX)`) without first defining `ARCOM_POSIX` substitutes an
  undefined variable, silently producing a no-op archive command with no error and no visible `ar`
  invocation — the failure only surfaces one step later, as `ranlib: ... No such file`.
- **`extension/custom.py`**: godot-cpp's Linux `use_static_cpp` option (default `True`) appends
  `-static-libgcc -static-libstdc++`, which requires a static `libstdc++.a` — not installed by this
  repo's base toolchain on every dev machine (only the shared `libstdc++.so` ships by default),
  failing with `cannot find -lstdc++`. `third_party/godot-cpp/SConstruct` already supports a
  `custom.py` options file (`customs = ["custom.py"]`) for exactly this kind of local override, but
  `SConscript()`-included scripts run with Python's cwd changed to their own directory — a bare
  `"custom.py"` there resolves inside `third_party/godot-cpp/`, not `extension/`. `extension/
  SConstruct` instead passes `customs = [File("custom.py").srcnode().abspath]` through the `exports`
  dict (godot-cpp's own `customs += Import("customs")` hook), so `extension/custom.py`'s
  `use_static_cpp = False` default applies regardless of that cwd shift — still overridable on the
  command line (`scons -C extension use_static_cpp=yes`) since `Variables(customs, ARGUMENTS)` lets
  `ARGUMENTS` win.

Output naming: `env.SharedLibrary("../game/bin/libneo_snake{}{}".format(env["suffix"],
env["SHLIBSUFFIX"]), ...)`, matching `third_party/godot-cpp/test/SConstruct`'s own convention.
`env["suffix"]` is entirely godot-cpp's own computation (`tools/godotcpp.py`) — platform, target,
arch, and conditionally `.nothreads` when `threads=no` — so `scons -C extension threads=no` produces
`game/bin/libneo_snake.linux.template_debug.x86_64.nothreads.so` with no extra code here; `game/bin/`
is where `game/bin/neo_snake.gdextension` (TASK-027) will point its per-platform `[libraries]`
entries.

`extension/src/register_types.{hpp,cpp}` mirrors `third_party/godot-cpp/test/src/register_types.*`
exactly (the `GDExtensionBool GDE_EXPORT neo_snake_library_init(...)` entry point, `GDREGISTER_CLASS`
in `initialize_neo_snake_module`). `extension/src/neo_snake_world.{hpp,cpp}` is the actual shim: one
`NeoSnakeWorld` method per `include/neo_snake.h` `ns_*` function, no simulation logic reimplemented.
Two details worth calling out:

- **`BIND_CONSTANT`, not `BIND_ENUM_CONSTANT`**: `include/neo_snake.h`'s result/status/dir/event
  codes are anonymous C enums (`enum { NS_OK = 0, ... };`). `BIND_ENUM_CONSTANT` calls a
  `godot::GetTypeInfo<T>`-dependent template to look up the enum's registered name, which only
  resolves for a properly `VARIANT_ENUM_CAST`-registered Variant enum type — an anonymous C enum has
  no such specialization and fails with `incomplete type 'godot::GetTypeInfo<<unnamed enum>, void>'`.
  `BIND_CONSTANT` calls `ClassDB::bind_integer_constant` directly, with no `GetTypeInfo` involved, and
  works for any integer-convertible constant regardless of its C++ enum type.
- **Manual `ns_world` alignment**: `NeoSnakeWorld` owns a `std::vector<uint8_t> storage_` sized
  `ns_world_size(config) + ns_world_align() - 1`, then carves out an `ns_world_align()`-aligned
  pointer by hand (`init()` in `neo_snake_world.cpp`) — `std::vector`'s own default allocation
  alignment is not guaranteed to satisfy whatever `ns_world_align()` reports.

### `task check` wiring

New `taskfiles/extension.yml`, included in the root `taskfile.yml` as `extension:`, with one
`build` task (`dir: extension`, `cmds: [{task: :core:abi-symbols}, scons]`) — the leading-colon
`:core:abi-symbols` reference is required because Task resolves a bare `core:abi-symbols` from
*inside* an included taskfile relative to that file's own namespace (`extension:core:abi-symbols`,
which does not exist), not to the root; a leading colon anchors the reference to the root Taskfile
instead. `extension:build` runs immediately after `core:difftest` and before `game:import` in the
top-level `check` task, so `core/zig-out/lib/libneo_snake.a` is freshly rebuilt (via the
`:core:abi-symbols` call) before the shim links against it.

## `game/bin/neo_snake.gdextension` and `game/simulation/world.gd` (TASK-027)

`game/simulation/world.gd` (`class_name SimulationWorld`) is the sole `.gd` file in the repo
allowed to reference the `NeoSnakeWorld` class — every other script goes through it instead. Each
of its methods forwards to exactly one `NeoSnakeWorld` method (same one-call-per-method rule
`extension/src/neo_snake_world.cpp` itself follows relative to `include/neo_snake.h`), so no
simulation logic is duplicated at the GDScript layer either. `game/tests/test_gdextension_present.gd`
is a deliberate, narrow exception: `ClassDB.class_exists("NeoSnakeWorld")` names the class as a
string to verify the extension actually registered it (its own AC), which is a different thing
from *using* `NeoSnakeWorld` as a type — it doesn't instantiate it or hold a reference to it, so it
doesn't defeat the sole-referencer rule the way a second `NeoSnakeWorld.new()` call elsewhere would.
That test exists specifically because a silently-unloaded GDExtension would otherwise leave
`SimulationWorld`'s own `NeoSnakeWorld.new()` call failing (or every dependent test skipping) with
no test pinpointing the actual cause.

`game/bin/neo_snake.gdextension` is committed; the platform binaries it points at
(`game/bin/libneo_snake.*`) stay gitignored (`*.so` and friends), rebuilt locally by
`extension:build` or fetched as a release asset. Its `[libraries]` section currently lists:

- `linux.debug.x86_64` — the only platform actually built and verified so far (TASK-026).
- `macos.debug` / `macos.release` — no binary yet, but TASK-043 already writes to these two keys
  as a `libneo_snake.macos.<target>.framework` bundle (not an arch-suffixed path — a fat/universal
  framework, matching godot-cpp's own macOS convention), so pre-declaring them now means TASK-043
  only has to add the bundle, not also edit this manifest.

Windows and web keys are deliberately left out: TASK-046 (Windows) and TASK-048 (the real web
build) each add their own keys when they land, rather than this task guessing at conventions
neither has established yet. `compatibility_minimum` is pinned to `"4.7"`, matching
`game/project.godot`'s own `config/features` pin, not godot-cpp's own lower `test/` default.

## `tools/validate_simulation_boundary.py` (TASK-029)

Mirrors azure-dreams' `validate_simulation_boundary.py` with the failure direction flipped: that
script bans engine dependencies *inside* a GDScript-native simulation directory, whereas here the
real simulation lives in `core/*.zig`, reached only through the GDExtension, so this scans every
`.gd` file *outside* `game/simulation/` instead. It fails on three things: a `NeoSnakeWorld`
reference (the sole-referencer rule `game/simulation/world.gd`'s header already documents,
TASK-027); a call to one of reference/snake.html's own internal simulation verb names (`advance`,
`place_food`/`placeFood`, `tick_ms`/`tickMs`, `speed_mul`/`speedMul`) — `world.gd`'s actual public
wrapper API (`init`, `reset`, `queue_dir`, `step`, `pump`, `player_view_get`, `body_copy`) is
deliberately not on this list, since that's the sanctioned way the rest of the game talks to the
sim; and global RNG usage (`randomize`/`randi`/`randf`/`seed`/etc.), since the sim has its own
seeded RNG (`core/rng.zig`) and nothing outside it should reach for the engine's instead.
`game/tests/test_gdextension_present.gd`'s `ClassDB.class_exists("NeoSnakeWorld")` call (see above)
is allowlisted by exact pattern, since it names the class without depending on its API.
`game/addons/` (vendored gdUnit4, whose own fuzzers legitimately call `randi`/`seed` internally) and
generated directories (`.godot/`, `reports/`) are excluded outright — they aren't this repo's code.

The second half of the script is a separate, non-regex check: it parses `neo_snake.gdextension` via
`configparser` (the file is INI-formatted) and walks `game/bin/` for actual platform binary
artifacts (`.so`/`.dylib`/`.dll` files, `.framework` directories), asserting each one is referenced
by some `[libraries]` key. This is binary-driven rather than key-driven deliberately: TASK-027 already
pre-declares `macos.debug`/`macos.release` keys with no binary behind them yet (see above), so a
key-driven "every declared key needs a binary on disk" check would permanently fail on any
single-platform dev machine. Binary-driven instead catches the actual failure this task cares about
— a platform key silently dropped from the file while its binary is still sitting in `game/bin/`,
which nothing else in the suite would otherwise notice.

Wired in as `game:boundary-check` (`taskfiles/game.yml`), placed in the top-level `check` task
immediately after `extension:build` and before `game:import` — the same "cheap static check before
a slower Godot step" ordering already used for `core:abitest-purity`, and it needs `extension:build`
to have just run so the orphaned-binary check has a real artifact to check against.

## `game/content/{tuning,palette,modes}.json` + `game/content/loader.gd` (TASK-030)

Per [[decision-010]] (`backlog/decisions/decision-010 - Tuning-constants-moved-to-content-tuning.json.md`),
every gameplay-feel/presentation constant `reference/snake.html` hardcodes in its IIFE — particle
counts/drag/lifetime, flash decay and alpha factors, food-pulse timing, render geometry fractions
(corner radii, eye offsets, shadow-blur factors), the swipe-recognition threshold, and per-mode best
scores — moves into three versioned JSON files instead of GDScript source, so tuning changes are
reviewable without touching code. This is deliberately **not** the same as the frozen ABI constants
in `core/world.zig` (`COLS`/`ROWS`/`BASE_MS`/`MIN_MS`/`TICK_PERIOD_US`): those are pinned by
[abi-decisions.md](abi-decisions.md) freeze #5 and must never live in a designer-editable file, so
none of them appear in `game/content/`.

Two fields specifically satisfy TASK-030 AC#3's traceability requirement:

- `tuning.json`'s `input.swipe_threshold_cell_fraction` replaces the oracle's fixed `24`-CSS-pixel
  swipe threshold (`reference/snake.html:613`) with a fraction of the board's current cell size, per
  [[decision-011]] (`backlog/decisions/decision-011 - Board-scaled-swipe-threshold.md`) — the same
  swipe reads as "about half a cell" on a phone or a tablet instead of "exactly 24 device pixels."
- `tuning.json`'s `scoring.best_score_defaults` (one entry per mode id declared in `modes.json`)
  is the seed data for [[decision-009]]'s per-mode persisted best score
  (`backlog/decisions/decision-009 - Per-mode-best-score-and-persisted-mode.md`) — the oracle
  persists exactly one `localStorage["snake.best"]` shared across modes; the Godot port persists one
  best score per mode instead, and this is where each mode's zero-valued starting point lives before
  any save file exists.

`game/content/palette.json` carries only colors (the `:root` CSS custom properties plus the
canvas-only hex/RGB values `render()` uses that never had a CSS variable — checkerboard tile,
food/snake/eye/particle/flash colors); `game/content/tuning.json` carries every other magic number.
`game/content/modes.json` carries the mode list itself (`wall`/`wrap`, matching the oracle's
`<select id="mode">` options) plus which mode is the bootstrap default.

`game/content/loader.gd` (`class_name ContentLoader`) loads and schema-validates each file:
`load_tuning()` / `load_palette()` / `load_modes()` each return `{ok, error, data}`; `load_all()`
additionally cross-checks that `tuning.json`'s `scoring.best_score_defaults` has exactly one entry
per mode id in `modes.json` — neither a stale id nor a missing one. Validation walks a small schema
dictionary (nested dict → recurse, `"number"` → accept `TYPE_INT`/`TYPE_FLOAT` since
`JSON.parse_string` always decodes numbers as `TYPE_FLOAT`, `["array_of", <schema>]` → every array
element must match, otherwise an exact `typeof()` match) rather than hand-writing one `if` per
field, so every malformed-input case (parse error, missing key, wrong type, mismatched mode ids)
reports a specific, file-and-field-qualified error string instead of a generic failure —
`game/tests/test_content_loader.gd` exercises each of these against temp files under `user://`.
`loader.gd` never references `NeoSnakeWorld`, a sim-verb name, or global RNG, so it passes
`game:boundary-check` (TASK-029) the same as any other non-simulation script.

## `game/simulation/tick_driver.gd` (TASK-031)

`TickDriver.advance_frame(world, raw_frame_ms, running, gate)` is the only place a per-frame `dt`
crosses from Godot's render loop into `SimulationWorld.pump()` (`ns_pump`, `core/world.zig`'s own
accumulator). It is deliberately a plain `RefCounted`, not a `Node`: not `_physics_process` (a
variable step re-read after every tick, an engine-owned catch-up cap, and it would force the sim
onto the scene tree for no reason), and not a `Timer` (fires on a fixed interval with no
accumulator, so it discards whatever time is left over instead of carrying it — a long hitch would
silently lose ticks the oracle's own `S.acc` accumulator would still run).

`advance_frame` never reads a clock (no `OS.get_ticks_usec`/`Time.*`) and never inspects `world`
state itself — `raw_frame_ms`, `running`, and `gate` are all caller-supplied, so the function is
pure forwarding onto `SimulationWorld.pump`, with no catch-up or clamping logic of its own layered
on top (that all already lives in `ns_pump`). `running` and `gate` are two independent
caller-supplied preconditions rather than one combined flag: `running` stands for whether the
app/scene tree is currently processing frames at all (false while engine-paused, e.g. a modal
settings/quit overlay a future task adds), and `gate` for whether the game's own state currently
permits ticking (e.g. world status is playing). Either being false discards that frame's `dt`
outright rather than banking it for a later call — matching `ns_pump`'s own "not playing" no-op
instead of quietly accumulating backlog time behind the caller's back. This has no analogue in
`reference/snake.html`: the oracle's own `frame()` loop reads `performance.now()` and the DOM's
`blur` event directly, since it has no ABI boundary to keep pure across.

`game/tests/test_tick_driver.gd` feeds a synthetic per-frame sequence — including a 200ms hitch well
past `ns_pump`'s 64ms `MAX_DT_US` clamp, and two frames gated closed — against a fresh world (score
0, so `TICK_PERIOD_US[0]` = 130000us) and asserts the exact resulting tick count at every step. The
numbers are chosen to cross-check directly against `core/world.zig`'s own `"pump clamps to
MAX_STEPS per call and carries the remainder over"` test, so the hitch's clamped-to-64000us
contribution and the 62000us carried remainder both match an already-verified worked example rather
than a number invented for this test alone. A separate test statically greps the source for clock
reads, operationalizing AC#1 rather than leaving it to code review alone.

## `game/presentation/board/{board_geometry,fx_state,board_view}.gd` (TASK-032)

`BoardView` (`Control`) renders one player's board in a single `_draw()` call, statement order
matching `reference/snake.html`'s `render()` back-to-front layering exactly (`snake.html:433-531`):
background, checkerboard, grid, food, snake body (tail-first), eyes, particles, flash overlay, pause
vignette. `BoardGeometry.DRAW_LAYER_ORDER` names that same sequence as data, and
`game/tests/test_board_geometry.gd` pins it directly, so the ordering invariant is an enforced check
rather than something only code review protects.

All geometry/color math (segment weight/pad/color, food pulse/pad, corner radius, eye offsets/radius,
grid line offsets, the checkerboard `Image` bake, and `docs/canonical-state.md`'s 44-byte canonical
header decode) lives in `BoardGeometry`, a pure static `RefCounted` with no `Node`/viewport
dependency — every number is pinned by a gdUnit4 test without instantiating a scene. `BoardView`
itself is the only file that issues actual `draw_*()` calls. Neither `SimulationWorld.player_view_get`
nor `.body_copy` expose cols/rows/food position, so `BoardGeometry.decode_canon_header` reads them
directly out of `world.serialize()`'s canonical bytes — a documented wire format, not a workaround.

Grid lines use a float `Color` (alpha assigned directly, not `Color8`), matching AC#3's requirement
that `0.019`-scale alpha values not round through 8-bit quantization. The checkerboard bake can't
avoid that same quantization — `Image.FORMAT_RGBA8` is intrinsic to AC#2's single-baked-texture
requirement — so per [[decision-023]]
(`backlog/decisions/decision-023 - Checkerboard-alpha-quantized-by-8-bit-baked-texture.md`) the
resulting ~3% alpha deviation is accepted as a cost of that approach, not a latent bug.

`FxState` mirrors the oracle's `burst()`/`decayFx()` (`snake.html:411-430`) as cosmetic, render-only
particle/flash state that never feeds back into `SimulationWorld` or `docs/canonical-state.md`.
Its randomness comes from a small hand-rolled xorshift32 PRNG rather than Godot's
`RandomNumberGenerator`: `tools/validate_simulation_boundary.py`'s `game:boundary-check` (TASK-029)
bans `randi`/`randf`/`randi_range`/`randf_range`/`seed`/`randomize` anywhere outside
`game/simulation/`, and that regex matches those names called on any receiver, not just Godot's
global RNG — so a local `RandomNumberGenerator` instance still trips the gate. Rather than relaxing
that check, `FxState` avoids the banned identifiers entirely.

Godot's 2D `CanvasItem` API has no equivalent to the oracle's `ctx.shadowBlur` glow on food/snake-head
and no single-call filled-rounded-rect primitive; per
[[decision-022]] (`backlog/decisions/decision-022 - No-canvas-shadow-glow-blur-in-board_view.gd.md`),
`board_view.gd` fills with flat colors (same shape/color/layer order, no glow) via `StyleBoxFlat` +
`draw_style_box` for rounded rects, judged disproportionate scope for a data-driven renderer and not
required by any of this task's Acceptance Criteria.

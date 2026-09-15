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

Four of those layers — background, checkerboard, grid, food — describe the shared board, not a
player, and the first three are opaque. `BoardView.draws_shared_board` (default `true`) gates them
so that when two `BoardView`s are stacked for local 2-player (TASK-051's `board_view_p2`), only the
bottom-most one paints them; the upper view would otherwise repaint an opaque board over the lower
player's snake every frame and make that player invisible (TASK-055). Snake, eyes, particles, flash
and pause vignette stay per-view — each is per-player state or translucent. `DRAW_LAYER_ORDER` is
unchanged: the bottom view still draws the full sequence.

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

## `game/platform/{input_router,input_defaults,swipe_gesture,analog_latch}.gd` (TASK-033)

Four paths converge on `InputRouter._unhandled_input` (`_unhandled_input`, not `_input`, so a focused
UI control gets first refusal of the event — AC#2), mirroring the oracle's single-choke-point
`queueDir` (`snake.html:569-576`, `docs/architecture.md`'s "Input" section): keyboard actions, touch
swipe, and analog stick motion. `InputRouter` emits `direction_queued`/`pause_requested`/
`restart_requested` signals rather than calling `SimulationWorld` itself — the "no instant 180"
reversal-legality check already lives in `core/world.zig`'s `queue_dir`, so this stays a pure
translation layer with no game-state knowledge of its own, the same thin-forwarding role
`game/simulation/tick_driver.gd` plays for the tick loop. No scene wires it up yet, matching every
other platform/presentation script landed so far.

`InputDefaults` is the single source of truth for action names and their expected physical keycodes
(mirroring the oracle's `KEY` table, `snake.html:578-582`: arrows and WASD both map to the same four
directions, Space pauses/starts, R restarts). `project.godot`'s `[input]` section declares the actual
`InputMap` (AC#1 — bindings live in a diffable config file, not runtime code), and
`game/tests/test_input_defaults.gd` asserts the loaded `InputMap` matches `InputDefaults` exactly in
both directions, so the two can't silently drift apart.

The oracle's Space key does two jobs — pause/resume, and start/restart from the menu or dead screen.
This port splits them: Space is pause-only (`GameScreen._on_pause_requested` returns unless the
shared status is `PLAYING`), and Enter/Kp Enter select, confirming whichever overlay control has
focus through Godot's built-in `ui_accept`. Because `ui_accept`'s engine default also includes
Space, `project.godot` declares its own `ui_accept` (Enter + Kp Enter) to replace it — without that
override Space would still activate the focused button. See
[[decision-038]] (`backlog/decisions/decision-038 - Space-is-pause-only-Enter-is-select.md`).

`SwipeGesture` is a pure `RefCounted` port of the oracle's `touchstart`/`touchmove`/`touchend`
handling (`snake.html:603-618`) with no `Node` dependency (AC#4) — same "pure static/no viewport"
posture as `BoardGeometry`. The oracle's fixed `24` CSS-pixel drag threshold becomes board-scaled per
[[decision-011]] (`backlog/decisions/decision-011 - Board-scaled-swipe-threshold.md`): `cell_px *`
`content/tuning.json`'s already-wired `input.swipe_threshold_cell_fraction` (`0.5`), floored at the
oracle's original `24` so the gesture never reads as more sensitive than the oracle on a low-density
screen. This reuses the cell-fraction field decision-011 already established rather than introducing
a second, board-pixel-relative formula.

`AnalogLatch` implements a 0.55-fire/0.35-release hysteresis per stick axis (AC#3): once an axis
latches past `0.55`, it must fall back under `0.35` before a fresh push past `0.55` can fire again, so
jitter sitting anywhere between the two thresholds can never double-fire. `reference/snake.html` has
no gamepad support at all — this is a wholly new capability, not a port of existing oracle behavior,
so per DoD#2 there is nothing to record as a *deviation*; the one genuine oracle-behavior deviation
this task introduces (the swipe threshold) is already covered by decision-011 above.

## `game/platform/save_store.gd` (TASK-034)

`SaveStore` takes its base directory as a constructor parameter (AC#1) rather than hardcoding
`user://`, so tests point it at a throwaway directory and never touch real player save data. It
replaces the oracle's single `localStorage["snake.best"]` scalar (`snake.html:294`, `389`) with a
versioned on-disk shape per [[decision-009]]
(`backlog/decisions/decision-009 - Per-mode-best-score-and-persisted-mode.md`): a v2 document holding
`best_scores` per mode and the last-selected mode, rather than one shared scalar. `SCHEMA_VERSION`
plus a `_migrations` dict of `Callable`s (built in `_init()`, since GDScript can't hold an unbound
instance-method reference in a `const`) carries a v1 `{"version": 1, "best": <int>}` document forward
to v2, assigning the migrated scalar to the `"wall"` mode (the oracle's only mode) and leaving other
modes at `content/tuning.json`'s `scoring.best_score_defaults`. Those defaults, and `"wall"` as
`content/modes.json`'s default mode, are hardcoded rather than loaded via `ContentLoader` at runtime,
so a missing or malformed content file can never break a save/load — this stays a self-contained
file-I/O primitive. JSON reads follow `content/loader.gd`'s established `JSON.new()` + `.parse()`
convention, and — since JSON numbers always decode as `TYPE_FLOAT` in Godot, the same caveat
`loader.gd` documents on its schema — `_normalize_v2` casts `best_scores` values back to `int` on the
way out so callers never re-cast.

Writes rotate `tmp → bak → dst` (AC#3) rather than overwriting `dst` directly: the new document is
written to `save.json.tmp`, any existing `save.json` is renamed to `save.json.bak`, then `save.json.tmp`
is promoted to `save.json`. `load_or_default` falls back to `save.json.bak` if `save.json` is missing or
fails to parse, so a crash between those two renames still recovers the last-known-good save;
`game/tests/test_save_store.gd` fabricates that exact interrupted-write filesystem state directly via
`FileAccess`/`DirAccess` (bypassing `SaveStore`'s own API) to exercise the fallback for real, plus a
normal two-writes-in-a-row test confirming the rotation itself. Per [[decision-013]]
(`backlog/decisions/decision-013 - Debounced-disk-writes.md`), deciding *when* to call `save()` (e.g.
debounced at game-over/pause/background) is a caller concern, not this class's — `SaveStore` only
implements *how* a write lands safely on disk.

`parse_legacy_best` (AC#4) mirrors the oracle's `Number(x) || 0` fallback (`snake.html:294`) as a pure,
directly-testable function with no `JavaScriptBridge` dependency. The actual web-import path,
`import_web_legacy_best`, is a thin wrapper gated behind `OS.has_feature("web")` that calls
`JavaScriptBridge.eval` and folds the result through the same v1→v2 migration — untestable in headless
native Godot, so it carries a doc comment describing the manual web-export verification procedure
instead, per AC#4's "or documented manual check" allowance.

## `game/platform/app_lifecycle.gd` (TASK-035)

`AppLifecycle` ports the oracle's window-`blur` auto-pause (`snake.html:620`) onto Godot's
`_notification()` MainLoop callback. Which of `NOTIFICATION_APPLICATION_FOCUS_OUT` /
`NOTIFICATION_WM_WINDOW_FOCUS_OUT` actually fires is unconfirmed across desktop/mobile/web at design
time (AC#1), so both — and their `_IN` counterparts — are listened for defensively. Per
[[decision-012]] (`backlog/decisions/decision-012 - Focus-out-pause-covering-Android.md`), this also
covers Android backgrounding, which has no `blur`-equivalent guarantee the way desktop browsers do.

A `_focused` flag ensures `focus_lost` emits at most once per genuine focus transition (AC#2), even
when both `_OUT` constants fire for the same underlying event; the `_IN` notifications exist solely to
reset that flag for the next transition. There is no focus-regained signal — mirroring the oracle
exactly, since `snake.html` has no resume-on-focus behavior to port, only pause-on-blur.
`game_screen.gd` (TASK-036) is `focus_lost`'s first consumer, pausing the run app-side the same way
`snake.html:620`'s `blur` handler does.

`game/tests/test_app_lifecycle.gd` calls `_notification()` directly with Godot's own constants (AC#3) —
the same values the engine delivers to a live node — to verify the dedup logic on desktop without a
real window-manager focus change. Android/web coverage isn't automatable (no harness can simulate OS-
level backgrounding), consistent with decision-012's own note that correctness there relies on
manual/platform testing rather than an automated test.

## `game/presentation/screens/{game_screen_state,hud,overlay_panel,game_screen}.gd` (TASK-036)

`game_screen_state.gd` (`GameScreenState`, pure `RefCounted`) ports `showOverlay()`'s per-status
content (menu's static markup at `snake.html:227-241`, `togglePause()`'s call at `snake.html:562`,
`die()`'s and `win()`'s at `snake.html:402`/`407`) with no `Node`/`SimulationWorld` dependency, so
`game/tests/test_game_screen_state.gd` exercises every transition without a live scene.
`screen_for(sim_status, app_paused)` derives one of `SCREEN_MENU`/`SCREEN_PLAYING`/`SCREEN_PAUSED`/
`SCREEN_DEAD` — `app_paused` is layered in because the live world's own status never reaches
`NS_STATUS_PAUSED` (see below). `overlay_content()` returns plain-text title/sub/button strings (no
`<br>`/`<b>`), matching the task's own instruction to use real Control nodes instead of
`showOverlay()`'s `innerHTML`.

`hud.gd` (`Hud extends Control`) and `overlay_panel.gd` (`OverlayPanel extends Control`) are built
entirely in code in `_ready()`, following `board_view.gd`'s only precedent for a hand-authored node
tree (no `.tscn` exists anywhere in this repo). `OverlayPanel` is a single reused Control
reconfigured per screen via `configure()`, mirroring the oracle's single `#overlay` div that
`showOverlay()`/`hideOverlay()` reconfigure and toggle rather than swap. Per [[decision-024]], its
mode `<select>`-equivalent (`OptionButton`) is shown only for `SCREEN_MENU`, even though the
oracle's own `<select>` is structurally visible for every overlay state.

The menu screen is where the player count is chosen. `overlay_content(SCREEN_MENU, …)` sets
`show_player_select` and a `controls` legend (`GameScreenState.CONTROLS_LEGEND` — "Player 1: Arrow
Keys" / "Player 2: WASD", naming decision-035's keyboard split) and leaves `button_label` empty;
`OverlayPanel` then shows its "1 Player Game" / "2 Player Game" buttons instead of the single action
button and emits `player_count_selected(count)`. Every other screen is confirming one thing —
Resume, Play Again — so it keeps the single action button and hides these. The dead screen adds one
more (`show_return_to_title`): a "Return to Title" button below Play Again, which re-runs
`world.init()` — the only way back to `.menu`, since `world.reset()` restarts a run and no ABI call
moves a live world backwards. `GameScreen._player_count`
feeds `world.init` and gates `board_view_p2`, the HUD's P2 row, and player-1 direction input, because
`core/abi.zig` rejects any call naming a player the world doesn't have. The count is fixed for the
run; it can only change back on the menu.

**Start headings (`game/simulation/start_directions.gd`).** Core spawns every snake facing right,
pinned byte-for-byte against `reference/oracle/sim.mjs` by the committed corpus, so randomizing the
heading is a Godot-layer choice applied on top: `_start_or_restart()` queues `DIR_RIGHT` first —
that call is what flips the world out of menu/dead, and core's `queueDir` runs `start()` → `reset()`
which re-forces `.right`, clobbering anything queued alongside it — then queues the drawn headings
against the now-playing world, where they survive and commit on the first tick.
`StartDirections.LEGAL` omits `DIR_LEFT`: `reset()` lays the body out horizontally head-first at
`(8, cy), (7, cy), (6, cy)`, so a left-facing snake would move onto its own neck, which is precisely
what `queueDir`'s 180 guard rejects. A 1-player game draws uniformly from the other three; a
2-player game additionally forbids player 0 heading down while player 1 heads up, the only pairing
that points them at each other given decision-034's shared spawn column. Every path that puts a snake back on the fixed spawn rerolls through one
`GameScreen._apply_start_directions()` — `_start_or_restart()`'s init/reset *and* R's mid-run
`world.reset()`, which otherwise silently kept the sim's own right-facing spawn. That helper does
not stop at `queue_dir`: queuing alone only sets `next_dir`, so the heading would not commit until
the first pumped tick and the snake would render facing east for a frame before pivoting. It steps
the sim `SNAKE_LEN - 1` times right there, before anything is drawn, which both commits the heading
and walks every segment off the east-west spawn layout, so the first frame shows a straight snake
already pointing the right way. `ns_step` is used rather than `pump` because it advances exactly one
tick and consumes no accumulator time. Events from those steps are drained and discarded: a pellet
can sit in the stepped-over cells, and firing an eat cue for a bite the player never saw would be
worse than the quiet point it scores. One consequence worth knowing: a run begins on a randomized
heading, so the player's first input is constrained relative to it by the usual 180 guard.
`StartDirections` draws from its own seeded `RandomNumberGenerator`, not the engine's global RNG, so
a test can pin the sequence; it is independent of the simulation's seeded stream (`core/rng.zig`,
`docs/rng.md`), which stays reserved for food placement and is pinned by the corpus. It lives in
`game/simulation/` because seeding an RNG at all is something
`tools/validate_simulation_boundary.py` allows nowhere else (same reason as `seed_source.gd`).
`GameScreen._randomize_start` turns it off for the TASK-037 parity capture harness alone, whose
screenshots are compared against the oracle's own right-facing spawn.

`game_screen.gd` (`GameScreen extends Control`) is the top-level orchestrator: it loads content via
`ContentLoader`, save data via `SaveStore`, generates a fresh RNG seed via `seed_source.gd`'s
`SeedSource.fresh()` (the only `randi()` caller outside `game/simulation/`'s own boundary-gate
exemption a live app needs), and wires `SimulationWorld`, `TickDriver`, `BoardView`, `Hud`,
`OverlayPanel`, `InputRouter`, and `AppLifecycle` together. `_process()` snapshots the food cell via
`serialize()`/`decode_canon_header()` immediately before each frame's `TickDriver.advance_frame()`
call (so a drained `NS_EVENT_EAT` has a coordinate to hand `BoardView.notify_eat()`), then drains
events and reacts per kind — `NS_EVENT_DIE` sets `board_view.fx.flash = 1.0` directly (no `FxState`
method covers `die()`'s explicit `S.flash=1`, since a win always co-occurs with an eat and so
already gets its flash from `FxState.burst()`), and `NS_EVENT_WIN` marks the following dead screen
as a win rather than a game over.

Pause is entirely app-level: no export function ever drives a live world's status to
`NS_STATUS_PAUSED`, so `GameScreen` tracks its own `_paused: bool` and passes `gate=not _paused` to
`TickDriver.advance_frame` (`running` is always `true` — this app has no separate engine-pause
concept). Per [[decision-024]], `board_view.gd`'s `_draw_pause_vignette()` branch stays dead code
until/unless a later task drives a real paused world status through.

`game/tests/test_game_screen.gd` instantiates a real `GameScreen`, following
`test_app_lifecycle.gd`'s `add_child()`-then-call convention, with `save_dir_override` redirecting
`SaveStore` off real `user://` data the same way `test_save_store.gd` isolates its own temp dir.

## `tools/capture_parity.sh` + `taskfiles/parity.yml` (TASK-037)

Golden-image parity suite, run via `task parity:capture` (never `task check` — see below). Renders
both `reference/snake.html` (a real Firefox window) and the Godot build at each of `menu` /
`playing` / `paused` / `dead`, under one headless `sway` compositor, capturing a PNG per state per
side into `artifacts/parity/` (gitignored) for a human to eyeball side by side.

**Why `sway`+`wtype`+`grim`, not `xvfb-run`.** [[decision-025]] has the full investigation; in short,
`xvfb-run` wraps an X11 virtual framebuffer, but both the Godot build and Firefox render natively via
Wayland on this machine, and no `Xvfb` package exists here at all. `sway`+`wtype`+`grim` is the
combination `~/git/zelda3`'s `backlog/tasks/task-005` already proved on this same box, after ruling
out `weston`, `ydotool`/`uinput`, and `cage`.

**Why Godot's states are driven by a debug hook, not simulated key events.** `wtype` key injection
into a live Godot window under headless sway does not produce any observable game-state change,
despite genuine `wl_keyboard` protocol events reaching Godot's Wayland thread ([[decision-025]]) —
apparently a Godot-Wayland-backend-specific issue, since the identical mechanism works fine against
Firefox (below). `game_screen.gd`'s `_maybe_drive_capture_state()` (gated behind an
`--capture-state=` CLI user-arg no normal launch ever passes) instead calls `GameScreen`'s own
already-tested handlers directly — `_on_direction_queued()` to start, `_on_pause_requested()` to
pause, and a `set_process(false)`-then-manual-`_process()` loop to reach `dead` without waiting on
real wall-clock ticks or racing the engine's own automatic per-frame call.

**Why the oracle side is driven by real key injection.** `reference/snake.html` must never be edited
(`AGENTS.md`), so it has no equivalent hook — and needs none: unlike Godot, Firefox's GTK/Wayland
input handling accepts `wtype`-injected keys correctly (`Up` to start, `Space` to pause/resume, and
just letting wall-clock time pass after a start reliably runs the snake into the wall for `dead`,
since the post-start direction is always clobbered to right — [[decision-015]]). Each state launches
a fresh Firefox instance against a fresh temp profile rather than reusing one window, so there is
never any input-ordering ambiguity between states (e.g. a stray second `Space` toggling pause back
off).

**Comparison methodology — judgment-matched, not pixel-exact.** This suite has no automated
pixel-diff pass/fail gate; it produces comparable screenshots for a human reviewer to judge, per the
task's own Description. Two categories of visual divergence are *expected* and not evidence of a
regression:

- **Canvas `shadowBlur` vs. `board_view.gd`'s additive radial-gradient sprite approximation**
  ([[decision-006]], [[decision-022]]) — the oracle's Gaussian canvas glow has no direct Godot
  `CanvasItem` equivalent; the port approximates it, and the difference is cosmetic and permanent.
- **Integer vs. float `StyleBoxFlat` corner radii** ([[decision-007]]) — Godot's `StyleBoxFlat` only
  accepts integer corner radii where the oracle's CSS `border-radius` is a float, producing a
  sub-pixel rounding difference on rounded UI elements.

A reviewer comparing `artifacts/parity/godot-*.png` against `artifacts/parity/oracle-*.png` should
expect matching layout, color, text, and game state per pair, but should *not* flag either of the
above as a bug — they are already-accepted, permanent divergences, not regressions to chase.

**Why this is not part of `task check`.** AC#2 offers an explicit either/or: wired into `task check`,
or "a documented separate task" — this follows `oracle:fuzz`'s existing precedent (a real, documented
taskfile target deliberately excluded from `check`) rather than the former, since the suite requires
`sway`/`wtype`/`grim`/`firefox` (Linux + Wayland only, per `platforms: [linux]` on the task) and
produces screenshots for manual review rather than a hermetic pass/fail result `check` could gate on.

## `tools/render_audio.py` + `taskfiles/audio.yml` (TASK-038)

Renders text-source SFX patches (`audio/src/sfx/*.chip.json`) to 16-bit mono WAV using only the
Python stdlib (`wave`, `struct`, `math`, `json`) — no third-party audio dependency, matching the
`uv run --script` + PEP 723 inline-metadata convention already used by
`tools/validate_simulation_boundary.py`.

**Patch schema (`schema_version: 1`).** A patch names a `sample_rate`, a `duration_ms`, a `waveform`
(`square` | `triangle` | `noise`), an optional `duty` (square only, default `0.5`), and two
piecewise-linear breakpoint envelopes over time: `pitch_hz` and `volume`. Both envelopes are
`[[time_ms, value], ...]` lists starting at `t=0`, interpolated linearly between points and held flat
before the first / after the last — enough expressiveness for the eight short cues TASK-039 needs
(a pitch sweep for `eat`'s upward chirp or `die`'s descending noise decay, an amplitude envelope for
attack/decay shaping) without the extra parameters (vibrato, arpeggio, bit-crush) a general chiptune
tracker format would carry and this repo doesn't need. `noise` clocks a fixed-seed 15-bit Galois LFSR
(NES-APU-style) once per pitch-phase wrap rather than drawing from the platform RNG, so a patch's
rendered bytes depend only on its own JSON content.

**Why this guarantees byte-reproducibility (AC#2).** Nothing in the render path reads wall-clock time,
a random seed, or dict/set iteration order — every input is walked as an explicit sample-index loop
over IEEE-754 double arithmetic, which is deterministic given the same code and inputs. `--self-test`
renders an embedded fixture patch twice into in-memory buffers and asserts the bytes are identical;
`task audio:check` runs this before anything else.

**`task audio:render` vs. `task audio:check`.** `render` regenerates `game/content/audio/sfx/*.wav`
from every `audio/src/sfx/*.chip.json` — run this after authoring or editing a patch, then commit the
WAV alongside it (TASK-039 AC#2). `check` re-renders every patch into memory and diffs it byte-for-byte
against the committed WAV, failing loudly on any mismatch (a stale committed WAV that no longer
matches its source), and passes trivially when zero patches exist (true when this task landed, before
TASK-039 populated `audio/src/sfx/`).

`DEFAULT_OUT_DIR` was originally `audio/build/sfx/` when this tool first landed; TASK-039 moved it to
`game/content/audio/sfx/` once real Godot playback needed the WAVs reachable through `res://` — see
that section below for why.

**Why this *is* wired into `task check`, unlike `parity:capture` or `oracle:fuzz`.** Both of those are
excluded for a concrete environmental reason (a GUI/Wayland dependency, or being open-ended discovery
rather than regression). `audio:check` is pure stdlib Python with no such dependency — the same
`uv`+Python 3.13 toolchain `game:boundary-check` and `core:abitest-purity` already require — so there's
no reason to keep it out of the one documented gate; `check:`'s command chain now ends with
`audio:check`.

No entry in `backlog/decisions/` was needed for this task: [[decision-018]] already establishes that
`reference/snake.html` has no audio to diverge from, so there is no oracle-behavior deviation to
record here — only new, purely-additive build tooling.

## `audio/src/sfx/*.chip.json` + `game/presentation/audio/sfx_player.gd` (TASK-039)

The eight named cues (`eat`, `die`, `turn`, `start`, `pause`, `win`, `ui_move`, `ui_confirm`) as
`.chip.json` patches under the schema `tools/render_audio.py` (TASK-038) defines: `eat` is a short
upward `square` chirp, `die` a descending-pitch `noise` decay, `turn`/`ui_move` quiet ~20-25ms blips
so they don't stack unpleasantly under rapid input, `start` and `win` step through a short
`square`/`triangle` arpeggio via stacked-flat breakpoints (`[[t, v], [t2, v], [t2+0.001, v2], ...]` —
a near-zero time gap holds the first pitch flat then jumps instantly to the next, since the schema's
envelopes are otherwise linearly interpolated), and `pause` a single flat `triangle` tone. Rendered via
`task audio:render` to `game/content/audio/sfx/*.wav` and committed alongside the source patches.

**Why `game/content/audio/sfx/`, not `audio/build/sfx/`.** TASK-038 shipped `render_audio.py` with a
default out-dir of `audio/build/sfx/`, a directory outside the Godot project (`game/`) entirely. That
was fine as long as nothing needed to actually load a rendered WAV, but `SfxPlayer` (below) loads these
through Godot's `res://` resource filesystem, which only sees paths under `game/`. Rather than
symlinking a directory into the project (an extra moving part, and this repo has no existing precedent
for a checked-in symlink) or keeping two copies of the same WAV in sync, this task simply moved
`DEFAULT_OUT_DIR` in-place to `game/content/audio/sfx/` — co-located with the other checked-in content
`game/content/loader.gd` already reads (`tuning.json`, `palette.json`, `modes.json`), the established
convention in this repo for data the presentation layer loads by path at runtime. `audio/src/sfx/`
(the source patches) stays at the repo root, matching the milestone's own naming.

**`SfxPlayer` (`game/presentation/audio/sfx_player.gd`).** One `AudioStreamPlayer` child per cue,
keyed by name; `play(cue)` just calls that player's own `.play()`. No pooling or polyphony — every cue
is a single one-shot under ~450ms, so retriggering restarts it, which is unnoticeable at this length.
`GameScreen` owns the one instance (`sfx`), matching how it already owns `board_view`/`hud`/`overlay`/
`input_router`/`app_lifecycle`. Lives entirely in presentation — `core/*.zig` and `include/neo_snake.h`
carry no audio-related symbol, satisfying the milestone's "core never knows audio exists" rule (the
other two uncoupling rules, catch-up coalescing and replay suppression, are TASK-041's job, not this
one's).

**Wiring (`game_screen.gd`).** `eat`/`die`/`win` fire from the same `event_drain()` match block that
already drives `board_view.notify_eat()`/`fx.flash` (TASK-036) — one `sfx.play()` call added per
existing `EVENT_*` branch, no new control flow. `start` fires once from `_start_or_restart()`, the
existing single choke point every start/restart path (menu direction input, R, the overlay button)
already funnels through. `pause` fires only on the false→true edge of `_on_pause_requested()`'s toggle
(pausing, not resuming — no cue was requested for resume). `turn` fires from `_on_direction_queued()`'s
gameplay branch (after the menu/dead auto-start branch, which plays `start` instead, per the class doc's
existing note on `queueDir()`'s auto-start quirk). `ui_confirm` fires from `_on_overlay_action_pressed()`
unconditionally (so pressing "Start" plays both `ui_confirm`, a button-click acknowledgment, and
`start`, the gameplay stinger — a deliberate, common two-cue layering, not a bug) and `ui_move` from
`_on_mode_selected()` (mode dropdown cycling).

**Testing (`game/tests/test_sfx_player.gd`, `game/tests/test_game_screen.gd`).** `test_sfx_player.gd`
asserts all eight cues load a real `AudioStreamWAV` and that `play()` sets the corresponding player's
`playing` to `true` — the closest automated proxy to "audibly triggered" a headless test runner can
assert. `test_game_screen.gd` gained one case per UI-reachable cue (`start`, `pause`, `turn`,
`ui_confirm`, `ui_move`) asserting the same `playing` flag after invoking the real handler. `eat`/`die`/
`win` are deliberately left unasserted at this layer — driving a real eat/death/win through
`GameScreen._process()` needs a specific food/snake state this repo has no existing test harness for,
and the pre-existing `board_view.notify_eat()`/`fx.flash` calls sitting in the exact same match block
have never had a `GameScreen`-level test either; this follows that same established boundary rather
than inventing new state-forcing machinery for audio alone.

**AC#3's manual check.** The sandbox this task ran in reports no sound card (`aplay -l` finds none), so
no literal by-ear confirmation was possible here. What was verified instead: every rendered WAV is
non-silent and non-clipping (peak sample well under the 16-bit ceiling on every cue — checked by hand
against the committed files), and the `SfxPlayer`/`GameScreen` tests above confirm every cue actually
starts playback when its real trigger fires. A human with working audio output should still do a quick
real listen-through before calling this fully done.

No entry in `backlog/decisions/` was needed: audio remains purely additive per [[decision-018]], and
the `DEFAULT_OUT_DIR` move is a build-tooling detail, not a `reference/snake.html` behavior deviation.

## `tools/render_music.py` + `audio/src/music/*.fur` + `game/presentation/audio/music_player.gd` (TASK-040)

Adds a tracker-authored music master, rendered offline to a committed OGG, and an audio bus layout
(`Master -> Music / SFX / UI`) that both the existing SFX cues and the new music track route through.

**Furnace, not a hand-rolled synth.** TASK-038/039's `render_audio.py` hand-synthesizes short SFX
patches directly in Python — fine for eight one-shot cues, but composing a full melodic track sample-
by-sample in the same style would be a real tracker's job done badly by hand. Instead this task pins
[Furnace](https://github.com/tildearrow/furnace) (`tools/game_toolchain.lock`: `FURNACE_VERSION`,
checksum-verified Linux tarball / macOS DMG URLs, same pattern as the Godot fallback binary above) and
authors `audio/src/music/theme.fur` against Furnace's own public `.fur` format spec — never by copying,
cloning, or lightly editing any of Furnace's own bundled demo songs, which its own `demos/README.md`
states are third-party copyrighted, not GPL like the tracker itself.

**Bootstrap and dispatch mirror Godot's, generalized.** `tools/toolchain.py`'s `godot_xdg_env()` became
`game_tools_xdg_env()` (the XDG sandbox-redirect trick isn't Godot-specific) and gained
`furnace_binary_path()`. `tools/bootstrap.py game furnace` downloads and extracts the Linux tarball (or
mounts/copies the macOS DMG — Furnace, unlike Godot, ships no macOS zip alternative, so the DMG path
uses `hdiutil attach`/`detach` and is untested on this Linux sandbox) to `.tools/game/furnace/` (already
covered by the existing `/.tools/*` `.gitignore` entry). `tools/run.py furnace [args...]` dispatches
through the pinned binary exactly like `tools/run.py godot` does.

**The render pipeline has two chained external steps, neither of them ffmpeg** (not installable on this
host without an unconfigured system repo):

1. The pinned `furnace` binary renders `.fur` to WAV via its built-in console/export mode:
   `furnace -console -view nothing -loglevel warning -output out.wav -loops 0 in.fur`. This runs fully
   headless — no Xvfb/X11 needed, unlike *interactive* Furnace authoring, which does need a GUI this
   sandbox doesn't have (see "AC#3's manual check" below). `-safemode` cannot be combined with
   `-console`/`-output` — Furnace refuses that combination outright — and `-loglevel` only accepts
   `warning`, not `warn`.
2. `soundfile` (the first non-stdlib Python dependency in this repo's tooling, declared via PEP 723
   `dependencies = [...]` and run with `uv run --script`) re-encodes the WAV to OGG Vorbis — its bundled
   libsndfile has Vorbis support compiled in, so no ffmpeg/oggenc/sox is needed either.

**Ogg container non-determinism (a genuinely new finding, not assumed going in).** Two Furnace renders
of the same `.fur` are byte-identical WAVs (`--self-test` proves this per-run). But two `soundfile` Ogg
encodes of that *same* WAV are never byte-identical — libogg embeds a randomized per-logical-stream
serial number in the container on every encode (confirmed: first byte difference at offset 15, the Ogg
page header). The decoded PCM samples, however, are bit-identical across encodes (confirmed with
`numpy.array_equal`, max abs diff `0.0`). So `--check` never diffs raw `.ogg` bytes — it decodes both
the committed file and a fresh render with `soundfile` and compares the sample arrays.

**`task audio:music-render` vs. `task audio:music-check`** (`taskfiles/audio.yml`) mirror
`audio:render`/`audio:check`'s shape: `render` regenerates `game/content/audio/music/*.ogg` from every
`audio/src/music/*.fur`; `check` runs `--self-test` then `--all --check`. Unlike `audio:check` (pure
stdlib, no external binary), `music-check` requires the bootstrapped `furnace` binary — the same
category of dependency `game:test` already has on the bootstrapped Godot binary, so it's wired into the
main `check:` chain on that precedent rather than excluded the way `parity:capture`/`oracle:fuzz` are.

**Bus layout (`game/default_bus_layout.tres`).** Godot auto-loads bus layouts from the fixed resource
path `res://default_bus_layout.tres` with no `project.godot` entry required (confirmed via the Godot
docs), so the three-bus layout (`Music`, `SFX`, `UI`, each sending to `Master`) lives at the project
root rather than needing any project-settings edit. `SfxPlayer` splits its eight cues across two of the
three buses: `ui_move`/`ui_confirm` (menu-navigation feedback) route to `UI`; the other six (in-game
feedback: `eat`, `die`, `turn`, `start`, `pause`, `win`) route to `SFX`. This split is a new
`SfxPlayer.UI_CUES` list, not a task requirement spelled out anywhere else — the bus layout only needed
to exist and be routed to correctly, so this is the most natural interpretation of "UI" vs. "SFX" given
the two categories of cue that already existed.

**`MusicPlayer` (`game/presentation/audio/music_player.gd`).** `reference/snake.html` has no music at
all, so unlike every SFX cue there is no oracle cue-point to match — the simplest correct design is a
single `AudioStreamPlayer` on the `Music` bus, loaded with `game/content/audio/music/theme.ogg`
(`loop = true` set on the `AudioStreamOggVorbis` resource), started once and left running continuously.
`GameScreen` owns the one instance (`music`), added and started in `_ready()` alongside `sfx`. It is not
gated on game status (menu/playing/paused/dead) — there's no reference behavior to derive a gating rule
from, and continuous background music is the ordinary default for this genre absent a specific reason
to stop it.

**Testing (`game/tests/test_music_player.gd`).** Asserts the committed OGG loads a real stream, that the
stream's `loop` flag is set, that the player's `bus` is `"Music"`, and that `play()`/`stop()` actually
start/stop playback — the same headless proxy for "audibly triggered" `test_sfx_player.gd` already uses.

**AC#3's manual check.** As with TASK-039, this sandbox reports no sound card (`aplay -l` finds none),
so no by-ear confirmation was possible here. What was verified instead: the rendered track is
non-silent (RMS≈4888) and non-clipping (peak 16383 of a 32767 ceiling), `~12.8s` long, and the
`MusicPlayer`/bus-routing tests above confirm it actually starts on the `Music` bus. A human with
working audio output should do a real listen-through (and confirm the loop point isn't audibly jarring)
before calling this fully done.

No entry in `backlog/decisions/` was needed: [[decision-018]] already establishes `reference/snake.html`
has no audio to diverge from, so a music track and bus layout are purely additive, not a behavior
deviation.

## `tools/validate_audio_boundary.py` + `AudioEventCoalescer` + `set_replaying()` (TASK-041)

Enforces the three audio-uncoupling rules the milestone has been stating since TASK-039/040 but never
actually mechanically checked: the core never knows audio exists, catch-up coalescing is presentation
policy, and replay/rollback playback must be silent.

**`tools/validate_audio_boundary.py` (AC#1).** A dedicated script, not an extension of
`validate_simulation_boundary.py` (TASK-029, above) — that tool scans `.gd` files *outside*
`game/simulation/` for sim-boundary violations, the opposite direction and file scope from what AC#1
needs (audio tokens *inside* `include/neo_snake.h` and `core/*.zig`/`*.c`). Strips comments before
scanning — `include/neo_snake.h` already carries one legitimate comment describing `ns_event`'s
consumer as "e.g. audio, TASK-041", which must not itself trip the check — then greps the remaining
code for `audio|sound|sfx|music` (case-insensitive, word-prefixed). Wired in as `core:audio-boundary-
check` (`taskfiles/core.yml`), placed in `check:` right after `core:abi-header-check` and before
`core:abi-symbols`, alongside the other cheap static core-boundary checks.

**`AudioEventCoalescer` (`game/presentation/audio/audio_event_coalescer.gd`, AC#2).** `core/abi.zig`'s
`ns_pump` loops `stepOneTick` while ticks remain in the frame's accumulator budget (up to
`world.MAX_STEPS`), so a single `ns_pump` call after a hitch can genuinely advance several ticks at
once, each eating tick pushing its own independent `NS_EVENT_EAT`. The pre-existing `GameScreen._process()`
code called `sfx.play("eat")` once per drained event, so a six-tick catch-up frame would have played the
eat cue six times — a real bug, not a hypothetical one. `AudioEventCoalescer.cues_for(events)` is a
pure static helper (`class_name`, no Node dependency — the same testable-pure-helper pattern
`GameScreenState`/`BoardGeometry` already established) that reduces a frame's event array to a
`{"eat": bool, "die": bool, "win": bool}` dictionary; `GameScreen._process()` now calls `sfx.play()` at
most once per cue per frame, gated on that result, instead of once per event. Die/win needed no
coalescing logic of their own — `ns_pump`'s loop condition already includes `w.status == .playing`, so
it stops the instant a tick transitions status to `.dead`, meaning at most one die/win event can ever
appear in a single drain.

Tested with synthetic event arrays (`game/tests/test_audio_event_coalescer.gd`) rather than driving a
real catch-up hitch through `GameScreen`, on the same precedent TASK-039 already recorded above:
forcing a specific food/snake state through `GameScreen._process()` needs test-harness machinery this
repo doesn't have. A synthetic six-`EVENT_EAT` array is exactly what a real six-tick catch-up drain
looks like at the point `AudioEventCoalescer` consumes it, so the pure-function test is a faithful
proxy without inventing new state-forcing infrastructure.

**`set_replaying(bool)` on `SfxPlayer`/`MusicPlayer` (AC#3).** Both players gained a `_replaying` flag
and a `set_replaying(replaying)` setter; `play()`/`play(cue)` become a no-op while it's `true`. Lives on
the presentation-layer players themselves, not on `core/*.zig`, per the same "core never knows audio
exists" rule AC#1 enforces. No `GameScreen.set_replaying()` forwarding method was added: no rollback or
replay driver exists yet in this codebase (deferred to TASK-051+ multiplayer work per
`docs/canonical-state.md`), so a forwarding method with no caller would be speculative. The flag sits
directly on `SfxPlayer`/`MusicPlayer`, ready for a future rollback driver to call.

Verified two ways: direct unit tests on each player (`test_sfx_player.gd`, `test_music_player.gd`) confirm
`play()` is suppressed while replaying and restored once it isn't; and a corpus-wide integration test
(`test_corpus_replay.gd`, `test_set_replaying_true_suppresses_all_sfx_and_music_during_a_corpus_replay`)
drives every corpus trace except `win-full-board` (not ABI-representable — see the existing
`_replay()` skip logic) through the existing `_replay()` driver with both players held in replaying
mode and an `on_tick` callback that unconditionally calls `sfx.play()`/`music.play()` per drained event
(routed through `AudioEventCoalescer`), then asserts no `AudioStreamPlayer` in either player is ever
`playing` across the entire corpus — thousands of real ticks including eat/die/win events. `_replay()`'s
signature gained an optional `on_tick: Callable = Callable()` parameter (called just before each tick's
`expected_tick` increment) to make this possible without duplicating the driver.

No entry in `backlog/decisions/` was needed: this task enforces existing architectural rules rather than
introducing new `reference/snake.html`-observable behavior — [[decision-018]]'s "audio is purely
additive" reasoning applies here exactly as it did to TASK-039/040.

## `game/platform/save_store.gd` + `game/platform/keybind_codec.gd` + `game/presentation/board/fx_state.gd` + `game/presentation/screens/settings_panel.gd` (TASK-042)

Adds a settings screen and three accessibility/QoL features the oracle never had: per-bus volume
(AC#1), a reduce-flash gate (AC#2), and keybind rebinding (AC#3).

**`SaveStore`'s v3 schema (AC#1, AC#3).** `SCHEMA_VERSION` moved 2 → 3, adding a `settings` block
(`volume_db: Dictionary` keyed by `AUDIO_BUSES := ["Master", "Music", "SFX", "UI"]`, `reduce_flash:
bool`, `keybinds: Dictionary` keyed by `InputDefaults` action names) alongside the existing
`best_scores`/`last_mode`. `_migrate_v2_to_v3()` carries `best_scores`/`last_mode` forward unchanged
and fills `settings` with `_default_settings()` — a v2 save has no opinion on volume/flash/keybinds,
so a fresh default is the only sound migration, not an attempt to infer one from absence.
`_normalize_settings()` applies the same "explicit defaults, not absence-means-default" rule
`_normalize_v3()` already applies to `best_scores`: any bus or action missing from a hand-edited or
older save (including a v3 save written before a new action existed) falls back to its default rather
than leaving `SettingsPanel`/`GameScreen` to guess. `KeybindCodec.default_keybinds()` is the single
source of truth for which actions get a keybind entry, so `SaveStore` never hardcodes the action list
itself.

**`KeybindCodec` (`game/platform/keybind_codec.gd`, AC#3).** Encodes a rebound key as
`"key:" + OS.get_keycode_string(keycode)` rather than serializing the `InputEventKey` itself — the
task's own AC#3 requirement, so a save file survives a future Godot engine/input-system version change
even if `InputEvent`'s internal shape doesn't. `decode()` reverses this via
`OS.find_keycode_from_string()`, returning `KEY_NONE` for a malformed or unrecognized string rather
than throwing, so a corrupted save degrades to "unbound" instead of failing to load.
`apply_to_input_map(keybinds)` is the only place that touches the live `InputMap`: it erases each
action's existing events (`InputMap.action_erase_events`) and re-adds one built from the decoded
keycode, using `physical_keycode` (not `keycode`) to match the layout-independent convention
`project.godot`/`InputDefaults.ACTION_PHYSICAL_KEYCODES` already established.

**`FxState.reduce_flash` (`game/presentation/board/fx_state.gd`, AC#2).** A `reduce_flash: bool` field
gates both `burst()` (particles + flash, the eat/die effect) and a new `trigger_flash()` method
(flash-only, used directly by `GameScreen`'s die branch instead of assigning the flash timer inline).
When `true`, both become no-ops — the accessibility rationale (photosensitivity) is recorded in
[[decision-016]], which already covered the flash effect itself; this task only adds the toggle that
gates it, not a new behavior needing its own decision entry.

**`SettingsPanel` (`game/presentation/screens/settings_panel.gd`, AC#1/AC#2/AC#3).** A pure-presentation
`Control`, built in code rather than a `.tscn` — matching `OverlayPanel`/`BoardView`'s code-first
convention, this repo's only precedent for a hand-authored node tree. Owns per-bus `HSlider`s, a
reduce-flash `CheckBox`, and one rebind `Button` per `InputDefaults.ACTION_PHYSICAL_KEYCODES` action;
`set_settings()` seeds all three from a loaded save using `set_value_no_signal`/
`set_pressed_no_signal` so applying a load doesn't re-emit every value as a user edit. It only edits
values and emits `volume_changed`/`reduce_flash_changed`/`keybind_changed`/`closed` — mirroring how
`OverlayPanel` emits `action_pressed`/`mode_selected` without knowing what `GameScreen` does with them.
Rebinding is two-step: `_on_rebind_pressed(action)` arms `_listening_action` and shows "Press a
key...", then the next `InputEventKey` in `_unhandled_key_input()` is captured by `_capture_key()` (a
separate method so a test can drive a rebind directly with a synthetic event, bypassing the scene
tree's real input pipeline) and encoded via `KeybindCodec.encode()`.

**Wiring (`GameScreen`, `OverlayPanel`).** `OverlayPanel` gained a persistent "Settings" button
(`settings_requested` signal) alongside its existing title/sub/mode-select/action controls — visible
whenever the overlay itself is (menu, paused, dead), hidden while playing, with no per-screen toggle
needed. `GameScreen` owns the `SettingsPanel` instance, connects all four of its signals, and adds a
`_settings_open` guard to `_refresh_screen()` so the normal overlay-visibility logic doesn't fight the
settings screen while it's open. `_apply_settings(settings)` is the one place that pushes a settings
dict into the live systems it governs (`AudioServer.set_bus_volume_db` per bus,
`board_view.fx.reduce_flash`, `KeybindCodec.apply_to_input_map`) — called once at startup from the
loaded save, and again after every change signal, immediately followed by `save_store.save()`.

No entry in `backlog/decisions/` was needed beyond the pre-existing [[decision-016]] (reduce-flash
rationale): volume persistence and the keybind stable-string format are both directly specified by the
task's own AC text, not new judgment calls needing a record of their own.

## Native macOS arm64 build ([[decision-026]], TASK-043)

`task check` runs fully green natively on darwin/arm64 (AC#1), including Tier-D, producing
`game/bin/libneo_snake.macos.template_debug.framework/` and `.../template_release.framework/`
bundles matching `game/bin/neo_snake.gdextension`'s `macos.debug`/`macos.release` keys (AC#2). Three
build/tooling gaps only surface when actually building on macOS rather than cross-compiling from
Linux — all three are covered in detail, including the exact failure output and numeric bounds, by
[[decision-026]]; this section only summarizes what changed and where.

**`extension/SConstruct`** appends `-Wl,-ld_classic` to `LINKFLAGS` inside its
`env["platform"] == "macos"` branch (immediately before the framework-bundle packaging code already
described above), working around Apple's newer default linker ("ld-prime", Xcode 26+) rejecting
`core/zig-out/lib/libneo_snake.a` at final-link time over Mach-O archive-member alignment. Linux is
unaffected — this branch never executes there.

**`taskfiles/extension.yml`'s `build:` task is gated `platforms: [linux]`**, alongside the
pre-existing `build-macos:` task (`platforms: [darwin/arm64]`). A bare `scons` invocation defaults
`arch=universal` on macOS, which cannot link against the single-arch `libneo_snake.a` `zig build abi`
produces there — `extension:build-macos` already pins `arch=arm64` explicitly for both
`template_debug` and `template_release` and is the sole macOS path in `task check`.

**`taskfiles/audio.yml`'s `music-check:` task is gated `platforms: [linux]`.** Furnace's synthesis is
cross-platform deterministic, but the OGG Vorbis encode step is not bit-exact across
platforms/builds, so the committed `.ogg`'s exact-sample-equality check only holds on the platform
that asset was actually rendered on (Linux). `audio:check` (SFX, WAV, byte-exact) is unaffected and
still runs on every platform.

Confirmed end to end on a real Apple Silicon host (Xcode 26.6): `task check` reaches
`audio:music-check`, which silently no-ops per go-task's `platforms:` allow-list semantics, and the
whole chain exits 0 — 119/119 gdUnit4 test cases, both framework bundles built, no step skipped that
wasn't deliberately gated.

## macOS code signing and notarization ([[decision-027]], TASK-044)

`taskfiles/release.yml` (`release:` in the root `taskfile.yml`) runs the whole unattended macOS
release pipeline as `task release:ship-macos`: an ephemeral signing keychain, headless Godot export
(the `.app` and its embedded GDExtension `.framework` both sign against the imported Developer ID
identity with hardened runtime enabled), independent signature verification, notarization, and
stapling — with keychain/API-key cleanup registered via `defer:` so it runs even if a later step
fails (AC#4). Real credentials never live in this repo; they're supplied at runtime via
`APPLE_SIGNING_IDENTITY`/`APPLE_CERTIFICATE`/`APPLE_CERTIFICATE_PASSWORD`/`KEYCHAIN_PASSWORD`/
`APPLE_API_KEY_B64`/`APPLE_API_KEY`/`APPLE_API_ISSUER` env vars, each guarded by a `preconditions:`
check with an actionable message (AC#3).

**Signing hosts reached only over SSH need a `launchctl asuser` bridge.** [[decision-027]] has the
full investigation; in short, macOS's Security framework won't release an imported private key to a
process outside the GUI console login session's audit/bootstrap namespace, and a bare SSH session is
always outside it. `export-macos` wraps its godot invocation in
`sudo launchctl asuser "$(id -u)" ...` to re-attach into that namespace before signing starts, and
routes the resulting DMG's ownership fix (`sudo launchctl asuser` doesn't drop root's EUID) through
the identical `launchctl asuser` invocation rather than a bare `sudo chown`, so both stay covered by
one narrowly-scoped sudoers.d entry: `lance ALL=(root) NOPASSWD: /bin/launchctl asuser *`. That entry
must be installed directly by a human with sudo access on any such host — an agent must never be
given or asked for a sudo password, so this is a manual, one-time signing-host prerequisite, not
something `task release:ship-macos` provisions itself. It is a no-op wrapper on a machine where the
work is driven directly from a real console session (normal SSH-free signing needs no wrapping).

`export-macos` also resolves and invokes `godot` directly (`$(mise which godot)`) rather than going
through `./tools/run.py`: `tools/run.py`'s `uv run --script` shebang was confirmed (by direct A/B
testing under the same bridge) to break the audit-session inheritance the bridge is providing, even
though a directly-invoked `godot` binary signs correctly under the identical wrapper. This is scoped
to this one signing step — every other Godot invocation in this repo's task graph still goes through
`tools/run.py` as normal.

**`verify-signing` mounts the exported DMG (AC#2).** Godot's DMG export mode
(`export_path` ending in `.dmg` in `game/export_presets.cfg`) builds and signs the `.app` inside a
private temp directory and never leaves a loose bundle under `game/build/macos/` — only the final
signed `.dmg`. `verify-signing` mounts it read-only via `hdiutil attach -nobrowse -readonly`, verifies
the embedded `libneo_snake.macos.template_release.framework` directly (it's `dlopen`'d at runtime, so
`codesign --verify --deep --strict` on the `.app` alone doesn't walk into it) plus its hardened-runtime
flag, then the `.app`'s own nested signatures, then the DMG's own signature, and always detaches the
mounted volume via a `trap ... EXIT` regardless of which check fails.

**`notarize` adds a Gatekeeper-assessment step `~/git/mt`'s equivalent task doesn't have.** After
`xcrun notarytool submit --wait` and `xcrun stapler staple`, it runs
`spctl -a -vv --type open --context context:primary-signature` against the stapled DMG and asserts
`accepted`/`source=Notarized Developer ID` — the automatable proxy for AC#1 ("opens on a clean Mac
with no Gatekeeper prompt"), rather than trusting `notarytool`'s own submit response as sufficient
proof.

Confirmed end to end against live Apple infrastructure on `mini`: real notarization (Accepted), real
stapling, `spctl` reporting `accepted`, both the `.framework` and `.app` independently verified signed
with hardened runtime, credential preconditions failing with the intended messages when unset, and a
forced-failure scratch-taskfile run confirming `defer:`-registered keychain cleanup still executes
when `export-macos` fails.

## Linux x86_64 build via Docker ([[decision-028]], TASK-045)

`docker/linux/Dockerfile` is a five-stage build — `deps` (base toolchain) → `src` (repo source) →
`check` / `build` (parallel targets off `src`) → `artifacts` (extraction only) — that produces
`game/bin/libneo_snake.linux.template_debug.x86_64.so`, matching TASK-043's precedent that a
platform "build" task's deliverable is the GDExtension bundle itself, not a full Godot export.

```
docker build --target check .
docker build --target artifacts --output type=local,dest=dist .
```

**`check` runs Tier-A/B/C** (`task core:test core:difftest core:abitest`) — no Godot, SCons, or
godot-cpp needed, since none of those three tiers touch the ABI/GDExtension layer. Tier-D
(`game:test`) needs a full Godot install and is out of scope for this container.

**`build` pins the glibc floor to `x86_64-linux-gnu.2.28`** via `taskfiles/extension.yml`'s `build:`
task, which gained an optional `ZIG_TARGET_FLAG` var (mirroring the mechanism `extension:build-macos`
already had for `-Dtarget=aarch64-macos`; empty by default, so `extension:build` is unchanged outside
this container). `2.28` was measured, not guessed: `objdump -T` against Godot 4.7.1-stable's own
officially shipped `linux_release.x86_64` export template (downloaded and checksum-verified against
`tools/game_toolchain.lock`) shows `GLIBC_2.28` as its highest referenced symbol version — pinning the
GDExtension to the same floor means it never demands a newer glibc than the engine itself already
does. The resulting `.so`'s own highest referenced symbol is `GLIBC_2.16`, comfortably under that
floor.

**Every toolchain download inside `deps` is checksum-verified** (Zig, `task`, `uv`, all
`curl -fsSL ... | sha256sum -c -` against this repo's own `.tool-versions` pins) and the base image is
pinned by digest, not just tag — matching this repo's existing `tools/game_toolchain.lock` convention
rather than an unverified `curl | sh` install. `scons` is installed via `pipx`, matching
`.tool-versions`' `pipx:scons` entry.

**AC#1's cross-host claim ("identical output from macOS or Linux") is verified by construction**,
detailed in full in [[decision-028]]: `mini` (the only macOS host available here) has no Docker
installed, so a literal same-build-on-two-real-hosts test wasn't possible. What was actually run: the
`artifacts` stage built twice independently, and the two resulting `.so` files are byte-identical
(`sha256sum` match exactly). The pinned digest, checksummed downloads, and absence of any
host-arch-conditional `RUN` step are what make that guarantee hold across host OSes too, not just
across repeat runs on this one.

## Windows x86_64 build via mingw cross-compilation ([[decision-029]], TASK-046)

`docker/windows/Dockerfile` mirrors `docker/linux/Dockerfile`'s five-stage shape, cross-compiling
the whole Windows GDExtension from a Linux host (route (a), decision-029) rather than a native
Windows CI runner: no code-signing requirement applies to a GDExtension `.dll`, so route (a)'s
"pure C ABI boundary, no libc crossing it" preference from the task's own Description applies
outright.

**Two toolchains are involved, not one.** Zig itself cross-compiles `core/`'s pure-Zig static
library for `-Dtarget=x86_64-windows-gnu` (no external mingw needed for this step — Zig bundles its
own mingw-w64 headers/import libs), but godot-cpp/SCons cannot use `zig cc` as a drop-in C++ cross
compiler for the GDExtension shim's own `.cpp` sources — `third_party/godot-cpp/tools/windows.py`
hardcodes real `x86_64-w64-mingw32-g++`/`-gcc`/`-gcc-ar`/`-ranlib` toolchain binary names, so a
genuine mingw-w64 install (Debian's `g++-mingw-w64-x86-64` package) is required for that half of
the build.

**Zig names a windows-gnu target's static library `neo_snake.lib`, not `libneo_snake.a`** — still a
plain `ar` archive of COFF objects underneath, just Windows' own conventional extension.
`taskfiles/core.yml`'s `abi-symbols` task gained an optional `CORE_LIB_NAME` var (default
`"libneo_snake.a"`, unchanged for every other target) so its `nm`-based symbol check can target the
right filename, and `extension/SConstruct` picks the matching name via `env["platform"] ==
"windows"`.

**The final link needs an explicit `-lntdll`.** Zig's windows-gnu std lib compiles panic/stack-guard
machinery referencing raw `NtAllocateVirtualMemory`/`NtFreeVirtualMemory` syscalls into every build;
a native `zig build-exe` resolves these itself, but `neo_snake.lib` is only a static archive, so
resolving them is deferred to whoever performs the final link — mingw's own `ld`, under godot-cpp's
`-Wl,--no-undefined`. `extension/SConstruct` appends `LIBS=["ntdll"]` for the windows platform,
linking mingw-w64's own `libntdll.a` import library.

**`extension:build-windows`** (`taskfiles/extension.yml`, gated `platforms: [linux]`, excluded from
`task check`'s chain — same precedent as `extension:build-macos`) rebuilds the core lib pinned to
`-Dtarget=x86_64-windows-gnu`, then runs `scons platform=windows use_mingw=yes use_static_cpp=yes
arch=x86_64` once per `target=template_debug`/`target=template_release`, producing
`game/bin/libneo_snake.windows.template_debug.x86_64.dll` and `.../template_release.x86_64.dll`.
`use_static_cpp=yes` statically links MinGW's own libgcc/libstdc++ into the `.dll` — verified via
`objdump -p` showing imports from only `KERNEL32.dll`, `msvcrt.dll`, and `ntdll.dll`, no MinGW
runtime DLL dependency.

**Exactly two new `.gdextension` keys**, `windows.debug.x86_64` and `windows.release.x86_64` — the
task's own Description speculatively estimated four; checking godot-cpp's own reference project
(`third_party/godot-cpp/test/project/my_test.gdextension`) shows one key per (target, arch) pair is
the correct convention, matching the existing `linux.debug.x86_64` key's shape.

**A `-windows-gnu`-built lib or `.dll` must never be linked into or alongside an MSVC-toolchain
build** (AC#3): MinGW's Itanium C++ ABI/name-mangling and MSVC's are not compatible, even though the
plain-C ABI `include/neo_snake.h` exposes across the Zig/C++ boundary is itself unaffected.

## Web spike: Zig+godot-cpp WASM toolchain, no COOP/COEP for nothreads dlink ([[decision-030]], TASK-047)

`taskfiles/web.yml`'s `bootstrap:` task runs `mise install emsdk@4.0.11` (pinned in
`tools/game_toolchain.lock`'s `EMSDK_VERSION`) — deliberately not written to `.tool-versions`
(task-002's rationale: emsdk is heavy and only needed on-demand). A build step that needs it
activates it per-invocation via `mise exec emsdk@{{.EMSDK_VERSION}} -- ...`, never `mise use`.

**The chain (`zig build-lib -target wasm32-emscripten --sysroot $EMSDK/upstream/emscripten` →
`scons platform=web arch=wasm32 threads=no lto=none target=template_release` against
`third_party/godot-cpp`) works unmodified** — proven with a throwaway hello-world GDExtension built
entirely outside this repo (session scratchpad, per the task's own "throwaway" framing; only this
doc section, the decision, and `taskfiles/web.yml` are real deliverables). No godot-cpp/`web.py`
changes were needed; `-sSIDE_MODULE=1`, `-sWASM_BIGINT`, and `-sSUPPORT_LONGJMP='wasm'` are applied
regardless of `threads`, confirming SIDE_MODULE dynamic linking is not inherently thread-gated.

**Settled the docs contradiction empirically, not just by reading source.** Godot's own docs say
enabling Extensions Support "requires... cross-origin isolation headers," unqualified — but
`platform/web/detect.py` (engine repo) shows `dlink_enabled` (GDExtension support) and `threads` are
independent SCons flags; nothing ties GDExtension loading to `-sUSE_PTHREADS=1`/SharedArrayBuffer.
Exported the spike headlessly with `variant/extensions_support=true`,
`variant/thread_support=false`, `progressive_web_app/enabled=false` (this maps to exactly the
`web_dlink_nothreads_release` template, confirmed via `export_plugin.h`'s
`_get_template_name`), served it with a plain `python3 -m http.server` sending no custom headers at
all, and loaded it with Playwright/Chromium. Result: `crossOriginIsolated: false`, zero page errors,
and the console shows the GDExtension loading and its FFI call returning the correct value
(`hello_value=42`) — full proof the chain works without cross-origin isolation for a nothreads
build. See [[decision-030]] for the complete reasoning and the Go decision.

**Go**: this repo's eventual web build can ship to itch.io/GitHub Pages (no custom-header hosting
needed) via `web_dlink_nothreads_release`/`_debug`, provided Thread Support stays disabled and (if a
PWA is ever added) `progressive_web_app/ensure_cross_origin_isolation_headers` stays `false` so the
generated service worker doesn't force headers a nothreads build doesn't need.

## Real web build: `extension:build-web`, `web_checksum_smoke_test.gd` ([[decision-031]], TASK-048)

`taskfiles/extension.yml`'s `build-web` task is the web counterpart to `extension:build` /
`build-macos` / `build-windows`: it rebuilds `core/zig-out/lib/libneo_snake.a` pinned to
`-Dtarget=wasm32-emscripten -Doptimize=ReleaseSmall`, then runs `scons platform=web arch=wasm32
threads=no lto=none` twice (`template_debug`/`template_release`), producing
`game/bin/libneo_snake.web.template_{debug,release}.wasm32.nothreads.wasm` — matching
`game/bin/neo_snake.gdextension`'s new `web.debug.wasm32.nothreads`/`web.release.wasm32.nothreads`
keys and `game/export_presets.cfg`'s new `[preset.1]` "Web" preset.

**`-Doptimize=ReleaseSmall` is mandatory, not a size choice**: `core/abi.zig` at the default Debug
(or explicit ReleaseSafe) optimize level pulls in Zig 0.16.0's `std.Io.Threaded` panic/safety-check
machinery, which references `posix.system.getrandom`/`IOV_MAX` — undefined for `wasm32-emscripten`
in this Zig version, so the build fails outright. `core:abi-symbols`' symbol-purity check also needs
`NM_BIN=llvm-nm` (emsdk's own bundled LLVM) here, since system `nm` can't parse a wasm archive
("file format not recognized"). See [[decision-031]] for the full diagnosis.

**`extension/SConstruct` needed one real fix**: its TASK-043 `ARCOM_POSIX`/`TEMPFILE(ARCOM_POSIX)`
`ar`-response-file workaround must skip `platform=web` as well as `macos` — godot-cpp's own
`tools/web.py` already applies the identical fix internally for web, so re-applying it here wrapped
`ARCOM_POSIX` in a self-referencing `TEMPFILE(ARCOM_POSIX)` and SCons' variable substitution
recursed past Python's recursion limit. This is the one genuine source-level bug this task found and
fixed, as opposed to purely additive taskfile/config work.

**AC#2 ("HashingContext.HASH_SHA256 is smoke-tested in the web runtime") names a class this codebase
never uses** — the real checksum chain is `core/canon.zig`'s SHA-256 via `ns_checksum` via
`NeoSnakeWorld.checksum()`, the same chain `game/tests/test_corpus_replay.gd` (Tier-D) already
exercises natively. `game/platform/web_checksum_smoke_test.gd` (a `Node`, instantiated by
`GameScreen._ready()` exactly like `AppLifecycle`, gated on `OS.has_feature("web")` so it's a no-op
everywhere else) replays the same `one-turn-per-tick` corpus trace `test_corpus_replay.gd` already
uses for its corrupted-checksum negative case, tick-by-tick through `SimulationWorld`, and prints
`WEB_CHECKSUM_SMOKE_TEST: PASS`/`FAIL <reason>` to the browser console — extending Tier-D's native
guarantee to the wasm32-emscripten target running in a real browser.

**`export_filter="all_resources"` does not include every extension by default**: `game/export_presets.cfg`'s
Web preset needed `include_filter="*.jsonl"` added, or the corpus trace files silently didn't make it
into the exported `.pck` even though `manifest.json` (a recognized `.json` extension) did — caught by
the smoke test failing to open the trace file in a real export, not by the export step itself
erroring.

**Verified end-to-end with a headless-Chromium Playwright session** (same pattern as decision-030's
spike) against the real project's `--export-debug "Web"` output: `WEB_CHECKSUM_SMOKE_TEST: PASS`,
zero `pageerror`s, zero `console:error` messages, and a real play session (movement, wall-collision
death, Game Over overlay, HUD score) rendering and responding to keyboard input correctly. See
[[decision-031]] for the full reasoning, including a native Linux `signal 11` seen once during setup
that did not reproduce after a clean rebuild.

## GitHub Actions CI: `taskfiles/ci.yml`, `.actrc`, act-verifiable ([[decision-032]], TASK-049)

`.github/workflows/ci.yml` runs on every push to `main` and every pull request:

- **`macos`** job (`runs-on: [self-hosted, macOS, ARM64]`) runs `task ci:macos-check` (a one-line
  wrapper around the existing `task check`) unconditionally, then `task ci:macos-release` (a
  wrapper around TASK-044's `task release:ship-macos`) only `if: github.event_name == 'push' &&
  github.ref == 'refs/heads/main'` — sign+notarize needs the Apple secrets and a real App Store
  Connect API call, so it does not run on every PR.
- **`linux`** job (`runs-on: ubuntu-latest`) runs `task ci:linux-docker-build`, a wrapper around
  `docker/linux/Dockerfile`'s `check` and `artifacts` stages (TASK-045) — all build logic lives in
  the Dockerfile, not the workflow YAML or the taskfile wrapper.

`.github/workflows/nightly-fuzz.yml` runs `task ci:fuzz` (wrapping `oracle:fuzz`, TASK-018) on a
daily cron plus `workflow_dispatch`, matching `taskfiles/oracle.yml`'s own note that fuzzing is
"deliberately NOT part of task check; run this nightly in CI instead."

`taskfiles/ci.yml` exists purely as this one-line-wrapper layer (`ci:macos-check`,
`ci:macos-release`, `ci:linux-docker-build`, `ci:fuzz`) so every workflow step reads as `task
ci:<target>` with no inline build logic, and so the exact same commands run identically whether
invoked by a human, by `act`, or by a real GitHub-hosted/self-hosted runner.

The root `.actrc` maps each of the `[self-hosted, macOS, ARM64]` labels individually to
`-self-hosted` (native host execution, no Docker container — mirrors `~/git/mt/.actrc`'s per-label
convention) and `ubuntu-latest` to act's own Ubuntu image. `act push -j macos` runs cleanly on a
non-Darwin verification host because `task ci:macos-check` is `platforms: [darwin]`-gated and
correctly no-ops (exit 0) elsewhere, the same way `task check` already no-ops
`extension:build-macos` on Linux. No separate Windows CI job exists — TASK-046 chose route (a)
(mingw cross-compilation from Linux), and TASK-049's own Description makes a Windows job conditional
on route (b) having been chosen instead. A live self-hosted macOS ARM64 runner already exists and
picked up the `macos` job on the very first real PR run (visible via real `/opt/homebrew/...`
output in the job log, even though the repo-scoped `gh api .../actions/runners` call reports zero
runners); the job's `env:` block sets `TASK_X_ENV_PRECEDENCE: "1"` directly, since the gitignored
`.env` that key normally lives in doesn't exist on the runner. The `macos` job also runs `task
game:bootstrap` before `task ci:macos-check` — `game/addons/gdUnit4/` and the Godot binary/export
templates are gitignored workspace-local state, so each checkout (even on the same persistent
runner host) needs its own bootstrap before `game:import`/`game:test` can run. See [[decision-032]]
for the full reasoning, including why the missing Apple signing secrets (the one real gap) don't
block any of this task's Acceptance Criteria.

## Release assets and README downloads: `.github/workflows/release.yml`, `tools/update_readme_downloads.py` ([[decision-033]], TASK-050)

`extension:build` (Linux) now runs `scons` twice (`target=template_debug` then
`target=template_release`), matching `build-macos`/`build-windows`/`build-web`'s established
two-scons-call pattern — previously a bare `scons` always defaulted to `template_debug`
(godot-cpp's own `tools/godotcpp.py` hardcodes that default), so `game/bin/neo_snake.gdextension`
had no `linux.release.x86_64` key to point at. `docker/linux/Dockerfile`'s `artifacts` stage now
extracts both `.so` files.

`game/export_presets.cfg` gained two new presets, authored from scratch (no prior Linux/Windows
preset existed) and empirically verified via real `--export-release` runs: `[preset.2]` "Linux"
and `[preset.3]` "Windows", both following the Web preset's `include_filter="*.jsonl"` fix (Godot's
`all_resources` export filter does not automatically include every extension) and confirmed to
place the release GDExtension binary flat next to the executable in the export output directory.
Windows has no code-signing (`codesign/*` disabled), per [[decision-029]].

`taskfiles/release.yml` gained `export-*`/`package-*`/`ship-*` task triads for Linux, Windows, and
Web, mirroring the existing `ship-macos` shape:

- Linux: `neo_snake-linux-x86_64.tar.gz` (`tar`).
- Windows: `neo_snake-windows-x86_64.zip` (`zip -j`, flattened paths).
- Web: `neo_snake-web.zip` (`zip -r` of the whole `build/web/` directory, `-x` self-excluded).
- macOS: unchanged — Godot's own DMG packaging (TASK-044) already produces `Neo Snake.dmg`.

Filenames were chosen so a substring match unambiguously identifies each platform (`.zip` alone
isn't unique between Windows and Web).

`.github/workflows/release.yml` (new, separate from `ci.yml`) triggers on `release: {types:
[published]}` and `workflow_dispatch` (with a `release-tag` input). Four platform jobs each build
their GDExtension, run `task release:ship-<platform>`, and upload the resulting asset via a thin
`task ci:release-<platform>` wrapper (`taskfiles/ci.yml`, matching TASK-049's one-`task`-call-per-
step convention). `linux`/`windows`/`web` run on `ubuntu-latest` via `jdx/mise-action@v2` to install
the full `.tool-versions`-pinned toolchain; `macos` runs on the existing self-hosted runner and
reuses `release:ship-macos`'s sign+notarize pipeline. A final `update-readme` job (`needs: [macos,
linux, windows, web]`, `if: always() && !cancelled() && contains(needs.*.result, 'success')`) runs
`tools/update_readme_downloads.py` against the release tag and commits+pushes the regenerated
`README.md` to `main` as `github-actions[bot]` with `[skip ci]`, only if the table actually changed.

`tools/update_readme_downloads.py` queries `gh api repos/{owner}/{repo}/releases/tags/{tag}`,
matches each asset to a platform by filename substring in a fixed, hardcoded order (not release-API
order — this is what makes a rerun against the same release byte-identical, satisfying AC#3), and
rewrites only the content between `README.md`'s `<!-- DOWNLOADS:START -->`/`<!-- DOWNLOADS:END
-->` markers. A platform missing from a given release (e.g. one job failed) is simply omitted from
the table rather than erroring. See [[decision-033]] for the full reasoning.

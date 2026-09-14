---
id: decision-031
title: 'Web build: Zig 0.16 ReleaseSmall mandatory, ARCOM_POSIX fix, AC#2 reinterpreted'
date: '2026-09-13 19:45'
status: Accepted
---
## Context

TASK-048 ships the real web build of `neo_snake`'s core/GDExtension (not the throwaway stub
`hello_value()` spike decision-030 proved the toolchain with), gated on that spike's Go. Three
things surfaced that this spike never hit, since it only ever compiled one trivial exported
function against no real dependencies.

**AC#2 as written names a class this codebase never uses.** AC#2 reads "HashingContext.HASH_SHA256
is smoke-tested in the web runtime." Godot's `HashingContext` GDScript/GDExtension class does not
appear anywhere in `game/` or `core/` (confirmed by exhaustive grep). The actual SHA-256 checksum
mechanism is entirely Zig-side and predates this task: `core/canon.zig`'s `checksum()` calls
`std.crypto.hash.sha2.Sha256.hash(...)` directly (first 8 digest bytes, per
`docs/canonical-state.md`'s checksum-trailer convention), exposed via `core/abi.zig`'s
`ns_checksum`, wrapped by `extension/src/neo_snake_world.cpp`'s `NeoSnakeWorld::checksum()`, and
already exercised natively by `game/tests/test_corpus_replay.gd` (Tier-D) against every committed
corpus trace. AC#2's real intent — confirming the checksum path Tier-D already trusts natively also
works once cross-compiled to `wasm32-emscripten` and run in an actual browser — is met by extending
that same chain to the web runtime, not by introducing Godot's unrelated `HashingContext` class.

**Zig 0.16.0 cannot build `core/abi.zig` for `wasm32-emscripten` at the default Debug optimize
level, or explicitly at ReleaseSafe.** Both fail identically:

```
lib/std/Io/Threaded.zig:2064:45: error: struct 'posix.system__struct_XXXX' has no member named 'getrandom'
const use_dev_urandom = @TypeOf(posix.system.getrandom) == void and native_os == .linux;
```

This comes from Zig std's own panic/safety-check machinery (`std.Io.Threaded`'s `RandomFile`),
which has no `posix.system.getrandom`/`IOV_MAX` binding for this target in this Zig version —
unrelated to `--sysroot` (tested explicitly, still fails). `-Doptimize=ReleaseSmall` (or
`ReleaseFast`) skips that code path and builds cleanly; `ReleaseSmall` is used since a smaller
`.wasm` is also strictly better for a browser download. This does not weaken AC#2's checksum
guarantee: stripping safety-check panics doesn't change the computed SHA-256 output for well-formed
input, only removes traps for malformed input the checksum path never receives.

**`extension/SConstruct`'s TASK-043 `ARCOM_POSIX`/`TEMPFILE(ARCOM_POSIX)` `ar`-response-file
workaround (for Linux's `ARG_MAX`) needed to exclude `platform=web`, not just `macos`.**
`third_party/godot-cpp/tools/web.py` already applies the identical two-line fix internally for
`platform=web` before `extension/SConstruct`'s own code runs. The original guard
(`if env["platform"] != "macos":`) re-applied the same transformation on top, wrapping
`env["ARCOM_POSIX"]` in a `TEMPFILE(ARCOM_POSIX)` that referred to itself — SCons' variable
substitution recursed until Python's recursion limit was hit. Fixed by changing the guard to
`if env["platform"] not in ("macos", "web"):`. This is a genuine, previously-latent SConstruct bug:
no prior task had ever run a `platform=web` scons build through this repo's own SConstruct before
(decision-030's spike used its own separate scratch SConstruct, not this one).

**A native Linux `signal 11` inside `neo_snake_library_init` during headless `--import`, seen once
mid-task, did not reproduce after a clean rebuild.** It occurred in a fresh worktree the first time
the native Linux `.so` was rebuilt after the web `.wasm` targets had already been built once in the
same worktree (both write `core/zig-out/lib/libneo_snake.a` sequentially, by design — the same
pattern `extension:build-macos`/`build-windows` already use). `file`/`nm`/`llvm-nm` cross-checks
found the on-disk core archive consistent and native at the time of the crash, and none of this
task's edits touch the native Linux code path, so the exact trigger was not pinned down further; a
`rm -f game/bin/libneo_snake.linux.template_debug.x86_64.so extension/.sconsign.dblite` + rebuild
made it disappear and it did not recur across the rest of this task's verification. Recorded here as
an open loose end, not as a fix, in case a future web+native interleaved build hits it again.

**Godot's `export_filter="all_resources"` does not include every file extension in the project by
default.** `game/tests/corpus/manifest.json` (a recognized `.json` extension) was packed into the
web export's `.pck` automatically, but the corpus trace files themselves
(`game/tests/corpus/*.jsonl`) were silently skipped — `.jsonl` isn't an extension Godot's exporter
auto-includes under "all_resources" the way `.json`/`.txt`/etc. are. This was caught empirically: a
first export attempt built and loaded fine (AC#1), but the web smoke test (AC#2) failed with
`could not open res://tests/corpus/one-turn-per-tick.jsonl` even though `strings` on the resulting
`.pck` showed content that turned out to be a red herring (the path string came from the smoke
test's own compiled script constant, and the `corpus_version` matches came from `manifest.json`, not
the trace files). Fixed by adding `include_filter="*.jsonl"` to `game/export_presets.cfg`'s Web
preset. Silent, not a hard export error, so this is worth flagging for anyone adding a new
non-standard extension under `res://` that a web (or any packed) export needs to actually ship.

## Decision

Ship the real web build with: `-Doptimize=ReleaseSmall` on the wasm32-emscripten core build
(mandatory, not just a size choice); the `ARCOM_POSIX` guard excluding both `macos` and `web`;
`include_filter="*.jsonl"` on the Web export preset; and AC#2 satisfied via a new
`game/platform/web_checksum_smoke_test.gd` (a `Node`, instantiated by `GameScreen._ready()` exactly
like `AppLifecycle`, gated on `OS.has_feature("web")` so it is a no-op on every other platform) that
replays the same `one-turn-per-tick` corpus trace `test_corpus_replay.gd` already uses for its own
corrupted-checksum negative case, tick-by-tick through `SimulationWorld`, and prints
`WEB_CHECKSUM_SMOKE_TEST: PASS`/`FAIL <reason>` to the browser console. Verified empirically with a
headless-Chromium Playwright session (same pattern as decision-030's spike) against the real
project's `--export-debug "Web"` output: `WEB_CHECKSUM_SMOKE_TEST: PASS`, zero `pageerror`s, zero
`console:error` messages, and a real play session (movement, wall-collision death, Game Over
overlay, HUD score) rendering and responding to keyboard input correctly (AC#3).

## Consequences

- A future task adding a new non-`.json`/`.gd`/`.tscn`-style raw data file under `res://` that must
  ship in a packed export needs to check whether it lands in the `.pck` at all, not just whether the
  export step exits zero — `include_filter` is the fix, and this bit silently rather than loudly.
- The native Linux `signal 11` seen once and not reproduced is not root-caused; if it recurs, suspect
  build-order interleaving between web (`wasm32-emscripten`) and native `core:abi-symbols` /
  `extension:build` invocations sharing `core/zig-out/lib/libneo_snake.a` and `extension/.sconsign.dblite`
  in the same worktree, and try a clean rebuild of the affected target first.
- `web_checksum_smoke_test.gd` deliberately duplicates a trimmed-down copy of
  `test_corpus_replay.gd`'s `_replay()` logic for one hardcoded trace, rather than sharing code with
  the gdUnit4 suite, so it can run standalone at boot in an exported build without depending on
  gdUnit4's test-runner being present there.

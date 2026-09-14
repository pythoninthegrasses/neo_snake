---
id: TASK-048
title: Ship the real web build
status: Done
assignee: []
created_date: '2026-09-09 22:16'
labels: []
milestone: m-7
dependencies:
  - TASK-047
priority: medium
type: feature
ordinal: 48000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Ship the real web build of the neo_snake core, depending on the web spike (task-047) passing. lto=none is mandatory — without it, emscripten-clang bitcode and Zig-clang bitcode mix during linking, which is unsupported. Smoke-test that HashingContext (used for the SHA-256 checksum) actually exists and works correctly in the web runtime, since Tier-D's cross-language checksum guarantee depends on it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The real neo_snake core builds and loads as a web export with lto=none
- [x] #2 HashingContext.HASH_SHA256 is smoke-tested in the web runtime and matches the Tier-D checksum for a committed corpus trace
- [x] #3 The web build is playable end-to-end in a browser with no console errors related to the extension
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 task check is green
- [x] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [x] #3 Docs touched by the change are updated in the same commit
- [x] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

## Notes

AC#2 as written names `HashingContext.HASH_SHA256`, a Godot class this codebase never uses — the
real SHA-256 checksum chain is Zig-side (`core/canon.zig`'s `checksum()` via
`std.crypto.hash.sha2.Sha256`, exposed through `core/abi.zig`'s `ns_checksum` and
`extension/src/neo_snake_world.cpp`'s `NeoSnakeWorld::checksum()`), already exercised natively by
Tier-D (`game/tests/test_corpus_replay.gd`). AC#2 is satisfied by extending that same chain to the
web runtime instead: a new `game/platform/web_checksum_smoke_test.gd` (`OS.has_feature("web")`-gated,
instantiated by `GameScreen._ready()` like `AppLifecycle`) replays the `one-turn-per-tick` corpus
trace tick-by-tick and prints `WEB_CHECKSUM_SMOKE_TEST: PASS`/`FAIL <reason>` to the browser console.
Verified with a headless-Chromium Playwright session against the real `--export-debug "Web"` output:
PASS, zero pageerrors, zero console:error, and a real play session (movement, wall-collision death,
Game Over overlay) rendering and responding to input correctly.

Two build-toolchain findings were mandatory to get a working web export at all: Zig 0.16.0 requires
`-Doptimize=ReleaseSmall` for `wasm32-emscripten` (Debug/ReleaseSafe fail on
`std.Io.Threaded`'s `RandomFile` referencing an unbound `posix.system.getrandom` for this target);
and `extension/SConstruct`'s `ARCOM_POSIX` guard needed to exclude `platform=web` as well as
`macos`, since `godot-cpp`'s own `tools/web.py` already applies the same ar-response-file fix,
and doubling it caused unbounded SCons variable-substitution recursion. Separately, Godot's
`export_filter="all_resources"` silently drops `.jsonl` files from the exported `.pck` (a
previously-unknown gotcha, unrelated to any error/warning at export time) — fixed with
`include_filter="*.jsonl"` on the Web preset, without which the smoke test above could never find
its corpus trace in a real export.

Full details, code excerpts, and the open (non-reproduced) native-Linux segfault loose end are in
[[decision-031]] and `docs/build-layout.md`'s new TASK-048 section.

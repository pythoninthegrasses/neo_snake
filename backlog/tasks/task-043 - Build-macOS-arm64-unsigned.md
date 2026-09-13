---
id: TASK-043
title: 'Build macOS arm64, unsigned'
status: Done
assignee: []
created_date: '2026-09-09 22:15'
labels: []
milestone: m-7
dependencies:
  - TASK-042
priority: high
type: feature
ordinal: 43000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Produce an unsigned macOS arm64 build of the extension and game: -Dtarget=aarch64-macos for the Zig core plus scons platform=macos arch=arm64 for the extension, output as a framework-style bundle (libneo_snake.macos.<target>.framework/...) matching the macos.debug/macos.release keys the .gdextension expects. This is the primary platform per the corresponding backlog/decisions/ entry (macOS-first, Linux-secondary), and the one that builds natively rather than through a cross toolchain.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 task check is fully green on darwin/arm64, including Tier-D
- [x] #2 The build produces a libneo_snake.macos.<target>.framework bundle matching the .gdextension's macos.debug/macos.release keys
- [x] #3 The Task target is gated with platforms: [darwin/arm64] so it does not silently attempt to run on Linux
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 task check is green
- [x] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [x] #3 Docs touched by the change are updated in the same commit
- [x] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

## Implementation Notes

Ran the full gate natively on a real Apple Silicon host (`mini`, macOS, Xcode 26.6) rather than
guessing at cross-platform correctness. Three build/tooling gaps only surface on a genuine native
macOS build; all three, their exact failure signatures, and the decision made for each are recorded
in [[decision-026]] and summarized in `docs/build-layout.md`'s new TASK-043 section:

1. **`-Wl,-ld_classic`** added to `extension/SConstruct`'s macOS `LINKFLAGS` — Apple's newer default
   linker ("ld-prime", Xcode 26+) rejects `core/zig-out/lib/libneo_snake.a` at final-link time over
   Mach-O archive-member alignment; the older `ld_classic` linker does not enforce this.
2. **`taskfiles/extension.yml`'s `build:` task gated `platforms: [linux]`** — a bare `scons` on macOS
   defaults `arch=universal`, which cannot link against the single-arch core static library.
   `extension:build-macos` (already gated `platforms: [darwin/arm64]`, satisfying AC#3) is the sole
   macOS path, pinning `arch=arm64` explicitly for both `template_debug` and `template_release`.
3. **`taskfiles/audio.yml`'s `music-check:` task gated `platforms: [linux]`** — Furnace's synthesis is
   cross-platform deterministic, but the OGG Vorbis encode step is not bit-exact across
   platforms/builds (max abs sample diff ≈0.014, ~3.8% of samples differ between a macOS arm64 render
   and the Linux-rendered committed asset), so exact-sample-equality only holds on the platform the
   committed `.ogg` was actually rendered on. Confirmed with the user before gating (chose "gate to
   Linux only" over adding a numeric tolerance).

Verified end to end on `mini`: `task check` runs `extension:build-macos` in place of `extension:build`,
reaches `audio:music-check` which silently no-ops per go-task's `platforms:` allow-list semantics, and
the whole chain exits 0 — 119/119 gdUnit4 test cases pass, both `libneo_snake.macos.template_debug
.framework` and `libneo_snake.macos.template_release.framework` bundles are produced matching
`game/bin/neo_snake.gdextension`'s `macos.debug`/`macos.release` keys, and `extension:build` (Linux)
still passes unaffected.

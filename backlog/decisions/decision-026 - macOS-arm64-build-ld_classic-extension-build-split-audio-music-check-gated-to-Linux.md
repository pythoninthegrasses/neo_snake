---
id: decision-026
title: 'macOS arm64 build: ld_classic, extension:build split, audio:music-check gated to Linux'
date: '2026-09-13 00:00'
status: Accepted
---
## Context

TASK-043 requires `task check` to be fully green natively on darwin/arm64 (AC#1), including Tier-D.
Running the real gate end to end on an actual Apple Silicon machine (`mini`, macOS, Xcode 26.6)
surfaced three build/tooling incompatibilities that don't exist on the Linux x86_64 host this repo
was previously only ever verified on. None of these are deviations from `reference/snake.html`'s
behavior — they're build-tooling decisions, the same category `decision-025` (`sway`+`wtype`+`grim`
substituted for `xvfb-run`) already established a precedent for recording here.

**1. Mach-O archive-alignment link failure.** `extension/SConstruct`'s final link step against
`core/zig-out/lib/libneo_snake.a` (produced by `zig build abi`) failed under Xcode 26.6's default
linker ("ld-prime") with `ld: 64-bit mach-o member 'libneo_snake_zcu.o' not 8-byte aligned in
... libneo_snake.a`. Zig's own archiver doesn't 8-byte-align every member; Apple's newer linker
enforces that where the older `ld_classic` (still shipped, deprecated) does not. Confirmed directly
against the real archive on `mini` before applying a fix.

**2. `scons`'s `arch=universal` default on macOS.** The pre-existing `extension:build` task invokes a
bare `scons` with no `arch=`/`platform=` override. On Linux this resolves to the host's native arch
and links fine. On macOS, `scons` defaults `platform=macos` to `arch=universal` (an x86_64 + arm64 fat
binary) — but `core/zig-out/lib/libneo_snake.a` is single-arch (whatever `zig build abi` natively
targets, arm64 on `mini`), so the universal link fails with `ld: symbol(s) not found for architecture
x86_64`. The pre-existing `extension:build-macos` task (added in an earlier TASK-043 iteration)
already pins `arch=arm64` explicitly for both `template_debug`/`template_release`, so it doesn't hit
this — the bare `extension:build` task is the one that can't coexist with a native macOS run.

**3. OGG Vorbis encoding is not cross-platform bit-exact.** `audio:music-check`'s `--all --check` step
decodes both a fresh Furnace render and the committed `game/content/audio/music/*.ogg` back to PCM and
requires exact sample equality (`np.array_equal`). Furnace's synthesis itself is cross-platform
deterministic — a fresh render on `mini` produced the identical 564482-sample shape as the Linux
render. But the subsequent WAV→OGG(Vorbis) encode step (libsndfile/libvorbis) introduces small
platform/build-dependent floating-point differences: max absolute sample difference ≈0.0139, mean
≈2.2e-5, ~3.8% of all sample-values (43,030 of 1,128,964) nonzero-different between a macOS arm64
render and the Linux-rendered committed asset. This had never been exercised before, since `task
check` had never previously run on macOS. Flagged to the user before deciding (three options: gate to
Linux only, add a numeric tolerance, or stop for more design thought) — the user chose gating.

## Decision

**`extension/SConstruct`** appends `-Wl,-ld_classic` to `LINKFLAGS` inside its `env["platform"] ==
"macos"` branch, only for macOS — Linux is unaffected (`extension:build` still passes with no
LINKFLAGS change).

**`taskfiles/extension.yml`'s `build:` task is gated `platforms: [linux]`.** `extension:build-macos`
(already `platforms: [darwin/arm64]`-gated) is the sole macOS path, pinning `arch=arm64` explicitly —
the same platform-split pattern `parity:capture` already established (`platforms: [linux]`).

**`taskfiles/audio.yml`'s `music-check:` task is gated `platforms: [linux]`.** Exact-sample-equality
against the committed `.ogg` only holds on the platform that asset was actually rendered on (Linux);
`music-render`/the asset itself are unaffected — only the `--check` comparison, which is meaningless
across a lossy encoder's platform-dependent output, is gated. Chosen over an add-a-tolerance
alternative: a numeric epsilon would have to be picked without a principled bound (this is encoder
noise, not a modeled error source) and would silently weaken the check's actual guarantee (byte/sample
exactness) for every platform, not just document a real cross-platform limit.

## Consequences

- `task check` on macOS runs `extension:build-macos` instead of `extension:build`, and skips
  `audio:music-check` entirely (silently, per go-task's `platforms:` allow-list semantics) — both are
  by-design absences confirmed in the passing `mini` run, not missing coverage.
- Regenerating `game/content/audio/music/*.ogg` (`audio:music-render`) must continue to happen on
  Linux to keep the committed assets canonical; a macOS-rendered `.ogg` would not itself be wrong, but
  would only pass `--check` on the machine that rendered it, defeating the check's purpose as a
  committed-asset guarantee.
- Any future asset/check pipeline with a lossy cross-platform encode step in this repo should default
  to this same platform-gating pattern rather than a tolerance-based comparison, absent a principled
  error bound.

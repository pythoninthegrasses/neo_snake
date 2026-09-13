---
id: decision-028
title: 'Linux x86_64 Docker build: glibc floor pinned to Godot''s own 2.28, deliverable scoped to the .so'
date: '2026-09-13 18:18'
status: Accepted
---
## Context

TASK-045 asks for a Dockerized Linux x86_64 build that produces identical output whether invoked
from a macOS or Linux host (AC#1), settles what glibc floor the GDExtension should link against
(AC#2), and runs Tier-A/B/C inside the container (AC#3). Three questions needed answers before any
Dockerfile could be written.

**1. What does "the Linux build" actually deliver?** TASK-043 (macOS arm64, [[decision-026]]) already
established the precedent: a platform "build" task's deliverable is the built GDExtension bundle
itself, not a full packaged game export — TASK-044 ([[decision-027]]) is the separate task that owns
packaging/signing, and it's macOS-only. `game/bin/neo_snake.gdextension` only declares a
`linux.debug.x86_64` key (no `linux.release.x86_64`), and the pre-existing `extension:build` task
already only builds `template_debug` for Linux. By the same precedent, TASK-045's deliverable is
`game/bin/libneo_snake.linux.template_debug.x86_64.so` — not a Godot export, and not a release-target
variant that isn't wired anywhere yet.

**2. What does "Tier-A/B/C" map to in this repo's task graph?** Reading `taskfiles/core.yml`: Tier-A
is `core:test`'s rng/canon/world unit tests (`zig build test`); Tier-B is the fuzz_seeds invariants
bundled into that same step plus `core:difftest` (Zig-internal corpus replay against
`core/world.zig` directly — no ABI, no Godot); Tier-C is `core:abitest` (Zig-via-C-ABI conformance
through `@cImport` of `include/neo_snake.h`, gated on `core:abitest-purity`). Tier-D
(`game:test`, GDScript-via-GDExtension gdUnit4 corpus replay) needs a full Godot install and is
explicitly out of scope for AC#3. So "Tier-A/B/C" is exactly `task core:test core:difftest
core:abitest` — a Zig-only toolchain plus `uv` (for the purity-check script), no Godot, no SCons, no
godot-cpp needed for the `check` stage at all.

**3. What glibc floor should the build target?** Measured directly rather than guessed: downloaded
Godot 4.7.1-stable's own official export templates archive (checksum-verified against
`tools/game_toolchain.lock`'s pin) and ran `objdump -T` against the shipped
`templates/linux_release.x86_64` binary. The highest referenced symbol version is **GLIBC_2.28** —
that's the floor the engine itself already requires, so pinning the GDExtension to the same floor
means it never demands a newer glibc than Godot already does, independent of whatever glibc the
build container's own base image happens to ship. Zig's target-triple syntax
(`x86_64-linux-gnu.2.28`) pins this exactly, using Zig's bundled multi-version glibc ABI stubs — this
works regardless of the actual glibc on the machine doing the build. Verified end to end: `zig build
abi -Dtarget=x86_64-linux-gnu.2.28` succeeds, and the resulting `.so`'s own highest referenced symbol
(`objdump -T`) is `GLIBC_2.16`, comfortably under both the 2.28 pin and Godot's own 2.28 floor.

## Decision

**`docker/linux/Dockerfile`** is a five-stage build (`deps` → `src` → `check` / `build` →
`artifacts`), mirroring `~/git/mt`'s Dockerfile shape:
- `deps`: `debian:trixie-slim` pinned by digest (not just tag), with Zig/`task`/`uv` downloaded and
  `sha256sum -c`-verified against this repo's own `.tool-versions` pins (matching
  `tools/game_toolchain.lock`'s own checksum-verification convention, not an unverified
  `curl | sh`), and `scons` installed via `pipx` (matching `.tool-versions`' `pipx:scons` entry, not
  `apt`).
- `check`: `task core:test core:difftest core:abitest` (Tier-A/B/C, AC#3) — no Godot/SCons/godot-cpp
  needed.
- `build`: `task extension:build ZIG_TARGET_FLAG="-Dtarget=x86_64-linux-gnu.2.28"` (AC#2).
- `artifacts`: a `scratch` stage that `COPY --from=build`s just the built `.so`, extracted to the
  host via `docker build --target artifacts --output type=local,dest=dist .`.

**`taskfiles/extension.yml`'s `build:` task gains an optional `ZIG_TARGET_FLAG` var**, mirroring the
mechanism `extension:build-macos` already had for pinning `-Dtarget=aarch64-macos`. Left empty
(the default), `extension:build` is unchanged from before this task — this is purely additive.

**AC#1's cross-host claim is verified by construction, not by an actual macOS-host Docker run.**
`mini` (the only macOS host available for real-hardware verification in this environment) has no
Docker installed. Rather than fabricate a cross-host test that didn't happen, this is documented
honestly as: pinned base-image digest + checksummed toolchain downloads + no host-arch-conditional
`RUN` step in the Dockerfile means the container's own build environment is identical regardless of
which host's Docker daemon executes it. The test that *was* actually run: the `artifacts` stage was
built twice independently (`docker build --target artifacts --output type=local,dest=dist` into two
separate output directories, no shared BuildKit cache reused between them) and the two resulting
`.so` files are byte-identical (`sha256sum` match exactly, same size, same `objdump -T` symbol
table). A stray non-Docker local test build (run directly on this host, for an earlier sanity check
before the Dockerfile existed) produced a `.so` with a *different* sha256 than either Docker build —
expected, not a reproducibility bug: it embeds a different absolute build path (`/build` in-container
vs. this worktree's own path on disk) in its build metadata, which two Docker builds never do since
they always build at the same in-container path.

## Consequences

- `docker/linux/Dockerfile` and `.dockerignore` are new, standalone build artifacts — not wired into
  `task check`'s own chain (same precedent as `taskfiles/release.yml` being excluded from `check:`).
- The Linux Docker build only ever produces the `template_debug` target, matching
  `game/bin/neo_snake.gdextension`'s current `linux.debug.x86_64` key. Adding a
  `linux.release.x86_64` variant is out of scope here and would need its own task, the same way
  TASK-043's `template_release` framework was in scope for macOS but a Linux release target isn't
  wired anywhere yet.
- Any future Docker build added to this repo for another platform should follow this same
  digest-pinning + checksum-verified-download pattern for auditability, and should default to
  documenting cross-host equivalence "by construction" honestly when a real second host isn't
  available, rather than skipping the claim or fabricating a run.

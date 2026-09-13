---
id: decision-029
title: 'Windows x86_64 mingw cross build: neo_snake.lib naming, ntdll link, 2-key .gdextension'
date: '2026-09-13 18:50'
status: Accepted
---
## Context

TASK-046 asks for a Windows x86_64 build, picking between route (a) mingw cross-compilation from
Linux or (b) a native Windows CI runner (AC#1), passing Tier-A/B/C at minimum (AC#2), and
documenting that a `-windows-gnu`-built lib is never linked against an MSVC toolchain (AC#3).

**Route (a) vs (b).** The task's own Description already states a preference: "(a) for the
extension since the ABI boundary is pure C with no libc dependency crossing it; fall back to (b)
only if code signing becomes a hard requirement." No code-signing requirement applies to a
GDExtension `.dll` (unlike TASK-044's macOS `.app` packaging/notarization, [[decision-027]]) — so
route (a) is chosen outright, matching TASK-045's own Linux-Docker precedent ([[decision-028]]) of
cross-building from Linux rather than standing up a second native CI runner per platform.

**Zig produces `neo_snake.lib`, not `libneo_snake.a`, for a windows-gnu target.** `zig build abi
-Dtarget=x86_64-windows-gnu` names its static library output `neo_snake.lib` — still a plain `ar`
archive of COFF objects underneath (confirmed via `file`), just Windows' own conventional
extension, not an MSVC-style COFF import library. `nm -g --defined-only` works unmodified against
it, showing the same unprefixed `ns_*` symbol names as the native ELF build (Windows x86_64 doesn't
prepend an underscore to cdecl symbols, unlike Mach-O) — so `taskfiles/core.yml`'s `abi-symbols`
task needed no logic change, only a parameterized filename (`CORE_LIB_NAME`, default
`"libneo_snake.a"`, unchanged for every other target). `extension/SConstruct`'s core-lib-linking
line picks the matching filename via `env["platform"] == "windows"`.

**godot-cpp/SCons cannot use `zig cc` as a drop-in C++ cross compiler for the GDExtension shim
itself.** `third_party/godot-cpp/tools/windows.py`'s cross-compile branch hardcodes real
mingw-w64 toolchain binary names (`x86_64-w64-mingw32-g++`/`-gcc`/`-gcc-ar`/`-ranlib`, or the
`-clang` variants under `use_llvm=yes`) — only the Zig-compiled `core/` static library can use
Zig's own bundled cross-toolchain; the shim's own `.cpp` sources and godot-cpp's generated bindings
still need a genuine `x86_64-w64-mingw32-*` toolchain (Debian's `g++-mingw-w64-x86-64` package,
`14.2.0-17+27` on `trixie`) on `PATH`.

**The final Windows link needs an explicit `-lntdll`.** Cross-building `docker/windows/Dockerfile`'s
`build` stage initially failed at the final `.dll` link (mingw's own `ld`, invoked by SCons) with
`undefined reference to 'NtAllocateVirtualMemory'` / `'NtFreeVirtualMemory'`. Root cause: Zig's
windows-gnu std lib compiles panic/stack-guard machinery that references these raw `ntdll.dll`
syscalls into every build (even one that never panics), and a native `zig build-exe` resolves them
itself at final-link time — but `core/zig-out/lib/neo_snake.lib` is only a static archive, so that
resolution is deferred to whoever performs the actual final link, which here is mingw's own `ld`
under godot-cpp's `-Wl,--no-undefined` (`tools/windows.py`). mingw-w64 ships an import library for
exactly this (`/usr/x86_64-w64-mingw32/lib/libntdll.a`, confirmed present in the
`g++-mingw-w64-x86-64` package) — `extension/SConstruct` now appends `LIBS=["ntdll"]` when
`env["platform"] == "windows"`. Verified fixed: both `template_debug` and `template_release` link
cleanly after this change.

**Exactly two new `.gdextension` keys are needed, not four.** The task's own Description
speculatively estimated "four additional .gdextension keys" for Windows support. Checking
godot-cpp's own reference project (`third_party/godot-cpp/test/project/my_test.gdextension`) shows
the correct convention is one key per (target, arch) pair — `windows.debug.x86_64` and
`windows.release.x86_64` — exactly two keys for one architecture's debug+release pair, matching
the existing `linux.debug.x86_64` key's own shape. The task's four-key estimate is superseded by
this measurement; proceeding with the godot-cpp-convention-correct two-key form.

## Decision

**Route (a), mingw cross-compilation from Linux**, implemented as:

- `taskfiles/core.yml`'s `abi-symbols` task gains an optional `CORE_LIB_NAME` var (default
  `"libneo_snake.a"`, unchanged for every existing caller) so the `nm`-based symbol check can target
  `zig-out/lib/neo_snake.lib` instead.
- `extension/SConstruct` picks `core_lib_name = "neo_snake.lib"` when `env["platform"] ==
  "windows"`, else `"libneo_snake.a"`, and appends `LIBS=["ntdll"]` for the windows platform only.
- `taskfiles/extension.yml` gains `build-windows:`, mirroring `build-macos:`'s shape: rebuild
  `core/zig-out/lib/neo_snake.lib` pinned to `-Dtarget=x86_64-windows-gnu`, then run `scons
  platform=windows use_mingw=yes use_static_cpp=yes arch=x86_64` once per `target=template_debug`
  and `target=template_release`. Gated `platforms: [linux]` (always a cross-build from Linux, never
  run natively) and not wired into the root `check:` chain — same Docker-only-path precedent as
  `extension:build-macos`/`extension:build` (TASK-045).
- `game/bin/neo_snake.gdextension` gains `windows.debug.x86_64` and `windows.release.x86_64`,
  pointing at `libneo_snake.windows.template_debug.x86_64.dll` and
  `.../template_release.x86_64.dll`.
- `docker/windows/Dockerfile` mirrors `docker/linux/Dockerfile`'s five-stage shape (`deps` installs
  Debian's `g++-mingw-w64-x86-64` alongside the same pinned+checksummed Zig/`task`/`uv`/`scons` as
  the Linux container; `check` runs Tier-A/B/C; `build` runs `task extension:build-windows`;
  `artifacts` extracts both `.dll`s via a `scratch` stage).

**AC#3 (MSVC-ABI incompatibility) is documented in three places**: this decision, the
`extension:build-windows` task's own `summary:` doc-comment (`taskfiles/extension.yml`), and
`docs/build-layout.md`'s TASK-046 section — MinGW's and MSVC's Itanium vs. Microsoft C++
ABI/name-mangling are not compatible, even though the plain-C ABI `include/neo_snake.h` exposes
across the Zig/C++ boundary is itself unaffected by this.

**Verified end to end, not just by construction**: `docker build --target check` (Tier-A/B/C) and
`docker build --target artifacts --output type=local,dest=<dir>` (the actual `extension:build-windows`
task) were both run against this repo's own worktree. The extracted
`libneo_snake.windows.template_debug.x86_64.dll` and `.../template_release.x86_64.dll` are genuine
PE32+ DLLs (`file`), and `objdump -p` on the release build shows imports from only `KERNEL32.dll`,
`msvcrt.dll`, and `ntdll.dll` — no `libgcc_s_seh-1.dll`/`libstdc++-6.dll`/`libwinpthread-1.dll`
MinGW runtime dependency, confirming `use_static_cpp=yes` statically linked MinGW's own
libgcc/libstdc++ as intended (mirroring TASK-043's macOS `use_static_cpp` rationale).

## Consequences

- `docker/windows/Dockerfile` and `taskfiles/extension.yml`'s `build-windows:` task are new,
  standalone build artifacts, gated `platforms: [linux]` and excluded from `task check`'s own chain
  — same precedent as the Linux Docker path (TASK-045) and the macOS build path (TASK-043).
- `CORE_LIB_NAME` and the `env["platform"] == "windows"` branch in `SConstruct` are the only changes
  to shared (non-Windows-specific) files; both default to the pre-TASK-046 behavior, so
  `extension:build`/`core:abi-symbols`'s native Linux/macOS paths are unaffected.
- Any future platform build added to this repo that produces a static archive Zig cross-compiled
  for a non-native target should check, the same way this task did, whether Zig's std lib pulls in
  target-OS syscalls that the final linker won't resolve automatically from a bare static archive —
  this is not unique to Windows/ntdll, just the first time it surfaced.
- A Windows CI runner (route (b)) remains available as a fallback if a future requirement (e.g.
  code-signing the `.dll`) makes it necessary; nothing here forecloses adding one later.

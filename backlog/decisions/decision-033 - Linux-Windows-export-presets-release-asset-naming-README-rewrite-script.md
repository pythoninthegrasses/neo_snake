---
id: decision-033
title: Linux/Windows export presets authored from scratch; per-platform asset naming; README rewrite script
status: Accepted
date: 2026-09-13
---

## Context

TASK-050 publishes per-platform release assets and wires a README download table. Two gaps existed
before this task: `extension:build` only ever produced a `template_debug` GDExtension on Linux (no
`template_release` key, since godot-cpp's own `tools/godotcpp.py` defaults `target=` to
`template_debug` when unset), and `game/export_presets.cfg` had only macOS ([[decision-026]]) and
Web ([[decision-031]]) presets — no Linux or Windows preset existed to export against, and no prior
art in this repo showed what one should look like.

## Decision

**`extension:build` now runs `scons` twice** (`target=template_debug` then `target=template_release`),
mirroring `build-macos`/`build-windows`/`build-web`'s already-established two-scons-call pattern,
rather than adding a parallel `build-release` task. `game/bin/neo_snake.gdextension` gained a
`linux.release.x86_64` key pointing at the new binary. `docker/linux/Dockerfile`'s `artifacts` stage
extracts both the debug and release `.so` now.

**Two new export presets were authored from Godot 4.x conventions** (no prior Linux/Windows preset
existed to copy) and validated empirically via real `--export-release` runs, not left as an
unverified guess:

- `[preset.2]` "Linux" — `export_path="build/linux/neo_snake.x86_64"`, `include_filter="*.jsonl"`
  (mirroring the Web preset's TASK-048 corpus-trace fix — Godot's `all_resources` filter does not
  automatically include every extension), `binary_format/architecture="x86_64"`.
- `[preset.3]` "Windows" — `export_path="build/windows/neo_snake.exe"`, same `include_filter` fix,
  all `codesign/*` fields disabled since neo_snake's Windows build path has no code-signing
  ([[decision-029]]).

Both were confirmed via direct export testing to place the release GDExtension binary flat next to
the executable in the export output directory (not nested under a `res://bin/`-mirroring path),
which is why the packaging tasks below list flat filenames directly.

**Asset naming, chosen so a filename-substring match is unambiguous per platform** (the README
rewrite script and `gh release upload` both key off this):

- macOS: `Neo Snake.dmg` (Godot's own DMG packaging, unchanged from TASK-044, no separate packaging
  task needed).
- Linux: `neo_snake-linux-x86_64.tar.gz` (`tar`).
- Windows: `neo_snake-windows-x86_64.zip` (`zip -j`, flattening paths).
- Web: `neo_snake-web.zip` (`zip -r` of the whole `build/web/` directory, `-x` self-excluding so a
  rerun doesn't zip a stale copy of its own previous archive into the new one).

`.zip` alone is not unique between Windows and Web, so the README rewrite script
(`tools/update_readme_downloads.py`) matches on `"windows"`/`"web"` substrings in the filename, not
the extension.

`taskfiles/release.yml` gained `export-*`/`package-*`/`ship-*` task triads for Linux/Windows/Web,
matching the established `ship-macos` shape (`preconditions:` guarding each `package-*` task on its
`export-*` task's expected output, `platforms: [linux]` gating matching the sibling build tasks).

**`.github/workflows/release.yml` is a new, separate workflow** (not folded into the existing
`ci.yml`), triggered by `release: {types: [published]}` plus `workflow_dispatch` (with a
`release-tag` input for manual/dry-run testing). Four platform jobs (`macos`, `linux`, `windows`,
`web`) each build their GDExtension, run `task release:ship-<platform>`, and `gh release upload
--clobber` the resulting asset via a thin `task ci:release-<platform>` wrapper (matching TASK-049's
"every CI step is one `task ci:<target>` call" convention — no build or upload logic lives directly
in the workflow YAML). A final `update-readme` job (`needs: [macos, linux, windows, web]`, `if:
always() && !cancelled() && contains(needs.*.result, 'success')`) runs `tools/update_readme_downloads.py`
against the release tag and commits+pushes to `main` as `github-actions[bot]` with `[skip ci]` only
if the table actually changed — so a partial release (some platform jobs failed) still gets whatever
assets did land reflected in the README, and a job with nothing to commit doesn't create an empty
commit.

The Linux/Windows/Web jobs use `jdx/mise-action@v2` to install the full `.tool-versions`-pinned
toolchain on `ubuntu-latest` (not previously used in any workflow in this repo, but a natural fit —
`.tool-versions` already pins everything these jobs need: `godot`, `zig`, `task`, `uv`,
`pipx:scons`), rather than a per-tool `setup-*` action per dependency.

## Consequences

- `tools/update_readme_downloads.py` (new) queries `gh api repos/{owner}/{repo}/releases/tags/{tag}`,
  matches assets to a fixed, hardcoded platform order (not whatever order the API returns assets
  in — this is what makes a second run against the same release byte-identical, satisfying AC#3),
  and rewrites only the content between `README.md`'s new `<!-- DOWNLOADS:START -->`/`<!--
  DOWNLOADS:END -->` markers.
- A platform with no matching asset in a given release is simply omitted from the table (a partial
  release, e.g. one platform job failed) rather than erroring — the script renders whichever
  platforms actually published, in a fixed order.
- `taskfiles/ci.yml` gained five new tasks (`release-macos`, `release-linux`, `release-windows`,
  `release-web`, `update-readme`), each `requires: vars: [RELEASE_TAG]` so a missing tag fails loudly
  rather than uploading to the wrong release or silently no-oping.

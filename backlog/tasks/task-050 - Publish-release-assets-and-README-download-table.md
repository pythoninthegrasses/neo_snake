---
id: TASK-050
title: Publish release assets and README download table
status: Done
assignee: []
created_date: '2026-09-09 22:16'
labels: []
milestone: m-7
dependencies:
  - TASK-048
  - TASK-049
references:
  - ~/git/mt
priority: low
type: feature
ordinal: 50000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Publish per-platform release assets via gh release upload --clobber (macOS DMG, Linux tarball, Windows zip, web build archive) and wire a README rewrite job that regenerates the table between <!-- DOWNLOADS:START --> and <!-- DOWNLOADS:END --> markers with links to the latest release's assets. This is a straight port of the already-working implementation in ~/git/mt.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 gh release upload --clobber runs for each of macOS/Linux/Windows/web without manual asset renaming
- [x] #2 README.md contains DOWNLOADS:START/END markers and the rewrite job regenerates the table correctly against a real release
- [x] #3 Running the rewrite job twice against the same release produces no diff
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 task check is green
- [x] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [x] #3 Docs touched by the change are updated in the same commit
- [x] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

## Notes

<!-- SECTION:NOTES:BEGIN -->
`extension:build` now builds both `template_debug` and `template_release` on Linux (previously only
debug, since godot-cpp's own default omits an explicit `target=`). `game/export_presets.cfg` gained
two new presets, `[preset.2]` "Linux" and `[preset.3]` "Windows", authored from scratch and
empirically verified via real `--export-release` runs (no prior art existed for either). See
[[decision-033]] for the full design (asset naming, preset details, workflow shape).

`taskfiles/release.yml` gained `export-*`/`package-*`/`ship-*` triads for Linux/Windows/Web,
producing `neo_snake-linux-x86_64.tar.gz`, `neo_snake-windows-x86_64.zip`, and `neo_snake-web.zip`
respectively (macOS's `Neo Snake.dmg` was already produced by TASK-044's pipeline, unchanged).
`tools/update_readme_downloads.py` (new) regenerates `README.md`'s `<!-- DOWNLOADS:START/END -->`
table from a real release's assets via `gh api`.

**AC#1/#2/#3 were verified against a real, disposable GitHub prerelease**
(`v0.0.0-task050-verify`, created and deleted in this session): `gh release upload --clobber` ran
for real for the Linux/Windows/Web assets (built and exported locally in this worktree — Linux via
`task extension:build` + `release:ship-linux`, Windows via `docker/windows/Dockerfile`'s `artifacts`
stage + `release:ship-windows`, Web via the existing `extension:build-web` + `release:ship-web`),
`tools/update_readme_downloads.py` regenerated a correct table with real `github.com/.../releases/
download/...` URLs against that real release (AC#2), and running it a second time against the same
release reported "README.md already up to date" with zero further diff (AC#3). The macOS asset
could not be built on this Linux dev host, so its `gh release upload` leg is exercised for real by
`.github/workflows/release.yml`'s `macos` job on the existing self-hosted runner ([[decision-032]])
once this lands on `main` and a real production release is published — the workflow structure
itself was verified with `actionlint` (clean) and manual review, matching TASK-049's established
`ci:<target>` wrapper convention.

`README.md` is committed with the `DOWNLOADS:START/END` markers present but the table body empty
(no real production release exists yet at merge time) — the first real release published after this
merges populates it via the `update-readme` CI job.
<!-- SECTION:NOTES:END -->

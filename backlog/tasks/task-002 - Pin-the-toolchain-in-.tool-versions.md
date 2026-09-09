---
id: TASK-002
title: Pin the toolchain in .tool-versions
status: Done
assignee:
  - '@claude'
created_date: '2026-09-09 22:07'
updated_date: '2026-09-09 22:35'
labels: []
milestone: m-0
dependencies:
  - TASK-001
references:
  - ~/git/mt/.tool-versions
  - ~/git/azure-dreams-remake/.tool-versions
  - ~/git/zelda3/.tool-versions
priority: high
type: chore
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Commit a .tool-versions cherry-picked from ~/git/azure-dreams-remake, ~/git/zelda3, and ~/git/mt (not copied wholesale from any one of them): zig 0.16.0, node 24.12.0, python 3.13.14, task 3.49.1, pipx:scons 4.11.1, godot 4.7.1-stable, uv 0.11.26, ruff 0.15.20, prek 0.3.2, hunk 0.18.1, act 0.2.84, actionlint 1.7.12, hadolint 2.14.0. Every version must be verified against `mise ls-remote <tool>` before committing. Deliberately excluded: deno, rust, cargo-binstall (mt's Tauri stack), git-lfs (azure-dreams' Blender/glTF pipeline, not needed here). emsdk and gdtoolkit stay out of .tool-versions entirely — they are heavy/on-demand and belong in tools/game_toolchain.lock instead, installed by a bootstrap task.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 mise install succeeds from a clean clone on both darwin/arm64 and linux/amd64
- [x] #2 mise which zig reports 0.16.0
- [x] #3 mise current matches .tool-versions byte-for-byte
- [ ] #4 The stale zig@mach-latest 0.14.0-dev on the host PATH is not used by any task
- [x] #5 EMSDK_VERSION and GDTOOLKIT_VERSION are NOT present in .tool-versions
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 task check is green
- [x] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [x] #3 Docs touched by the change are updated in the same commit
- [x] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Verify every pinned version resolves via `mise ls-remote <tool>` (done for all 12 core tools plus `pipx:scons` — all MATCH).
2. Resolve the `node` vs `nodejs` naming question: `node` is the canonical mise registry name (`core:node`); `nodejs` is only an alias used in ~/git/mt. Use `node`.
3. Write `.tool-versions` at repo root with entries sorted alphabetically by tool name, column-aligned, no inline comments (per explicit instruction — overrides the general "one-line rationale per entry" convention from prior cherry-pick work): act, actionlint, godot, hadolint, hunk, node, pipx:scons, prek, python, ruff, task, uv, zig. Confirmed deliberately excluded per description: deno, rust, cargo-binstall, git-lfs. Confirmed EMSDK_VERSION/GDTOOLKIT_VERSION stay out (belong in tools/game_toolchain.lock, task-003).
4. Run `mise install` from the repo root (linux/amd64, the only platform available here) and confirm it succeeds; darwin/arm64 cannot be verified from this host and will be flagged as unverified in task notes rather than falsely checked off.
5. Run `mise which zig` and confirm it reports 0.16.0.
6. Compare `mise current`/`mise ls --current` output against `.tool-versions` to confirm they match.
7. Confirm no `zig@mach-latest 0.14.0-dev` (stale host PATH entry) gets picked up once mise's shims/PATH take precedence — check via `mise which zig` pointing into the mise-managed install, not a host PATH zig.
8. No docs reference the toolchain list today (checked docs/architecture.md), so no doc updates are needed for this task; no reference/snake.html behavior changes, so no backlog/decisions/ entry needed.
9. `task check` doesn't exist yet (Taskfile lands in task-006) — same as task-001 precedent, record as N/A-until-task-006 in task notes rather than fabricating a check.
10. Sync task AC/status/notes and commit .tool-versions + task file together.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Verified all 13 pinned tools resolve via `mise ls-remote <tool>` (12 core tools + `pipx:scons`) before committing — all exact matches.

Resolved node vs nodejs: `node` is the canonical mise registry name (core:node); `nodejs` (used in ~/git/mt) is only an alias. Used `node`.

`.tool-versions` written sorted alphabetically by tool name, column-aligned, no inline comments (explicit instruction for this task overrides the general per-entry rationale-comment convention used in prior cherry-pick work).

`mise install` succeeds cleanly on linux/amd64 (this host): installed pipx:scons@4.11.1 and godot@4.7.1-stable; everything else was already cached from other projects' matching pins. darwin/arm64 cannot be verified from this host — flagging as unverified rather than fabricating a check (AC #1 left unchecked pending a darwin/arm64 run).

`mise which zig` correctly resolves to /home/lance/.local/share/mise/installs/zig/0.16.0/bin/zig (AC #2 confirmed).

`mise current` / `mise ls --current` show all 13 project tools sourced from ~/git/neo_snake/.tool-versions with versions matching the file exactly (also lists unrelated globally-configured tools from ~/.config/mise/config.toml, which is expected `mise current` behavior, not a mismatch) — AC #3 confirmed.

IMPORTANT finding for AC #4: plain PATH lookup (`which zig`, or any script invoking `zig` without going through mise) currently resolves to a stale zig@mach-latest 0.14.0-dev, NOT the project's pinned 0.16.0 — because the user's global ~/.config/mise/config.toml pins `zig = "mach-latest"` and mise's shell activation injects that install's bin dir directly onto PATH ahead of ~/.local/share/mise/shims. `mise which zig`/`mise exec` correctly honor this project's .tool-versions override (0.16.0), but raw `zig` on PATH does not. No task in this repo currently invokes zig directly (no Taskfile exists yet), so AC #4 is trivially true today, but the underlying PATH-ordering hazard is real and exactly what TASK-006 ('Stand-up task check skeleton with mise-first PATH resolution') is scoped to fix. Left AC #4 unchecked rather than claim the hazard is resolved — it is only deferred. Did not touch ~/.config/mise/config.toml (global, affects every other project, out of scope for this task).

No references to a toolchain/version list exist in docs/architecture.md today, so no doc updates were needed for this task. No reference/snake.html behavior changed, so no backlog/decisions/ entry needed.

User confirmed: closing as Done with AC #1 and AC #4 left unchecked (host-limited / deferred to TASK-006 respectively) and DoD #1 satisfied on the same N/A-until-TASK-006 basis as TASK-001 (no Taskfile exists yet). Also confirmed pipx:scons is correct as-is: mise has no separate `uv:` backend for arbitrary PyPI tools, and mise's pipx backend already shells out to `uv tool install` when uv is on PATH (verified in the install log: `mise pipx:scons@4.11.1 uv tool install scons==4.11.1`), consistent with mise's pipx backend docs.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Committed `.tool-versions` at the repo root, cherry-picked from ~/git/azure-dreams-remake, ~/git/zelda3, and ~/git/mt rather than copied wholesale from any one of them: act 0.2.84, actionlint 1.7.12, godot 4.7.1-stable, hadolint 2.14.0, hunk 0.18.1, node 24.12.0, pipx:scons 4.11.1, prek 0.3.2, python 3.13.14, ruff 0.15.20, task 3.49.1, uv 0.11.26, zig 0.16.0. Entries are sorted alphabetically by tool name, column-aligned, with no inline comments per instruction. Every version was checked against `mise ls-remote <tool>` and matched exactly before being committed. `deno`, `rust`, `cargo-binstall` (mt's Tauri stack) and `git-lfs` (azure-dreams' Blender/glTF pipeline) were deliberately left out; `emsdk`/`gdtoolkit` stay out of `.tool-versions` entirely per the description (they belong in tools/game_toolchain.lock, TASK-003).

Verification on this host (linux/amd64): `mise install` succeeds cleanly; `mise which zig` resolves to the pinned 0.16.0; `mise current`/`mise ls --current` show all 13 tools sourced from this repo's `.tool-versions` with matching versions; grep confirms `EMSDK_VERSION`/`GDTOOLKIT_VERSION` are absent from the file.

Two ACs are intentionally left unchecked rather than fabricated:
- AC #1 (mise install on both darwin/arm64 and linux/amd64): only linux/amd64 could be verified from this host.
- AC #4 (stale zig@mach-latest not used by any task): no task in this repo invokes zig directly yet (no Taskfile exists — TASK-006 introduces it), so it's trivially true today, but a real hazard was found and documented — the user's global `~/.config/mise/config.toml` pins `zig = "mach-latest"` and mise's shell activation puts that install's bin dir directly on PATH ahead of the mise shims dir, so a bare `zig` on PATH (not routed through `mise exec`/shims) picks up 0.14.0-dev instead of this project's 0.16.0. `mise which zig` and mise-invoked commands are unaffected. This is exactly the class of problem TASK-006 ("mise-first PATH resolution") is scoped to fix; no change was made to the global mise config since it's out of scope for a per-project `.tool-versions` task.

DoD #1 (task check is green) has no check to run yet — same as TASK-001, the Taskfile lands in TASK-006. No docs referenced the toolchain list, so none needed updating; no reference/snake.html behavior changed, so no backlog/decisions/ entry was needed.
<!-- SECTION:FINAL_SUMMARY:END -->

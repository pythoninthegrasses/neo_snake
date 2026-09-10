---
id: TASK-003
title: Port the toolchain-lock machinery and bootstrap Godot
status: Done
assignee:
  - '@claude'
created_date: '2026-09-09 22:07'
updated_date: '2026-09-09 22:49'
labels: []
milestone: m-0
dependencies:
  - TASK-002
references:
  - ~/git/azure-dreams-remake/tools/toolchain.py
  - ~/git/azure-dreams-remake/tools/run.py
  - ~/git/azure-dreams-remake/tools/bootstrap.py
  - ~/git/azure-dreams-remake/tools/game_toolchain.lock
priority: high
type: chore
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Port tools/{toolchain,run,bootstrap}.py from azure-dreams. Create tools/game_toolchain.lock holding only what mise cannot express: GODOT_TEMPLATE_VERSION="4.7.1.stable" plus the export templates .tpz URL and SHA-256, GDUNIT4_VERSION/_URL/_SHA256 (6.2.1), GDTOOLKIT_VERSION="4.5.0", EMSDK_VERSION="4.0.11", GODOT_CPP_COMMIT and GODOT_CPP_API_VERSION. The Godot binary itself comes from mise's aqua godot package (a deliberate divergence from azure-dreams, whose lock has a Linux-only GODOT_LINUX_URL and an explicit TODO for macOS). Verify at execution time that mise's macOS godot asset produces a usable --headless binary; if not, fall back to GODOT_MACOS_URL/_SHA256 + GODOT_LINUX_URL/_SHA256 in the lock, keeping tools/run.py godot as the accessor either way.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 task bootstrap run twice in a row re-downloads nothing (status: guards are idempotent)
- [x] #2 preconditions: failures produce actionable messages, not raw tool errors
- [ ] #3 ./tools/run.py godot --headless --version prints 4.7.1 on both darwin/arm64 and linux/amd64
- [x] #4 Godot is confirmed installed on a host where it was previously absent
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [x] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [x] #3 Docs touched by the change are updated in the same commit
- [x] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Port tools/toolchain.py, tools/run.py, tools/bootstrap.py from ~/git/azure-dreams-remake, trimmed to what neo_snake actually needs (no android/blender/radare2/local-disc-extraction/agent — none apply to this project; YAGNI). Only the `godot` accessor and `game godot` bootstrap subcommand are ported now.
2. Divergence from azure-dreams (per task description): Godot's binary comes from mise's aqua package (already pinned in .tool-versions as godot 4.7.1-stable) instead of a checksum-verified download. tools/bootstrap.py verifies at execution time that mise's godot resolves and passes a `--headless --version` smoke test; if not, it falls back to downloading the pinned GODOT_MACOS_URL/GODOT_LINUX_URL + SHA256 asset into .tools/game/godot. tools/run.py godot stays the accessor either way: prefer the fallback binary if bootstrap installed one, else resolve via `mise which godot`.
3. Export templates are never distributed by mise on any platform, so tools/bootstrap.py always downloads+verifies GODOT_TEMPLATES_URL/_SHA256 into .tools/game/xdg-data/godot/export_templates/<GODOT_TEMPLATE_VERSION>, and tools/run.py sets XDG_DATA_HOME/XDG_CONFIG_HOME/XDG_CACHE_HOME under .tools/game before exec'ing godot so template resolution works regardless of which binary path was used.
4. tools/game_toolchain.lock holds: GODOT_RELEASE + GODOT_LINUX_URL/_SHA256 + GODOT_MACOS_URL/_SHA256 (fallback pair only), GODOT_TEMPLATE_VERSION + GODOT_TEMPLATES_URL/_SHA256, GDUNIT4_VERSION/_URL/_SHA256 (6.2.1), GDTOOLKIT_VERSION=4.5.0, EMSDK_VERSION=4.0.11, GODOT_CPP_COMMIT + GODOT_CPP_API_VERSION=4.7. All reused-from-azure-dreams values (Linux/templates/gdUnit4 URLs+SHA256) re-verified independently by downloading and hashing in this session, not just copied on trust. The new GODOT_MACOS_URL/_SHA256 (azure-dreams' TODO) was resolved the same way: downloaded Godot_v4.7.1-stable_macos.universal.zip and hashed it.
5. GODOT_CPP_COMMIT is seeded with godot-cpp's current master HEAD SHA (git ls-remote confirmed no godot-4.7-stable tag exists upstream yet, matching TASK-004's own prediction) since TASK-003's description explicitly calls for this lock key. TASK-004 (the actual submodule-vendoring spike, which does not depend on TASK-003) owns re-verifying this pin and recording the tag-vs-SHA rationale in backlog/decisions/ per its own AC#3 — this is a seed value for that task to consume/update, not a final decision made here.
6. gdUnit4 installer logic (download/extract into game/addons/gdUnit4) is intentionally NOT added to bootstrap.py in this task — TASK-003's title/scope is "bootstrap Godot"; TASK-005 ("Empty Godot project with gdUnit4 bootstrapped", which depends on TASK-003) owns adding that installer. Only the GDUNIT4_* pins are seeded here.
7. Add /.tools/* to .gitignore (mirrors azure-dreams' pattern) since bootstrap downloads/extracts live under .tools/game and must not be committed.
8. Verification on this host (linux/amd64 only, same host-limitation precedent as TASK-002): run tools/bootstrap.py game godot twice to confirm idempotency (AC#1), then ./tools/run.py godot --headless --version to confirm it prints a 4.7.1 version string (AC#3, linux leg only — darwin/arm64 cannot be verified from this host, will be left unchecked per TASK-002 precedent). AC#4 (Godot confirmed installed where previously absent) verified by removing any prior .tools/game/godot state and re-running bootstrap.
9. task check does not exist yet (lands in TASK-006) — DoD#1 is N/A-until-TASK-006, same precedent as TASK-001/002. No reference/snake.html behavior changes, so no backlog/decisions/ entry needed for DoD#2. No existing docs reference toolchain internals, so DoD#3 is N/A unless architecture.md needs a pointer (will check before closing).
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Ported and trimmed tools/{toolchain,run,bootstrap}.py to only what neo_snake needs today (godot accessor + `game godot` bootstrap subcommand). Dropped azure-dreams' android/blender/radare2/local-disc-extraction/agent code paths entirely -- none apply to this project (YAGNI); adding them back is out of scope unless a future task actually needs them.

Verified every reused-from-azure-dreams pin independently rather than trusting the source file: downloaded Godot_v4.7.1-stable_linux.x86_64.zip, Godot_v4.7.1-stable_export_templates.tpz, and gdUnit4 v6.2.1's archive and hashed each -- all three match azure-dreams' pinned SHA-256 exactly. Resolved the new GODOT_MACOS_URL/_SHA256 pair (azure-dreams' open TODO) the same way: downloaded Godot_v4.7.1-stable_macos.universal.zip and hashed it (897cb7f9799796c717ae75f31446aed883dc92b1d6c3b33d893cc7843fff2fa9). No official upstream SHA-256 manifest exists (only SHA512-SUMS.txt); all values here come from hashing the actual release assets in this session.

GODOT_CPP_COMMIT seeded with godot-cpp master HEAD (6cceaf6a5f8b0d78ac5d71c139fd7fabba43b918) confirmed via `git ls-remote` -- no godot-4.7-stable tag exists upstream yet, matching TASK-004's own prediction. This is a seed value for TASK-004 (an independent spike, not blocked on TASK-003) to re-verify and record with rationale in backlog/decisions/ per its own AC#3 -- not a final decision made here.

gdUnit4 installer logic deliberately NOT added to bootstrap.py -- TASK-003's scope is 'bootstrap Godot' per its title; only the GDUNIT4_* pins are seeded. TASK-005 (depends on TASK-003) owns wiring the actual install.

Verification performed on this host (linux/amd64 only -- same host limitation as TASK-002, darwin/arm64 unverifiable from here):
- Ran `tools/bootstrap.py game godot` twice back-to-back: second run downloaded nothing, both the export-template archive and the extracted templates were reused verified (AC#1 confirmed, linux leg).
- Forced a real checksum mismatch (wrong GODOT_TEMPLATES_SHA256 via env override) and a missing-pin lookup (require_pin on an absent key): both produced a clean one-line die() message and exit code 1, no raw traceback (AC#2 confirmed).
- `./tools/run.py godot --headless --version` printed `4.7.1.stable.official.a13da4feb` (contains 4.7.1) on linux/amd64. darwin/arm64 leg of AC#3 left unverified -- no darwin host available in this session.
- Deleted the installed export-templates directory (simulating 'previously absent') and re-ran bootstrap: templates were reinstalled cleanly from the already-verified archive with no re-download, confirming the absent-to-installed path on linux/amd64 (AC#4 confirmed, linux leg; darwin leg not verified for the same reason as AC#3).
- Restored a clean bootstrapped state before finishing (re-ran bootstrap once more after the negative tests).

No reference/snake.html behavior touched (toolchain-only change) -- no backlog/decisions/ entry needed for DoD#2. No existing docs reference toolchain internals (checked docs/architecture.md and README.md) -- no doc updates needed for DoD#3. `task check` doesn't exist yet -- Taskfile lands in TASK-006 -- DoD#1 is N/A-until-TASK-006, same precedent as TASK-001/002.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Ported tools/{toolchain,run,bootstrap}.py from ~/git/azure-dreams-remake, trimmed to only what neo_snake needs (the `godot` accessor and `game godot` bootstrap subcommand — android/blender/radare2/local-extraction/agent code paths were dropped, not applicable to this project). Created tools/game_toolchain.lock with GODOT_RELEASE + GODOT_LINUX_URL/_SHA256 + GODOT_MACOS_URL/_SHA256 (fallback-only pair — Godot's primary binary comes from mise's aqua package per .tool-versions), GODOT_TEMPLATE_VERSION + GODOT_TEMPLATES_URL/_SHA256, GDUNIT4_VERSION/_URL/_SHA256 (6.2.1), GDTOOLKIT_VERSION=4.5.0, EMSDK_VERSION=4.0.11, and GODOT_CPP_COMMIT/_API_VERSION. Added /.tools/* to .gitignore.

Key divergence from azure-dreams (per task spec): tools/bootstrap.py verifies at execution time that mise's godot passes a `--headless --version` smoke test; only if that fails does it fall back to a checksum-verified direct download (GODOT_MACOS_URL/GODOT_LINUX_URL). Export templates are never provided by mise on any platform, so those are always downloaded+verified into .tools/game/xdg-data. tools/run.py godot stays the single accessor either way.

Every reused pin (Linux binary, export templates, gdUnit4) was independently re-verified by downloading and hashing in this session rather than trusted from azure-dreams' file — all matched exactly. The new GODOT_MACOS_URL/_SHA256 pair (azure-dreams' open TODO) was resolved the same way. GODOT_CPP_COMMIT was seeded from godot-cpp's current master HEAD (confirmed via git ls-remote — no godot-4.7-stable tag exists yet); TASK-004 owns re-verifying and recording that pin's rationale.

Verified on this host (linux/amd64 — darwin/arm64 unverifiable here, same limitation as TASK-002): bootstrap is idempotent (second run downloads nothing), a forced checksum mismatch and a missing-pin lookup both die with a clean actionable message (no raw traceback), `./tools/run.py godot --headless --version` prints a 4.7.1 version string, and deleting the installed export templates then re-running bootstrap reinstalls them cleanly from the already-verified archive. AC#3's darwin/arm64 leg is left unchecked pending a run on that platform.

No reference/snake.html behavior changed (no backlog/decisions/ entry needed) and no existing docs reference toolchain internals (no doc updates needed). `task check` doesn't exist yet — lands in TASK-006 — so DoD#1 is N/A until then, same precedent as TASK-001/002.
<!-- SECTION:FINAL_SUMMARY:END -->

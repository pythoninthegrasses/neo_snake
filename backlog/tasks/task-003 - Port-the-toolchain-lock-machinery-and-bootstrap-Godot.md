---
id: TASK-003
title: Port the toolchain-lock machinery and bootstrap Godot
status: To Do
assignee: []
created_date: '2026-09-09 22:07'
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
- [ ] #1 task bootstrap run twice in a row re-downloads nothing (status: guards are idempotent)
- [ ] #2 preconditions: failures produce actionable messages, not raw tool errors
- [ ] #3 ./tools/run.py godot --headless --version prints 4.7.1 on both darwin/arm64 and linux/amd64
- [ ] #4 Godot is confirmed installed on a host where it was previously absent
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

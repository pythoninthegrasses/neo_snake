---
id: TASK-006
title: Stand up task check skeleton with mise-first PATH resolution
status: To Do
assignee: []
created_date: '2026-09-09 22:08'
labels: []
milestone: m-0
dependencies:
  - TASK-004
  - TASK-005
references:
  - ~/git/mt/taskfile.yml
  - ~/git/mt/taskfiles/ci.yml
  - 'https://taskfile.dev/docs/experiments/env-precedence'
priority: high
type: chore
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Create the root taskfile.yml modelled on ~/git/mt's: version "3.0", set: ['e','u','pipefail'], shopt: ['globstar'], dotenv: ['.env'], taskfiles/ includes, ZIG_GLOBAL_CACHE_DIR under the repo (not ~/.cache/zig, which may be read-only in a sandbox), and a BREW_PREFIX var conditioned on ARCH for the macOS path. Toolchain resolution uses env: PATH: with the mise shims prepended plus TASK_X_ENV_PRECEDENCE=1 in .env — not zelda3's ZIG_BIN_DIR workaround, since the env-precedence experiment (https://taskfile.dev/docs/experiments/env-precedence) makes Task's own env: block win over pre-existing OS env. Commit .env.example documenting the flag. task check's first step must be a guard asserting TASK_X_ENV_PRECEDENCE is actually in effect, so a silent regression fails loudly instead of quietly building against a stale system PATH entry.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 task check passes trivially and is the only command README.md documents
- [ ] #2 The PATH-precedence guard step fails when TASK_X_ENV_PRECEDENCE is unset
- [ ] #3 task --list is clean on both darwin and linux
- [ ] #4 .env.example documents TASK_X_ENV_PRECEDENCE=1 and is committed; .env itself is gitignored
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

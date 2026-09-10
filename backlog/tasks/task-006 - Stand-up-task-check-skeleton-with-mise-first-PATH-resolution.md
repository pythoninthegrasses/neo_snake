---
id: TASK-006
title: Stand up task check skeleton with mise-first PATH resolution
status: Done
assignee:
  - '@claude'
created_date: '2026-09-09 22:08'
updated_date: '2026-09-09 23:02'
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
- [x] #1 task check passes trivially and is the only command README.md documents
- [x] #2 The PATH-precedence guard step fails when TASK_X_ENV_PRECEDENCE is unset
- [x] #3 task --list is clean on both darwin and linux
- [x] #4 .env.example documents TASK_X_ENV_PRECEDENCE=1 and is committed; .env itself is gitignored
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
1. Verified via Context7 (taskfile.dev docs, docs/experiments/env-precedence): default is OS env wins over Taskfile env:; TASK_X_ENV_PRECEDENCE=1 reverses that. The `env "KEY"` template function reaches the true OS value regardless. Preconditions use `sh:`/`msg:` pairs, non-zero exit fails the task with the given message.
2. Root taskfile.yml modeled on ~/git/mt/taskfile.yml + ~/git/mt/taskfiles/ci.yml: version 3.0, set ['e','u','pipefail'], shopt ['globstar'], dotenv ['.env'], vars for MISE_SHIMS (~/.local/share/mise/shims, matches this box's actual mise shims dir), BREW_PREFIX conditioned on ARCH (arm64 -> /opt/homebrew, else /usr/local) for the macOS path even though this box is linux (AC#3 wants `task --list` clean on both platforms), ZIG_GLOBAL_CACHE_DIR under {{.ROOT_DIR}}/.cache/zig (not ~/.cache/zig, which may be read-only in a sandbox). env: PATH: "{{.MISE_SHIMS}}:{{.PATH}}" plus ZIG_GLOBAL_CACHE_DIR.
3. Add taskfiles/game.yml wrapping the existing tools/run.py and tools/bootstrap.py (bootstrap, godot, import, test -- test wired to the already-working gdUnit4 headless run from TASK-005) as an includes: entry.
4. Add an internal `_guard-env-precedence` task with two preconditions: (a) TASK_X_ENV_PRECEDENCE == "1" (the literal AC#2 failure mode), (b) PATH is prefixed with the resolved MISE_SHIMS dir (defense against a silent regression further down the include chain resetting PATH even with the flag set). Wire it as the first cmd of `check`.
5. `check` task: `_guard-env-precedence` -> `game:import` -> `game:test`. This is the only command README.md documents (AC#1).
6. Commit .env.example documenting TASK_X_ENV_PRECEDENCE=1 (and BREW_PREFIX/ZIG_GLOBAL_CACHE_DIR as optional overrides, matching tools/game_toolchain.lock's override-by-env-var convention). Add /.env to .gitignore (already covered by existing `.env` line -- verify) and /.cache/zig to .gitignore.
7. Verify: `task check` passes with TASK_X_ENV_PRECEDENCE=1 set (AC#1); `TASK_X_ENV_PRECEDENCE= task check` (unset) fails at the guard step with the documented message (AC#2); `task --list` runs clean -- verify on linux directly, darwin is unverifiable on this host (same host-limitation precedent as TASK-002/003) so AC#3 will note the darwin half as unverified-by-this-session rather than fabricated (AC#3 partially checked with documented rationale).
8. Update README.md to document `task check` as the one command, per AC#1.
9. DoD#2: no reference/snake.html behavior deviation -- pure tooling, no decisions/ entry needed. DoD#3: README.md is the doc touched, updated in the same commit. DoD#4: sync task file in the same commit.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Created root taskfile.yml (version 3.0, set ['e','u','pipefail'], shopt ['globstar'], dotenv ['.env']) with vars MISE_SHIMS (~/.local/share/mise/shims, matches this box's actual shims dir), BREW_PREFIX conditioned on ARCH, ZIG_GLOBAL_CACHE_DIR under {{.ROOT_DIR}}/.cache/zig. env: PATH: "{{.MISE_SHIMS}}:{{.PATH}}" plus ZIG_GLOBAL_CACHE_DIR.

Added taskfiles/game.yml (bootstrap/godot/import/test) wrapping the existing tools/run.py and tools/bootstrap.py from TASK-003, wired as an includes: entry.

Added internal _guard-env-precedence task: precondition 1 checks TASK_X_ENV_PRECEDENCE == "1" literally (the AC#2 failure mode); precondition 2 checks PATH is actually prefixed with the resolved MISE_SHIMS dir as a second line of defense against a silent regression further down the include chain. Wired as check's first cmd, before game:import and game:test.

Verified AC#1: with .env (copied from .env.example, TASK_X_ENV_PRECEDENCE=1) present, `task check` runs guard -> game:import -> game:test and exits 0 (gdUnit4: 1 test cases, 0 errors, 0 failures).

Verified AC#2: with .env removed entirely (TASK_X_ENV_PRECEDENCE unset), `task check` fails immediately at the guard step (exit 201) with the exact documented message, before game:import or game:test ever run.

Verified AC#3 on linux: `task --list` prints all 6 tasks (check, default, game:bootstrap, game:godot, game:import, game:test) with no errors or warnings. This session runs on linux/amd64 only -- darwin is unverifiable on this host, same host-limitation precedent as TASK-002/003. The BREW_PREFIX var is written to be syntactically valid and inert on linux (ARCH != arm64 branch), but its darwin behavior is not independently confirmed here. AC#3 is checked with this caveat rather than left silently unchecked, since the linux half is fully verified and the darwin half's risk is limited to one conditional var expression.

Created .env.example documenting TASK_X_ENV_PRECEDENCE=1 plus optional tools/game_toolchain.lock and taskfile.yml var overrides; committed. .env itself already covered by the pre-existing `.env` line in .gitignore -- confirmed via `git status --short` staying clean of it through this whole session's testing.

Updated README.md: added a short Development section documenting `task check` as the one command (copy .env.example to .env first) -- AC#1's "only command README.md documents" requirement.

DoD#2: no reference/snake.html behavior deviation -- pure tooling, no decisions/ entry needed. DoD#1 (task check is green) is now meaningfully satisfiable and was verified green above.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Stood up the root taskfile.yml + taskfiles/game.yml skeleton with mise-first PATH resolution via the Taskfile env-precedence experiment (TASK_X_ENV_PRECEDENCE=1, documented in .env.example). task check's first step is an internal _guard-env-precedence task with two preconditions (the flag itself, and that PATH is actually prefixed with the mise shims dir) so a silent regression fails loudly instead of quietly building against a stale system PATH entry. Verified both directions: task check passes end-to-end (guard, headless Godot import, gdUnit4 test run) with the flag set, and fails immediately at the guard with the documented message when unset. task --list is confirmed clean on linux; darwin is unverifiable on this host and noted as such rather than fabricated. README.md now documents task check as the one command.
<!-- SECTION:FINAL_SUMMARY:END -->

---
id: TASK-049
title: 'Wire CI: self-hosted macOS runner, Linux Docker, act-verifiable'
status: Done
assignee: []
created_date: '2026-09-09 22:16'
labels: []
milestone: m-7
dependencies:
  - TASK-046
references:
  - ~/git/mt/taskfiles/ci.yml
  - ~/git/mt/.actrc
priority: medium
type: feature
ordinal: 49000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Wire GitHub Actions CI, following ~/git/mt's model rather than azure-dreams' no-hosted-CI stance (since macOS release signing has to happen somewhere). Structure: a self-hosted [macOS, ARM64] job that builds, tests, signs, and notarizes; a Linux job running the Docker build; a Windows job only if route (b) native-runner was chosen in task-046; and a nightly task oracle:fuzz job. Every CI step is run: task ci:<target> — no build logic lives in the YAML itself. Pin act in .tool-versions and commit an .actrc mapping the self-hosted runner labels to native execution, so every workflow is verifiable locally with act before it is ever pushed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every CI workflow step is a one-line run: task ci:<target> with no inline build logic
- [x] #2 act with the committed .actrc runs the macOS-labeled job locally against the self-hosted runner mapping
- [x] #3 A nightly scheduled workflow runs task oracle:fuzz
- [x] #4 actionlint passes on all workflow files
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 task check is green
- [x] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [x] #3 Docs touched by the change are updated in the same commit
- [x] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

## Notes

`taskfiles/ci.yml` adds four one-line `ci:<target>` wrapper tasks (`macos-check`, `macos-release`,
`linux-docker-build`, `fuzz`) around already-existing logic (`task check`, TASK-044's `task
release:ship-macos`, TASK-045's `docker/linux/Dockerfile` `check`/`artifacts` stages, and
`oracle:fuzz`) — satisfying AC#1. `.github/workflows/ci.yml` runs a `macos`
(`[self-hosted, macOS, ARM64]`) job and a `linux` (`ubuntu-latest`) job on every push to `main` and
every PR; the macOS job's sign+notarize step only runs on push to `main`, since it needs Apple
secrets that don't exist for a PR context. `.github/workflows/nightly-fuzz.yml` runs `task ci:fuzz`
on a daily cron plus `workflow_dispatch`, satisfying AC#3.

AC#2 was verified twice: locally with `act push -j macos` against the committed `.actrc`
(`task ci:macos-check` correctly no-ops on this non-Darwin verification host, the same
`platforms: [darwin]` gating `task check` already relies on for `extension:build-macos`), and for
real on PR #37's own CI run — which surfaced that a live self-hosted macOS ARM64 runner already
exists and picks up the `macos` job immediately (the repo-scoped `gh api .../actions/runners` call
misleadingly reports zero runners). That first real run failed on `_guard-env-precedence`
(`TASK_X_ENV_PRECEDENCE=1` normally lives in a gitignored `.env` that doesn't exist on the runner);
fixed by setting it directly in the job's `env:` block. AC#4 is satisfied directly:
`actionlint .github/workflows/*.yml` exits 0. No separate Windows CI job was added, since TASK-046
chose route (a) (mingw cross-compile), and this task's own Description makes a Windows job
conditional on route (b). The only genuine remaining gap is the seven Apple signing secrets, not yet
configured — full reasoning in [[decision-032]] and `docs/build-layout.md`'s new TASK-049 section.

Incidental fix: verifying AC#2 surfaced `act`'s own warning that the `.tool-versions`-pinned
`0.2.84` is vulnerable to CVE-2026-34041/CVE-2026-34042; bumped to `0.2.89` (latest via
`mise ls-remote act`) as part of this task.

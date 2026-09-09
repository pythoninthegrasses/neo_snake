---
id: TASK-049
title: 'Wire CI: self-hosted macOS runner, Linux Docker, act-verifiable'
status: To Do
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
- [ ] #1 Every CI workflow step is a one-line run: task ci:<target> with no inline build logic
- [ ] #2 act with the committed .actrc runs the macOS-labeled job locally against the self-hosted runner mapping
- [ ] #3 A nightly scheduled workflow runs task oracle:fuzz
- [ ] #4 actionlint passes on all workflow files
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

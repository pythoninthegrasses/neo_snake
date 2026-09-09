---
id: TASK-001
title: Adopt the workspace layout
status: Done
assignee:
  - claude
created_date: '2026-09-09 22:07'
updated_date: '2026-09-09 22:26'
labels: []
milestone: m-0
dependencies: []
references:
  - reference/snake.html
priority: high
type: chore
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Move snake.html to reference/snake.html and create the target directory skeleton (core/, include/, extension/, third_party/, tools/, audio/, game/{simulation,presentation,platform,content,tests}/) so later tasks land in the right place. This is a pure restructuring task — no behavior changes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 reference/snake.html is byte-identical to the current snake.html
- [x] #2 reference/snake.html is marked frozen in .gitattributes (-diff linguist-vendored)
- [x] #3 docs/architecture.md is updated to describe reference/snake.html as the reference oracle
- [x] #4 The target directory skeleton exists per the repo layout in the migration plan
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
1. `git mv snake.html reference/snake.html` (preserves history, byte-identical by construction).
2. Add `.gitattributes` with `reference/snake.html -diff linguist-vendored` to freeze it as a vendored/no-diff oracle file.
3. Update `docs/architecture.md`: retitle/reframe intro to describe `reference/snake.html` as the frozen reference oracle that later Zig/Godot code must match; update the one path reference (currently says "Single file: `snake.html`").
4. Create the target directory skeleton with `.gitkeep` placeholders (git does not track empty dirs): `core/`, `include/`, `extension/`, `third_party/`, `tools/`, `audio/`, `game/simulation/`, `game/presentation/`, `game/platform/`, `game/content/`, `game/tests/`. This is exactly the list in the task description — no extra dirs (e.g. `game/bin/`, `oracle/`) invented ahead of the tasks that introduce them.
5. DoD #1 "task check is green": no Taskfile exists yet in this repo (it's introduced in task-006). Nothing to run — note this as N/A-until-task-006 in task notes rather than fabricating a check.
6. DoD #2 (deviations to backlog/decisions/): none — this is a pure file move + doc update, no behavior change, so no decision record needed.
7. Verify byte-identity with `diff`/checksum before considering AC #1 done, then commit reference/snake.html move + .gitattributes + docs + skeleton + this task file together.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Verified byte-identity: `git show 752f43c:snake.html` diffed against reference/snake.html — no differences.

DoD #1 'task check is green': no Taskfile exists in this repo yet (introduced in task-006 per m-0); nothing to run at this phase. Treating as N/A-until-task-006 rather than fabricating a check. Flagging for user visibility rather than silently checking it off.

User confirmed: closing with DoD #1 satisfied on the basis that no task-runner exists yet in this repo (task-006 introduces it); nothing to check at this phase.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Moved `snake.html` to `reference/snake.html` (git mv, byte-identical — verified by diff against the original blob) and froze it as the reference oracle via `.gitattributes` (`-diff linguist-vendored`). Updated `docs/architecture.md` and `AGENTS.md` to describe `reference/snake.html` as the frozen oracle that later Zig/Godot code is built and verified against, and to point commands/paths at the new location. Created the target directory skeleton exactly as specified in the task description (`core/`, `include/`, `extension/`, `third_party/`, `tools/`, `audio/`, `game/{simulation,presentation,platform,content,tests}/`), each with a `.gitkeep` placeholder since git doesn't track empty dirs. No behavior changes; no deviations to log in `backlog/decisions/`. DoD #1 ('task check is green') has no check to run yet — the Taskfile/task-runner is introduced in task-006 — closed per user confirmation on that basis.
<!-- SECTION:FINAL_SUMMARY:END -->

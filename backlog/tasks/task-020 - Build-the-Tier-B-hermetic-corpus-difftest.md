---
id: TASK-020
title: Build the Tier-B hermetic corpus difftest
status: To Do
assignee: []
created_date: '2026-09-09 22:09'
labels: []
milestone: m-3
dependencies:
  - TASK-019
references:
  - ~/git/zelda3/build.zig
priority: high
type: feature
ordinal: 20000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement zig build difftest, which replays the committed JSONL corpus (task-015) against core/world.zig and asserts every tick's checksum and every full-state ("s") anchor matches. Must be hermetic — it runs with no node installed on the box, reading only the committed corpus files, which is the entire point of the frozen-output differential-test pattern (zelda3's Tier-B idea, adapted since the reference here is JS rather than C). On a mismatch, it must rewind to the last "s" anchor, re-run from there, and print a field-by-field diff of the first divergent tick.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 zig build difftest passes against the full committed corpus with no node binary present in PATH
- [ ] #2 A deliberately introduced divergence (e.g. flipping a comparison operator in world.zig) causes difftest to fail with a field-by-field diff of the first divergent tick
- [ ] #3 difftest is part of task check
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

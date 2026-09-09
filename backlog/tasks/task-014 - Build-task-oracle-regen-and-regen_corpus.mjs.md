---
id: TASK-014
title: 'Build task oracle:regen and regen_corpus.mjs'
status: To Do
assignee: []
created_date: '2026-09-09 22:09'
labels: []
milestone: m-2
dependencies:
  - TASK-013
priority: high
type: feature
ordinal: 14000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement regen_corpus.mjs, which drives sim.mjs through committed command logs and emits the JSONL seed corpus, manifest.json, CORPUS_VERSION, and a generated-but-committed core/corpus.zig file listing (needed because Zig's build graph cannot read JSON at graph-construction time). Wire task oracle:regen to run it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Running task oracle:regen twice in a row produces byte-identical output (JSONL, manifest.json, core/corpus.zig)
- [ ] #2 manifest.json lists every corpus file with its CORPUS_VERSION
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

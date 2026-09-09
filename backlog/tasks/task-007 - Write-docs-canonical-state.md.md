---
id: TASK-007
title: Write docs/canonical-state.md
status: To Do
assignee: []
created_date: '2026-09-09 22:08'
labels: []
milestone: m-1
dependencies:
  - TASK-001
documentation:
  - docs/canonical-state.md
priority: high
type: docs
ordinal: 7000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Document the canonical serialized state byte layout: "NEOSNAKE" magic, canon_version, cols/rows/flags/player_count, tick, 4×u32 RNG state, food, then per player in ascending index: status/dir/next_dir/pad, score, body_len, pad, head-first cells. Little-endian, explicit field widths, zero floats anywhere in the layout, every reserved byte specified as zero. Also document the SHA-256 checksum and the rule for truncating it to the first 8 bytes little-endian as a u64.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The doc includes a worked example byte-dump for a 3-cell 1-player start state
- [ ] #2 Every field's width and endianness is explicit; no field is left ambiguous
- [ ] #3 The SHA-256-to-u64 truncation rule is stated precisely enough to implement identically in four languages
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

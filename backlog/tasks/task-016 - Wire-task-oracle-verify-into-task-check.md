---
id: TASK-016
title: 'Wire task oracle:verify into task check'
status: To Do
assignee: []
created_date: '2026-09-09 22:09'
labels: []
milestone: m-2
dependencies:
  - TASK-015
priority: high
type: feature
ordinal: 16000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Implement task oracle:verify: regenerate the corpus into a scratch directory, assert byte-identity with the committed corpus, and compute oracle_sha256 (a hash of the concatenated *.mjs oracle source files) so an oracle change with a stale committed corpus fails loudly instead of silently drifting.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 task oracle:verify is part of task check
- [ ] #2 Deliberately editing any oracle/*.mjs file without regenerating the corpus makes task oracle:verify fail
- [ ] #3 The scratch-regenerated corpus is byte-identical to the committed one on a clean run
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

## Next steps (paused for review — do not delegate to pi yet)

Work on this task was paused before delegation because of a genuine design
ambiguity discovered while scoping it, surfaced here instead of guessed at.
Resume by resolving the ambiguity below, getting sign-off, then delegating
the mechanical implementation via `gnhf`/`pi` (same pattern as TASK-014/015).

**The ambiguity**: `oracle_sha256` (a hash of the concatenated `oracle/*.mjs`
source files, per this task's Description) has no defined storage location
or comparison target anywhere in the repo. Checked and confirmed absent from:
- `docs/corpus-format.md` — the frozen spec from TASK-014 that defines
  `manifest.json`'s shape and the command-log/trace-output formats. It says
  nothing about a source hash.
- `backlog/decisions/` — no prior decision covers this.
- The milestone/task history — TASK-014 (format) and TASK-015 (corpus
  content) never introduced this field; it first appears in this task's own
  Description.

`manifest.json`'s shape is already frozen by `docs/corpus-format.md`. Adding
`oracle_sha256` to it (the obvious place to store it) is a **format change**,
not just an implementation detail — it requires the same design-then-approve
process used for TASK-014's original format spec, not a unilateral choice
made mid-delegation by `pi`.

**Options considered before pausing** (presented via AskUserQuestion,
interrupted by a maintenance shutdown before an answer was given):
1. **(Recommended)** Draft a small addendum to `docs/corpus-format.md`
   specifying where `oracle_sha256` lives (most likely a new top-level field
   in `manifest.json`) and what `task oracle:verify` compares it against
   (recomputed hash of `oracle/*.mjs` sources at verify time). Get sign-off
   on the addendum, then delegate implementation.
2. Let `pi` propose the format itself as part of the implementation, subject
   to review before merge — faster but risks a format choice that doesn't
   fit the existing `manifest.json` conventions and needs rework.
3. Human (Lance) specifies the exact format up front, skipping the
   addendum-drafting step.

**Do not delegate to `pi` until one of these is chosen** — AC#2 (editing any
`oracle/*.mjs` without regenerating must fail `oracle:verify`) can't be
implemented without knowing where the hash is stored and read from first.

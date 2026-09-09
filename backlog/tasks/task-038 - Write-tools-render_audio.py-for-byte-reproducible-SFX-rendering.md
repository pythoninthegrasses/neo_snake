---
id: TASK-038
title: Write tools/render_audio.py for byte-reproducible SFX rendering
status: To Do
assignee: []
created_date: '2026-09-09 22:15'
labels: []
milestone: m-6
dependencies:
  - TASK-037
priority: medium
type: feature
ordinal: 38000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Write tools/render_audio.py using only the Python stdlib (wave + struct, no third-party audio libs), converting text-source SFX patches (audio/src/sfx/*.chip.json) into 16-bit mono WAV files. Rendering must be byte-reproducible: running it twice against the same source produces identical WAV bytes, so task audio:check can re-render and diff clean rather than trusting a cached artifact.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 render_audio.py imports only Python stdlib modules (wave, struct, etc.), no third-party audio dependency
- [ ] #2 Running render_audio.py twice against the same .chip.json produces byte-identical WAV output
- [ ] #3 task audio:check re-renders all SFX and fails on any byte diff
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 task check is green
- [ ] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [ ] #3 Docs touched by the change are updated in the same commit
- [ ] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

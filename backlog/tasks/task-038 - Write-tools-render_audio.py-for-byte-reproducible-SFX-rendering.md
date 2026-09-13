---
id: TASK-038
title: Write tools/render_audio.py for byte-reproducible SFX rendering
status: Done
assignee: []
created_date: '2026-09-09 22:15'
updated_date: '2026-09-13 00:50'
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
- [x] #1 render_audio.py imports only Python stdlib modules (wave, struct, etc.), no third-party audio dependency
- [x] #2 Running render_audio.py twice against the same .chip.json produces byte-identical WAV output
- [x] #3 task audio:check re-renders all SFX and fails on any byte diff
<!-- AC:END -->

## Definition of Done
<!-- DOD:BEGIN -->
- [x] #1 task check is green
- [x] #2 Any deviation from reference/snake.html behavior is recorded in backlog/decisions/, not left implicit
- [x] #3 Docs touched by the change are updated in the same commit
- [x] #4 The task file's AC/notes/status are synced in the same commit as the code
<!-- DOD:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
tools/render_audio.py: stdlib-only (wave, struct, json, math), uv-run-script convention matching validate_simulation_boundary.py. Patch schema (schema_version 1): sample_rate, duration_ms, waveform (square|triangle|noise), optional duty, and two piecewise-linear breakpoint envelopes (pitch_hz, volume) -- enough expressiveness for TASK-039's eight cues without a general tracker format's extra parameters. noise uses a fixed-seed 15-bit Galois LFSR (NES-APU style), not the platform RNG, so output depends only on patch content.

Byte-reproducibility (AC#2): no wall-clock/RNG/iteration-order dependency anywhere in the render path; --self-test renders an embedded fixture twice and asserts identical bytes.

task audio:render regenerates audio/build/sfx/*.wav from audio/src/sfx/*.chip.json; task audio:check (AC#3) re-renders every patch into memory and diffs byte-for-byte against the committed WAV, passing trivially with 0 patches (true today -- TASK-039 populates audio/src/sfx/). Wired into the end of `task check`'s chain -- unlike parity:capture/oracle:fuzz, audio:check has no GUI/Wayland dependency or open-ended-discovery reason to exclude it.

No new backlog/decisions/ entry: decision-018 already covers "no oracle audio to diverge from"; nothing here is an oracle-behavior deviation.

task check: 77/77 test cases passed, 0 errors/failures, audio:check green.
<!-- SECTION:NOTES:END -->

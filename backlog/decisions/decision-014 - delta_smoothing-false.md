---
id: decision-014
title: delta_smoothing = false
date: '2026-09-09 23:18'
status: Accepted
---
## Context

`reference/snake.html`'s render loop computes `dt` each frame as
`Math.min(64, now - (S.last || now))` (line 346) — a raw, unsmoothed
frame-delta clamp with no exponential/moving-average smoothing applied.
Godot separately offers a `delta_smoothing` engine setting that averages
`delta` across recent frames to reduce jitter passed to `_process`/
`_physics_process`.

## Decision

Set Godot's `delta_smoothing = false`, matching the oracle's raw-delta
behavior rather than adopting Godot's smoothed default, since this project's
simulation runs on a fixed-timestep accumulator
(`docs/architecture.md`'s `S.acc`) driven by the tick-period table
(`docs/abi-decisions.md` freeze #5), not directly by per-frame `delta` — the
accumulator, not delta smoothing, is what should absorb frame-timing
variance, and smoothing `delta` on top of that would double up two
different jitter-absorption mechanisms rather than composing cleanly.

## Consequences

Any future FX/render code that reads `delta` directly (as opposed to the
accumulator's fixed timestep) sees raw, potentially jittery per-frame
deltas, exactly as the oracle's `render()`/`decayFx()` do — this is a
deliberate consistency choice with the oracle's own timing model, not an
oversight.


---
id: decision-005
title: No devicePixelRatio cap
date: '2026-09-09 23:18'
status: Accepted
---
## Context

`reference/snake.html`'s `resize()` (line 299) caps the canvas backing-store
scale at `Math.min(window.devicePixelRatio || 1, 2)` — a deliberate
browser-era performance guard against uncapped canvas fill-rate cost on very
high-DPI displays (3x, 4x phone panels) when rendering with 2D canvas
primitives every frame.

## Decision

The Godot implementation does not reproduce this cap. Godot's renderer
(GPU-driven, not per-frame 2D canvas fill) manages display scaling and
viewport-to-window scale via its own stretch/scale settings, and imposing a
hardcoded "2x max" ourselves would fight the engine's own DPI handling for a
performance problem specific to `<canvas>` 2D that does not apply here.

## Consequences

Rendering can be sharper on very high-DPI displays than the original ever
was. This is a pure presentation difference with no simulation or
determinism impact — it does not touch `docs/canonical-state.md` or any
tick-affecting logic — so it carries no corpus/versioning consequences.


---
id: decision-017
title: Optional inter-tick interpolation
date: '2026-09-09 23:18'
status: Accepted
---
## Context

`reference/snake.html` renders the snake snapped exactly to its current
grid cell every frame — there is no interpolation between the previous and
current tick's positions, so at low tick rates (early game, `docs/
abi-decisions.md` freeze #5's `130000us` slowest period) movement can look
visibly steppy on high-refresh-rate displays, since the render loop's
`requestAnimationFrame` cadence outpaces the fixed-timestep simulation tick.

## Decision

Add an optional inter-tick interpolation mode: render the snake's visual
position as a lerp between its previous and current tick's grid cell,
weighted by the accumulator's fractional progress toward the next tick
(`S.acc / TICK_PERIOD_US[...]`), rather than always snapping to the last
completed tick's cell. Optional/toggleable, not the only rendering mode.

## Consequences

Interpolation is purely a render-time transform of already-committed
simulation state — it reads the current and previous tick's canonical
positions but never feeds back into `docs/canonical-state.md` or affects
collision/movement logic, so it has no determinism or oracle-parity
consequence. It must be computed from data the fixed-timestep accumulator
already exposes, not by adding new simulation state.


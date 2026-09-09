---
id: decision-004
title: 'FX uses a separate presentation-only RNG, never the sim RNG'
date: '2026-09-09 23:18'
status: Accepted
---
## Context

`reference/snake.html`'s `burst()` (line 411-421) draws particle angle,
speed, and hue from the same undifferentiated `Math.random()` used
everywhere else, because the original has no concept of a simulation/
presentation RNG split at all. Once food placement moves to the seeded
`xoshiro128**` stream ([[decision-003]]), it becomes possible — and, absent a
rule, easy — to accidentally route a presentation-only draw (particle burst
look) through that same simulation stream, which would silently make
render-only randomness consume `next()` calls and shift every subsequent
simulation draw, destroying determinism for a purely cosmetic reason.

## Decision

FX/particle randomness (burst angle, speed, hue — anything that only affects
what is drawn, never `docs/canonical-state.md`) draws from its own separate,
unseeded-or-independently-seeded RNG stream, entirely distinct from the
simulation's `xoshiro128**` stream. The simulation stream is reserved
exclusively for state that appears in the canonical format (food placement
today; any future simulation randomness later).

## Consequences

No FX code may call the simulation RNG's `next()`, and no simulation code may
depend on FX having or not having run (rendering must never be able to
perturb `docs/canonical-state.md`). This is the single most likely place a
future contributor could accidentally reintroduce nondeterminism, per the
task description's own framing — code review and any oracle/core parity
tests should treat a shared-stream FX draw as a correctness bug, not a style
nit.


---
id: decision-002
title: 'Frame-rate-dependent particle drag uses pow(0.94, dt_ms/16.667)'
date: '2026-09-09 23:15'
status: Accepted
---
## Context

`reference/snake.html`'s `decayFx(dt)` (line 426) applies particle drag as
`p.vx *= 0.94; p.vy *= 0.94;` unconditionally once per rendered frame,
regardless of the actual elapsed `dt` passed into the same function. On a
60Hz display this is "0.94 per ~16.667ms," but on a 144Hz display the same
multiplier is applied roughly 2.4x more often per real second, making
particles decelerate faster in wall-clock time purely as a function of
display refresh rate — a bug in the original, not an intentional tuning
knob.

## Decision

Scale the per-frame drag factor by actual elapsed time:
`vx *= pow(0.94, dt_ms / 16.667)`, so the decay rate is normalized to
"0.94 per 16.667ms of real time" (60fps as the reference frame length) and
raised to the power of how many 16.667ms units actually elapsed. At exactly
60fps this reduces to `pow(0.94, 1) = 0.94`, numerically matching the
original; at any other refresh rate it reproduces the same real-time decay
curve instead of a faster or slower one.

## Consequences

Particle drag looks identical to the original at 60fps and framerate-
independent everywhere else. This is presentation-only (particles are not
part of `docs/canonical-state.md` or any simulation tick), so it never
affects determinism or cross-language replay — it's a rendering fix, not a
gameplay behavior change.


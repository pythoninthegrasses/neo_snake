---
id: decision-016
title: Reduce-flash accessibility gate
date: '2026-09-09 23:18'
status: Accepted
---
## Context

`reference/snake.html` has a screen-flash effect (`S.flash`, decayed in
`decayFx()`, line 423) with no accessibility gate at all — no check for the
browser's `prefers-reduced-motion` media query or any in-game equivalent
setting, so the flash always plays for every player regardless of
photosensitivity or motion-sensitivity needs.

## Decision

Add a reduce-flash accessibility setting (or honor the platform's
reduced-motion signal where one exists) that suppresses or attenuates the
flash effect when enabled, gating a feature the oracle applies
unconditionally.

## Consequences

This is presentation-only (the flash is not part of
`docs/canonical-state.md`), so gating it has no simulation/determinism
consequence; it is a genuine feature addition beyond the oracle's behavior,
recorded here because DoD conventions require any behavior not present in
`reference/snake.html` to be registered rather than left implicit, even when
the change is purely additive/accessibility-motivated.


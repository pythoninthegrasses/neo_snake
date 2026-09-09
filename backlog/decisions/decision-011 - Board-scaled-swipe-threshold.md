---
id: decision-011
title: Board-scaled swipe threshold
date: '2026-09-09 23:18'
status: Accepted
---
## Context

`reference/snake.html`'s swipe gesture handling (`touchmove`, line 609-617)
uses a hardcoded `24` (CSS pixel) minimum drag distance before recognizing a
swipe direction, regardless of the board's on-screen cell size — so the same
`24px` threshold feels very different on a phone showing tiny cells versus a
tablet showing large ones.

## Decision

Scale the swipe-recognition threshold with the board's current on-screen
cell size (or another render-scale-derived quantity) instead of a fixed
pixel constant, so a swipe reads as "roughly a fraction of one cell" across
screen sizes rather than "exactly 24 device pixels."

## Consequences

Swipe feel is consistent across device sizes/resolutions instead of the
oracle's fixed-pixel behavior; the exact scaling factor is a tuning value
(candidate for `content/tuning.json`, [[decision-010]]) rather than a
frozen ABI constant, since it is purely an input-handling/UX concern with no
effect on `docs/canonical-state.md`.


---
id: decision-007
title: Integer vs float StyleBoxFlat corner radii
date: '2026-09-09 23:18'
status: Accepted
---
## Context

`reference/snake.html`'s CSS uses fractional-capable `border-radius` values
(e.g. lines 65, 89, 139, 163, 182, 198 — all currently whole numbers in this
file, but CSS itself permits sub-pixel radii and browsers render them with
antialiased subpixel precision). Godot's `StyleBoxFlat.corner_radius_*`
properties are typed as integers (pixels), with no equivalent sub-pixel
mode.

## Decision

Any UI chrome ported to Godot `StyleBoxFlat` rounds its corner radius to the
nearest integer pixel rather than attempting a subpixel-accurate
reproduction.

## Consequences

Corner rounding may be visually off by at most half a pixel compared to the
browser reference at any given zoom level — imperceptible in practice, and
a hard engine constraint rather than a design choice, so no future "fix" is
expected or possible without moving off `StyleBoxFlat`.


---
id: decision-006
title: Canvas shadowBlur approximated via additive radial-gradient sprite
date: '2026-09-09 23:18'
status: Accepted
---
## Context

`reference/snake.html` uses the 2D canvas API's `ctx.shadowBlur` (lines 465,
485) to give the snake head and food a soft glow — a browser-native blur
filter applied by the canvas renderer with no direct equivalent in Godot's
2D pipeline (Godot has no per-draw-call "shadowBlur" primitive for
`CanvasItem` drawing).

## Decision

Approximate the same soft-glow look with a pre-baked additive
radial-gradient sprite (a small texture whose alpha falls off from center to
edge) drawn under/around the glowing element, instead of a real per-pixel
blur.

## Consequences

The glow's falloff curve is an approximation of `shadowBlur`'s Gaussian-like
falloff, not a pixel-identical reproduction — acceptable because this is
pure visual polish with no gameplay or determinism stake. Future visual
tuning of "the glow" means editing the sprite/gradient asset, not a blur
radius parameter.


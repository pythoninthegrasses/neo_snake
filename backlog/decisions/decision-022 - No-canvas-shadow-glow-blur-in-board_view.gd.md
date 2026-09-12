---
id: decision-022
title: No canvas shadow/glow blur in board_view.gd
date: '2026-09-12 22:40'
status: Accepted
---
## Context

`reference/snake.html`'s `render()` uses `ctx.shadowColor`/`ctx.shadowBlur` to glow the food pellet
and the snake's head (snake.html:463-465, 483-485), each frame re-deriving the blur radius from the
food's pulse phase. Godot's 2D `CanvasItem` API (`draw_rect`, `draw_style_box`, `draw_circle`, ...)
has no equivalent soft-shadow/blur primitive — reproducing it would require a custom shader and an
extra backbuffer/viewport pass, which is disproportionate scope for a data-driven board renderer
(TASK-032) and not required by any of that task's Acceptance Criteria.

## Decision

`board_view.gd`'s `_draw()` fills food and snake segments with flat, unblurred colors — same fill
color, same shape, same corner radius, same back-to-front layer order as the oracle, just without
the soft glow. `game/content/palette.json`'s `food_shadow`/`snake_head_shadow` fields (TASK-030) are
kept as-is (they cost nothing to leave and record the oracle's intended glow color) but are unused
by `board_view.gd` until/unless a later task adds a shader-based glow pass.

## Consequences

Purely cosmetic: no gameplay, determinism, or `docs/canonical-state.md` implication. If a future task
wants the glow back, it can add a `CanvasItemMaterial`/custom shader pass without touching this
decision's fill-color/layering logic at all.

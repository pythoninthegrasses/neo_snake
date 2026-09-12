---
id: decision-023
title: Checkerboard alpha quantized by 8-bit baked texture
date: '2026-09-12 23:10'
status: Accepted
---
## Context

TASK-032 AC#2 requires the checkerboard background to render via a single baked `ImageTexture`
rather than 288 individual per-cell `fillRect` calls (`reference/snake.html:439-446`,
`rgba(255,255,255,.019)`). Baking necessarily means building the tile color into an `Image` with
`Image.FORMAT_RGBA8`, which quantizes each channel to 8 bits: `0.019 * 255 = 4.845`, stored as the
nearest integer `5`, read back as `5 / 255 ~= 0.0196`. This is the same class of rounding AC#3 calls
out by name for grid lines (why grid lines instead use a float `Color`, not `Color8`) — but for the
checkerboard specifically, AC#2 mandates the one approach (a baked texture) that makes the
quantization unavoidable.

## Decision

Accept the ~3% relative deviation (`0.0196` vs `0.019`) in the checkerboard tile's alpha as the cost
of satisfying AC#2's single-draw-call requirement. `game/tests/test_board_geometry.gd`'s checkerboard
test asserts alpha within a `0.004` tolerance rather than exact equality, documenting the quantization
as expected rather than a latent bug.

## Consequences

Purely cosmetic, sub-perceptual at `.55` opacity difference on a `.019`-alpha overlay: no gameplay,
determinism, or `docs/canonical-state.md` implication. If a future task needs exact-alpha checkerboard
fidelity, it would need a higher-precision image format (e.g. `FORMAT_RGBAF`) traded against the
larger texture size, which AC#2 does not require.

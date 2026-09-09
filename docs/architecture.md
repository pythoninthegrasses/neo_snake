# Architecture

Single file: `snake.html`. No build step, no dependencies, no modules — open in a browser.

Everything lives in one IIFE (`(() => { ... })();`) at the bottom of the file. CSS is in `<style>`
in `<head>`; there is no other file to keep in sync.

## Layout of the file

| Region | Contents |
| --- | --- |
| `<style>` | Theme via CSS custom properties, HUD/overlay styling, touch D-pad (revealed by `@media (hover: none) and (pointer: coarse)`) |
| markup | HUD stats, `.stage` > `canvas` + `.overlay`, D-pad, footer key hints |
| `<script>` | The whole game |

## State

One mutable object, `S`, holds all game state — there is no framework and no re-render diffing:

```js
S = { snake, dir, nextDir, food, score, best, status, wrap, acc, last, flash, particles }
```

`status` is the only state machine: `menu | playing | paused | dead`. Control flow branches on it
constantly (input, tick, overlay, pause). Grep for `S.status ===` when changing behavior — every
screen transition touches it.

DOM nodes are cached once in `el` (via `getElementById`). HUD text is written imperatively by
`sync()`; call `sync()` after any state change that the HUD displays.

## The two loops

`frame(now)` is the single `requestAnimationFrame` loop; `render()` runs every frame regardless of
pause state (so the board, particles and vignette stay correct while paused).

Simulation is **fixed-timestep with an accumulator**, deliberately decoupled from framerate:

- `S.acc += dt`, where `dt` is clamped to 64 ms so a backgrounded tab can't fast-forward the game.
- `while (S.acc >= tickMs()) advance()`, guarded by `guard++ < 6` to bound catch-up work.
- `tickMs()` is re-read *inside* the loop, because eating can raise the speed mid-frame.

Speed: `speedMul() = 1 + min(score, 40) * 0.035`, applied as `BASE_MS / speedMul()` and floored at
`MIN_MS`. Tuning difficulty means editing `BASE_MS` (130) / `MIN_MS` (55) — not framerate.

## Simulation (`advance()`)

Order matters here; this is the classic place snake clones break:

1. Commit `S.nextDir` into `S.dir` — input is queued, never applied instantly (that's what makes
   two direction presses in one tick safe, and what blocks 180° reversals in `queueDir`).
2. Compute the new head; wrap with modulo, or bail to `die()` if out of bounds (wall mode).
3. `const body = eating ? S.snake : S.snake.slice(0, -1)` — self-collision is tested against the
   tail *minus the cell it is about to vacate*. This is why moving into the space your tail leaves
   is legal. Keep that distinction if refactoring.
4. Only then `unshift` the head and `pop` the tail when not eating.

`placeFood()` builds the full list of unoccupied cells and picks one at random — O(COLS×ROWS) per
apple, fine at 24×24. Returning no free cells is the win condition.

## Rendering

`render()` draws in strict back-to-front order: background → checkerboard → grid lines → food →
snake body (iterated **tail-first**, `for (i = n-1; i >= 0; i--)`, so the head paints on top) →
eyes → particles → flash → pause vignette.

Everything is positioned in cell units multiplied by `cell`, which is derived from canvas pixel
size in `resize()`. Never hardcode pixel coordinates.

## Input

Four paths converge on `queueDir(name)`: keyboard, touch D-pad, swipe on `.stage`, and (indirectly)
the overlay button. `queueDir` is the single choke point for legality — reject reversals there, not
at the call sites.

Direction keys map through the `KEY` table to the four `DIRS` vectors; add bindings there rather
than branching in the handler.

## Overlay vs canvas

The DOM `.overlay` (toggled by `.show`) handles all text and buttons; the canvas handles the pause
vignette. `showOverlay()` takes HTML for its body — it uses `innerHTML`, so don't interpolate
untrusted strings.

## Verifying changes without a browser

There is no test suite. The practical approach used previously: `node --check` the extracted script
for syntax, then run it under a stubbed DOM (`document`/`canvas.getContext` as a Proxy, fake
`requestAnimationFrame` you pump manually, stub `localStorage`). To unit-test mechanics, expose the
internals by rewriting the IIFE's closing `})();` to attach `S`/`advance`/`reset` to `globalThis`
first, then drive `advance()` directly with a fabricated `S.food` — that is how eat, wall-death,
wrap and reversal-guard behavior were checked.

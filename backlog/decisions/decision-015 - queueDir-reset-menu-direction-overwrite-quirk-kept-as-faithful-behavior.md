---
id: decision-015
title: queueDir/reset menu-direction-overwrite quirk kept as faithful behavior
date: '2026-09-09 23:18'
status: Accepted
---
## Context

`reference/snake.html`'s `queueDir()` (line 569-576), when called from the
menu or dead state, sets `S.nextDir` to the pressed direction and then calls
`start()` because `S.status === "menu" || S.status === "dead"`. But `start()`
calls `reset()`, which unconditionally overwrites
`S.dir = S.nextDir = DIRS.right` (line 312) — clobbering the direction that
was just queued by the very keypress that triggered `start()`. The net
effect: pressing Up (or Left/Down) from the menu still starts the snake
moving right, only Right itself "does what you'd expect," and this has
presumably been the oracle's actual behavior the whole time it's been used
as a reference, unnoticed or unremarked.

## Decision

This is a real bug in `reference/snake.html`, but it is being **kept as
faithful oracle behavior, not fixed**. The Godot implementation must
reproduce it exactly: starting the game via any directional input while in
`menu`/`dead` state results in the snake moving right on the first tick,
regardless of which direction key/swipe/button triggered the start.

## Consequences

Any future contributor who "fixes" this — making the first queued direction
actually take effect on start — is introducing an undocumented divergence
from the oracle and must instead either (a) leave it alone, or (b) record a
*new*, separate `backlog/decisions/` entry explicitly superseding this one if
a deliberate, reviewed change is ever wanted. A differential oracle-vs-Godot
test that exercises "start via non-Right input" should assert the snake
moves right, not fail expecting the pressed direction — asserting the
"intuitive" behavior would itself be the bug.


---
id: decision-008
title: HUD-not-synced-on-win-frame bug
date: '2026-09-09 23:18'
status: Accepted
---
## Context

`reference/snake.html`'s `win()` (line 405-408) sets `S.status = "dead"` and
shows the win overlay immediately, without first re-running the HUD update
step (`el.score`/`el.best` text content, normally refreshed once per
`advance()`) for the final winning tick — so the on-canvas/DOM score label
can lag one tick behind the score value baked into the win overlay's own
message text on the exact frame the board fills. This is a genuine,
reproducible bug in the oracle, not a deliberate design choice.

## Decision

Reproduce this bug rather than fix it: the Godot implementation's HUD update
must follow the oracle's own call order exactly, including on the win-frame
path, so that any given tick's observable (HUD text, overlay text) output
matches the oracle bug-for-bug rather than a "corrected" version the oracle
was never verified against.

## Consequences

A future contributor who notices the HUD momentarily disagreeing with the
overlay on a win frame should treat it as expected, oracle-faithful behavior,
not a regression to fix — unless a separate, explicit decision is made later
to diverge from the oracle here (which would itself need its own
`backlog/decisions/` entry, per this repo's convention of registering
divergences, not silently introducing or silently "fixing" them).


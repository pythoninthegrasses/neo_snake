---
id: decision-013
title: Debounced disk writes
date: '2026-09-09 23:18'
status: Accepted
---
## Context

`reference/snake.html` writes to `localStorage` synchronously and
immediately every time the best score changes (line 389:
`localStorage.setItem("snake.best", String(S.best))`), which is cheap and
fine for a browser's `localStorage` (an in-process synchronous key-value
store) but is not the right pattern for a native game writing an actual save
file to disk, where frequent small synchronous writes are comparatively
expensive and can cause hitches or excess disk wear if triggered every tick
a score changes.

## Decision

Debounce persisted-state disk writes (best score, persisted mode
([[decision-009]])) — coalesce rapid successive changes into a single
write after a short delay or on a natural checkpoint (e.g. game-over, pause,
app-background) rather than writing on every change.

## Consequences

A crash or force-quit within the debounce window can lose the most recent
unsaved change (e.g. a best score set moments before a crash); this is an
accepted tradeoff for reduced disk I/O, not a correctness requirement, since
persisted best/mode are convenience state, not simulation state subject to
`docs/canonical-state.md`'s determinism guarantees.


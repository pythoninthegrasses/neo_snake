---
id: decision-009
title: Per-mode best score and persisted mode
date: '2026-09-09 23:18'
status: Accepted
---
## Context

`reference/snake.html` persists exactly one best score under a single
`localStorage` key (`"snake.best"`, line 294/389) shared across every game
mode (the `<select id="mode">` at line 234 offers at least a normal/wrap
distinction), and does not persist which mode was last selected — every page
load resets the mode selector to its default and a wrap-mode run's high
score can overwrite (or be overwritten by) a normal-mode run's, since both
share one key.

## Decision

Persist a best score per mode (a separate stored value per mode identifier,
not one shared scalar) and persist the last-selected mode itself, restoring
it on next launch instead of always defaulting.

## Consequences

Save data grows from one scalar to one entry per mode plus a mode selection;
any future new mode needs its own best-score slot from the start rather than
sharing one. This changes user-visible persisted state shape versus the
oracle, so any save-migration tooling (if ever needed) must account for the
oracle's single-key format as the "old" shape.


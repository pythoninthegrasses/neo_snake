---
id: decision-018
title: No audio (snake.html has none)
date: '2026-09-09 23:18'
status: Accepted
---
## Context

`reference/snake.html` has no audio whatsoever — no sound effects, no
music, not even a stub `<audio>` element or `AudioContext` reference
anywhere in the file. Any audio added to the Godot implementation is
therefore, by definition, new functionality with no oracle behavior to
match or diverge from.

## Decision

Audio (sound effects, music, or both) may be added to the Godot
implementation as a purely additive feature. This entry exists to record
that the oracle's silence is a fact about `reference/snake.html`, not a
constraint the Godot implementation must also satisfy — the absence of
audio in the oracle is not itself a design decision to preserve.

## Consequences

No oracle-parity test can meaningfully assert anything about audio (there is
nothing to compare against), so audio correctness is validated by manual
testing, not the differential corpus. Adding audio never touches
`docs/canonical-state.md` and carries no `NS_ABI_VERSION`/`NS_CANON_VERSION`/
`CORPUS_VERSION` consequences.


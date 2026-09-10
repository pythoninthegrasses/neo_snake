---
id: decision-010
title: Tuning constants moved to content/tuning.json
date: '2026-09-09 23:18'
status: Accepted
---
## Context

`reference/snake.html` hardcodes every gameplay tuning constant (tick-speed
formula coefficients, particle counts/lifetimes, flash decay rate, swipe
threshold, etc.) directly in the IIFE's JS source — appropriate for a
single frozen-oracle file that must never be edited (per this repo's own
`AGENTS.md`), but not appropriate for an actively-developed Godot project
where tuning needs to be iterated on without recompiling/redeploying code.

## Decision

Move tuning constants that are not part of the frozen ABI/canonical-format
freezes (`docs/abi-decisions.md`) out of code and into a data file,
`content/tuning.json`, loaded at runtime.

## Consequences

Any constant placed in `content/tuning.json` must not be one of the six
frozen ABI decisions (the tick-period table, RNG algorithm, canonical
format, etc. — those are pinned precisely because every implementation must
agree on them bit-for-bit, which a designer-editable JSON file would
undermine). This is purely a workflow/maintainability change for
presentation and non-ABI gameplay-feel tuning, not a simulation behavior
change by itself.


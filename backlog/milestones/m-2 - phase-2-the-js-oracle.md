---
id: m-2
title: "Phase 2: The JS oracle"
---

## Description

Extract a headless JS core from reference/snake.html (rng.mjs, canon.mjs, sim.mjs) implementing Phase 1's frozen contracts. Generate and commit the first JSONL seed corpus, and wire task oracle:verify so a stale oracle/corpus pair fails loudly. Built before the Zig core so the core targets something concrete.

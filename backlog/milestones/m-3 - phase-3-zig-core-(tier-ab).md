---
id: m-3
title: "Phase 3: Zig core (Tier-A/B)"
---

## Description

core/rng.zig, core/canon.zig, core/world.zig: pure, no libc, no allocator. Tier-A unit suite (zig build test), Tier-B hermetic corpus difftest against the committed JSONL corpus (zig build difftest), fuzz invariants over 256 committed seeds, and the nightly discovery fuzzer that promotes failing seeds into the permanent corpus.

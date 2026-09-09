---
id: decision-003
title: Math.random() replaced by the seeded xoshiro128** PRNG
date: '2026-09-09 23:18'
status: Accepted
---
## Context

`reference/snake.html` draws all randomness (food placement, particle burst
angle/speed/hue) from the browser's implicit, unseeded `Math.random()`. That
is fine for a single-player, non-replayable, single-runtime game, but this
project needs the same sequence of simulation random draws to be reproducible
byte-for-byte across the JS oracle, the Zig core, and GDScript, and
eventually across two networked peers in lockstep multiplayer — none of
which `Math.random()` can guarantee (it isn't seedable, and isn't specified
to produce the same sequence across engines or even across runs).

## Decision

Replace `Math.random()`, for all simulation-affecting randomness (food
placement), with a single explicitly-seeded `xoshiro128**` stream, fully
specified in `docs/rng.md` (TASK-008) and frozen as ABI freeze #3 in
`docs/abi-decisions.md` (TASK-009).

## Consequences

Every implementation (oracle, core, GDExtension shim) must use the exact
`next()` algorithm and seeding rule in `docs/rng.md`, not "a good PRNG" —
any substitution is a breaking change per freeze #3, invalidating every
committed corpus fixture. This is the seed decision that TASK-008/009 build
on; it exists here to record *why* the divergence from the oracle's
behavior was introduced, not to restate the algorithm itself.


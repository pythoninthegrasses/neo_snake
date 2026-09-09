# RNG: xoshiro128**

The simulation uses a single seeded **xoshiro128\*\*** stream (Blackman & Vigna, 2018) in place of
`reference/snake.html`'s bare `Math.random()`. This is a deliberate divergence from the oracle
(seeding is required for deterministic replay across JS/Zig/GDScript and for lockstep netcode) —
see `backlog/decisions/` (seeded by TASK-011) for the formal record. This document is the
implementation spec: the algorithm, the seeding rule, the bounded-draw formula, and why all of it
stays bit-exact in JavaScript's float64 without `Math.imul` or `BigInt`.

The 128-bit state (`s0, s1, s2, s3`, each `u32`) is exactly the `rng_state` field reserved in
`docs/canonical-state.md`.

## `next()`: the core step

Per-call state transition and output, using 32-bit unsigned values throughout (all arithmetic
below is modulo 2^32 except where noted):

```
rotl(x, k) = (x << k) | (x >> (32 - k))          // 32-bit rotate left

next():
    result = rotl(s1 * 5, 7) * 9
    t      = s1 << 9

    s2 ^= s0
    s3 ^= s1
    s1 ^= s2
    s0 ^= s3

    s2 ^= t
    s3  = rotl(s3, 11)

    return result   // the u32 output
```

This is the reference `xoshiro128**` step verbatim (confirmed against the public reference
implementation at prng.di.unimi.it/xoshiro128starstar.c) — no modification, no simplification.
State must never be all-zero (the algorithm's own precondition); a zero seed is a caller bug, not
a case this spec needs to handle gracefully.

### JS-exactness argument

JavaScript numbers are float64 and represent integers exactly up to 2^53
(`Number.MAX_SAFE_INTEGER + 1 = 9,007,199,254,740,992`). Every intermediate value in `next()` must
stay under that bound for the JS oracle to match Zig/GDScript's native 32-bit-wrapping integer math
bit-for-bit:

- `s1 * 5`: `s1 < 2^32`, so `s1 * 5 < 5 * (2^32 - 1) < 2^35`.
- `rotl(s1*5, 7)`: a 32-bit rotate of a value already reduced mod 2^32 (via `>>> 0` in JS, or
  native wraparound in Zig/GDScript) — result `< 2^32`.
- `rotl(...) * 9`: `< 9 * (2^32 - 1) < 2^36`.

Both products (`2^35`, `2^36`) are many orders of magnitude below `2^53`, so JS represents them
exactly as ordinary numbers; no `Math.imul` (which exists precisely to work around 32-bit overflow
in *larger* products) and no `BigInt` are needed anywhere in `next()`. Every implementation must
still mask/truncate to 32 bits after each operation that can exceed it (`s1*5`, `<< 9`, the final
`*9`) — in JS via `>>> 0`, in Zig via wrapping `u32` arithmetic (`*%`, `<<`), in GDScript via `& 0xFFFFFFFF`
after each shift/multiply — so that rotate and xor operate on the correct 32-bit value in all three
languages.

## Seeding

The state is seeded with **four literal `u32` values**, one per state word (`s0, s1, s2, s3`),
supplied directly by the caller (e.g. from `canon_version`'s companion seed field, a test fixture,
or a lockstep session's agreed-upon seed) — **never** expanded from a single `u64`/string seed via
a splitmix-style expander. This is deliberate: every published splitmix64-style seed expander
multiplies by a 64-bit odd constant (e.g. splitmix64's `0x9E3779B97F4A7C15`), and a full 64x64-bit
multiply's product can exceed `2^53`, silently losing bits in the JS oracle while Zig's native
`u64` arithmetic stays exact — a JS-vs-Zig divergence baked into the seed itself, before a single
`next()` call. Requiring four literal `u32`s up front removes that failure mode entirely: seeding
has no arithmetic to lose precision over.

## Bounded draw: `boundedDraw(next, n)`

Used to pick a uniformly-distributed index in `[0, n)` from a raw `u32` draw, via the classic
multiply-high (fixed-point) technique:

```
boundedDraw(next, n):
    r = next()                    // u32
    return (r * n) >> 32          // top 32 bits of the 64-bit product r * n
```

`r` and `n` are both treated as unsigned; the result is `floor((r / 2^32) * n)`, i.e. `r`
interpreted as a fraction of `[0, 1)` scaled into `[0, n)`.

**JS implementation note and exactness domain:** `r < 2^32` and the product `r * n` must stay
under `2^53` for the JS oracle to compute it exactly with a plain `*` (no `BigInt`, no splitting
into high/low halves). Solving `r_max * n < 2^53` for the worst case `r = 2^32 - 1` gives
**`n < 2,097,152` (2^21)** as the exact validity domain of this formula in JS. Any `n` at or above
that bound requires a 64-bit-safe implementation (e.g. `BigInt` in JS, or splitting `r` into
high/low 16-bit halves) — this project's boards (`cols`, `rows` each realistically well under 256,
so free-cell counts are at most a few thousand) never approach it, but a future board-size change
that pushes free-cell counts past 2^21 must revisit this formula, not just this comment. Given
`r * n < 2^53` holds, `(r * n) >> 32` is computed in JS as `Math.floor((r * n) / 4294967296)` —
a right-shift-by-32 is not directly usable in JS because `>>`/`>>>` first coerce their operands to
32-bit, which would truncate `r * n` before the shift.

In Zig and GDScript (both of which have real 64-bit integer types), the same formula is a literal
`u64` multiply followed by a real `>> 32`, with no domain restriction below `2^64`.

### Accepted divergence: modulo bias

This formula has a small, well-understood modulo bias: outputs are not perfectly uniform over
`[0, n)` unless `n` is a power of two (some remainders are very slightly more likely than others,
with bias magnitude `O(n / 2^32)`). `reference/snake.html`'s original `(Math.random() * n) | 0` has
its own distinct bias (float64 double-rounding, entirely different shape). Neither is Fisher-Yates
levels of concern at these board sizes, and **this bias is an accepted, deliberate divergence from
`reference/snake.html`'s float-based random draw** — the point of switching PRNGs is determinism
and cross-language reproducibility, not eliminating a bias that was already present in a different
form. It is not "fixed" (e.g. via rejection sampling) because rejection sampling makes the number
of `next()` calls per draw data-dependent, which is worse for lockstep netcode than a small,
well-characterized bias.

## Food placement

1. Enumerate free cells in **row-major order**: outer loop over `y` from `0` to `rows-1`, inner
   loop over `x` from `0` to `cols-1` (matching `reference/snake.html`'s `placeFood()` loop order
   exactly), collecting every `(x, y)` not occupied by any player's snake.
2. Draw `boundedDraw(next, free.length)` from the shared RNG stream and index into the free-cell
   list to get the new food position. If `free.length == 0`, there is no food to place (the
   `0xFFFF, 0xFFFF` sentinel in `docs/canonical-state.md`).
3. **Multiplayer**: when more than one player needs a food placement in the same tick (e.g. two
   players both ate on the same step, or initial reset with `player_count > 1`), placements happen
   **in ascending player index order**, each consuming the next draw(s) from the single shared RNG
   stream — never a per-player RNG stream (see `docs/abi-decisions.md`, TASK-009, for why: per-player
   streams make rollback netcode reconstruct-order-dependent). This makes the sequence of RNG draws
   — and therefore the resulting food positions — deterministic given only the seed and the players'
   actions, independent of any engine-internal iteration order.

## Test vectors

Generated and independently re-derived from the algorithm above (script, not hand-computed) —
useful as a first correctness check for any new-language port:

Seed `s0,s1,s2,s3 = 1,2,3,4`, first 8 raw `next()` outputs (`u32`, hex):

```
0x00002d00, 0x00000000, 0x005a7080, 0x04389d80,
0x79199d9b, 0x61963b24, 0x4cb9b57a, 0xde9d7431
```

State after those 8 calls: `s0=0x3320a290, s1=0xebdc5e1d, s2=0x90c43618, s3=0xe4b42f08`.

Same seed, `boundedDraw(next, 573)` (`573` = free cells on a 24x24 board minus a 3-cell starting
snake) for the first 5 draws, continuing the stream from the fresh seed (not from the state above):

```
0, 0, 0, 9, 271
```

A port that reproduces both sequences exactly from the same seed is verified against this spec.

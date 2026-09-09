// xoshiro128** PRNG oracle — implementation of docs/rng.md.
//
// Seeded from four literal u32 words (never expanded from a single seed); see
// docs/rng.md for why the state stays bit-exact in float64 without Math.imul
// or BigInt. Every operation that can exceed 32 bits is masked with `>>> 0`.

const u32 = (x) => x >>> 0;

// 32-bit rotate left. The `>>> 0` on the left operand keeps the shifted value
// 32 bits wide before the or; the final `>>> 0` normalizes the result.
const rotl = (x, k) => (((x >>> 0) << k) | (x >>> (32 - k))) >>> 0;

/**
 * Create a fresh stream from four u32 state words (s0..s3).
 * State must never be all-zero — a zero seed is a caller bug, not a case
 * this spec handles gracefully.
 */
export function createRng(seed) {
  if (!Array.isArray(seed) || seed.length !== 4) {
    throw new TypeError('seed must be four u32 values [s0, s1, s2, s3]');
  }
  const s = seed.map(u32);
  if (s[0] === 0 && s[1] === 0 && s[2] === 0 && s[3] === 0) {
    throw new RangeError('rng state must not be all-zero');
  }

  // The core step from docs/rng.md. Each word is masked back to 32 bits after
  // every operation that can exceed one (`* 5`, `* 9`, `<< 9`): JS's bitwise
  // operators coerce through *signed* 32 bits, so an unmasked product above
  // 2^31 would reach xor as a negative value and corrupt the state.
  function next() {
    const result = (rotl((s[1] * 5) >>> 0, 7) * 9) >>> 0;
    const t = (s[1] << 9) >>> 0;

    s[2] = (s[2] ^ s[0]) >>> 0;
    s[3] = (s[3] ^ s[1]) >>> 0;
    s[1] = (s[1] ^ s[2]) >>> 0;
    s[0] = (s[0] ^ s[3]) >>> 0;

    s[2] = (s[2] ^ t) >>> 0;
    s[3] = rotl(s[3], 11);

    return result;
  }

  return {
    next,
    // Copy of the current state, e.g. to fill the canon `rng_state` field.
    state: () => s.slice(),
  };
}

/**
 * Uniform-ish index in [0, n) from one raw u32 draw: the top 32 bits of the
 * 64-bit product r * n. Valid in JS for n < 2^21 (2,097,152) — beyond that
 * `r * n` exceeds Number.MAX_SAFE_INTEGER and the low bits are no longer
 * exact; see docs/rng.md ("Bounded draw").
 */
export function boundedDraw(next, n) {
  if (!Number.isInteger(n) || n <= 0 || n >= 2097152) {
    throw new RangeError('boundedDraw requires an integer n in (0, 2^21)');
  }
  const r = next();
  return Math.floor((r * n) / 4294967296);
}

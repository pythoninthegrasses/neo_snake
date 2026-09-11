//! xoshiro128** PRNG — implementation of docs/rng.md.
//!
//! Seeded from four literal u32 words (never expanded from a single seed;
//! see docs/rng.md for why). Native u32 wrapping arithmetic replaces the JS
//! oracle's `>>> 0` masks: every operation that can exceed 32 bits (`* 5`,
//! `* 9`, `<< 9`) wraps, so rotate and xor operate on the correct 32-bit
//! value exactly as docs/rng.md's JS-exactness argument requires.
//!
//! No allocator, no libc: the state is four `u32`s owned by the caller.

const std = @import("std");

pub const Rng = struct {
    s0: u32,
    s1: u32,
    s2: u32,
    s3: u32,

    /// Seeds the stream from four u32 words (s0..s3). State must never be
    /// all-zero — a zero seed is a caller bug, not a case this spec handles
    /// gracefully (xoshiro's own precondition).
    pub fn init(seed: [4]u32) Rng {
        std.debug.assert(seed[0] != 0 or seed[1] != 0 or seed[2] != 0 or seed[3] != 0);
        return .{ .s0 = seed[0], .s1 = seed[1], .s2 = seed[2], .s3 = seed[3] };
    }

    fn rotl(x: u32, comptime k: u5) u32 {
        // std.math.rotl wraps the shift count (1 +% ~k), so it stays in-range
        // even when 32 - k would overflow a u5 shift operand.
        return std.math.rotl(u32, x, k);
    }

    /// The core step from docs/rng.md: the reference xoshiro128** step
    /// verbatim, no modification.
    pub fn next(self: *Rng) u32 {
        const result = rotl(self.s1 *% 5, 7) *% 9;
        const t = self.s1 << 9;

        self.s2 ^= self.s0;
        self.s3 ^= self.s1;
        self.s1 ^= self.s2;
        self.s0 ^= self.s3;

        self.s2 ^= t;
        self.s3 = rotl(self.s3, 11);

        return result;
    }

    /// Uniform-ish index in [0, n): the top 32 bits of the 64-bit product
    /// `r * n` (docs/rng.md "Bounded draw"). Zig has real 64-bit integers,
    /// so unlike the JS oracle this has no exactness domain below 2^64;
    /// `n > 0` is all that is required. The modulo bias is the accepted,
    /// deliberate divergence documented in docs/rng.md.
    pub fn boundedDraw(self: *Rng, n: u32) u32 {
        std.debug.assert(n > 0);
        const r: u64 = self.next();
        return @truncate((r * @as(u64, n)) >> 32);
    }

    /// Current state words, e.g. to fill the canon `rng_state` field
    /// (docs/canonical-state.md).
    pub fn state(self: Rng) [4]u32 {
        return .{ self.s0, self.s1, self.s2, self.s3 };
    }
};

// docs/rng.md "Test vectors": seed [1,2,3,4], first 8 raw next() outputs —
// the same sequence reference/oracle/rng.mjs produces (AC#2).
test "next matches docs/rng.md published vector" {
    var rng = Rng.init(.{ 1, 2, 3, 4 });
    const expected = [_]u32{
        0x00002d00, 0x00000000, 0x005a7080, 0x04389d80,
        0x79199d9b, 0x61963b24, 0x4cb9b57a, 0xde9d7431,
    };
    for (expected) |want| {
        try std.testing.expectEqual(want, rng.next());
    }
    try std.testing.expectEqualSlices(
        u32,
        &[_]u32{ 0x3320a290, 0xebdc5e1d, 0x90c43618, 0xe4b42f08 },
        &rng.state(),
    );
}

// Same seed, boundedDraw(next, 573) for the first 5 draws, fresh stream
// (docs/rng.md "Test vectors").
test "boundedDraw matches docs/rng.md published vector" {
    var rng = Rng.init(.{ 1, 2, 3, 4 });
    const expected = [_]u32{ 0, 0, 0, 9, 271 };
    for (expected) |want| {
        try std.testing.expectEqual(want, rng.boundedDraw(573));
    }
}

//! Tier-C ABI conformance tests (TASK-025): every test in this file reaches
//! core/abi.zig exclusively through `@cImport(include/neo_snake.h)` — never by
//! `@import`ing world.zig/rng.zig/canon.zig/corpus.zig directly. That rule is
//! mechanically enforced by tools/validate_abi_test_purity.py, which fails the
//! build if this file `@import`s anything other than `"std"`. Without that
//! guard Tier-C silently degrades into a second copy of Tier-A (docs/abi-impl.md
//! makes the same "why a separate boundary" case for abi.zig itself).
//!
//! Five named tests, matching the task description one-for-one:
//!   1. the ABI version handshake
//!   2. ns_body_copy reporting the true required length on a too-small buffer
//!   3. every ns_result value reachable from at least one call path
//!   4. @sizeOf/@offsetOf on the C structs matching docs/canonical-state.md
//!   5. a committed corpus trace replaying to its committed checksum

const std = @import("std");

const c = @cImport({
    @cInclude("neo_snake.h");
});

/// Every test here uses a small, fixed 12x12 board — comfortably under this
/// buffer's size (checked at runtime against ns_world_size, not assumed).
const StorageBuf = struct {
    bytes: [4096]u8 align(16) = undefined,

    fn ptr(self: *StorageBuf) *c.ns_world {
        return @ptrCast(&self.bytes);
    }
};

fn makeConfig(cols: u16, rows: u16, wrap: bool, seed: [4]u32) c.ns_config {
    return .{
        .abi_version = c.NS_ABI_VERSION,
        .cols = cols,
        .rows = rows,
        .player_count = 1,
        .wrap = if (wrap) 1 else 0,
        .rng_seed = seed,
        .speed_source = c.NS_SPEED_SOURCE_SCORE_TABLE,
        ._pad = .{ 0, 0, 0 },
    };
}

fn initOk(storage: *StorageBuf, config: *const c.ns_config) !void {
    try std.testing.expect(c.ns_world_size(config) <= storage.bytes.len);
    try std.testing.expectEqual(@as(c.ns_result, c.NS_OK), c.ns_world_init(storage.ptr(), config));
}

test "ns_world_init rejects a mismatched abi_version and accepts the real one" {
    var storage: StorageBuf = .{};
    var config = makeConfig(12, 12, false, .{ 1, 2, 3, 4 });

    config.abi_version = c.NS_ABI_VERSION + 1;
    try std.testing.expectEqual(
        @as(c.ns_result, c.NS_ERR_ABI_VERSION_MISMATCH),
        c.ns_world_init(storage.ptr(), &config),
    );

    config.abi_version = c.NS_ABI_VERSION;
    try initOk(&storage, &config);
}

test "ns_body_copy reports the true required length on a too-small buffer" {
    var storage: StorageBuf = .{};
    const config = makeConfig(12, 12, false, .{ 1, 2, 3, 4 });
    try initOk(&storage, &config);

    // Any legal direction from .menu auto-starts the game (decision-015);
    // reset()'s starting snake is always 3 cells regardless of which
    // direction was queued (reset() overwrites next_dir right after).
    try std.testing.expectEqual(@as(c.ns_result, c.NS_OK), c.ns_queue_dir(storage.ptr(), 0, c.NS_DIR_UP));

    var too_small: [1]c.ns_cell = undefined;
    var required: usize = 0;
    const res = c.ns_body_copy(storage.ptr(), 0, &too_small, too_small.len, &required);
    try std.testing.expectEqual(@as(c.ns_result, c.NS_ERR_BUFFER_TOO_SMALL), res);
    try std.testing.expectEqual(@as(usize, 3), required);

    var exact: [3]c.ns_cell = undefined;
    try std.testing.expectEqual(
        @as(c.ns_result, c.NS_OK),
        c.ns_body_copy(storage.ptr(), 0, &exact, exact.len, &required),
    );
    try std.testing.expectEqual(@as(usize, 3), required);
}

test "every ns_result value is reachable from at least one call path" {
    var storage: StorageBuf = .{};
    var config = makeConfig(12, 12, false, .{ 1, 2, 3, 4 });

    // NS_ERR_ABI_VERSION_MISMATCH
    config.abi_version = c.NS_ABI_VERSION + 1;
    try std.testing.expectEqual(
        @as(c.ns_result, c.NS_ERR_ABI_VERSION_MISMATCH),
        c.ns_world_init(storage.ptr(), &config),
    );
    config.abi_version = c.NS_ABI_VERSION;

    // NS_ERR_INVALID_ARGUMENT (a zero player_count is rejected before any
    // world exists)
    const bad_count = blk: {
        var cfg = config;
        cfg.player_count = 0;
        break :blk cfg;
    };
    try std.testing.expectEqual(
        @as(c.ns_result, c.NS_ERR_INVALID_ARGUMENT),
        c.ns_world_init(storage.ptr(), &bad_count),
    );

    // NS_OK
    try initOk(&storage, &config);

    // NS_ERR_INVALID_ARGUMENT again, this time from an out-of-range player
    // index on an already-initialized world.
    try std.testing.expectEqual(
        @as(c.ns_result, c.NS_ERR_INVALID_ARGUMENT),
        c.ns_queue_dir(storage.ptr(), 1, c.NS_DIR_UP),
    );

    // NS_ERR_BUFFER_TOO_SMALL
    try std.testing.expectEqual(@as(c.ns_result, c.NS_OK), c.ns_queue_dir(storage.ptr(), 0, c.NS_DIR_UP));
    var too_small: [1]c.ns_cell = undefined;
    var required: usize = 0;
    try std.testing.expectEqual(
        @as(c.ns_result, c.NS_ERR_BUFFER_TOO_SMALL),
        c.ns_body_copy(storage.ptr(), 0, &too_small, too_small.len, &required),
    );

    // NS_ERR_DECODE_FAILED (garbage bytes, wrong magic)
    const garbage = [_]u8{0} ** 44;
    try std.testing.expectEqual(
        @as(c.ns_result, c.NS_ERR_DECODE_FAILED),
        c.ns_deserialize(storage.ptr(), &garbage, garbage.len),
    );
}

test "@sizeOf/@offsetOf on the wire structs match docs/canonical-state.md exactly" {
    try std.testing.expectEqual(@as(usize, 44), @sizeOf(c.ns_canon_header));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(c.ns_canon_header, "magic"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(c.ns_canon_header, "canon_version"));
    try std.testing.expectEqual(@as(usize, 10), @offsetOf(c.ns_canon_header, "cols"));
    try std.testing.expectEqual(@as(usize, 12), @offsetOf(c.ns_canon_header, "rows"));
    try std.testing.expectEqual(@as(usize, 14), @offsetOf(c.ns_canon_header, "flags"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(c.ns_canon_header, "player_count"));
    try std.testing.expectEqual(@as(usize, 20), @offsetOf(c.ns_canon_header, "tick"));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(c.ns_canon_header, "rng_state"));
    try std.testing.expectEqual(@as(usize, 40), @offsetOf(c.ns_canon_header, "food_x"));
    try std.testing.expectEqual(@as(usize, 42), @offsetOf(c.ns_canon_header, "food_y"));

    // ns_player_view doubles as the wire-exact mirror of the per-player
    // 16-byte fixed block (include/neo_snake.h's own comment on the type).
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(c.ns_player_view));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(c.ns_player_view, "status"));
    try std.testing.expectEqual(@as(usize, 1), @offsetOf(c.ns_player_view, "dir"));
    try std.testing.expectEqual(@as(usize, 2), @offsetOf(c.ns_player_view, "next_dir"));
    try std.testing.expectEqual(@as(usize, 4), @offsetOf(c.ns_player_view, "score"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(c.ns_player_view, "body_len"));
}

// --- corpus replay -----------------------------------------------------

/// Trivial hex decoder, deliberately re-implemented here rather than
/// `@import`ed from anywhere: the purity rule only allows `"std"`, and this
/// is small enough that duplicating it costs less than the alternative
/// (some non-"std" shared module Tier-C would then depend on).
fn hexDecode(alloc: std.mem.Allocator, hex: []const u8) ![]u8 {
    std.debug.assert(hex.len % 2 == 0);
    const out = try alloc.alloc(u8, hex.len / 2);
    for (out, 0..) |*b, i| b.* = try std.fmt.parseInt(u8, hex[i * 2 .. i * 2 + 2], 16);
    return out;
}

fn dirFromName(name: []const u8) ?c.ns_dir {
    if (std.mem.eql(u8, name, "up")) return c.NS_DIR_UP;
    if (std.mem.eql(u8, name, "down")) return c.NS_DIR_DOWN;
    if (std.mem.eql(u8, name, "left")) return c.NS_DIR_LEFT;
    if (std.mem.eql(u8, name, "right")) return c.NS_DIR_RIGHT;
    return null;
}

/// Serializes the live world and checks its checksum trailer against `want`
/// (a corpus line's decimal-string `c` field) via ns_serialize + ns_checksum.
/// ns_checksum takes the *whole* already-encoded record (header + player
/// records + the trailer ns_serialize just wrote) and itself hashes only the
/// prefix up to but not including the last 8 bytes (docs/canonical-state.md's
/// algorithm) — the trailer bytes are present in what's passed but excluded
/// from what's hashed, not excluded from the argument itself.
fn expectChecksum(storage: *StorageBuf, want_decimal: []const u8) !void {
    var out_buf: [512]u8 = undefined;
    var written: usize = 0;
    try std.testing.expectEqual(
        @as(c.ns_result, c.NS_OK),
        c.ns_serialize(storage.ptr(), &out_buf, out_buf.len, &written),
    );
    try std.testing.expect(written >= 8);

    var checksum: u64 = 0;
    try std.testing.expectEqual(
        @as(c.ns_result, c.NS_OK),
        c.ns_checksum(&out_buf, written, &checksum),
    );
    const want = try std.fmt.parseInt(u64, want_decimal, 10);
    try std.testing.expectEqual(want, checksum);
}

const RawInEvent = struct { p: u8, dir: []const u8 };
const RawLine = struct {
    t: u32,
    in: []const RawInEvent,
    c: []const u8,
    s: ?[]const u8 = null,
};
const RawHeader = struct {
    seed: [4]u32,
    cols: u16,
    rows: u16,
    wrap: bool,
    players: u8,
    corpus_version: u32,
};

test "a committed corpus trace replays to its committed checksum using only the C API" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // core/ and game/ are sibling directories (docs/corpus-format.md); this
    // is the same small trace difftest.zig's Tier-B pass replays, chosen here
    // for its size (6 tick lines) and because it exercises a real
    // reversal-rejection (down, then a rejected up-after-down, then right).
    const path = "../game/tests/corpus/reject-180-down-then-up.jsonl";
    const raw = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, alloc, .limited(1 << 20));

    var it = std.mem.splitScalar(u8, raw, '\n');
    const header_text = it.first();
    const header = try std.json.parseFromSliceLeaky(RawHeader, alloc, header_text, .{});
    try std.testing.expectEqual(@as(u8, 1), header.players);

    var storage: StorageBuf = .{};
    const config = makeConfig(header.cols, header.rows, header.wrap, header.seed);
    try initOk(&storage, &config);

    var first_line = true;
    while (it.next()) |text| {
        if (text.len == 0) continue;
        const line = try std.json.parseFromSliceLeaky(RawLine, alloc, text, .{});

        if (first_line) {
            first_line = false;
            // The ABI always starts a fresh world in .menu (decision-015),
            // while this trace — like every committed corpus trace — was
            // recorded from a world that started already .playing
            // (regen_corpus.mjs's initialState()). ns_deserialize is the
            // legitimate C-API entry point to reach that same starting
            // point directly, the same way difftest.zig's Tier-B replay
            // bypasses the menu transition via world_mod.initWorld.
            const anchor_hex = line.s orelse return error.MissingTickZeroAnchor;
            const rec = try hexDecode(alloc, anchor_hex);
            try std.testing.expectEqual(
                @as(c.ns_result, c.NS_OK),
                c.ns_deserialize(storage.ptr(), rec.ptr, rec.len),
            );
            try expectChecksum(&storage, line.c);
            continue;
        }

        const inputs = try alloc.alloc(c.ns_input, line.in.len);
        for (line.in, inputs) |ev, *inp| {
            inp.* = .{
                .player = ev.p,
                .dir = dirFromName(ev.dir) orelse return error.UnknownDirection,
                ._pad = .{ 0, 0 },
            };
        }
        try std.testing.expectEqual(
            @as(c.ns_result, c.NS_OK),
            c.ns_step(storage.ptr(), inputs.ptr, inputs.len),
        );
        try expectChecksum(&storage, line.c);

        if (line.s) |hex| {
            const want = try hexDecode(alloc, hex);
            var out_buf: [512]u8 = undefined;
            var written: usize = 0;
            try std.testing.expectEqual(
                @as(c.ns_result, c.NS_OK),
                c.ns_serialize(storage.ptr(), &out_buf, out_buf.len, &written),
            );
            try std.testing.expectEqualSlices(u8, want, out_buf[0..written]);
        }
    }
}

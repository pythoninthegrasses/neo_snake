//! Canonical-state serializer — implementation of docs/canonical-state.md.
//!
//! Byte-for-byte wire format used to compare simulation state across the JS
//! oracle (reference/oracle/canon.mjs), this Zig core, and any future host.
//! Every multi-byte field is written and read little-endian; reserved bytes
//! are zeroed on write and ignored (not validated) on read. The checksum
//! trailer is the first 8 bytes of SHA-256(header || player records) copied
//! verbatim — a byte reinterpretation of the digest, not a numeric-value
//! truncation (docs/canonical-state.md, "Checksum trailer").
//!
//! No allocator, no libc: encode writes into a caller-supplied buffer and
//! decode reads into caller-supplied player/cell slices (docs/abi-decisions.md
//! freeze #2), the same fixed-size-or-caller-owned rule as core/rng.zig.
//! SHA-256 comes from std.crypto, which is pure Zig and allocates nothing.

const std = @import("std");

pub const NS_CANON_VERSION: u16 = 1;
pub const MAGIC = "NEOSNAKE";
pub const HEADER_BYTES: usize = 44;
pub const PLAYER_FIXED_BYTES: usize = 16;
pub const CHECKSUM_BYTES: usize = 8;

/// Cell coordinate sentinel for "no food placed" (board full / win).
pub const NO_CELL: u16 = 0xFFFF;

/// Header `flags` bit 0 = wrap mode (`S.wrap`); bits 1-15 reserved, zero.
const FLAG_WRAP: u16 = 0x0001;

/// `status` encoding (docs/architecture.md's order `menu | playing | paused |
/// dead`), reused so the numbers stay traceable to reference/snake.html.
pub const Status = enum(u8) { menu, playing, paused, dead };

/// `dir` / `next_dir` encoding (snake.html's `DIRS` key order
/// `up, down, left, right`).
pub const Dir = enum(u8) { up, down, left, right };

pub const Cell = struct {
    x: u16,
    y: u16,
};

pub const Player = struct {
    status: Status,
    dir: Dir,
    next_dir: Dir,
    score: u32,
    /// Head-first: `cells[0]` is the snake's head.
    cells: []const Cell,
};

pub const State = struct {
    cols: u16,
    rows: u16,
    wrap: bool,
    tick: u32,
    /// xoshiro128** state words s0..s3 (core/rng.zig).
    rng_state: [4]u32,
    /// `null` writes/reads the `NO_CELL` sentinel in both food_x and food_y.
    food: ?Cell,
    players: []const Player,
};

/// Total encoded length of `state`: fixed header, one
/// `16 + 4 * body_len` record per player, plus the 8-byte checksum trailer.
/// Callers size their encode/decode buffers with this.
pub fn encodedLen(state: State) usize {
    var n: usize = HEADER_BYTES;
    for (state.players) |p| n += PLAYER_FIXED_BYTES + 4 * p.cells.len;
    return n + CHECKSUM_BYTES;
}

pub const EncodeError = error{BufferTooSmall};

/// Serialize `state` into `buf` (size it with `encodedLen`), returning the
/// exact record slice. Reserved bytes are written as zero regardless of
/// `buf`'s prior contents, so a reused buffer cannot leak stale bytes.
pub fn encode(state: State, buf: []u8) EncodeError![]u8 {
    std.debug.assert(state.players.len >= 1 and state.players.len <= 255);
    const need = encodedLen(state);
    if (buf.len < need) return error.BufferTooSmall;

    var o: usize = 0;
    const end = comptime MAGIC.len;
    @memcpy(buf[0..end], MAGIC);
    o += end;
    writeU16(buf, &o, NS_CANON_VERSION);
    writeU16(buf, &o, state.cols);
    writeU16(buf, &o, state.rows);
    writeU16(buf, &o, if (state.wrap) FLAG_WRAP else 0);
    buf[o] = @intCast(state.players.len);
    o += 1;
    // reserved[17..20): pads tick to a 4-byte offset.
    writeBytes(buf, &o, &[_]u8{ 0, 0, 0 });
    writeU32(buf, &o, state.tick);
    for (state.rng_state) |w| writeU32(buf, &o, w);
    writeU16(buf, &o, if (state.food) |f| f.x else NO_CELL);
    writeU16(buf, &o, if (state.food) |f| f.y else NO_CELL);

    // Per-player records, ascending player index.
    for (state.players) |p| {
        buf[o] = @intFromEnum(p.status);
        buf[o + 1] = @intFromEnum(p.dir);
        buf[o + 2] = @intFromEnum(p.next_dir);
        buf[o + 3] = 0; // reserved — pads score to a 4-byte offset
        o += 4;
        writeU32(buf, &o, p.score);
        writeU32(buf, &o, @intCast(p.cells.len));
        writeU32(buf, &o, 0); // reserved
        for (p.cells) |c| {
            writeU16(buf, &o, c.x);
            writeU16(buf, &o, c.y);
        }
    }

    // Checksum trailer: first 8 digest bytes over everything before it,
    // copied verbatim (digest order).
    checksumInto(buf[0..o], buf[o .. o + CHECKSUM_BYTES]);
    return buf[0..need];
}

pub const DecodeError = error{
    RecordTooShort,
    BadMagic,
    UnsupportedVersion,
    BadPlayerCount,
    TruncatedRecord,
    TrailingBytes,
    OutOfSpace,
};

/// Parse a canonical record into caller-supplied `players_out` / `cells_out`
/// buffers (no allocation; size `players_out` with the header's
/// `player_count` and `cells_out` with the summed `body_len`). Validates
/// magic/version/length but not the checksum (see `verify`). The returned
/// State borrows `bytes` (nothing is copied out of it).
pub fn decode(bytes: []const u8, players_out: []Player, cells_out: []Cell) DecodeError!State {
    if (bytes.len < HEADER_BYTES + CHECKSUM_BYTES) return error.RecordTooShort;
    if (!std.mem.eql(u8, bytes[0..MAGIC.len], MAGIC)) return error.BadMagic;

    const version = readU16(bytes, 8);
    if (version != NS_CANON_VERSION) return error.UnsupportedVersion;

    const player_count = bytes[16];
    if (player_count < 1) return error.BadPlayerCount;
    if (players_out.len < player_count) return error.OutOfSpace;

    var players_left: usize = bytes.len - CHECKSUM_BYTES; // bounds every record read
    var o: usize = HEADER_BYTES;
    var cell_used: usize = 0;
    for (0..player_count) |i| {
        if (players_left < PLAYER_FIXED_BYTES) return error.TruncatedRecord;
        const body_len = readU32(bytes, o + 8);
        const cells_bytes = @as(usize, body_len) * 4;
        if (players_left < PLAYER_FIXED_BYTES + cells_bytes) return error.TruncatedRecord;
        if (cell_used + body_len > cells_out.len) return error.OutOfSpace;

        const cells = cells_out[cell_used .. cell_used + body_len];
        var c = o + PLAYER_FIXED_BYTES;
        for (0..body_len) |j| {
            cells[j] = .{ .x = readU16(bytes, c), .y = readU16(bytes, c + 2) };
            c += 4;
        }
        players_out[i] = .{
            .status = statusFromBytes(bytes[o]) orelse return error.TruncatedRecord,
            .dir = dirFromBytes(bytes[o + 1]) orelse return error.TruncatedRecord,
            .next_dir = dirFromBytes(bytes[o + 2]) orelse return error.TruncatedRecord,
            .score = readU32(bytes, o + 4),
            .cells = cells,
        };
        cell_used += body_len;
        o += PLAYER_FIXED_BYTES + cells_bytes;
        players_left -= PLAYER_FIXED_BYTES + cells_bytes;
    }
    if (o + CHECKSUM_BYTES != bytes.len) return error.TrailingBytes;

    const food_x = readU16(bytes, 40);
    const food_y = readU16(bytes, 42);
    return .{
        .cols = readU16(bytes, 10),
        .rows = readU16(bytes, 12),
        .wrap = (readU16(bytes, 14) & FLAG_WRAP) != 0,
        .tick = readU32(bytes, 20),
        .rng_state = .{ readU32(bytes, 24), readU32(bytes, 28), readU32(bytes, 32), readU32(bytes, 36) },
        .food = if (food_x == NO_CELL or food_y == NO_CELL) null else Cell{ .x = food_x, .y = food_y },
        .players = players_out[0..player_count],
    };
}

/// The record's checksum: first 8 bytes of SHA-256 over every byte up to
/// (but not including) the 8-byte trailer, reinterpreted as a little-endian
/// `u64` (digest[0] is the least-significant byte).
pub fn checksum(bytes: []const u8) u64 {
    std.debug.assert(bytes.len >= CHECKSUM_BYTES);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes[0 .. bytes.len - CHECKSUM_BYTES], &digest, .{});
    return std.mem.readInt(u64, digest[0..8], .little);
}

/// Recompute the checksum and compare it against the trailer byte-for-byte.
pub fn verify(bytes: []const u8) bool {
    std.debug.assert(bytes.len >= CHECKSUM_BYTES);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes[0 .. bytes.len - CHECKSUM_BYTES], &digest, .{});
    const trailer = bytes[bytes.len - CHECKSUM_BYTES ..];
    for (0..CHECKSUM_BYTES) |i| {
        if (digest[i] != trailer[i]) return false;
    }
    return true;
}

fn checksumInto(body: []const u8, out: []u8) void {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(body, &digest, .{});
    @memcpy(out, digest[0..CHECKSUM_BYTES]);
}

// writeInt/readInt take fixed-array pointers; the record is byte-packed so
// align(1) is what the layout guarantees, and each slice is exactly 2/4 bytes.
fn writeU16(buf: []u8, o: *usize, v: u16) void {
    const w: *align(1) [2]u8 = @ptrCast(buf[o.* .. o.* + 2]);
    std.mem.writeInt(u16, w, v, .little);
    o.* += 2;
}

fn writeU32(buf: []u8, o: *usize, v: u32) void {
    const w: *align(1) [4]u8 = @ptrCast(buf[o.* .. o.* + 4]);
    std.mem.writeInt(u32, w, v, .little);
    o.* += 4;
}

fn writeBytes(buf: []u8, o: *usize, v: []const u8) void {
    @memcpy(buf[o.* .. o.* + v.len], v);
    o.* += v.len;
}

fn readU16(buf: []const u8, off: usize) u16 {
    const r: *align(1) const [2]u8 = @ptrCast(buf[off .. off + 2]);
    return std.mem.readInt(u16, r, .little);
}

fn readU32(buf: []const u8, off: usize) u32 {
    const r: *align(1) const [4]u8 = @ptrCast(buf[off .. off + 4]);
    return std.mem.readInt(u32, r, .little);
}

fn statusFromBytes(v: u8) ?Status {
    return switch (v) {
        0 => .menu,
        1 => .playing,
        2 => .paused,
        3 => .dead,
        else => null,
    };
}

fn dirFromBytes(v: u8) ?Dir {
    return switch (v) {
        0 => .up,
        1 => .down,
        2 => .left,
        3 => .right,
        else => null,
    };
}

// --- Tier-A tests (docs/canonical-state.md's worked example) ---------------

// The doc's published 80-byte hex dump, byte for byte. Checksum trailer
// `5a 33 a2 41 af 35 a7 d1` == 0xd1a735af41a2335a little-endian ==
// 15107102501874316122 (the value recorded as the "c" node in
// docs/corpus-format.md's trace example, produced by canon.mjs in task-012).
fn workedExample() State {
    return .{
        .cols = 24,
        .rows = 24,
        .wrap = false,
        .tick = 0,
        .rng_state = .{ 1, 2, 3, 4 },
        .food = .{ .x = 0, .y = 0 },
        .players = &[_]Player{.{
            .status = .playing,
            .dir = .right,
            .next_dir = .right,
            .score = 0,
            .cells = &[_]Cell{ .{ .x = 8, .y = 12 }, .{ .x = 7, .y = 12 }, .{ .x = 6, .y = 12 } },
        }},
    };
}

const expected_bytes = [_]u8{
    0x4e, 0x45, 0x4f, 0x53, 0x4e, 0x41, 0x4b, 0x45, 0x01, 0x00, 0x18, 0x00, 0x18, 0x00, 0x00, 0x00, //
    0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, //
    0x03, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x03, 0x03, 0x00, //
    0x00, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x08, 0x00, 0x0c, 0x00, //
    0x07, 0x00, 0x0c, 0x00, 0x06, 0x00, 0x0c, 0x00, 0x5a, 0x33, 0xa2, 0x41, 0xaf, 0x35, 0xa7, 0xd1, //
};

test "worked example encodes to the published 80 bytes" {
    const state = workedExample();
    try std.testing.expectEqual(@as(usize, 80), encodedLen(state));

    var buf: [80]u8 = undefined;
    const rec = try encode(state, &buf);
    try std.testing.expectEqualSlices(u8, &expected_bytes, rec);
}

test "worked example checksum matches task-012" {
    const state = workedExample();
    var buf: [80]u8 = undefined;
    const rec = try encode(state, &buf);

    // Trailer as a little-endian u64 == the corpus "c" node value.
    try std.testing.expectEqual(@as(u64, 0xd1a735af41a2335a), checksum(rec));
    try std.testing.expectEqual(@as(u64, 15107102501874316122), checksum(rec));
    try std.testing.expect(verify(rec));
}

test "worked example round-trips through decode" {
    const state = workedExample();
    var buf: [80]u8 = undefined;
    const rec = try encode(state, &buf);

    var players: [4]Player = undefined;
    var cells: [32]Cell = undefined;
    const got = try decode(rec, &players, &cells);

    try std.testing.expectEqual(@as(u16, 24), got.cols);
    try std.testing.expectEqual(@as(u16, 24), got.rows);
    try std.testing.expectEqual(false, got.wrap);
    try std.testing.expectEqual(@as(u32, 0), got.tick);
    try std.testing.expectEqualSlices(u32, &[_]u32{ 1, 2, 3, 4 }, &got.rng_state);
    try std.testing.expect(got.food != null);
    try std.testing.expectEqual(@as(u16, 0), got.food.?.x);
    try std.testing.expectEqual(@as(u16, 0), got.food.?.y);
    try std.testing.expectEqual(@as(usize, 1), got.players.len);
    try std.testing.expectEqual(Status.playing, got.players[0].status);
    try std.testing.expectEqual(Dir.right, got.players[0].dir);
    try std.testing.expectEqual(Dir.right, got.players[0].next_dir);
    try std.testing.expectEqualSlices(Cell, state.players[0].cells, got.players[0].cells);

    // Re-encoding the decoded state reproduces the record byte for byte.
    var buf2: [80]u8 = undefined;
    const rec2 = try encode(got, &buf2);
    try std.testing.expectEqualSlices(u8, rec, rec2);
}

test "no-food sentinel round-trips as null" {
    var state = workedExample();
    state.food = null;

    var buf: [80]u8 = undefined;
    const rec = try encode(state, &buf);
    // food_x/food_y both hold the sentinel.
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xff, 0xff, 0xff, 0xff }, rec[40..44]);
    try std.testing.expect(verify(rec));

    var players: [4]Player = undefined;
    var cells: [32]Cell = undefined;
    const got = try decode(rec, &players, &cells);
    try std.testing.expect(got.food == null);
}

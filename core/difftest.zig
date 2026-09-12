//! Tier-B hermetic corpus replay for core/world.zig — the differential gate
//! over the committed JSONL corpus (TASK-020).
//!
//! Every trace listed in core/corpus.zig is replayed against world.zig: the
//! trace header configures the world, each tick line's `in` list is queued via
//! `queueDir()` before that tick's single `advance()` (the order
//! reference/oracle/regen_corpus.mjs's renderTrace() uses — the order a real
//! keypress reaches the sim between ticks), and the resulting canonical record
//! must equal the line's `c` checksum and, where the line carries one, its
//! full-state "s" anchor.
//!
//! Hermetic: the only inputs are the committed corpus files — no node, no
//! oracle source, no network. The oracle ran once, in regen, and its output is
//! frozen here (zelda3's Tier-B idea, with a JS reference instead of a C one).
//! `oracle:verify` stays the gate keeping the corpus faithful to the oracle;
//! this gate is on world.zig agreeing with the frozen corpus, so it runs on a
//! box with no JS toolchain at all.
//!
//! On a mismatch the driver reports a field-by-field diff between the
//! mismatching tick's own computed state (already in hand — it's exactly what
//! the checksum comparison just encoded, not recomputed) and the last "s"
//! anchor at or before it (the nearest point the trace itself proves correct).
//! tick/rng_state/food are expected to move between an anchor and a later
//! tick, so their difference alone is not the bug; it is there so a reviewer
//! can sanity-check the delta against however many ticks and inputs separate
//! the two. Comparing against the last anchor rather than the first also
//! keeps the report bounded — at most 64 ticks apart — instead of walking the
//! whole trace a second time. A trace has no full expected state to compare
//! against at every tick (only checksums), so this is the closest honest
//! field-by-field ground truth the corpus can offer for a non-anchor tick.
//!
//! This driver is NOT under the "no allocator, no libc" freeze of
//! docs/build-layout.md: that freeze is scoped to the pure simulation library
//! (rng/canon/world) so it stays freestanding- and WASM-portable (TASK-047).
//! Replaying a corpus means reading files and parsing JSONL, so this file
//! allocates and does file I/O — by design, one file, so the freeze's boundary
//! stays exactly where the library's does.

const std = @import("std");
const canon = @import("canon");
const corpus_mod = @import("corpus");
const world_mod = @import("world");
const rng = @import("rng");

const Cell = canon.Cell;
const Dir = canon.Dir;
const Player = canon.Player;
const State = canon.State;
const World = world_mod.World;

/// The biggest board this driver will size scratch for. Every committed
/// trace is far under it; a header over it is rejected rather than
/// overflowing a stack/arena buffer sized from it.
const max_board_cells: usize = 4096;

/// docs/corpus-format.md's anchor rule, named once so the rewind comment and
/// the code agree.
const anchor_interval = 64;

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    const io = init.io;

    var ticks: usize = 0;
    var anchors: usize = 0;
    for (corpus_mod.entries) |entry| {
        var trace = try Trace.load(alloc, io, entry);
        ticks += trace.lines.len;
        anchors += trace.anchor_lines.len;
        if (try trace.replay(alloc)) |report| {
            std.debug.print("{s}\n", .{report});
            return error.DifftestMismatch;
        }
    }
    std.debug.print(
        "difftest: {d} traces, {d} tick lines, {d} anchors — all match\n",
        .{ corpus_mod.entries.len, ticks, anchors },
    );
}

// --- trace model ------------------------------------------------------------

/// One corpus trace: its header, its tick lines, and the canonical states
/// decoded from the lines that carry an "s" anchor.
const Trace = struct {
    name: []const u8,
    /// The trace's own RNG seed — the only seed a replay has, since the
    /// command logs are the oracle's input, not this one's.
    seed: [4]u32,
    cols: u16,
    rows: u16,
    wrap: bool,
    lines: []const Line,
    /// Anchors in tick order, with the line index each came from, so the
    /// diagnostic can ask for "the last anchor at or before line N".
    /// Parallel to `anchor_states`.
    anchor_lines: []const usize,
    anchor_states: []const State,

    /// Scratch for the forward replay loop: world_mod's caller-owned body
    /// buffer, this trace's single-player record, and a reused encode
    /// buffer — no allocation inside the tick loop.
    cells: []Cell,
    player: Player,
    players: [1]Player,
    buf: []u8,

    /// One tick line: what to feed the sim, and what the oracle recorded.
    const Line = struct {
        /// Directions this line queues (via queueDir) before its advance().
        dirs: []const Dir,
        /// The line's `c` field. Decimal string in the JSON — a u64 checksum
        /// does not fit in a JSON number — parsed to u64 here.
        checksum: u64,
        /// The line's `s` field, lowercase hex; empty when the line has none.
        state_hex: []const u8,
    };

    /// `entry.path` is relative to game/ (docs/corpus-format.md), and core/
    /// and game/ are siblings, so it resolves from wherever `zig build
    /// difftest` runs (core/, matching the rest of taskfiles/core.yml).
    fn load(alloc: std.mem.Allocator, io: std.Io, entry: corpus_mod.Entry) !Trace {
        const path = try std.fs.path.join(alloc, &.{ "..", "game", entry.path });
        const raw = std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .limited(8 << 20)) catch |err|
            std.process.fatal("difftest: cannot read {s} (listed in core/corpus.zig): {t}", .{ path, err });

        var it = std.mem.splitScalar(u8, raw, '\n');
        const header_text = it.first();
        if (header_text.len == 0) std.process.fatal("difftest: {s}: empty trace file", .{path});
        const header = std.json.parseFromSliceLeaky(Header, alloc, header_text, .{}) catch |err|
            std.process.fatal("difftest: {s}: unreadable header: {t}", .{ path, err });

        // world.zig simulates one snake; every committed trace agrees, and
        // this refuses to quietly replay a multiplayer trace with one.
        if (header.players != 1) {
            std.process.fatal("difftest: {s}: {d}-player trace; core/world.zig simulates one snake", .{ path, header.players });
        }
        if (@as(usize, header.cols) * header.rows > max_board_cells) {
            std.process.fatal("difftest: {s}: {d}x{d} board over the {d}-cell cap", .{ path, header.cols, header.rows, max_board_cells });
        }

        var lines = std.ArrayList(Line).empty;
        var anchor_lines = std.ArrayList(usize).empty;
        var anchor_states = std.ArrayList(State).empty;

        var line_no: usize = 1;
        while (it.next()) |text| : (line_no += 1) {
            if (text.len == 0) continue;
            const raw_line = std.json.parseFromSliceLeaky(RawLine, alloc, text, .{}) catch |err|
                std.process.fatal("difftest: {s} line {d}: unreadable tick line: {t}", .{ path, line_no, err });
            if (raw_line.t != lines.items.len) {
                std.process.fatal("difftest: {s} line {d}: tick {d} out of order (expected {d})", .{ path, line_no, raw_line.t, lines.items.len });
            }

            const dirs = try alloc.alloc(Dir, raw_line.in.len);
            for (raw_line.in, dirs) |ev, *d| {
                if (ev.p != 0) std.process.fatal("difftest: {s} line {d}: input for player {d} in a single-player trace", .{ path, line_no, ev.p });
                d.* = dirFromName(ev.dir) orelse
                    std.process.fatal("difftest: {s} line {d}: unknown direction \"{s}\"", .{ path, line_no, ev.dir });
            }
            const checksum = std.fmt.parseInt(u64, raw_line.c, 10) catch |err|
                std.process.fatal("difftest: {s} line {d}: bad checksum \"{s}\": {t}", .{ path, line_no, raw_line.c, err });

            if (raw_line.s) |hex| {
                const rec = try hexDecode(alloc, hex);
                const players_out = try alloc.alloc(Player, 1);
                const cells_out = try alloc.alloc(Cell, header.cols * @as(usize, header.rows));
                const state = canon.decode(rec, players_out, cells_out) catch |err|
                    std.process.fatal("difftest: {s} line {d}: anchor state unreadable: {t}", .{ path, line_no, err });
                try anchor_lines.append(alloc, lines.items.len);
                try anchor_states.append(alloc, state);
            }
            try lines.append(alloc, .{ .dirs = dirs, .checksum = checksum, .state_hex = raw_line.s orelse "" });
        }
        if (lines.items.len == 0) std.process.fatal("difftest: {s}: no tick lines", .{path});
        if (anchor_lines.items.len == 0) std.process.fatal("difftest: {s}: trace has no \"s\" anchor to compare against", .{path});

        return .{
            .name = entry.name,
            .seed = header.seed,
            .cols = header.cols,
            .rows = header.rows,
            .wrap = header.wrap,
            .lines = try lines.toOwnedSlice(alloc),
            .anchor_lines = try anchor_lines.toOwnedSlice(alloc),
            .anchor_states = try anchor_states.toOwnedSlice(alloc),
            .cells = try alloc.alloc(Cell, world_mod.requiredCells(header.cols, header.rows)),
            .player = undefined,
            .players = undefined,
            .buf = try alloc.alloc(u8, maxRecordLen(header.cols, header.rows)),
        };
    }

    /// Drive the whole trace, asserting every tick. Returns a report string
    /// on the first mismatch, `null` once every line has matched.
    fn replay(t: *Trace, alloc: std.mem.Allocator) !?[]const u8 {
        var w: World = undefined;
        // regen_corpus.mjs's initialState() takes status: 'playing' directly
        // rather than going through queueDir's menu-to-playing transition, so
        // the tick-0 anchor is a fresh world at tick 0, not one advance in.
        world_mod.initWorld(&w, t.cells, t.cols, t.rows, t.wrap, t.seed, .playing);

        for (t.lines, 0..) |line, i| {
            for (line.dirs) |d| world_mod.queueDir(&w, d);
            world_mod.advance(&w);

            const got = t.encode(&w);
            if (canon.checksum(got) != line.checksum) {
                return try t.diagnose(alloc, i, got, "checksum mismatch", canon.checksum(got), line.checksum);
            }
            if (line.state_hex.len > 0) {
                const want = try hexDecode(alloc, line.state_hex);
                if (!std.mem.eql(u8, want, got)) {
                    return try t.diagnose(alloc, i, got, "checksum matched but anchor bytes differ", 0, 0);
                }
            }
        }
        return null;
    }

    /// The canonical record for a world driven by this trace's config — the
    /// same field-by-field canon.State construction as world.zig's own
    /// round-trip test; world_mod exposes World fields, not a canon.State.
    fn encode(t: *Trace, w: *const World) []const u8 {
        t.player = .{
            .status = w.status,
            .dir = w.dir,
            .next_dir = w.next_dir,
            .score = w.score,
            .cells = world_mod.cells(w),
        };
        t.players[0] = t.player;
        const state = State{
            .cols = w.cols,
            .rows = w.rows,
            .wrap = w.wrap,
            .tick = w.tick,
            .rng_state = w.rng.state(),
            .food = w.food,
            .players = &t.players,
        };
        return canon.encode(state, t.buf) catch
            std.process.fatal("difftest: {s}: canonical record exceeded its buffer", .{t.name});
    }

    /// Report a mismatch at line `i`: decode `got` (already computed by the
    /// caller — no re-simulation needed) and the last anchor at or before
    /// `i`, and print every canon.State/Player field of both side by side.
    fn diagnose(
        t: *Trace,
        alloc: std.mem.Allocator,
        i: usize,
        got: []const u8,
        reason: []const u8,
        got_checksum: u64,
        want_checksum: u64,
    ) ![]const u8 {
        var anchor_pos: usize = 0;
        for (t.anchor_lines, 0..) |al, k| {
            if (al <= i) anchor_pos = k;
        }
        const anchor_line = t.anchor_lines[anchor_pos];
        const anchor_state = t.anchor_states[anchor_pos];

        const current_players = try alloc.alloc(Player, 1);
        const current_cells = try alloc.alloc(Cell, world_mod.requiredCells(t.cols, t.rows));
        const current_state = canon.decode(got, current_players, current_cells) catch |err|
            std.process.fatal("difftest: {s}: line {d}'s own computed state failed to decode: {t}", .{ t.name, i, err });

        var out = std.ArrayList(u8).empty;
        if (want_checksum != 0) {
            try out.print(alloc, "difftest: {s}: {s} at tick {d} (want {d}, got {d})\n", .{ t.name, reason, i, want_checksum, got_checksum });
        } else {
            try out.print(alloc, "difftest: {s}: {s} at tick {d}\n", .{ t.name, reason, i });
        }
        try out.print(
            alloc,
            "  comparing tick {d} (first divergence) against the last verified anchor at tick {d} ({d} ticks apart, cap {d}):\n",
            .{ i, anchor_line, i - anchor_line, anchor_interval },
        );
        try appendFieldDiff(&out, alloc, anchor_state, current_state);
        try out.print(alloc,
            \\  tick/rng_state/food are expected to move between an anchor and a
            \\  later tick — their difference alone is not the bug. Check whether
            \\  dir/score/cells match what {d} ticks of the recorded inputs should
            \\  have produced from the anchor.
            \\
        , .{i - anchor_line});
        return out.toOwnedSlice(alloc);
    }
};

fn appendFieldDiff(out: *std.ArrayList(u8), alloc: std.mem.Allocator, a: State, b: State) !void {
    try out.print(alloc, "    {s:<10} anchor={any}\n{s:<15}current={any}\n", .{ "cols", a.cols, "", b.cols });
    try out.print(alloc, "    {s:<10} anchor={any}\n{s:<15}current={any}\n", .{ "rows", a.rows, "", b.rows });
    try out.print(alloc, "    {s:<10} anchor={any}\n{s:<15}current={any}\n", .{ "wrap", a.wrap, "", b.wrap });
    try out.print(alloc, "    {s:<10} anchor={d}\n{s:<15}current={d}\n", .{ "tick", a.tick, "", b.tick });
    try out.print(alloc, "    {s:<10} anchor={any}\n{s:<15}current={any}\n", .{ "rng_state", a.rng_state, "", b.rng_state });
    try out.print(alloc, "    {s:<10} anchor={any}\n{s:<15}current={any}\n", .{ "food", a.food, "", b.food });

    const ap = a.players[0];
    const bp = b.players[0];
    try out.print(alloc, "    {s:<10} anchor={any}\n{s:<15}current={any}\n", .{ "status", ap.status, "", bp.status });
    try out.print(alloc, "    {s:<10} anchor={any}\n{s:<15}current={any}\n", .{ "dir", ap.dir, "", bp.dir });
    try out.print(alloc, "    {s:<10} anchor={any}\n{s:<15}current={any}\n", .{ "next_dir", ap.next_dir, "", bp.next_dir });
    try out.print(alloc, "    {s:<10} anchor={d}\n{s:<15}current={d}\n", .{ "score", ap.score, "", bp.score });
    try out.print(alloc, "    {s:<10} anchor={any}\n{s:<15}current={any}\n", .{ "cells", ap.cells, "", bp.cells });
}

fn maxRecordLen(cols: u16, rows: u16) usize {
    const cells = @as(usize, cols) * rows;
    return canon.HEADER_BYTES + canon.PLAYER_FIXED_BYTES + 4 * (cells + 1) + canon.CHECKSUM_BYTES;
}

fn hexDecode(alloc: std.mem.Allocator, hex: []const u8) ![]u8 {
    std.debug.assert(hex.len % 2 == 0);
    const out = try alloc.alloc(u8, hex.len / 2);
    for (out, 0..) |*b, i| {
        b.* = try std.fmt.parseInt(u8, hex[i * 2 .. i * 2 + 2], 16);
    }
    return out;
}

fn dirFromName(name: []const u8) ?Dir {
    if (std.mem.eql(u8, name, "up")) return .up;
    if (std.mem.eql(u8, name, "down")) return .down;
    if (std.mem.eql(u8, name, "left")) return .left;
    if (std.mem.eql(u8, name, "right")) return .right;
    return null;
}

// --- JSONL wire shapes (docs/corpus-format.md) ------------------------------

const Header = struct {
    seed: [4]u32,
    cols: u16,
    rows: u16,
    wrap: bool,
    players: u8,
    corpus_version: u32,
};

const InEvent = struct {
    p: u8,
    dir: []const u8,
};

/// One tick line as JSON sees it, before `Trace.Line` resolves `in`'s
/// direction names to `Dir` and `c`'s decimal string to a `u64`.
const RawLine = struct {
    t: u32,
    in: []const InEvent,
    c: []const u8,
    s: ?[]const u8 = null,
};

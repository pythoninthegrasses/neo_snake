//! Live fuzz-runner for `task oracle:fuzz` (TASK-022).
//!
//! Takes one argument — the path to a command log (docs/corpus-format.md's
//! *input* format, the same one core/difftest.zig's committed traces were
//! generated from), drives it straight through core/world.zig exactly the
//! way reference/oracle/regen_corpus.mjs's renderTrace() drives sim.mjs
//! (queue this tick's events, then advance(), stop at the first tick whose
//! status is not playing or once the header's `ticks` cap is reached), and
//! prints one "<tick>\t<checksum>" line per simulated tick to stderr (this
//! codebase's established std.debug.print convention — see
//! core/difftest.zig) — nothing else goes to stderr on a normal run, so
//! reference/oracle/fuzz.mjs can parse it line-for-line.
//!
//! Unlike core/difftest.zig, this has no expected value of its own to
//! compare against: reference/oracle/fuzz.mjs is what runs the same command
//! log through reference/oracle/sim.mjs and diffs the two outputs. This
//! file only reproduces world.zig's half of that diff, live — oracle:fuzz
//! needs both a live node and a live zig, unlike the hermetic Tier-B
//! difftest that replays a frozen, committed corpus.
//!
//! Single-player only, matching world.zig — a multi-player command log is
//! rejected loudly, same as difftest.zig.
//!
//! Not under the "no allocator, no libc" freeze (docs/build-layout.md) for
//! the same reason difftest.zig isn't: reading and parsing a file needs
//! both, and that freeze is scoped to the pure simulation library.

const std = @import("std");
const canon = @import("canon");
const world_mod = @import("world");

const Cell = canon.Cell;
const Dir = canon.Dir;
const Player = canon.Player;
const State = canon.State;
const World = world_mod.World;

/// Same cap as core/difftest.zig, for the same reason: scratch is sized
/// once from the header, not reallocated per tick.
const max_board_cells: usize = 4096;

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    const io = init.io;

    const args = try init.minimal.args.toSlice(alloc);
    if (args.len != 2) std.process.fatal("usage: fuzzrun <command-log-path>", .{});
    const path = args[1];

    const raw = std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .limited(8 << 20)) catch |err|
        std.process.fatal("fuzzrun: cannot read {s}: {t}", .{ path, err });

    var it = std.mem.splitScalar(u8, raw, '\n');
    const header_text = it.first();
    if (header_text.len == 0) std.process.fatal("fuzzrun: {s}: empty command log", .{path});
    const header = std.json.parseFromSliceLeaky(Header, alloc, header_text, .{}) catch |err|
        std.process.fatal("fuzzrun: {s}: unreadable header: {t}", .{ path, err });

    if (header.players != 1) {
        std.process.fatal("fuzzrun: {s}: {d}-player log; core/world.zig simulates one snake", .{ path, header.players });
    }
    if (@as(usize, header.cols) * header.rows > max_board_cells) {
        std.process.fatal("fuzzrun: {s}: {d}x{d} board over the {d}-cell cap", .{ path, header.cols, header.rows, max_board_cells });
    }

    var events = std.ArrayList(Event).empty;
    var line_no: usize = 1;
    while (it.next()) |text| : (line_no += 1) {
        if (text.len == 0) continue;
        const raw_ev = std.json.parseFromSliceLeaky(RawEvent, alloc, text, .{}) catch |err|
            std.process.fatal("fuzzrun: {s} line {d}: unreadable event: {t}", .{ path, line_no, err });
        if (raw_ev.p != 0) std.process.fatal("fuzzrun: {s} line {d}: input for player {d} in a single-player log", .{ path, line_no, raw_ev.p });
        const d = dirFromName(raw_ev.in) orelse
            std.process.fatal("fuzzrun: {s} line {d}: unknown direction \"{s}\"", .{ path, line_no, raw_ev.in });
        try events.append(alloc, .{ .t = raw_ev.t, .dir = d });
    }

    var w: World = undefined;
    const cells = try alloc.alloc(Cell, world_mod.requiredCells(header.cols, header.rows));
    world_mod.initWorld(&w, cells, header.cols, header.rows, header.wrap, header.seed, .playing);

    const buf = try alloc.alloc(u8, maxRecordLen(header.cols, header.rows));
    var players: [1]Player = undefined;

    var ev_idx: usize = 0;
    var tick: u32 = 0;
    while (true) : (tick += 1) {
        while (ev_idx < events.items.len and events.items[ev_idx].t == tick) : (ev_idx += 1) {
            world_mod.queueDir(&w, events.items[ev_idx].dir);
        }
        world_mod.advance(&w);

        players[0] = .{
            .status = w.status,
            .dir = w.dir,
            .next_dir = w.next_dir,
            .score = w.score,
            .cells = world_mod.cells(&w),
        };
        const state = State{
            .cols = w.cols,
            .rows = w.rows,
            .wrap = w.wrap,
            .tick = w.tick,
            .rng_state = w.rng.state(),
            .food = w.food,
            .players = &players,
        };
        const rec = canon.encode(state, buf) catch
            std.process.fatal("fuzzrun: {s}: canonical record exceeded its buffer", .{path});
        std.debug.print("{d}\t{d}\n", .{ tick, canon.checksum(rec) });

        if (w.status != .playing or tick + 1 >= header.ticks) break;
    }
}

const Event = struct {
    t: u32,
    dir: Dir,
};

fn dirFromName(name: []const u8) ?Dir {
    if (std.mem.eql(u8, name, "up")) return .up;
    if (std.mem.eql(u8, name, "down")) return .down;
    if (std.mem.eql(u8, name, "left")) return .left;
    if (std.mem.eql(u8, name, "right")) return .right;
    return null;
}

fn maxRecordLen(cols: u16, rows: u16) usize {
    const cells = @as(usize, cols) * rows;
    return canon.HEADER_BYTES + canon.PLAYER_FIXED_BYTES + 4 * (cells + 1) + canon.CHECKSUM_BYTES;
}

// --- command-log wire shape (docs/corpus-format.md) -------------------------

const Header = struct {
    seed: [4]u32,
    cols: u16,
    rows: u16,
    wrap: bool,
    players: u8,
    ticks: u32,
};

const RawEvent = struct {
    t: u32,
    p: u8,
    in: []const u8,
};

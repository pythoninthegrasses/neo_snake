//! Deterministic snake simulation — the Zig port of reference/oracle/sim.mjs.
//!
//! Movement, direction commit, collision, food placement, scoring, the win
//! condition, and the ns_pump tick accumulator, mirroring sim.mjs line for
//! line where its statement order is load-bearing (the `advance()` order:
//! input commit -> move -> collision against the tail minus the cell it is
//! about to vacate -> unshift/pop, and decision-015's menu-direction
//! overwrite quirk, kept verbatim as faithful behavior).
//!
//! The one place this deliberately does not mirror sim.mjs's arithmetic: the
//! accumulator. sim.mjs's `step()` still evaluates the oracle's float-ms
//! `tickMs()` formula, but docs/abi-decisions.md freeze #5 requires this
//! core's accumulator to read the committed integer microsecond
//! `TICK_PERIOD_US` table instead — so `pump` takes an integer-microsecond
//! `dt` and never touches a float. See the `pump` doc comment.
//!
//! No allocator, no libc: the snake body lives in a caller-supplied cell
//! buffer (docs/abi-decisions.md freeze #2's caller-owned-memory rule), the
//! RNG state is four u32s owned inline (core/rng.zig), and nothing here
//! imports std.heap or links libc — the same constraints as core/rng.zig and
//! core/canon.zig, so this code can later target freestanding/WASM (TASK-047)
//! without relinking. World size and layout will be determined by
//! ns_world_size/ns_world_init in a later task (TASK-023's C ABI); this is
//! the pure-Zig core those exports will wrap.

const std = @import("std");
const rng = @import("rng");
const canon = @import("canon");

pub const Cell = canon.Cell;
pub const Dir = canon.Dir;
pub const Status = canon.Status;

/// Default board dimensions (the oracle's COLS/ROWS).
pub const COLS = 24;
pub const ROWS = 24;

/// The oracle's timing constants (docs/architecture.md "The two loops"),
/// kept for reference; the accumulator itself runs on the microsecond table
/// below, so these ms values are documentation, not arithmetic inputs here.
pub const BASE_MS = 130;
pub const MIN_MS = 55;

/// sim.mjs's frame() dt clamp: a long frame gap can't fast-forward the sim.
const MAX_DT_US = 64 * 1000;
/// sim.mjs's frame() catch-up guard: at most this many advances per pump.
const MAX_STEPS = 6;

/// The frozen integer tick-period table (docs/abi-decisions.md freeze #5,
/// derived in task-010): the five values
/// `round(max(55, 130/(1+min(score,40)*0.035)) * 1000)` at the only score
/// thresholds the oracle's float formula ever actually produces during play
/// (score increments by exactly 10). Committed integers, copied verbatim —
/// never recomputed from floats here or anywhere else.
///
/// Index rule (freeze #5, verbatim): `TICK_PERIOD_US[i]` with
/// `i = min(score / 10, 4)` using integer division — an exact lookup, since
/// score is always a non-negative multiple of 10 in real play.
pub const TICK_PERIOD_US = [_]u32{ 130000, 96296, 76471, 63415, 55000 };

/// Tick period in microseconds for the current score — the table lookup,
/// never the float formula.
pub fn tickPeriodUs(score: u32) u32 {
    return TICK_PERIOD_US[@min(score / 10, TICK_PERIOD_US.len - 1)];
}

/// Unit step vectors, indexed by canon.Dir's encoding (snake.html's DIRS
/// declaration order: up, down, left, right). Signed so head math can go
/// negative before wrapping or bounds-checking.
pub const DIR_VEC = [4]struct { dx: i16, dy: i16 }{
    .{ .dx = 0, .dy = -1 }, // up
    .{ .dx = 0, .dy = 1 }, // down
    .{ .dx = -1, .dy = 0 }, // left
    .{ .dx = 1, .dy = 0 }, // right
};

/// One snake, one board, one RNG stream — sim.mjs's state object `S`, with
/// the presentation-only fields (flash, particles, the overlay/HUD sync)
/// dropped as they have no canonical byte (docs/canonical-state.md) and the
/// accumulator converted to integer microseconds (see `pump`).
///
/// The snake body is a window into a caller-supplied cell buffer (AC#2: all
/// caller-provided memory arrives as explicit function parameters, never a
/// global). The caller sizes the buffer via `requiredCells` (cols*rows is
/// always enough); `cells()` returns the live head-first snake, matching
/// canon.Player.cells' head-first convention.
pub const World = struct {
    cols: u16,
    rows: u16,
    wrap: bool,
    tick: u32,
    score: u32,
    status: Status,
    dir: Dir,
    next_dir: Dir,
    /// `null` is the win / board-full state (the canonical 0xFFFF sentinel).
    food: ?Cell,

    /// The single shared RNG stream (docs/rng.md, freeze #3).
    rng: rng.Rng,

    /// ns_pump's fixed-timestep accumulator in integer microseconds — the
    /// carry-over between pump calls. Not part of the canonical state, just
    /// like sim.mjs's S.acc is not part of the oracle's.
    acc_us: u32,

    /// Caller-owned body storage; `cells()` is the live view into it.
    cells_buf: []Cell,
    cells_len: u32,
};

/// Minimum caller-supplied cell-buffer length for a board: the snake can
/// occupy every cell on a full-board win.
pub fn requiredCells(cols: u16, rows: u16) usize {
    return @as(usize, cols) * @as(usize, rows);
}

/// sim.mjs's initialState(): a fresh world at the oracle's reset() starting
/// position, food drawn from `seed`. `status` chooses the initial
/// state-machine position — the oracle's own reset() never sets status
/// itself, but initialState takes it as a parameter, so this mirrors that.
/// `cells_buf` must be at least `requiredCells(cols, rows)` long.
pub fn initWorld(w: *World, cells_buf: []Cell, cols: u16, rows: u16, wrap: bool, seed: [4]u32, status: Status) void {
    std.debug.assert(cells_buf.len >= requiredCells(cols, rows));
    w.* = .{
        .cols = cols,
        .rows = rows,
        .wrap = wrap,
        .tick = 0,
        .score = 0,
        .status = status,
        .dir = .right,
        .next_dir = .right,
        .food = null,
        .rng = rng.Rng.init(seed),
        .acc_us = 0,
        .cells_buf = cells_buf,
        .cells_len = 0,
    };
    reset(w);
}

/// The live snake, head-first: `cells()[0]` is the head.
pub fn cells(w: *const World) []const Cell {
    return w.cells_buf[0..w.cells_len];
}

/// sim.mjs's reset(): 3-cell snake at row (rows/2)|0, head at (8, cy)
/// head-first, dir/next_dir forced to right, score/tick/accumulator cleared,
/// food placed. Like the oracle's, this does not touch `status` — start()
/// sets that after calling it. `wrap` is a preserved setting, not reset.
pub fn reset(w: *World) void {
    const cy = w.rows / 2; // integer division, == the oracle's (rows/2)|0
    w.cells_buf[0] = .{ .x = 8, .y = cy };
    w.cells_buf[1] = .{ .x = 7, .y = cy };
    w.cells_buf[2] = .{ .x = 6, .y = cy };
    w.cells_len = 3;
    w.dir = .right;
    w.next_dir = .right;
    w.score = 0;
    w.tick = 0;
    w.acc_us = 0;
    placeFood(w);
}

/// sim.mjs's start(): reset() first, then status = playing.
pub fn start(w: *World) void {
    reset(w);
    w.status = .playing;
}

/// True if any body cell sits on (x, y). O(body_len), like the oracle's
/// `occupied()`; board and snake sizes make the linear scan cheap.
fn occupied(w: *const World, x: u16, y: u16) bool {
    for (cells(w)) |c| {
        if (c.x == x and c.y == y) return true;
    }
    return false;
}

/// sim.mjs's placeFood(): the same row-major (outer y, inner x) free-cell
/// enumeration — so the same draw indexes the same cell — but found by
/// counting free cells and walking to the drawn one instead of building a
/// free-cell list, since this code has no allocator. The snake never
/// self-overlaps and every body cell is on-board, so the free count is
/// exactly cols*rows - body_len.
pub fn placeFood(w: *World) void {
    const total = requiredCells(w.cols, w.rows);
    const free = total - w.cells_len;
    if (free == 0) {
        w.food = null;
        return;
    }
    const idx = w.rng.boundedDraw(@intCast(free));
    var seen: u32 = 0;
    for (0..w.rows) |y| {
        for (0..w.cols) |x| {
            if (occupied(w, @intCast(x), @intCast(y))) continue;
            if (seen == idx) {
                w.food = .{ .x = @intCast(x), .y = @intCast(y) };
                return;
            }
            seen += 1;
        }
    }
    unreachable; // seen must reach idx < free
}

/// sim.mjs's queueDir(): the single choke point for input legality. The
/// 180-degree guard reads `dir` while playing and `next_dir` in every other
/// status; a direction queued from menu/dead starts the game, whose reset()
/// then overwrites that direction — decision-015, kept verbatim.
pub fn queueDir(w: *World, d: Dir) void {
    const ref = if (w.status == .playing) w.dir else w.next_dir;
    const rv = DIR_VEC[@intFromEnum(ref)];
    const dv = DIR_VEC[@intFromEnum(d)];
    if (dv.dx == -rv.dx and dv.dy == -rv.dy) return; // no instant 180
    w.next_dir = d;
    if (w.status == .menu or w.status == .dead) start(w);
}

/// sim.mjs's togglePause(): a no-op outside playing/paused.
pub fn togglePause(w: *World) void {
    if (w.status == .playing) {
        w.status = .paused;
    } else if (w.status == .paused) {
        w.status = .playing;
    }
}

/// sim.mjs's advance(): one simulation step. Statement order is load-bearing
/// — see this module's header. The die()/win() transitions return before the
/// tick increment, matching the oracle's early `return die(S)` /
/// `return win(S)`.
pub fn advance(w: *World) void {
    w.dir = w.next_dir;

    const head = cells(w)[0];
    const v = DIR_VEC[@intFromEnum(w.dir)];
    var nx: i32 = @as(i32, head.x) + @as(i32, v.dx);
    var ny: i32 = @as(i32, head.y) + @as(i32, v.dy);

    if (w.wrap) {
        // The oracle's own expression, kept verbatim: adding cols/rows first
        // is what keeps the remainder non-negative for a head at x=0 moving
        // left (Zig's @mod is already floored modulo, but the oracle adds
        // first too, and @mod(x+cols, cols) is exactly that expression).
        nx = @mod(nx + @as(i32, w.cols), @as(i32, w.cols));
        ny = @mod(ny + @as(i32, w.rows), @as(i32, w.rows));
    } else if (nx < 0 or ny < 0 or nx >= @as(i32, w.cols) or ny >= @as(i32, w.rows)) {
        return die(w);
    }
    const ncell = Cell{ .x = @intCast(nx), .y = @intCast(ny) };

    // Tail vacates this tick unless we eat: self-collision is tested against
    // the body minus the cell it is about to vacate, which is why moving
    // into the space your tail leaves is legal.
    const eating = w.food != null and ncell.x == w.food.?.x and ncell.y == w.food.?.y;
    const body_len_check: u32 = if (eating) w.cells_len else w.cells_len - 1;
    for (0..body_len_check) |i| {
        const c = w.cells_buf[i];
        if (c.x == ncell.x and c.y == ncell.y) return die(w);
    }

    // unshift: shift the body up one slot (@memmove handles the overlap),
    // then write the new head. When not eating the shift drops the tail
    // cell — the same "pop" the oracle does, subsumed by the shift.
    const buf = w.cells_buf[0 .. w.cells_len + 1];
    @memmove(buf[1..], buf[0..w.cells_len]);
    w.cells_buf[0] = ncell;
    if (eating) {
        w.cells_len += 1;
        w.score += 10;
        placeFood(w);
        if (w.food == null) return win(w);
    }
    w.tick += 1;
}

/// The oracle's die(): status dead (its overlay is presentation).
fn die(w: *World) void {
    w.status = .dead;
}

/// The oracle's win(): the same dead status die() sets (its overlay differs;
/// the status does not — docs/canonical-state.md has no separate win code).
fn win(w: *World) void {
    w.status = .dead;
}

/// sim.mjs's step()/frame() loop — the ns_pump accumulator — minus the
/// clock: `dt_us` is the caller's already-computed frame delta in integer
/// microseconds (clamped to 64 ms, so no single frame can fast-forward the
/// sim), and the accumulator runs at most MAX_STEPS advances, with the tick
/// period re-read each iteration because eating raises the speed mid-frame.
/// Returns the number of advances performed, so a caller (task-031's
/// tick_driver, TASK-019's clamp test) can assert the exact tick count.
///
/// Integer microseconds throughout, never a float, per docs/abi-decisions.md
/// freeze #5: the period comes from the committed TICK_PERIOD_US table, and
/// the first-frame dt sentinel (sim.mjs's `S.last` bookkeeping) lives in the
/// caller's clock, not here — this core never reads a clock of its own.
pub fn pump(w: *World, dt_us: u32) u32 {
    if (w.status != .playing) return 0;

    const dt = @min(dt_us, MAX_DT_US);
    w.acc_us += dt;

    var steps: u32 = 0;
    var step_us = tickPeriodUs(w.score);
    while (w.acc_us >= step_us and w.status == .playing and steps < MAX_STEPS) {
        w.acc_us -= step_us;
        advance(w);
        step_us = tickPeriodUs(w.score);
        steps += 1;
    }
    return steps;
}

// --- Tier-A smoke tests ---------------------------------------------------
// The exhaustive named Tier-A suite (nine named cases incl. the
// serialize∘deserialize identity) is TASK-019's scope; these are the
// minimal checks that keep `zig build test` green for this module and pin
// the highest-risk behaviors (starting position/food draw, the tail-chase
// split, the accumulator carry) while TASK-018 is still in flight.

test "refAllDecls" {
    std.testing.refAllDecls(@This());
}

test "reset matches the oracle's starting position and food draw" {
    var buf: [COLS * ROWS]Cell = undefined;
    var w: World = undefined;
    initWorld(&w, &buf, COLS, ROWS, false, .{ 1, 2, 3, 4 }, .menu);

    try std.testing.expectEqual(Status.menu, w.status);
    try std.testing.expectEqual(@as(u32, 0), w.score);
    try std.testing.expectEqual(@as(u32, 0), w.tick);
    try std.testing.expectEqualSlices(Cell, &[_]Cell{
        .{ .x = 8, .y = 12 }, .{ .x = 7, .y = 12 }, .{ .x = 6, .y = 12 },
    }, cells(&w));
    // First food draw: boundedDraw over 573 free cells (576-3), whose first
    // value on a fresh [1,2,3,4] stream is 0 per docs/rng.md -> (0, 0).
    try std.testing.expect(w.food != null);
    try std.testing.expectEqual(@as(u16, 0), w.food.?.x);
    try std.testing.expectEqual(@as(u16, 0), w.food.?.y);
}

test "advance: move, eat, and wall death" {
    var buf: [COLS * ROWS]Cell = undefined;
    var w: World = undefined;
    initWorld(&w, &buf, COLS, ROWS, false, .{ 1, 2, 3, 4 }, .playing);
    w.food = .{ .x = 9, .y = 12 }; // directly ahead of the start head

    advance(&w);
    try std.testing.expectEqual(@as(u32, 1), w.tick);
    try std.testing.expectEqual(@as(u32, 10), w.score);
    try std.testing.expectEqual(@as(u32, 4), w.cells_len);
    try std.testing.expectEqual(@as(u16, 9), cells(&w)[0].x);
    try std.testing.expectEqual(Status.playing, w.status);
    // The new food must never land on the snake.
    try std.testing.expect(!occupied(&w, w.food.?.x, w.food.?.y));

    // Straight into the right wall dies, one tick before that was fine.
    w.food = null;
    while (w.status == .playing) advance(&w);
    try std.testing.expectEqual(Status.dead, w.status);
}

test "tail-chase split: entering the vacating tail cell survives" {
    var buf: [COLS * ROWS]Cell = undefined;
    var w: World = undefined;
    initWorld(&w, &buf, COLS, ROWS, false, .{ 1, 2, 3, 4 }, .playing);
    // Head (5,5) chasing its own tail: body laid out so (4,5) is the tail,
    // and moving left onto it is legal because not eating means it vacates.
    w.cells_buf[0] = .{ .x = 5, .y = 5 };
    w.cells_buf[1] = .{ .x = 10, .y = 5 };
    w.cells_buf[2] = .{ .x = 4, .y = 5 };
    w.cells_len = 3;
    w.dir = .left;
    w.next_dir = .left;
    w.food = null;

    advance(&w);
    try std.testing.expectEqual(Status.playing, w.status);
    try std.testing.expectEqualSlices(Cell, &[_]Cell{
        .{ .x = 4, .y = 5 }, .{ .x = 5, .y = 5 }, .{ .x = 10, .y = 5 },
    }, cells(&w));
}

test "wrap: the oracle's (+size) remainder, wall mode is the contrast" {
    var buf: [COLS * ROWS]Cell = undefined;

    var w: World = undefined;
    initWorld(&w, &buf, COLS, ROWS, true, .{ 1, 2, 3, 4 }, .playing);
    w.cells_buf[0] = .{ .x = 0, .y = 5 };
    w.cells_buf[1] = .{ .x = 1, .y = 5 };
    w.cells_buf[2] = .{ .x = 2, .y = 5 };
    w.dir = .left;
    w.next_dir = .left;
    w.food = null;
    advance(&w);
    try std.testing.expectEqual(@as(u16, COLS - 1), cells(&w)[0].x);

    // Wall mode: the same step dies instead of wrapping.
    var wall: World = undefined;
    initWorld(&wall, &buf, COLS, ROWS, false, .{ 1, 2, 3, 4 }, .playing);
    wall.cells_buf[0] = .{ .x = 0, .y = 5 };
    wall.cells_buf[1] = .{ .x = 1, .y = 5 };
    wall.cells_buf[2] = .{ .x = 2, .y = 5 };
    wall.dir = .left;
    wall.next_dir = .left;
    wall.food = null;
    advance(&wall);
    try std.testing.expectEqual(Status.dead, wall.status);
}

test "queueDir: 180 reject, decision-015 menu overwrite, pause toggle" {
    var buf: [COLS * ROWS]Cell = undefined;
    var w: World = undefined;
    initWorld(&w, &buf, COLS, ROWS, false, .{ 1, 2, 3, 4 }, .playing);

    queueDir(&w, .left); // exact opposite of dir=right -> rejected
    try std.testing.expectEqual(Dir.right, w.next_dir);
    queueDir(&w, .up); // legal against dir=right
    try std.testing.expectEqual(Dir.up, w.next_dir);
    advance(&w);
    try std.testing.expectEqual(Dir.up, w.dir); // commit-before-move

    // From menu, up starts the game but reset() clobbers it back to right —
    // decision-015, kept verbatim.
    var menu: World = undefined;
    initWorld(&menu, &buf, COLS, ROWS, false, .{ 1, 2, 3, 4 }, .menu);
    queueDir(&menu, .up);
    try std.testing.expectEqual(Status.playing, menu.status);
    try std.testing.expectEqual(Dir.right, menu.dir);
    try std.testing.expectEqual(Dir.right, menu.next_dir);

    // Left from a right-facing menu is 180-rejected, so it never starts.
    var rejected: World = undefined;
    initWorld(&rejected, &buf, COLS, ROWS, false, .{ 1, 2, 3, 4 }, .menu);
    queueDir(&rejected, .left);
    try std.testing.expectEqual(Status.menu, rejected.status);

    togglePause(&w);
    try std.testing.expectEqual(Status.paused, w.status);
    togglePause(&w);
    try std.testing.expectEqual(Status.playing, w.status);
}

test "pump: dt clamp, carry-over, and the speed table" {
    var buf: [COLS * ROWS]Cell = undefined;
    var w: World = undefined;
    initWorld(&w, &buf, COLS, ROWS, false, .{ 1, 2, 3, 4 }, .playing);
    w.food = null;

    // First frame: nothing accumulated past the 64 ms clamp, no tick yet.
    try std.testing.expectEqual(@as(u32, 0), pump(&w, 64_000));
    try std.testing.expectEqual(@as(u32, 64_000), w.acc_us);
    try std.testing.expectEqual(@as(u32, 0), w.tick);

    // A huge gap contributes only the clamped 64 ms, never fast-forwards.
    var big: World = undefined;
    initWorld(&big, &buf, COLS, ROWS, false, .{ 1, 2, 3, 4 }, .playing);
    big.food = null;
    big.score = 40; // fastest period, 55000 us
    try std.testing.expectEqual(@as(u32, 1), pump(&big, 32_000_000));
    try std.testing.expectEqual(@as(u32, 64_000 - 55_000), big.acc_us);

    // Carry-over: 64 + 64 + 64 ms crosses the 130000 us first tick on the
    // third pump, leaving 192000-130000 = 62000 us behind.
    var acc: World = undefined;
    initWorld(&acc, &buf, COLS, ROWS, false, .{ 1, 2, 3, 4 }, .playing);
    acc.food = null;
    try std.testing.expectEqual(@as(u32, 0), pump(&acc, 64_000));
    try std.testing.expectEqual(@as(u32, 0), pump(&acc, 64_000));
    try std.testing.expectEqual(@as(u32, 1), pump(&acc, 64_000));
    try std.testing.expectEqual(@as(u32, 62_000), acc.acc_us);
    try std.testing.expectEqual(@as(u32, 1), acc.tick);

    // Paused frames advance nothing.
    acc.status = .paused;
    try std.testing.expectEqual(@as(u32, 0), pump(&acc, 64_000));
}

test "win: eating the last free cell on a full board ends the game dead" {
    // A 2x2 board, snake over three cells, food on the only free cell: the
    // eating move pins the tail (no vacate), the eat scores, and placeFood
    // finds no free cell — the win, which is `dead` in the oracle too.
    var buf: [4]Cell = undefined;
    var w: World = undefined;
    initWorld(&w, &buf, 2, 2, false, .{ 1, 2, 3, 4 }, .playing);
    w.cells_buf[0] = .{ .x = 1, .y = 0 };
    w.cells_buf[1] = .{ .x = 1, .y = 1 };
    w.cells_buf[2] = .{ .x = 0, .y = 1 };
    w.cells_len = 3;
    w.dir = .left;
    w.next_dir = .left;
    w.food = .{ .x = 0, .y = 0 };

    advance(&w);
    try std.testing.expectEqual(Status.dead, w.status);
    try std.testing.expectEqual(@as(u32, 10), w.score);
    try std.testing.expect(w.food == null);
    try std.testing.expectEqual(@as(u32, 4), w.cells_len);
}

test "tickPeriodUs indexes the frozen table verbatim" {
    // docs/abi-decisions.md freeze #5's five committed integers, verbatim.
    try std.testing.expectEqual(@as(u32, 130000), tickPeriodUs(0));
    try std.testing.expectEqual(@as(u32, 96296), tickPeriodUs(10));
    try std.testing.expectEqual(@as(u32, 76471), tickPeriodUs(20));
    try std.testing.expectEqual(@as(u32, 63415), tickPeriodUs(30));
    try std.testing.expectEqual(@as(u32, 55000), tickPeriodUs(40));
    // min(score/10, 4) clamps everything from 40 up to the last entry.
    try std.testing.expectEqual(@as(u32, 55000), tickPeriodUs(1000));
}

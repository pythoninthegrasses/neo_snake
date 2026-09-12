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

// --- Tier-A suite (TASK-019) ----------------------------------------------
// One named test per load-bearing behavior in this module: the advance()
// statement order (docs/architecture.md "Simulation"), the tail-chase
// survive/eat split, the negative-wrap arithmetic, the ns_pump clamp and
// accumulator carry (docs/abi-decisions.md freeze #5), and the canonical
// serialize∘deserialize identity (docs/canonical-state.md). Each maps to a
// single Acceptance Criterion so a regression names itself.

test "refAllDecls" {
    std.testing.refAllDecls(@This());
}

test "advance commits next_dir into dir before the head moves" {
    // advance()'s first line is `w.dir = w.next_dir`; the committed
    // direction — not a stale one — is what moves the head the very same
    // tick. Queuing a legal turn and advancing once must reflect it in both
    // `dir` and the head position, not one tick later.
    var buf: [COLS * ROWS]Cell = undefined;
    var w: World = undefined;
    initWorld(&w, &buf, COLS, ROWS, false, .{ 1, 2, 3, 4 }, .playing);
    w.food = null;

    queueDir(&w, .up); // legal against dir=right
    advance(&w);

    try std.testing.expectEqual(Dir.up, w.dir); // committed this tick
    try std.testing.expectEqual(@as(u16, 8), cells(&w)[0].x); // head at (8,11)
    try std.testing.expectEqual(@as(u16, 11), cells(&w)[0].y); // ...one up from (8,12)
    try std.testing.expectEqual(@as(u32, 1), w.tick);
}

test "wrap uses @mod on the (+size) offset, not raw signed %" {
    // Zig's % truncates toward zero, so `-1 % 24 == -1`, not 23. advance()
    // wraps with `@mod(nx + cols, cols)` (the oracle's own +size expression)
    // precisely so a head walking off x=0/y=0 lands on cols-1/rows-1. This
    // pins the arithmetic identity: a naive `%` without the +size offset (or
    // with `%` instead of `@mod`) lands on a negative / wrong value here.
    var buf: [COLS * ROWS]Cell = undefined;

    // x = 0 moving left: pre-wrap nx is -1.
    var w: World = undefined;
    initWorld(&w, &buf, COLS, ROWS, true, .{ 1, 2, 3, 4 }, .playing);
    w.cells_buf[0] = .{ .x = 0, .y = 5 };
    w.cells_buf[1] = .{ .x = 1, .y = 5 };
    w.cells_buf[2] = .{ .x = 2, .y = 5 };
    w.dir = .left;
    w.next_dir = .left;
    w.food = null;
    advance(&w);
    try std.testing.expectEqual(Status.playing, w.status);
    try std.testing.expectEqual(@as(u16, COLS - 1), cells(&w)[0].x);

    // y = 0 moving up: pre-wrap ny is -1.
    var v: World = undefined;
    initWorld(&v, &buf, COLS, ROWS, true, .{ 1, 2, 3, 4 }, .playing);
    v.cells_buf[0] = .{ .x = 5, .y = 0 };
    v.cells_buf[1] = .{ .x = 5, .y = 1 };
    v.cells_buf[2] = .{ .x = 5, .y = 2 };
    v.dir = .up;
    v.next_dir = .up;
    v.food = null;
    advance(&v);
    try std.testing.expectEqual(Status.playing, v.status);
    try std.testing.expectEqual(@as(u16, ROWS - 1), cells(&v)[0].y);
}

test "tail-chase survives entering the vacating tail cell when not eating" {
    // Self-collision is checked against the body minus the cell the tail is
    // about to vacate, so moving into the space your tail leaves is legal —
    // but only because not eating means the tail actually moves this tick.
    var buf: [COLS * ROWS]Cell = undefined;
    var w: World = undefined;
    initWorld(&w, &buf, COLS, ROWS, false, .{ 1, 2, 3, 4 }, .playing);
    w.cells_buf[0] = .{ .x = 5, .y = 5 }; // head
    w.cells_buf[1] = .{ .x = 10, .y = 5 }; // mid (never adjacent to the move)
    w.cells_buf[2] = .{ .x = 4, .y = 5 }; // tail, the cell the head enters
    w.cells_len = 3;
    w.dir = .left;
    w.next_dir = .left;
    w.food = null; // not eating -> tail vacates

    advance(&w);
    try std.testing.expectEqual(Status.playing, w.status);
    try std.testing.expectEqualSlices(Cell, &[_]Cell{
        .{ .x = 4, .y = 5 }, .{ .x = 5, .y = 5 }, .{ .x = 10, .y = 5 },
    }, cells(&w));
}

test "tail-chase dies entering the tail cell when eating" {
    // The single most likely thing to get wrong in a port: this is the exact
    // layout as the surviving case except food now sits on the tail cell too.
    // Eating pins the tail (the snake grows instead of shifting), so the same
    // move that was legal a moment ago is now a fatal self-collision.
    var buf: [COLS * ROWS]Cell = undefined;
    var w: World = undefined;
    initWorld(&w, &buf, COLS, ROWS, false, .{ 1, 2, 3, 4 }, .playing);
    w.cells_buf[0] = .{ .x = 5, .y = 5 }; // head
    w.cells_buf[1] = .{ .x = 10, .y = 5 }; // mid
    w.cells_buf[2] = .{ .x = 4, .y = 5 }; // tail == next cell == food
    w.cells_len = 3;
    w.dir = .left;
    w.next_dir = .left;
    w.food = .{ .x = 4, .y = 5 }; // the move is a scoring move

    advance(&w);
    // eating -> body_len_check == cells_len (tail included) -> self-hit -> die
    try std.testing.expectEqual(Status.dead, w.status);
}

test "out-of-bounds death happens after the direction commit" {
    // The wall-mode bounds check runs after `w.dir = w.next_dir`, so a fatal
    // step still commits the new direction: `dir` reflects the direction that
    // actually walked off the board, proving the commit is unconditional and
    // not skipped when the move turns out to be fatal.
    var buf: [COLS * ROWS]Cell = undefined;
    var w: World = undefined;
    initWorld(&w, &buf, COLS, ROWS, false, .{ 1, 2, 3, 4 }, .playing);
    w.cells_buf[0] = .{ .x = 12, .y = 0 }; // head against the top edge
    w.cells_buf[1] = .{ .x = 11, .y = 0 };
    w.cells_buf[2] = .{ .x = 10, .y = 0 };
    w.cells_len = 3;
    w.dir = .right; // moving right along the top row
    w.next_dir = .right;
    w.food = null;

    queueDir(&w, .up); // legal turn (not a 180 of right) that walks off y=0
    advance(&w);

    try std.testing.expectEqual(Dir.up, w.dir); // committed even though fatal
    try std.testing.expectEqual(Status.dead, w.status); // died moving up, off the top
}

test "advance scores 10 before placeFood and wins only after the increment" {
    // Inside the eating branch the order is: grow, score += 10, placeFood,
    // and only if placeFood finds no free cell does the game win. On a full
    // board that means the score increment has already landed (10) at the
    // moment the win fires, not skipped or ordered after the win.
    var buf: [4]Cell = undefined;
    var w: World = undefined;
    initWorld(&w, &buf, 2, 2, false, .{ 1, 2, 3, 4 }, .playing);
    w.cells_buf[0] = .{ .x = 1, .y = 0 };
    w.cells_buf[1] = .{ .x = 1, .y = 1 };
    w.cells_buf[2] = .{ .x = 0, .y = 1 };
    w.cells_len = 3;
    w.dir = .left;
    w.next_dir = .left;
    w.food = .{ .x = 0, .y = 0 }; // the only free cell on a 2x2 board

    advance(&w);
    try std.testing.expectEqual(@as(u32, 10), w.score); // incremented first
    try std.testing.expectEqual(@as(u32, 4), w.cells_len); // grew to fill the board
    try std.testing.expect(w.food == null); // placeFood found no free cell
    try std.testing.expectEqual(Status.dead, w.status); // win == dead (oracle parity)
}

test "queueDir reads dir while playing and next_dir in every other status" {
    // queueDir's 180 guard is `if (status == .playing) dir else next_dir`.
    // Both branches are pinned with `dir` and `next_dir` deliberately made to
    // differ, so a guard that reads the wrong field rejects/accepts wrongly.
    var buf: [COLS * ROWS]Cell = undefined;

    // Playing: guard reads dir. dir=up, next_dir=right; .down is the reverse
    // of dir (reject), but NOT the reverse of next_dir (would wrongly accept
    // if the guard read next_dir).
    var p: World = undefined;
    initWorld(&p, &buf, COLS, ROWS, false, .{ 1, 2, 3, 4 }, .playing);
    p.dir = .up;
    p.next_dir = .right;
    queueDir(&p, .down);
    try std.testing.expectEqual(Dir.right, p.next_dir); // rejected: guard read dir=up

    // Paused (non-playing): guard reads next_dir. dir=up, next_dir=right;
    // .left is the reverse of next_dir (reject), but NOT of dir (would wrongly
    // accept if the guard read dir).
    var q: World = undefined;
    initWorld(&q, &buf, COLS, ROWS, false, .{ 1, 2, 3, 4 }, .paused);
    q.dir = .up;
    q.next_dir = .right;
    queueDir(&q, .left);
    try std.testing.expectEqual(Dir.right, q.next_dir); // rejected: guard read next_dir=right
    try std.testing.expectEqual(Status.paused, q.status); // a rejected input never resumes
}

test "pump clamps to MAX_STEPS per call and carries the remainder over" {
    // docs/abi-decisions.md freeze #5: the accumulator runs on integer us.
    // (a) A pump handed more accumulated time than MAX_STEPS ticks consumes at
    // most MAX_STEPS advances and leaves the rest in acc_us, never discarding
    // it. (b) A sub-tick remainder carries into the next pump and is consumed
    // there. Both are asserted here per AC#3.
    var buf: [COLS * ROWS]Cell = undefined;

    // The frozen table itself, so the pump math below is pinned to it.
    try std.testing.expectEqual(@as(u32, 130_000), tickPeriodUs(0));
    try std.testing.expectEqual(@as(u32, 55_000), tickPeriodUs(40));

    // (a) Clamp: score=40 -> 55000 us period, MAX_DT_US clamps dt to 64000 and
    // acc is preloaded with 10 ticks of time. Only MAX_STEPS fire; the other
    // four ticks' worth stays in acc_us.
    var w: World = undefined;
    initWorld(&w, &buf, COLS, ROWS, false, .{ 1, 2, 3, 4 }, .playing);
    w.food = null;
    w.score = 40; // fastest period, 55000 us
    w.acc_us = 550_000; // 10 ticks of prebuilt accumulated time
    const stepped = pump(&w, 0);
    try std.testing.expectEqual(@as(u32, MAX_STEPS), stepped);
    try std.testing.expectEqual(@as(u32, 550_000 - MAX_STEPS * 55_000), w.acc_us); // 220000 carried
    try std.testing.expectEqual(@as(u32, MAX_STEPS), w.tick); // 6 advances, snake still alive
    try std.testing.expectEqual(Status.playing, w.status);

    // (b) Carry-over: 64 + 64 + 64 ms against the 130000 us first period. The
    // first two pumps fall short; the third crosses the tick, and the 62000 us
    // that's left is exactly the unconsumed remainder, carried not discarded.
    var acc: World = undefined;
    initWorld(&acc, &buf, COLS, ROWS, false, .{ 1, 2, 3, 4 }, .playing);
    acc.food = null;
    try std.testing.expectEqual(@as(u32, 0), pump(&acc, 64_000)); // 64000 < 130000
    try std.testing.expectEqual(@as(u32, 0), pump(&acc, 64_000)); // 128000 < 130000
    try std.testing.expectEqual(@as(u32, 1), pump(&acc, 64_000)); // 192000 >= 130000
    try std.testing.expectEqual(@as(u32, 62_000), acc.acc_us); // 192000 - 130000
    try std.testing.expectEqual(@as(u32, 1), acc.tick);

    // A paused frame accumulates and advances nothing.
    acc.status = .paused;
    try std.testing.expectEqual(@as(u32, 0), pump(&acc, 64_000));
}

test "serialize then deserialize round-trips a driven World" {
    // canon.encode/decode operate on canon.State, not World, and there is no
    // World->canon.State helper in this module, so the conversion is built
    // field-by-field inline here (per TASK-019). The world is driven through
    // an eat, further advances, and a pump so tick, score, rng_state and the
    // body all diverge from their initial values before the round-trip.
    var buf: [COLS * ROWS]Cell = undefined;
    var w: World = undefined;
    initWorld(&w, &buf, COLS, ROWS, false, .{ 1, 2, 3, 4 }, .playing);
    w.food = .{ .x = 9, .y = 12 }; // directly ahead -> eat on the first advance
    advance(&w); // score 10, body grows, placeFood advances the rng stream
    advance(&w);
    advance(&w);
    _ = pump(&w, 64_000); // accumulator + possibly another advance

    try std.testing.expect(w.food != null); // a real, non-null food to round-trip
    try std.testing.expect(w.tick > 0);
    try std.testing.expect(w.score > 0);

    // Build canon.State from the world's live fields (head-first cells view).
    const snapshot = w.rng.state();
    const player = canon.Player{
        .status = w.status,
        .dir = w.dir,
        .next_dir = w.next_dir,
        .score = w.score,
        .cells = cells(&w),
    };
    const players_arr = [_]canon.Player{player};
    const state = canon.State{
        .cols = w.cols,
        .rows = w.rows,
        .wrap = w.wrap,
        .tick = w.tick,
        .rng_state = snapshot,
        .food = w.food,
        .players = &players_arr,
    };

    var enc: [512]u8 = undefined;
    const rec = try canon.encode(state, &enc);
    try std.testing.expect(canon.verify(rec));

    var players: [1]canon.Player = undefined;
    var decoded_cells: [COLS * ROWS]canon.Cell = undefined;
    const got = try canon.decode(rec, &players, &decoded_cells);

    // Every field of the decoded state equals the world it was built from.
    try std.testing.expectEqual(w.cols, got.cols);
    try std.testing.expectEqual(w.rows, got.rows);
    try std.testing.expectEqual(w.wrap, got.wrap);
    try std.testing.expectEqual(w.tick, got.tick);
    try std.testing.expectEqualSlices(u32, &snapshot, &got.rng_state);
    try std.testing.expect(got.food != null);
    try std.testing.expectEqual(w.food.?.x, got.food.?.x);
    try std.testing.expectEqual(w.food.?.y, got.food.?.y);

    try std.testing.expectEqual(@as(usize, 1), got.players.len);
    const gp = got.players[0];
    try std.testing.expectEqual(w.status, gp.status);
    try std.testing.expectEqual(w.dir, gp.dir);
    try std.testing.expectEqual(w.next_dir, gp.next_dir);
    try std.testing.expectEqual(w.score, gp.score);
    try std.testing.expectEqualSlices(canon.Cell, cells(&w), gp.cells);
}

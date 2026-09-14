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
//!
//! TASK-051 (backlog/decisions/decision-034) generalized this module from a
//! single scalar player to `player_count` (1 or 2) players sharing one
//! board, one food cell, and one RNG stream. `player_count == 1` reproduces
//! every byte of the original single-player behavior — the frozen oracle
//! corpus/fuzz invariants exercise exactly that path, unchanged — the
//! multi-player path is purely additive. See decision-034 for the collision,
//! elimination, and starting-position rules a two-player match uses that a
//! single-player game never exercises.

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
/// `pub` so core/abi.zig's ns_pump (TASK-024) can reproduce this exact loop
/// while recording a per-tick event, instead of duplicating the constant.
pub const MAX_DT_US = 64 * 1000;
/// sim.mjs's frame() catch-up guard: at most this many advances per pump.
pub const MAX_STEPS = 6;

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

/// Highest player count this module (and core/abi.zig's ABI surface) knows
/// how to simulate — decision-034 scoped real multiplayer to exactly two
/// local players, not an arbitrary N; raising this later is additive.
pub const MAX_PLAYERS: u8 = 2;

/// One player's own slice of an otherwise-shared World: direction, score,
/// elimination flag, and body. `alive` starts true and only ever latches to
/// false (on death or on winning — decision-034 keeps the single-player
/// win()-is-just-a-flavor-of-die() convention) until the next reset().
/// `status` is deliberately not tracked per player: a live player's exposed
/// status is always the shared `World.status`, and an eliminated player's is
/// always `.dead` — core/abi.zig projects that directly from `alive` plus
/// `World.status` rather than this struct duplicating the enum.
pub const PlayerState = struct {
    dir: Dir,
    next_dir: Dir,
    score: u32,
    alive: bool,
    /// Caller-owned; sized `requiredCells(cols, rows)` by ns_world_init
    /// (AC#2: all caller-provided memory arrives as explicit parameters).
    cells_buf: []Cell,
    cells_len: u32,
};

/// One snake-or-two, one board, one RNG stream — sim.mjs's state object `S`,
/// with the presentation-only fields (flash, particles, the overlay/HUD
/// sync) dropped as they have no canonical byte (docs/canonical-state.md)
/// and the accumulator converted to integer microseconds (see `pump`).
///
/// `status` is the shared game phase (menu/playing/paused/dead), exactly as
/// in the single-player original: pausing pauses every player at once (a
/// shared-screen local match has one pause key), and the phase only becomes
/// `.dead` once every player is eliminated (`advance`'s tail computes this
/// every tick — decision-034). `food`, `tick`, and `rng` are likewise
/// board-level, not per-player: one shared food cell, one shared clock, one
/// shared RNG stream (docs/abi-decisions.md freeze #1), matching
/// docs/canonical-state.md's wire format, which has exactly one of each at
/// the record header level and only status/dir/next_dir/score/cells inside
/// each per-player record.
pub const World = struct {
    cols: u16,
    rows: u16,
    wrap: bool,
    tick: u32,
    status: Status,
    /// `null` is the win / board-full state (the canonical 0xFFFF sentinel).
    food: ?Cell,

    /// The single shared RNG stream (docs/rng.md, freeze #3).
    rng: rng.Rng,

    /// ns_pump's fixed-timestep accumulator in integer microseconds — the
    /// carry-over between pump calls. Not part of the canonical state, just
    /// like sim.mjs's S.acc is not part of the oracle's.
    acc_us: u32,

    player_count: u8,
    players: [MAX_PLAYERS]PlayerState,
};

/// Minimum caller-supplied cell-buffer length for one player's board: the
/// snake can occupy every cell on a full-board win. A caller sizing storage
/// for `player_count` players needs `player_count * requiredCells(...)`
/// cells total (core/abi.zig's ns_world_size does exactly this).
pub fn requiredCells(cols: u16, rows: u16) usize {
    return @as(usize, cols) * @as(usize, rows);
}

/// The live snake, head-first: `cells(w, player)[0]` is that player's head.
pub fn cells(w: *const World, player: u8) []const Cell {
    const p = &w.players[player];
    return p.cells_buf[0..p.cells_len];
}

/// True if any body cell of any player (dead or alive — decision-034: an
/// eliminated player's corpse is a permanent obstacle, never cleared) sits
/// on (x, y). O(total body length), like the oracle's single-player
/// `occupied()`; board and snake sizes make the linear scan cheap.
fn occupied(w: *const World, x: u16, y: u16) bool {
    for (0..w.player_count) |i| {
        for (cells(w, @intCast(i))) |c| {
            if (c.x == x and c.y == y) return true;
        }
    }
    return false;
}

/// sim.mjs's placeFood(): the same row-major (outer y, inner x) free-cell
/// enumeration — so the same draw indexes the same cell — but found by
/// counting free cells and walking to the drawn one instead of building a
/// free-cell list, since this code has no allocator. Extended (decision-034)
/// to count every player's body, dead or alive, as occupied: the single
/// shared food cell can never land on anyone's snake, living or eliminated.
pub fn placeFood(w: *World) void {
    const total = requiredCells(w.cols, w.rows);
    var occupied_count: usize = 0;
    for (0..w.player_count) |i| occupied_count += w.players[i].cells_len;
    const free = total - occupied_count;
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

/// sim.mjs's reset(): a 3-cell snake per player, head at (8, cy) head-first,
/// dir/next_dir forced to right, score cleared, every player marked alive,
/// shared tick/accumulator cleared, food placed. Like the oracle's, this
/// does not touch `status` — start() sets that after calling it. `wrap` is a
/// preserved setting, not reset.
///
/// decision-034's starting-row formula, `cy(i) = rows * (i+1) / (player_count
/// + 1)`, spaces `player_count` players evenly down the board and is an
/// exact generalization of the single-player original: at player_count == 1
/// it reduces to `rows * 1 / 2 == rows / 2`, the oracle's own formula,
/// byte-for-byte (integer division), so single-player starting position is
/// unchanged.
pub fn reset(w: *World) void {
    for (0..w.player_count) |i| {
        const cy = @as(u16, @intCast(@as(u32, w.rows) * (i + 1) / (@as(u32, w.player_count) + 1)));
        var p = &w.players[i];
        p.cells_buf[0] = .{ .x = 8, .y = cy };
        p.cells_buf[1] = .{ .x = 7, .y = cy };
        p.cells_buf[2] = .{ .x = 6, .y = cy };
        p.cells_len = 3;
        p.dir = .right;
        p.next_dir = .right;
        p.score = 0;
        p.alive = true;
    }
    w.tick = 0;
    w.acc_us = 0;
    placeFood(w);
}

/// sim.mjs's initialState(): a fresh world at the oracle's reset() starting
/// position, food drawn from `seed`. `status` chooses the initial
/// state-machine position — the oracle's own reset() never sets status
/// itself, but initialState takes it as a parameter, so this mirrors that.
/// `cells_buf` must be at least `player_count * requiredCells(cols, rows)`
/// long; it is partitioned into `player_count` equal per-player sub-slices,
/// in order (core/abi.zig's ns_world_init owns the actual byte layout this
/// partitions).
pub fn initWorld(w: *World, cells_buf: []Cell, cols: u16, rows: u16, player_count: u8, wrap: bool, seed: [4]u32, status: Status) void {
    std.debug.assert(player_count >= 1 and player_count <= MAX_PLAYERS);
    const per_player = requiredCells(cols, rows);
    std.debug.assert(cells_buf.len >= per_player * player_count);

    w.cols = cols;
    w.rows = rows;
    w.wrap = wrap;
    w.tick = 0;
    w.status = status;
    w.food = null;
    w.rng = rng.Rng.init(seed);
    w.acc_us = 0;
    w.player_count = player_count;
    for (0..player_count) |i| {
        w.players[i] = .{
            .dir = .right,
            .next_dir = .right,
            .score = 0,
            .alive = true,
            .cells_buf = cells_buf[i * per_player .. (i + 1) * per_player],
            .cells_len = 0,
        };
    }
    reset(w);
}

/// sim.mjs's start(): reset() first, then status = playing.
pub fn start(w: *World) void {
    reset(w);
    w.status = .playing;
}

/// sim.mjs's queueDir(): the single choke point for input legality. The
/// 180-degree guard reads `dir` while playing and `next_dir` in every other
/// status; a direction queued from menu/dead starts the game (or restarts a
/// finished match — decision-015's quirk, kept verbatim and, per
/// decision-034, whole-world: any one player's first legal input starts or
/// restarts the shared match for everyone, matching a same-screen local
/// match's "press any direction to begin" convention). An already-eliminated
/// player queuing a direction mid-match is accepted but inert — `advance`
/// never reads a dead player's dir/next_dir again until the next reset().
pub fn queueDir(w: *World, player: u8, d: Dir) void {
    const p = &w.players[player];
    const ref = if (w.status == .playing) p.dir else p.next_dir;
    const rv = DIR_VEC[@intFromEnum(ref)];
    const dv = DIR_VEC[@intFromEnum(d)];
    if (dv.dx == -rv.dx and dv.dy == -rv.dy) return; // no instant 180
    p.next_dir = d;
    if (w.status == .menu or w.status == .dead) start(w);
}

/// sim.mjs's togglePause(): a no-op outside playing/paused. Whole-world, not
/// per-player — a shared-screen local match pauses for both players at once.
pub fn togglePause(w: *World) void {
    if (w.status == .playing) {
        w.status = .paused;
    } else if (w.status == .paused) {
        w.status = .playing;
    }
}

/// Per-player phase-1 (read-only) result: where advance() would move this
/// player's head, whether that move eats the shared food, or whether it is
/// already fatal — computed against the tick's *starting* snapshot (nobody
/// else has moved yet), so which order players are visited in cannot change
/// the outcome (decision-020's phase-separation pattern, generalized here to
/// include real cross-player collision, which decision-020's own primitive
/// deliberately left unmodeled).
const PlayerMove = struct {
    dies: bool,
    new_head: Cell,
    eats: bool,
};

/// Phase 1 for one player: commit dir, compute the candidate head, and check
/// walls/wrap, self-collision (tail-vacate exception preserved verbatim),
/// and — decision-034's new rule — collision against every *other* player's
/// full, pre-tick body (dead or alive: a corpse still blocks). No tail-vacate
/// exception is extended to an opponent's body: their tail's fate is still
/// unresolved at this point in the tick (phase 2 hasn't run), so treating
/// their whole pre-tick body as solid is the conservative, order-independent
/// reading of "occupied right now".
fn planMove(w: *const World, player: u8) PlayerMove {
    const p = &w.players[player];
    const head = p.cells_buf[0];
    const v = DIR_VEC[@intFromEnum(p.dir)];
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
        return .{ .dies = true, .new_head = undefined, .eats = false };
    }
    const nc = Cell{ .x = @intCast(nx), .y = @intCast(ny) };

    // Tail vacates this tick unless we eat: self-collision is tested against
    // the body minus the cell it is about to vacate, which is why moving
    // into the space your own tail leaves is legal.
    const eating = w.food != null and nc.x == w.food.?.x and nc.y == w.food.?.y;
    const self_check_len: u32 = if (eating) p.cells_len else p.cells_len - 1;
    for (0..self_check_len) |i| {
        const c = p.cells_buf[i];
        if (c.x == nc.x and c.y == nc.y) return .{ .dies = true, .new_head = undefined, .eats = false };
    }

    for (0..w.player_count) |j| {
        if (j == player) continue;
        for (cells(w, @intCast(j))) |c| {
            if (c.x == nc.x and c.y == nc.y) return .{ .dies = true, .new_head = undefined, .eats = false };
        }
    }

    return .{ .dies = false, .new_head = nc, .eats = eating };
}

/// sim.mjs's advance(), generalized to `player_count` players (decision-034).
/// Statement order is still load-bearing — see this module's header. Phase 1
/// (`planMove`, above) is read-only and order-independent; phase 2 below
/// always mutates in ascending player-index order, exactly like
/// decision-020's fuzz primitive, so a permuted visitation order can never
/// change the result. At `player_count == 1` every cross-player/head-to-head
/// step below is a no-op (there is no other player), so this reproduces the
/// original single-player advance() byte-for-byte, including its
/// die()/win()-return-before-the-tick-increment quirk: `w.tick` only
/// advances when at least one player is still alive afterward, which for a
/// single player is exactly "didn't just die".
pub fn advance(w: *World) void {
    var dies: [MAX_PLAYERS]bool = .{ false, false };
    var new_head: [MAX_PLAYERS]Cell = undefined;
    var eats: [MAX_PLAYERS]bool = .{ false, false };

    // Phase 1: commit dir and plan each still-alive player's move against
    // the tick's starting snapshot.
    for (0..w.player_count) |i| {
        const p = &w.players[i];
        if (!p.alive) continue;
        p.dir = p.next_dir;
        const move = planMove(w, @intCast(i));
        dies[i] = move.dies;
        new_head[i] = move.new_head;
        eats[i] = move.eats;
    }

    // Head-to-head: two still-surviving players landing on the same cell
    // this tick mutually kill each other (decision-034) — symmetric, so
    // visiting order doesn't matter; with MAX_PLAYERS == 2 there is only
    // ever one pair to check.
    for (0..w.player_count) |i| {
        if (!w.players[i].alive or dies[i]) continue;
        for (i + 1..w.player_count) |j| {
            if (!w.players[j].alive or dies[j]) continue;
            if (new_head[i].x == new_head[j].x and new_head[i].y == new_head[j].y) {
                dies[i] = true;
                dies[j] = true;
            }
        }
    }

    // Phase 2 (fixed ascending index, never a visitation order): mutate
    // bodies, resolve the shared food, and — only if something was eaten —
    // draw the one shared-RNG replacement food (docs/rng.md "Food placement"
    // point 3's ascending-index rule).
    var ate_this_tick = false;
    for (0..w.player_count) |i| {
        var p = &w.players[i];
        if (!p.alive) continue;
        if (dies[i]) {
            // decision-034: a corpse is left exactly where it fell — never
            // cleared — so it keeps blocking movement and food placement,
            // the same as the single-player original never clearing a dead
            // snake's body either.
            p.alive = false;
            continue;
        }
        const buf = p.cells_buf[0 .. p.cells_len + 1];
        @memmove(buf[1..], buf[0..p.cells_len]);
        p.cells_buf[0] = new_head[i];
        if (eats[i]) {
            p.cells_len += 1;
            p.score += 10;
            ate_this_tick = true;
        }
    }
    if (ate_this_tick) {
        w.food = null;
        placeFood(w);
        if (w.food == null) {
            // Board full: whoever just ate won (decision-034 keeps the
            // single-player win()-is-a-flavor-of-die() sentinel — no
            // separate "won" state exists in `alive`/`status`).
            for (0..w.player_count) |i| {
                if (w.players[i].alive and eats[i]) w.players[i].alive = false;
            }
        }
    }

    var any_alive = false;
    for (0..w.player_count) |i| {
        if (w.players[i].alive) any_alive = true;
    }
    if (any_alive) {
        w.tick += 1;
    } else {
        w.status = .dead;
    }
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
///
/// The tick period is read from player 0's score, matching core/abi.zig's
/// ns_pump/ns_step contract (docs/abi-header.md): speed is not yet a
/// per-player notion (decision-034 didn't need one — both a solo game and a
/// two-player match share one clock either way).
pub fn pump(w: *World, dt_us: u32) u32 {
    if (w.status != .playing) return 0;

    const dt = @min(dt_us, MAX_DT_US);
    w.acc_us += dt;

    var steps: u32 = 0;
    var step_us = tickPeriodUs(w.players[0].score);
    while (w.acc_us >= step_us and w.status == .playing and steps < MAX_STEPS) {
        w.acc_us -= step_us;
        advance(w);
        step_us = tickPeriodUs(w.players[0].score);
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
// single Acceptance Criterion so a regression names itself. Every test here
// drives `initWorld` with `player_count = 1`, proving the single-player path
// this task's generalization must not disturb; decision-034's own new tests
// (below) cover the two-player-only behavior.

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
    initWorld(&w, &buf, COLS, ROWS, 1, false, .{ 1, 2, 3, 4 }, .playing);
    w.food = null;

    queueDir(&w, 0, .up); // legal against dir=right
    advance(&w);

    try std.testing.expectEqual(Dir.up, w.players[0].dir); // committed this tick
    try std.testing.expectEqual(@as(u16, 8), cells(&w, 0)[0].x); // head at (8,11)
    try std.testing.expectEqual(@as(u16, 11), cells(&w, 0)[0].y); // ...one up from (8,12)
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
    initWorld(&w, &buf, COLS, ROWS, 1, true, .{ 1, 2, 3, 4 }, .playing);
    w.players[0].cells_buf[0] = .{ .x = 0, .y = 5 };
    w.players[0].cells_buf[1] = .{ .x = 1, .y = 5 };
    w.players[0].cells_buf[2] = .{ .x = 2, .y = 5 };
    w.players[0].dir = .left;
    w.players[0].next_dir = .left;
    w.food = null;
    advance(&w);
    try std.testing.expectEqual(Status.playing, w.status);
    try std.testing.expectEqual(@as(u16, COLS - 1), cells(&w, 0)[0].x);

    // y = 0 moving up: pre-wrap ny is -1.
    var v: World = undefined;
    initWorld(&v, &buf, COLS, ROWS, 1, true, .{ 1, 2, 3, 4 }, .playing);
    v.players[0].cells_buf[0] = .{ .x = 5, .y = 0 };
    v.players[0].cells_buf[1] = .{ .x = 5, .y = 1 };
    v.players[0].cells_buf[2] = .{ .x = 5, .y = 2 };
    v.players[0].dir = .up;
    v.players[0].next_dir = .up;
    v.food = null;
    advance(&v);
    try std.testing.expectEqual(Status.playing, v.status);
    try std.testing.expectEqual(@as(u16, ROWS - 1), cells(&v, 0)[0].y);
}

test "tail-chase survives entering the vacating tail cell when not eating" {
    // Self-collision is checked against the body minus the cell the tail is
    // about to vacate, so moving into the space your tail leaves is legal —
    // but only because not eating means the tail actually moves this tick.
    var buf: [COLS * ROWS]Cell = undefined;
    var w: World = undefined;
    initWorld(&w, &buf, COLS, ROWS, 1, false, .{ 1, 2, 3, 4 }, .playing);
    w.players[0].cells_buf[0] = .{ .x = 5, .y = 5 }; // head
    w.players[0].cells_buf[1] = .{ .x = 10, .y = 5 }; // mid (never adjacent to the move)
    w.players[0].cells_buf[2] = .{ .x = 4, .y = 5 }; // tail, the cell the head enters
    w.players[0].cells_len = 3;
    w.players[0].dir = .left;
    w.players[0].next_dir = .left;
    w.food = null; // not eating -> tail vacates

    advance(&w);
    try std.testing.expectEqual(Status.playing, w.status);
    try std.testing.expectEqualSlices(Cell, &[_]Cell{
        .{ .x = 4, .y = 5 }, .{ .x = 5, .y = 5 }, .{ .x = 10, .y = 5 },
    }, cells(&w, 0));
}

test "tail-chase dies entering the tail cell when eating" {
    // The single most likely thing to get wrong in a port: this is the exact
    // layout as the surviving case except food now sits on the tail cell too.
    // Eating pins the tail (the snake grows instead of shifting), so the same
    // move that was legal a moment ago is now a fatal self-collision.
    var buf: [COLS * ROWS]Cell = undefined;
    var w: World = undefined;
    initWorld(&w, &buf, COLS, ROWS, 1, false, .{ 1, 2, 3, 4 }, .playing);
    w.players[0].cells_buf[0] = .{ .x = 5, .y = 5 }; // head
    w.players[0].cells_buf[1] = .{ .x = 10, .y = 5 }; // mid
    w.players[0].cells_buf[2] = .{ .x = 4, .y = 5 }; // tail == next cell == food
    w.players[0].cells_len = 3;
    w.players[0].dir = .left;
    w.players[0].next_dir = .left;
    w.food = .{ .x = 4, .y = 5 }; // the move is a scoring move

    advance(&w);
    // eating -> self_check_len == cells_len (tail included) -> self-hit -> die
    try std.testing.expectEqual(Status.dead, w.status);
}

test "out-of-bounds death happens after the direction commit" {
    // The wall-mode bounds check runs after `w.dir = w.next_dir`, so a fatal
    // step still commits the new direction: `dir` reflects the direction that
    // actually walked off the board, proving the commit is unconditional and
    // not skipped when the move turns out to be fatal.
    var buf: [COLS * ROWS]Cell = undefined;
    var w: World = undefined;
    initWorld(&w, &buf, COLS, ROWS, 1, false, .{ 1, 2, 3, 4 }, .playing);
    w.players[0].cells_buf[0] = .{ .x = 12, .y = 0 }; // head against the top edge
    w.players[0].cells_buf[1] = .{ .x = 11, .y = 0 };
    w.players[0].cells_buf[2] = .{ .x = 10, .y = 0 };
    w.players[0].cells_len = 3;
    w.players[0].dir = .right; // moving right along the top row
    w.players[0].next_dir = .right;
    w.food = null;

    queueDir(&w, 0, .up); // legal turn (not a 180 of right) that walks off y=0
    advance(&w);

    try std.testing.expectEqual(Dir.up, w.players[0].dir); // committed even though fatal
    try std.testing.expectEqual(Status.dead, w.status); // died moving up, off the top
}

test "advance scores 10 before placeFood and wins only after the increment" {
    // Inside the eating branch the order is: grow, score += 10, placeFood,
    // and only if placeFood finds no free cell does the game win. On a full
    // board that means the score increment has already landed (10) at the
    // moment the win fires, not skipped or ordered after the win.
    var buf: [4]Cell = undefined;
    var w: World = undefined;
    initWorld(&w, &buf, 2, 2, 1, false, .{ 1, 2, 3, 4 }, .playing);
    w.players[0].cells_buf[0] = .{ .x = 1, .y = 0 };
    w.players[0].cells_buf[1] = .{ .x = 1, .y = 1 };
    w.players[0].cells_buf[2] = .{ .x = 0, .y = 1 };
    w.players[0].cells_len = 3;
    w.players[0].dir = .left;
    w.players[0].next_dir = .left;
    w.food = .{ .x = 0, .y = 0 }; // the only free cell on a 2x2 board

    advance(&w);
    try std.testing.expectEqual(@as(u32, 10), w.players[0].score); // incremented first
    try std.testing.expectEqual(@as(u32, 4), w.players[0].cells_len); // grew to fill the board
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
    initWorld(&p, &buf, COLS, ROWS, 1, false, .{ 1, 2, 3, 4 }, .playing);
    p.players[0].dir = .up;
    p.players[0].next_dir = .right;
    queueDir(&p, 0, .down);
    try std.testing.expectEqual(Dir.right, p.players[0].next_dir); // rejected: guard read dir=up

    // Paused (non-playing): guard reads next_dir. dir=up, next_dir=right;
    // .left is the reverse of next_dir (reject), but NOT of dir (would wrongly
    // accept if the guard read dir).
    var q: World = undefined;
    initWorld(&q, &buf, COLS, ROWS, 1, false, .{ 1, 2, 3, 4 }, .paused);
    q.players[0].dir = .up;
    q.players[0].next_dir = .right;
    queueDir(&q, 0, .left);
    try std.testing.expectEqual(Dir.right, q.players[0].next_dir); // rejected: guard read next_dir=right
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
    initWorld(&w, &buf, COLS, ROWS, 1, false, .{ 1, 2, 3, 4 }, .playing);
    w.food = null;
    w.players[0].score = 40; // fastest period, 55000 us
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
    initWorld(&acc, &buf, COLS, ROWS, 1, false, .{ 1, 2, 3, 4 }, .playing);
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
    initWorld(&w, &buf, COLS, ROWS, 1, false, .{ 1, 2, 3, 4 }, .playing);
    w.food = .{ .x = 9, .y = 12 }; // directly ahead -> eat on the first advance
    advance(&w); // score 10, body grows, placeFood advances the rng stream
    advance(&w);
    advance(&w);
    _ = pump(&w, 64_000); // accumulator + possibly another advance

    try std.testing.expect(w.food != null); // a real, non-null food to round-trip
    try std.testing.expect(w.tick > 0);
    try std.testing.expect(w.players[0].score > 0);

    // Build canon.State from the world's live fields (head-first cells view).
    const snapshot = w.rng.state();
    const player = canon.Player{
        .status = w.status,
        .dir = w.players[0].dir,
        .next_dir = w.players[0].next_dir,
        .score = w.players[0].score,
        .cells = cells(&w, 0),
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
    try std.testing.expectEqual(w.players[0].dir, gp.dir);
    try std.testing.expectEqual(w.players[0].next_dir, gp.next_dir);
    try std.testing.expectEqual(w.players[0].score, gp.score);
    try std.testing.expectEqualSlices(canon.Cell, cells(&w, 0), gp.cells);
}

// --- Two-player suite (TASK-051, decision-034) ----------------------------
// Covers exactly the behavior single-player play never exercises: the
// starting-row spacing formula, independent per-player elimination while the
// board keeps running for the survivor, cross-player body collision, and the
// symmetric head-to-head mutual kill.

test "two-player reset spaces starting rows using rows*(i+1)/(player_count+1)" {
    var buf: [2 * COLS * ROWS]Cell = undefined;
    var w: World = undefined;
    initWorld(&w, &buf, COLS, ROWS, 2, false, .{ 1, 2, 3, 4 }, .playing);

    // ROWS = 24: player 0 at 24*1/3 = 8, player 1 at 24*2/3 = 16.
    try std.testing.expectEqual(@as(u16, 8), cells(&w, 0)[0].y);
    try std.testing.expectEqual(@as(u16, 16), cells(&w, 1)[0].y);
    try std.testing.expectEqual(@as(u16, 8), cells(&w, 0)[0].x); // same starting column shape as solo play
    try std.testing.expectEqual(@as(u16, 8), cells(&w, 1)[0].x);
    try std.testing.expect(w.players[0].alive);
    try std.testing.expect(w.players[1].alive);
}

test "a player dying against a wall does not stop the surviving player" {
    var buf: [2 * COLS * ROWS]Cell = undefined;
    var w: World = undefined;
    initWorld(&w, &buf, COLS, ROWS, 2, false, .{ 1, 2, 3, 4 }, .playing);
    w.food = null;

    // Player 0 at the right edge, about to walk off; player 1 far away and
    // safe.
    w.players[0].cells_buf[0] = .{ .x = COLS - 1, .y = 0 };
    w.players[0].cells_buf[1] = .{ .x = COLS - 2, .y = 0 };
    w.players[0].cells_buf[2] = .{ .x = COLS - 3, .y = 0 };
    w.players[0].cells_len = 3;
    w.players[0].dir = .right;
    w.players[0].next_dir = .right;

    const pre_tick = w.tick;
    advance(&w);

    try std.testing.expect(!w.players[0].alive); // eliminated
    try std.testing.expect(w.players[1].alive); // untouched
    try std.testing.expectEqual(Status.playing, w.status); // match continues
    try std.testing.expectEqual(pre_tick + 1, w.tick); // the shared clock still ticked

    // The corpse stays exactly where it died (never cleared) and the
    // survivor keeps moving normally on a later tick.
    const corpse_head = cells(&w, 0)[0];
    try std.testing.expectEqual(@as(u16, COLS - 1), corpse_head.x);
    advance(&w);
    try std.testing.expectEqual(corpse_head, cells(&w, 0)[0]); // untouched by further advances
}

test "when every player is eliminated the world dies and the tick does not advance" {
    var buf: [2 * COLS * ROWS]Cell = undefined;
    var w: World = undefined;
    initWorld(&w, &buf, COLS, ROWS, 2, false, .{ 1, 2, 3, 4 }, .playing);
    w.food = null;

    // Both players walk off opposite edges on the same tick.
    w.players[0].cells_buf[0] = .{ .x = COLS - 1, .y = 0 };
    w.players[0].cells_buf[1] = .{ .x = COLS - 2, .y = 0 };
    w.players[0].cells_buf[2] = .{ .x = COLS - 3, .y = 0 };
    w.players[0].cells_len = 3;
    w.players[0].dir = .right;
    w.players[0].next_dir = .right;

    w.players[1].cells_buf[0] = .{ .x = 0, .y = 5 };
    w.players[1].cells_buf[1] = .{ .x = 1, .y = 5 };
    w.players[1].cells_buf[2] = .{ .x = 2, .y = 5 };
    w.players[1].cells_len = 3;
    w.players[1].dir = .left;
    w.players[1].next_dir = .left;

    const pre_tick = w.tick;
    advance(&w);

    try std.testing.expect(!w.players[0].alive);
    try std.testing.expect(!w.players[1].alive);
    try std.testing.expectEqual(Status.dead, w.status); // the match is over
    try std.testing.expectEqual(pre_tick, w.tick); // no player survived -> tick not incremented
}

test "entering an opponent's body cell is fatal even though it isn't self-collision" {
    var buf: [2 * COLS * ROWS]Cell = undefined;
    var w: World = undefined;
    initWorld(&w, &buf, COLS, ROWS, 2, false, .{ 1, 2, 3, 4 }, .playing);
    w.food = null;

    // Player 0 heads straight into the middle of player 1's stationary body.
    w.players[0].cells_buf[0] = .{ .x = 3, .y = 5 };
    w.players[0].cells_buf[1] = .{ .x = 2, .y = 5 };
    w.players[0].cells_buf[2] = .{ .x = 1, .y = 5 };
    w.players[0].cells_len = 3;
    w.players[0].dir = .right;
    w.players[0].next_dir = .right;

    // Player 1's body occupies (4,5) — directly ahead of player 0 — but is
    // parked far from its own head so it can't also collide with itself.
    w.players[1].cells_buf[0] = .{ .x = 10, .y = 10 };
    w.players[1].cells_buf[1] = .{ .x = 4, .y = 5 };
    w.players[1].cells_buf[2] = .{ .x = 10, .y = 12 };
    w.players[1].cells_len = 3;
    w.players[1].dir = .up;
    w.players[1].next_dir = .up;

    advance(&w);

    try std.testing.expect(!w.players[0].alive); // ran into player 1's body
    try std.testing.expect(w.players[1].alive); // player 1's own move was unobstructed
    try std.testing.expectEqual(Status.playing, w.status);
}

test "two players moving onto the same cell in the same tick mutually kill each other" {
    var buf: [2 * COLS * ROWS]Cell = undefined;
    var w: World = undefined;
    initWorld(&w, &buf, COLS, ROWS, 2, false, .{ 1, 2, 3, 4 }, .playing);
    w.food = null;

    // Player 0 moving right, player 1 moving left, both landing on (6, 5).
    w.players[0].cells_buf[0] = .{ .x = 5, .y = 5 };
    w.players[0].cells_buf[1] = .{ .x = 4, .y = 5 };
    w.players[0].cells_buf[2] = .{ .x = 3, .y = 5 };
    w.players[0].cells_len = 3;
    w.players[0].dir = .right;
    w.players[0].next_dir = .right;

    w.players[1].cells_buf[0] = .{ .x = 7, .y = 5 };
    w.players[1].cells_buf[1] = .{ .x = 8, .y = 5 };
    w.players[1].cells_buf[2] = .{ .x = 9, .y = 5 };
    w.players[1].cells_len = 3;
    w.players[1].dir = .left;
    w.players[1].next_dir = .left;

    advance(&w);

    try std.testing.expect(!w.players[0].alive);
    try std.testing.expect(!w.players[1].alive);
    try std.testing.expectEqual(Status.dead, w.status);
}

//! The C ABI wrapper — implementation of include/neo_snake.h (TASK-023).
//!
//! The ONLY Zig file in this project that exports symbols: every `export fn`
//! here has a matching declaration in include/neo_snake.h, and nothing here
//! adds behavior beyond wrapping core/world.zig, core/rng.zig, and
//! core/canon.zig behind that exact surface (docs/abi-header.md explains the
//! header's own design; docs/abi-impl.md explains the judgment calls this
//! file makes that the header doesn't already settle — the win/die event
//! split, player_count == 1 for now, the world's caller-owned memory layout).
//!
//! Caller-owned memory throughout (docs/abi-decisions.md freeze #2): the
//! caller allocates ns_world_size(config) bytes aligned to ns_world_align()
//! and passes that storage into every call; nothing here allocates.

const std = @import("std");
const world = @import("world");
const canon = @import("canon");

/// Only value #1 of docs/abi-decisions.md's multiplayer freeze is exercised
/// today (backlog/decisions/decision-020: full multiplayer is milestone
/// m-8, not this task). Every player-index check below compares against the
/// *stored* player_count rather than a literal 0, so relaxing this to > 1
/// later is additive, not a rewrite — see docs/abi-impl.md.
const MAX_SUPPORTED_PLAYERS: u8 = 1;

pub const Result = i32;
pub const NS_OK: Result = 0;
pub const NS_ERR_INVALID_ARGUMENT: Result = 1;
pub const NS_ERR_BUFFER_TOO_SMALL: Result = 2;
pub const NS_ERR_ABI_VERSION_MISMATCH: Result = 3;
pub const NS_ERR_DECODE_FAILED: Result = 4;

const NS_ABI_VERSION: u16 = 1;

const NS_DIR_UP: u8 = 0;
const NS_DIR_RIGHT: u8 = 3; // highest valid ns_dir value, for range checks

const NS_SPEED_SOURCE_SCORE_TABLE: u8 = 0;

const NS_EVENT_EAT: u8 = 0;
const NS_EVENT_DIE: u8 = 1;
const NS_EVENT_WIN: u8 = 2;

/// Mirrors ns_config (include/neo_snake.h) field-for-field, same order —
/// natural C alignment for this field sequence already matches the header's
/// explicit padding, so no `packed`/`align` overrides are needed.
pub const Config = extern struct {
    abi_version: u16,
    cols: u16,
    rows: u16,
    player_count: u8,
    wrap: u8,
    rng_seed: [4]u32,
    speed_source: u8,
    _pad: [3]u8,
};
comptime {
    std.debug.assert(@sizeOf(Config) == 28);
}

/// Mirrors ns_input.
pub const Input = extern struct {
    player: u8,
    dir: u8,
    _pad: [2]u8,
};
comptime {
    std.debug.assert(@sizeOf(Input) == 4);
}

/// Mirrors ns_player_view.
pub const PlayerView = extern struct {
    status: u8,
    dir: u8,
    next_dir: u8,
    _pad0: u8,
    score: u32,
    body_len: u32,
    _pad1: u32,
};
comptime {
    std.debug.assert(@sizeOf(PlayerView) == 16);
}

/// Mirrors ns_cell.
pub const Cell = extern struct {
    x: u16,
    y: u16,
};
comptime {
    std.debug.assert(@sizeOf(Cell) == 4);
}

/// Mirrors ns_event.
pub const Event = extern struct {
    tick: u32,
    player: u8,
    kind: u8,
    _pad: [2]u8,
};
comptime {
    std.debug.assert(@sizeOf(Event) == 8);
}

/// docs/abi-impl.md "Event queue capacity": a fixed ring buffer sized into
/// ns_world_size's storage, not a growable queue (freeze #2 forbids
/// allocating). Overflow drops the oldest event — see that doc for why a
/// silent drop here is acceptable while an ns_event_drain buffer never
/// drops anything.
const EVENT_QUEUE_CAP: usize = 64;

/// The real, caller-owned layout backing the opaque `ns_world`: the
/// simulation state, the fixed-capacity event ring, and (immediately
/// following this struct in the caller's buffer, see ns_world_init) the
/// snake's cell storage. `player_count` is echoed here (not just read from
/// the original config) so a later multiplayer loosening only ever needs to
/// change what values pass the ns_world_init check, not how call sites
/// address "this world's player count".
const WorldStorage = struct {
    world: world.World,
    player_count: u8,
    events: [EVENT_QUEUE_CAP]Event,
    event_head: usize,
    event_len: usize,
};
comptime {
    // The cell buffer is placed at offset @sizeOf(WorldStorage); that offset
    // must already satisfy Cell's alignment, or ns_world_init's pointer
    // arithmetic would hand world.zig a misaligned slice.
    std.debug.assert(@alignOf(WorldStorage) % @alignOf(world.Cell) == 0);
}

fn storageOf(ptr: *anyopaque) *WorldStorage {
    return @ptrCast(@alignCast(ptr));
}

fn storageOfConst(ptr: *const anyopaque) *const WorldStorage {
    return @ptrCast(@alignCast(ptr));
}

fn pushEvent(storage: *WorldStorage, tick: u32, player: u8, kind: u8) void {
    if (storage.event_len == EVENT_QUEUE_CAP) {
        // Drop the oldest queued event to make room (docs/abi-impl.md): an
        // undrained caller loses only history, never the world's own live
        // state, which stays queryable via ns_player_view_get regardless.
        storage.event_head = (storage.event_head + 1) % EVENT_QUEUE_CAP;
        storage.event_len -= 1;
    }
    const idx = (storage.event_head + storage.event_len) % EVENT_QUEUE_CAP;
    storage.events[idx] = .{ .tick = tick, .player = player, .kind = kind, ._pad = .{ 0, 0 } };
    storage.event_len += 1;
}

/// Advances exactly one tick and records the event it produced, if any.
/// docs/abi-impl.md "Telling win from die apart" explains why `ate` is what
/// distinguishes the two: core/world.zig's win() and die() both just set
/// status = .dead, and win() is only ever reached through the eating branch,
/// so "became dead AND scored this tick" is exactly winning.
fn stepOneTick(storage: *WorldStorage, player: u8) void {
    const w = &storage.world;
    const pre_score = w.score;
    const pre_status = w.status;
    world.advance(w);

    const ate = w.score != pre_score;
    if (ate) pushEvent(storage, w.tick, player, NS_EVENT_EAT);
    if (pre_status == .playing and w.status == .dead) {
        pushEvent(storage, w.tick, player, if (ate) NS_EVENT_WIN else NS_EVENT_DIE);
    }
}

fn buildCanonState(w: *const world.World, players_buf: *[1]canon.Player) canon.State {
    players_buf[0] = .{
        .status = w.status,
        .dir = w.dir,
        .next_dir = w.next_dir,
        .score = w.score,
        .cells = world.cells(w),
    };
    return .{
        .cols = w.cols,
        .rows = w.rows,
        .wrap = w.wrap,
        .tick = w.tick,
        .rng_state = w.rng.state(),
        .food = w.food,
        .players = players_buf[0..1],
    };
}

// --- World lifecycle --------------------------------------------------

export fn ns_world_size(config: *const Config) callconv(.c) usize {
    const cell_bytes = world.requiredCells(config.cols, config.rows) * @sizeOf(world.Cell);
    return @sizeOf(WorldStorage) + cell_bytes;
}

export fn ns_world_align() callconv(.c) usize {
    return @alignOf(WorldStorage);
}

export fn ns_world_init(world_ptr: *anyopaque, config: *const Config) callconv(.c) Result {
    if (config.abi_version != NS_ABI_VERSION) return NS_ERR_ABI_VERSION_MISMATCH;
    if (config.player_count == 0 or config.player_count > MAX_SUPPORTED_PLAYERS) return NS_ERR_INVALID_ARGUMENT;
    if (config.speed_source != NS_SPEED_SOURCE_SCORE_TABLE) return NS_ERR_INVALID_ARGUMENT;
    // reset()'s starting snake occupies x = 6..8, so cols must leave that
    // placement on the board; rows just needs to be nonzero for rows/2 to
    // land on a real row.
    if (config.cols <= 8 or config.rows == 0) return NS_ERR_INVALID_ARGUMENT;
    if (config.rng_seed[0] == 0 and config.rng_seed[1] == 0 and config.rng_seed[2] == 0 and config.rng_seed[3] == 0) {
        return NS_ERR_INVALID_ARGUMENT;
    }

    const storage = storageOf(world_ptr);
    storage.player_count = config.player_count;
    storage.event_head = 0;
    storage.event_len = 0;

    const base: [*]u8 = @ptrCast(world_ptr);
    const cells_ptr: [*]world.Cell = @ptrCast(@alignCast(base + @sizeOf(WorldStorage)));
    const cells_buf = cells_ptr[0..world.requiredCells(config.cols, config.rows)];

    // Starts in .menu, matching the reference app's own startup: the first
    // ns_queue_dir call is what transitions it to playing (decision-015).
    world.initWorld(&storage.world, cells_buf, config.cols, config.rows, config.wrap != 0, config.rng_seed, .menu);
    return NS_OK;
}

export fn ns_world_reset(world_ptr: *anyopaque) callconv(.c) Result {
    const storage = storageOf(world_ptr);
    world.reset(&storage.world);
    // docs/abi-impl.md: a fresh game discards stale events from the game it
    // replaced, same as it discards the old body/score/tick.
    storage.event_head = 0;
    storage.event_len = 0;
    return NS_OK;
}

// --- Input and stepping -------------------------------------------------

export fn ns_queue_dir(world_ptr: *anyopaque, player: u8, dir: u8) callconv(.c) Result {
    const storage = storageOf(world_ptr);
    if (player >= storage.player_count) return NS_ERR_INVALID_ARGUMENT;
    if (dir > NS_DIR_RIGHT) return NS_ERR_INVALID_ARGUMENT;
    world.queueDir(&storage.world, @enumFromInt(dir));
    return NS_OK;
}

export fn ns_step(world_ptr: *anyopaque, inputs: [*]const Input, input_count: usize) callconv(.c) Result {
    const storage = storageOf(world_ptr);

    // Validate the whole batch before mutating anything (all-or-nothing).
    var seen: u8 = 0;
    var i: usize = 0;
    while (i < input_count) : (i += 1) {
        const inp = inputs[i];
        if (inp.player >= storage.player_count) return NS_ERR_INVALID_ARGUMENT;
        const bit = @as(u8, 1) << @intCast(inp.player);
        if (seen & bit != 0) return NS_ERR_INVALID_ARGUMENT;
        seen |= bit;
        if (inp.dir > NS_DIR_RIGHT) return NS_ERR_INVALID_ARGUMENT;
    }

    const was_playing = storage.world.status == .playing;
    i = 0;
    while (i < input_count) : (i += 1) {
        const inp = inputs[i];
        world.queueDir(&storage.world, @enumFromInt(inp.dir));
    }
    // Only advance if the world was already playing before this call's
    // inputs landed — the call that starts the game from the menu must not
    // itself consume a tick (docs/abi-header.md).
    if (was_playing) stepOneTick(storage, 0);
    return NS_OK;
}

export fn ns_pump(world_ptr: *anyopaque, dt_us: u32, out_steps: *u32) callconv(.c) Result {
    const storage = storageOf(world_ptr);
    const w = &storage.world;
    if (w.status != .playing) {
        out_steps.* = 0;
        return NS_OK;
    }

    // The same accumulator loop as core/world.zig's pump(), reproduced here
    // (rather than calling it) so each advance can be individually recorded
    // as an event — delegating to pump() and diffing before/after snapshots
    // would reintroduce exactly the coalescing ambiguity events exist to
    // avoid (docs/abi-header.md).
    const dt = @min(dt_us, world.MAX_DT_US);
    w.acc_us += dt;
    var steps: u32 = 0;
    var step_us = world.tickPeriodUs(w.score);
    while (w.acc_us >= step_us and w.status == .playing and steps < world.MAX_STEPS) {
        w.acc_us -= step_us;
        stepOneTick(storage, 0);
        step_us = world.tickPeriodUs(w.score);
        steps += 1;
    }
    out_steps.* = steps;
    return NS_OK;
}

// --- Per-player state ----------------------------------------------------

export fn ns_player_view_get(world_ptr: *const anyopaque, player: u8, out_view: *PlayerView) callconv(.c) Result {
    const storage = storageOfConst(world_ptr);
    if (player >= storage.player_count) return NS_ERR_INVALID_ARGUMENT;
    const w = &storage.world;
    out_view.* = .{
        .status = @intFromEnum(w.status),
        .dir = @intFromEnum(w.dir),
        .next_dir = @intFromEnum(w.next_dir),
        ._pad0 = 0,
        .score = w.score,
        .body_len = w.cells_len,
        ._pad1 = 0,
    };
    return NS_OK;
}

export fn ns_body_copy(world_ptr: *const anyopaque, player: u8, out_cells: ?[*]Cell, out_capacity: usize, out_required: *usize) callconv(.c) Result {
    const storage = storageOfConst(world_ptr);
    if (player >= storage.player_count) return NS_ERR_INVALID_ARGUMENT;
    const w = &storage.world;
    const required: usize = w.cells_len;
    out_required.* = required;
    if (out_cells == null or out_capacity == 0) return NS_OK;
    if (out_capacity < required) return NS_ERR_BUFFER_TOO_SMALL;

    const live = world.cells(w);
    var idx: usize = 0;
    while (idx < required) : (idx += 1) {
        out_cells.?[idx] = .{ .x = live[idx].x, .y = live[idx].y };
    }
    return NS_OK;
}

// --- Canonical serialization ---------------------------------------------

export fn ns_canon_len(world_ptr: *const anyopaque) callconv(.c) usize {
    const storage = storageOfConst(world_ptr);
    var players_buf: [1]canon.Player = undefined;
    const state = buildCanonState(&storage.world, &players_buf);
    return canon.encodedLen(state);
}

export fn ns_serialize(world_ptr: *const anyopaque, out_buf: [*]u8, out_capacity: usize, out_written: *usize) callconv(.c) Result {
    const storage = storageOfConst(world_ptr);
    var players_buf: [1]canon.Player = undefined;
    const state = buildCanonState(&storage.world, &players_buf);
    const need = canon.encodedLen(state);
    if (out_capacity < need) {
        out_written.* = need;
        return NS_ERR_BUFFER_TOO_SMALL;
    }
    const rec = canon.encode(state, out_buf[0..out_capacity]) catch unreachable; // capacity already checked
    out_written.* = rec.len;
    return NS_OK;
}

export fn ns_deserialize(world_ptr: *anyopaque, bytes: [*]const u8, len: usize) callconv(.c) Result {
    const storage = storageOf(world_ptr);
    const record = bytes[0..len];
    if (!canon.verify(record)) return NS_ERR_DECODE_FAILED;

    var players_buf: [1]canon.Player = undefined;
    const decoded = canon.decode(record, &players_buf, storage.world.cells_buf) catch return NS_ERR_DECODE_FAILED;
    // Board size is fixed at ns_world_init time (it sizes the cell buffer);
    // a record for a different board can't be rehydrated into this world.
    if (decoded.cols != storage.world.cols or decoded.rows != storage.world.rows) return NS_ERR_DECODE_FAILED;
    if (decoded.players.len != 1) return NS_ERR_DECODE_FAILED;

    const p = decoded.players[0];
    const w = &storage.world;
    w.wrap = decoded.wrap;
    w.tick = decoded.tick;
    // Built directly rather than via rng.Rng.init: init() asserts a
    // non-all-zero seed, a real-gameplay precondition that a deserialized
    // (if adversarially crafted) record must not be able to turn into a
    // panic across the ABI boundary.
    w.rng = .{ .s0 = decoded.rng_state[0], .s1 = decoded.rng_state[1], .s2 = decoded.rng_state[2], .s3 = decoded.rng_state[3] };
    // The accumulator is presentation-timing state, not part of the
    // canonical snapshot (docs/canonical-state.md) — a freshly loaded world
    // owes it nothing from the session that produced the record.
    w.acc_us = 0;
    w.food = decoded.food;
    w.status = p.status;
    w.dir = p.dir;
    w.next_dir = p.next_dir;
    w.score = p.score;
    w.cells_len = @intCast(p.cells.len);

    storage.event_head = 0;
    storage.event_len = 0;
    return NS_OK;
}

export fn ns_checksum(canon_bytes: [*]const u8, len: usize, out_checksum: *u64) callconv(.c) Result {
    if (len < canon.CHECKSUM_BYTES) return NS_ERR_INVALID_ARGUMENT;
    out_checksum.* = canon.checksum(canon_bytes[0..len]);
    return NS_OK;
}

// --- Ordered event drain --------------------------------------------------

export fn ns_event_count(world_ptr: *const anyopaque) callconv(.c) usize {
    const storage = storageOfConst(world_ptr);
    return storage.event_len;
}

export fn ns_event_drain(world_ptr: *anyopaque, out_events: ?[*]Event, out_capacity: usize, out_count: *usize) callconv(.c) Result {
    const storage = storageOf(world_ptr);
    const n = @min(storage.event_len, out_capacity);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const idx = (storage.event_head + i) % EVENT_QUEUE_CAP;
        out_events.?[i] = storage.events[idx];
    }
    storage.event_head = (storage.event_head + n) % EVENT_QUEUE_CAP;
    storage.event_len -= n;
    out_count.* = n;
    return NS_OK;
}

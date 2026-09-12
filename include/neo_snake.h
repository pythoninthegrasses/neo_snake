/*
 * neo_snake.h — the frozen C ABI contract for the neo_snake core simulation.
 *
 * This is the ONLY header any consumer (GDExtension shim, native binding,
 * conformance test) is allowed to depend on. `core/abi.zig` (TASK-024) is the
 * only Zig file that may export symbols, and every export it makes must have
 * a matching declaration here — nothing more, nothing less.
 *
 * Design is constrained by docs/abi-decisions.md's six frozen decisions and
 * docs/canonical-state.md's byte-exact wire format; see docs/abi-header.md
 * for the rationale behind choices this header makes that those documents
 * don't already settle (ns_step/ns_queue_dir/ns_pump's relationship, the
 * speed_source policy field, why no struct field here is a bare C enum).
 *
 * Caller-owned memory throughout (docs/abi-decisions.md freeze #2): every
 * buffer is supplied by the caller, nothing here allocates, and there is no
 * `ns_world_destroy` — a caller that owns `ns_world_size()` bytes outright
 * never needs a matching free call from this side of the boundary.
 */

#ifndef NEO_SNAKE_H
#define NEO_SNAKE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(__cplusplus)
#define NS_STATIC_ASSERT(cond, msg) static_assert(cond, msg)
#else
#define NS_STATIC_ASSERT(cond, msg) _Static_assert(cond, msg)
#endif

/* ---------------------------------------------------------------------- */
/* Versioning                                                              */
/* ---------------------------------------------------------------------- */

/* Bump on any change to this header's function signatures, calling
 * convention, or exported semantics (docs/abi-decisions.md freeze #6). Every
 * binding must be rebuilt and relinked when this changes. */
#define NS_ABI_VERSION 1u

/* Bump alongside canon.zig's NS_CANON_VERSION; mirrored here so a pure-C
 * caller can validate a canonical buffer's version field without
 * reimplementing the constant (docs/canonical-state.md). */
#define NS_CANON_VERSION 1u

/* Sentinel for "no food placed" in both the live world and the canonical
 * wire format (docs/canonical-state.md `food_x`/`food_y`). */
#define NS_NO_CELL_COORD 0xFFFFu

/* ---------------------------------------------------------------------- */
/* Result codes                                                           */
/*                                                                         */
/* Plain int32_t, not a C enum: a C enum's underlying integer width is     */
/* unspecified by the language, which is exactly the kind of ambiguity a   */
/* frozen cross-language (C / C++ / Zig / GDExtension) ABI cannot afford.  */
/* Every named constant below must be reachable from at least one real     */
/* call path (TASK-025 conformance requirement).                          */
/* ---------------------------------------------------------------------- */

typedef int32_t ns_result;

enum {
    NS_OK = 0,
    /* A parameter is out of range or malformed: an unknown player index, a
     * duplicate player entry in one ns_step() call, an unrecognized
     * ns_speed_source, a zero player_count, etc. */
    NS_ERR_INVALID_ARGUMENT = 1,
    /* An output buffer's capacity was smaller than the required length.
     * The call still reports the true required length so the caller can
     * retry (the two-call length-then-copy contract; see ns_body_copy). */
    NS_ERR_BUFFER_TOO_SMALL = 2,
    /* config->abi_version did not equal NS_ABI_VERSION. */
    NS_ERR_ABI_VERSION_MISMATCH = 3,
    /* ns_deserialize was given bytes that are not a valid, well-formed
     * canonical record (bad magic, truncated, checksum mismatch). */
    NS_ERR_DECODE_FAILED = 4,
};

/* ---------------------------------------------------------------------- */
/* Value spaces                                                           */
/*                                                                         */
/* Same reasoning as ns_result: fixed-width typedefs with named constants, */
/* never a bare C enum, since these values are stored in ABI-crossing      */
/* structs (docs/canonical-state.md's status/dir encodings are reused     */
/* verbatim here — see that document for why these specific numbers).      */
/* ---------------------------------------------------------------------- */

typedef uint8_t ns_status;
enum {
    NS_STATUS_MENU = 0,
    NS_STATUS_PLAYING = 1,
    NS_STATUS_PAUSED = 2,
    NS_STATUS_DEAD = 3,
};

typedef uint8_t ns_dir;
enum {
    NS_DIR_UP = 0,
    NS_DIR_DOWN = 1,
    NS_DIR_LEFT = 2,
    NS_DIR_RIGHT = 3,
};

/* Selects how ns_step/ns_pump derive the current tick period from a
 * player's score. Only one policy exists today — the frozen
 * TICK_PERIOD_US table (docs/abi-decisions.md freeze #5, core/world.zig
 * tickPeriodUs) — but this is a config field, not a compile-time constant,
 * so a future alternative (e.g. a fixed practice-mode speed) is additive
 * rather than an ABI break. See docs/abi-header.md. */
typedef uint8_t ns_speed_source;
enum {
    NS_SPEED_SOURCE_SCORE_TABLE = 0,
};

typedef uint8_t ns_event_kind;
enum {
    NS_EVENT_EAT = 0,
    NS_EVENT_DIE = 1,
    NS_EVENT_WIN = 2,
};

/* ---------------------------------------------------------------------- */
/* Opaque world handle                                                    */
/* ---------------------------------------------------------------------- */

/* Never defined — callers only ever hold a pointer. The caller allocates
 * ns_world_size(config) bytes aligned to ns_world_align() and passes that
 * storage to ns_world_init(); nothing on this side of the ABI allocates,
 * and there is deliberately no ns_world_destroy (adding one later is
 * additive; removing one later is not). */
typedef struct ns_world ns_world;

/* ---------------------------------------------------------------------- */
/* Config                                                                  */
/* ---------------------------------------------------------------------- */

typedef struct ns_config {
    uint16_t abi_version;    /* must equal NS_ABI_VERSION */
    uint16_t cols;           /* board width in cells */
    uint16_t rows;           /* board height in cells */
    uint8_t player_count;    /* >= 1 */
    uint8_t wrap;            /* 0 or 1 */
    /* xoshiro128** seed words s0..s3 (docs/rng.md); must not be all-zero. */
    uint32_t rng_seed[4];
    ns_speed_source speed_source;
    uint8_t _pad[3]; /* specified-zero; reserved for future config growth */
} ns_config;
NS_STATIC_ASSERT(sizeof(ns_config) == 28, "ns_config layout changed");

/* ---------------------------------------------------------------------- */
/* Per-tick input                                                         */
/* ---------------------------------------------------------------------- */

typedef struct ns_input {
    uint8_t player;
    ns_dir dir;
    uint8_t _pad[2]; /* specified-zero */
} ns_input;
NS_STATIC_ASSERT(sizeof(ns_input) == 4, "ns_input layout changed");

/* ---------------------------------------------------------------------- */
/* Per-player view                                                        */
/*                                                                         */
/* Doubles as the wire-exact mirror of docs/canonical-state.md's 16-byte   */
/* per-player fixed block (offsets 0-15 of a player record) — the two      */
/* never needed to diverge, so there is one type instead of two near-      */
/* identical ones. `cells` is deliberately not embedded here (variable     */
/* length); read it via ns_body_copy.                                     */
/* ---------------------------------------------------------------------- */

typedef struct ns_player_view {
    ns_status status;
    ns_dir dir;
    ns_dir next_dir;
    uint8_t _pad0; /* specified-zero; pads score to a 4-byte offset */
    uint32_t score;
    uint32_t body_len; /* cell count; read cells via ns_body_copy */
    uint32_t _pad1;    /* specified-zero; canonical-state.md's reserved
                        * fourth fixed field */
} ns_player_view;
NS_STATIC_ASSERT(sizeof(ns_player_view) == 16, "must match docs/canonical-state.md's per-player fixed block");

typedef struct ns_cell {
    uint16_t x;
    uint16_t y;
} ns_cell;
NS_STATIC_ASSERT(sizeof(ns_cell) == 4, "ns_cell layout changed");

/* ---------------------------------------------------------------------- */
/* Canonical wire-format header                                           */
/*                                                                         */
/* Wire-exact mirror of docs/canonical-state.md's 44-byte header, so a     */
/* conformance test (TASK-025) or any low-level binding can @sizeOf/       */
/* @offsetOf against a real type declared in this header rather than a    */
/* hand-copied set of magic numbers.                                      */
/* ---------------------------------------------------------------------- */

typedef struct ns_canon_header {
    uint8_t magic[8]; /* ASCII "NEOSNAKE", no NUL terminator */
    uint16_t canon_version;
    uint16_t cols;
    uint16_t rows;
    uint16_t flags; /* bit 0 = wrap; bits 1-15 reserved, zero */
    uint8_t player_count;
    uint8_t _pad0[3]; /* specified-zero; pads tick to a 4-byte offset */
    uint32_t tick;
    uint32_t rng_state[4]; /* xoshiro128** s0..s3 */
    uint16_t food_x;       /* NS_NO_CELL_COORD if no food is placed */
    uint16_t food_y;
} ns_canon_header;
NS_STATIC_ASSERT(sizeof(ns_canon_header) == 44, "must match docs/canonical-state.md's header layout");

/* ---------------------------------------------------------------------- */
/* Ordered events                                                         */
/*                                                                         */
/* A consumer (e.g. audio, TASK-041) drains discrete, ordered events —    */
/* "player 0 ate at tick 42" — instead of diffing two full snapshots to    */
/* guess how many eats happened between them. Draining removes the        */
/* drained events; anything left over after a too-small out_capacity      */
/* stays queued for a subsequent drain call.                              */
/* ---------------------------------------------------------------------- */

typedef struct ns_event {
    uint32_t tick;
    uint8_t player;
    ns_event_kind kind;
    uint8_t _pad[2]; /* specified-zero */
} ns_event;
NS_STATIC_ASSERT(sizeof(ns_event) == 8, "ns_event layout changed");

/* ---------------------------------------------------------------------- */
/* World lifecycle                                                        */
/* ---------------------------------------------------------------------- */

/* Bytes the caller must allocate for one world, aligned to
 * ns_world_align(). Depends on config (cols * rows * player_count sizes
 * the per-player cell storage), so call it before allocating. */
size_t ns_world_size(const ns_config *config);

/* Required alignment for the storage passed to ns_world_init. */
size_t ns_world_align(void);

/* Initializes caller-supplied storage (ns_world_size(config) bytes,
 * aligned to ns_world_align()) as a fresh world. Returns
 * NS_ERR_ABI_VERSION_MISMATCH if config->abi_version != NS_ABI_VERSION,
 * NS_ERR_INVALID_ARGUMENT for any other malformed config (player_count ==
 * 0, an unrecognized speed_source, an all-zero rng_seed). */
ns_result ns_world_init(ns_world *world, const ns_config *config);

/* Resets an already-initialized world to a fresh game: body, score, tick,
 * and food are reset; the RNG stream is NOT reseeded (it continues from
 * its current state) — this mirrors core/world.zig's reset() exactly, not
 * a re-seed. To start a genuinely new stream, call ns_world_init again. */
ns_result ns_world_reset(ns_world *world);

/* ---------------------------------------------------------------------- */
/* Input and stepping                                                     */
/*                                                                         */
/* ns_step is the lockstep primitive (frozen name; backlog/decisions/      */
/* decision-020) that a future netcode layer (TASK-053) drives directly,   */
/* one call per confirmed simulation tick, with no accumulator involved.   */
/* ns_queue_dir and ns_pump are local-play conveniences layered on top —   */
/* see docs/abi-header.md for exactly how the three relate, in particular  */
/* why starting a game from the menu does not itself consume a tick.      */
/* ---------------------------------------------------------------------- */

/* Updates `player`'s queued direction (reversal-rejected, matching the
 * reference oracle's queueDir choke point) without advancing the
 * simulation. Also handles the reference behavior's automatic
 * menu/dead -> playing transition on the first legal direction. Never
 * performs a tick advance, regardless of the resulting status — call
 * ns_pump or ns_step for that. */
ns_result ns_queue_dir(ns_world *world, uint8_t player, ns_dir dir);

/* Applies `inputs` (each player index must be < config.player_count, no
 * duplicate player entries in one call) exactly as ns_queue_dir would, in
 * ascending player-index order, then — only if the world's simulation
 * status was ALREADY playing before this call's inputs were applied —
 * advances exactly one tick for every player, in ascending player-index
 * order for any shared-resource draw (docs/abi-decisions.md freeze #1).
 * If the world was not already playing (e.g. this call is what starts it
 * from the menu), no tick is advanced this call, matching ns_queue_dir's
 * own no-advance behavior. A player dying or winning this tick is a
 * normal outcome, not an error: it is reported via ns_player_view_get and
 * the event drain, never via ns_result. `inputs` may be empty. */
ns_result ns_step(ns_world *world, const ns_input *inputs, size_t input_count);

/* Fixed-timestep convenience for local play: clamps dt_us and advances at
 * most a bounded number of ticks (core/world.zig's pump()), calling
 * ns_step with an empty input list for each — any direction changes must
 * already have been queued via ns_queue_dir beforehand. No-ops (returns 0
 * steps) if the world is not currently playing. *out_steps receives the
 * number of ticks actually advanced. */
ns_result ns_pump(ns_world *world, uint32_t dt_us, uint32_t *out_steps);

/* ---------------------------------------------------------------------- */
/* Per-player state                                                        */
/* ---------------------------------------------------------------------- */

/* Fills *out_view for `player`. Present and exercised even when
 * config.player_count == 1. */
ns_result ns_player_view_get(const ns_world *world, uint8_t player, ns_player_view *out_view);

/* Two-call length-then-copy contract: pass out_cells == NULL (or
 * out_capacity == 0) to learn the required length via *out_required
 * without copying. Pass a real buffer of at least that length to copy
 * `player`'s body, head-first, into out_cells. Returns
 * NS_ERR_BUFFER_TOO_SMALL (still setting *out_required) if out_capacity is
 * smaller than required. */
ns_result ns_body_copy(const ns_world *world, uint8_t player, ns_cell *out_cells, size_t out_capacity, size_t *out_required);

/* ---------------------------------------------------------------------- */
/* Canonical serialization (docs/canonical-state.md)                       */
/* ---------------------------------------------------------------------- */

/* Exact byte length ns_serialize will write for this world's current
 * state (header + all player records + checksum trailer). */
size_t ns_canon_len(const ns_world *world);

/* Encodes the world's current state as a canonical record. Two-call
 * contract identical in spirit to ns_body_copy: call ns_canon_len first,
 * or retry with a larger buffer on NS_ERR_BUFFER_TOO_SMALL (*out_written
 * is left at the required length in that case). */
ns_result ns_serialize(const ns_world *world, uint8_t *out_buf, size_t out_capacity, size_t *out_written);

/* Rehydrates `world` from a canonical record produced by ns_serialize
 * (from any conforming implementation — JS oracle, this core, or a
 * future host). Returns NS_ERR_DECODE_FAILED on a malformed record (bad
 * magic, wrong canon_version, truncated, checksum mismatch). */
ns_result ns_deserialize(ns_world *world, const uint8_t *bytes, size_t len);

/* Computes the checksum trailer's algorithm (docs/canonical-state.md)
 * over an already-encoded canonical buffer (header + player records,
 * checksum trailer excluded) — operates on bytes, not a live world, so it
 * can validate a record received from elsewhere without decoding it. */
ns_result ns_checksum(const uint8_t *canon_bytes, size_t len, uint64_t *out_checksum);

/* ---------------------------------------------------------------------- */
/* Ordered event drain                                                    */
/* ---------------------------------------------------------------------- */

/* Number of events currently queued, without draining them. */
size_t ns_event_count(const ns_world *world);

/* Drains up to out_capacity queued events, in tick order, into
 * out_events; *out_count receives how many were actually written. Any
 * events beyond out_capacity remain queued for a subsequent call —
 * nothing is dropped by a too-small buffer. */
ns_result ns_event_drain(ns_world *world, ns_event *out_events, size_t out_capacity, size_t *out_count);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* NEO_SNAKE_H */

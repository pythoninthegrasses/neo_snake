/*
 * Compile-only smoke check for include/neo_snake.h (TASK-023). This proves
 * the header is self-consistent and that every declared type/function is
 * genuinely usable — not just that it exists — before core/abi.zig (TASK-024)
 * provides a real implementation to link against.
 *
 * Deliberately compiled to an object file, never linked or run: with no
 * implementation behind these symbols yet, referencing them is only valid
 * as long as nothing tries to resolve them. `zig cc -c` (see
 * taskfiles/core.yml's abi-header-check task) stops after this file becomes
 * an object file, which is exactly the point at which an unresolved extern
 * reference is still legal C.
 */

#include "neo_snake.h"

/* AC #1: ns_player_view_get exists and is exercised even when
 * player_count == 1 — a single-player config is exactly the case
 * multiplayer-shaped structs must not special-case away. */
static void exercise_single_player(void) {
    ns_config config = {0};
    config.abi_version = NS_ABI_VERSION;
    config.cols = 20;
    config.rows = 20;
    config.player_count = 1;
    config.wrap = 0;
    config.rng_seed[0] = 1;
    config.rng_seed[1] = 2;
    config.rng_seed[2] = 3;
    config.rng_seed[3] = 4;
    config.speed_source = NS_SPEED_SOURCE_SCORE_TABLE;

    size_t world_bytes = ns_world_size(&config);
    size_t world_align = ns_world_align();
    (void)world_bytes;
    (void)world_align;

    /* Never actually sized/aligned per ns_world_size/ns_world_align (no
     * implementation exists yet to allocate correctly for) — a fixed
     * storage buffer is enough for a compile-only reference. */
    static unsigned char storage[1];
    ns_world *world = (ns_world *)(void *)storage;
    ns_result r = ns_world_init(world, &config);

    ns_player_view view = {0};
    r = ns_player_view_get(world, 0, &view);

    ns_cell cells[8];
    size_t required = 0;
    r = ns_body_copy(world, 0, cells, 8, &required);
    r = ns_body_copy(world, 0, NULL, 0, &required);

    ns_input input = {0, NS_DIR_UP, {0, 0}};
    r = ns_step(world, &input, 1);
    r = ns_queue_dir(world, 0, NS_DIR_DOWN);

    uint32_t steps = 0;
    r = ns_pump(world, 16000u, &steps);
    r = ns_world_reset(world);

    uint8_t canon_buf[256];
    size_t written = 0;
    r = ns_serialize(world, canon_buf, sizeof(canon_buf), &written);
    r = ns_deserialize(world, canon_buf, written);

    uint64_t checksum = 0;
    r = ns_checksum(canon_buf, written, &checksum);

    ns_event events[4];
    size_t event_count = 0;
    r = ns_event_drain(world, events, 4, &event_count);
    size_t queued = ns_event_count(world);

    (void)r;
    (void)queued;
    (void)checksum;
}

/* Never invoked (there is nothing to run this against yet) — its only job
 * is to force the compiler to type-check every call above. */
void (*ns_abi_header_smoke_entry)(void) = exercise_single_player;

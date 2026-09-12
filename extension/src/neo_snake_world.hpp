#pragma once

#include <cstdint>
#include <vector>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

#include "neo_snake.h"

namespace godot {

// Thin GDExtension wrapper around include/neo_snake.h's C ABI (TASK-026).
// Every method here forwards to exactly one ns_* call; no simulation logic
// is reimplemented -- core/world.zig (via core/abi.zig) remains the only
// place game rules live.
class NeoSnakeWorld : public RefCounted {
	GDCLASS(NeoSnakeWorld, RefCounted)

protected:
	static void _bind_methods();

public:
	NeoSnakeWorld() = default;
	~NeoSnakeWorld() override = default;

	int init(int cols, int rows, int player_count, bool wrap, const PackedInt32Array &rng_seed, int speed_source);
	int reset();
	int queue_dir(int player, int dir);
	int step(const Array &inputs);
	Dictionary pump(int dt_us);
	Dictionary player_view_get(int player);
	Dictionary body_copy(int player);
	int canon_len();
	Dictionary serialize();
	int deserialize(const PackedByteArray &bytes);
	static Dictionary checksum(const PackedByteArray &bytes);
	int event_count();
	Dictionary event_drain(int capacity);

private:
	// storage_ is over-allocated by ns_world_align() - 1 bytes so an aligned
	// ns_world* can be carved out of it manually; std::vector's own default
	// alignment is not guaranteed to satisfy whatever ns_world_align()
	// reports (docs/build-layout.md), so this cannot be skipped.
	std::vector<uint8_t> storage_;
	ns_world *world_ = nullptr;

	bool is_ready() const { return world_ != nullptr; }
};

} // namespace godot

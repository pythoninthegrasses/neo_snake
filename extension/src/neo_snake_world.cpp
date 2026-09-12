#include "neo_snake_world.hpp"

#include <cstring>

#include <godot_cpp/core/class_db.hpp>

namespace godot {

namespace {

// Carves an ns_world_align()-aligned pointer out of `buf`, which must be at
// least ns_world_size(config) + ns_world_align() - 1 bytes long. Assumes
// ns_world_align() returns a power of two, matching every real alignment
// value the C ABI can report.
ns_world *align_world_ptr(std::vector<uint8_t> &buf) {
	size_t align = ns_world_align();
	uintptr_t base = reinterpret_cast<uintptr_t>(buf.data());
	uintptr_t aligned = (base + align - 1) & ~(align - 1);
	return reinterpret_cast<ns_world *>(aligned);
}

} // namespace

void NeoSnakeWorld::_bind_methods() {
	ClassDB::bind_method(D_METHOD("init", "cols", "rows", "player_count", "wrap", "rng_seed", "speed_source"), &NeoSnakeWorld::init);
	ClassDB::bind_method(D_METHOD("reset"), &NeoSnakeWorld::reset);
	ClassDB::bind_method(D_METHOD("queue_dir", "player", "dir"), &NeoSnakeWorld::queue_dir);
	ClassDB::bind_method(D_METHOD("step", "inputs"), &NeoSnakeWorld::step);
	ClassDB::bind_method(D_METHOD("pump", "dt_us"), &NeoSnakeWorld::pump);
	ClassDB::bind_method(D_METHOD("player_view_get", "player"), &NeoSnakeWorld::player_view_get);
	ClassDB::bind_method(D_METHOD("body_copy", "player"), &NeoSnakeWorld::body_copy);
	ClassDB::bind_method(D_METHOD("canon_len"), &NeoSnakeWorld::canon_len);
	ClassDB::bind_method(D_METHOD("serialize"), &NeoSnakeWorld::serialize);
	ClassDB::bind_method(D_METHOD("deserialize", "bytes"), &NeoSnakeWorld::deserialize);
	ClassDB::bind_static_method(get_class_static(), D_METHOD("checksum", "bytes"), &NeoSnakeWorld::checksum);
	ClassDB::bind_method(D_METHOD("event_count"), &NeoSnakeWorld::event_count);
	ClassDB::bind_method(D_METHOD("event_drain", "capacity"), &NeoSnakeWorld::event_drain);

	// BIND_CONSTANT, not BIND_ENUM_CONSTANT: these come from neo_snake.h's
	// anonymous C enums, which have no registered Variant enum type for
	// BIND_ENUM_CONSTANT's GetTypeInfo lookup to resolve.
	BIND_CONSTANT(NS_OK);
	BIND_CONSTANT(NS_ERR_INVALID_ARGUMENT);
	BIND_CONSTANT(NS_ERR_BUFFER_TOO_SMALL);
	BIND_CONSTANT(NS_ERR_ABI_VERSION_MISMATCH);
	BIND_CONSTANT(NS_ERR_DECODE_FAILED);

	BIND_CONSTANT(NS_STATUS_MENU);
	BIND_CONSTANT(NS_STATUS_PLAYING);
	BIND_CONSTANT(NS_STATUS_PAUSED);
	BIND_CONSTANT(NS_STATUS_DEAD);

	BIND_CONSTANT(NS_DIR_UP);
	BIND_CONSTANT(NS_DIR_DOWN);
	BIND_CONSTANT(NS_DIR_LEFT);
	BIND_CONSTANT(NS_DIR_RIGHT);

	BIND_CONSTANT(NS_SPEED_SOURCE_SCORE_TABLE);

	BIND_CONSTANT(NS_EVENT_EAT);
	BIND_CONSTANT(NS_EVENT_DIE);
	BIND_CONSTANT(NS_EVENT_WIN);
}

int NeoSnakeWorld::init(int cols, int rows, int player_count, bool wrap, const PackedInt32Array &rng_seed, int speed_source) {
	if (rng_seed.size() != 4) {
		return NS_ERR_INVALID_ARGUMENT;
	}

	ns_config config{};
	config.abi_version = static_cast<uint16_t>(NS_ABI_VERSION);
	config.cols = static_cast<uint16_t>(cols);
	config.rows = static_cast<uint16_t>(rows);
	config.player_count = static_cast<uint8_t>(player_count);
	config.wrap = wrap ? 1 : 0;
	for (int i = 0; i < 4; i++) {
		config.rng_seed[i] = static_cast<uint32_t>(rng_seed[i]);
	}
	config.speed_source = static_cast<ns_speed_source>(speed_source);

	size_t align = ns_world_align();
	size_t size = ns_world_size(&config);
	storage_.assign(size + align - 1, 0);
	world_ = nullptr;

	ns_world *candidate = align_world_ptr(storage_);
	ns_result result = ns_world_init(candidate, &config);
	if (result == NS_OK) {
		world_ = candidate;
	}
	return result;
}

int NeoSnakeWorld::reset() {
	if (!is_ready()) {
		return NS_ERR_INVALID_ARGUMENT;
	}
	return ns_world_reset(world_);
}

int NeoSnakeWorld::queue_dir(int player, int dir) {
	if (!is_ready()) {
		return NS_ERR_INVALID_ARGUMENT;
	}
	return ns_queue_dir(world_, static_cast<uint8_t>(player), static_cast<ns_dir>(dir));
}

int NeoSnakeWorld::step(const Array &inputs) {
	if (!is_ready()) {
		return NS_ERR_INVALID_ARGUMENT;
	}

	std::vector<ns_input> ns_inputs;
	ns_inputs.reserve(inputs.size());
	for (int i = 0; i < inputs.size(); i++) {
		Dictionary entry = inputs[i];
		ns_input input{};
		input.player = static_cast<uint8_t>(static_cast<int>(entry["player"]));
		input.dir = static_cast<ns_dir>(static_cast<int>(entry["dir"]));
		ns_inputs.push_back(input);
	}

	return ns_step(world_, ns_inputs.data(), ns_inputs.size());
}

Dictionary NeoSnakeWorld::pump(int dt_us) {
	Dictionary out;
	if (!is_ready()) {
		out["result"] = NS_ERR_INVALID_ARGUMENT;
		out["steps"] = 0;
		return out;
	}

	uint32_t steps = 0;
	ns_result result = ns_pump(world_, static_cast<uint32_t>(dt_us), &steps);
	out["result"] = result;
	out["steps"] = static_cast<int>(steps);
	return out;
}

Dictionary NeoSnakeWorld::player_view_get(int player) {
	Dictionary out;
	if (!is_ready()) {
		out["result"] = NS_ERR_INVALID_ARGUMENT;
		return out;
	}

	ns_player_view view{};
	ns_result result = ns_player_view_get(world_, static_cast<uint8_t>(player), &view);
	out["result"] = result;
	if (result == NS_OK) {
		out["status"] = view.status;
		out["dir"] = view.dir;
		out["next_dir"] = view.next_dir;
		out["score"] = static_cast<int>(view.score);
		out["body_len"] = static_cast<int>(view.body_len);
	}
	return out;
}

Dictionary NeoSnakeWorld::body_copy(int player) {
	Dictionary out;
	if (!is_ready()) {
		out["result"] = NS_ERR_INVALID_ARGUMENT;
		return out;
	}

	size_t required = 0;
	ns_result result = ns_body_copy(world_, static_cast<uint8_t>(player), nullptr, 0, &required);
	if (result != NS_OK && result != NS_ERR_BUFFER_TOO_SMALL) {
		out["result"] = result;
		return out;
	}

	std::vector<ns_cell> cells(required);
	size_t actual_required = 0;
	result = ns_body_copy(world_, static_cast<uint8_t>(player), cells.data(), cells.size(), &actual_required);
	out["result"] = result;
	if (result == NS_OK) {
		PackedVector2Array out_cells;
		out_cells.resize(static_cast<int>(cells.size()));
		for (size_t i = 0; i < cells.size(); i++) {
			out_cells[static_cast<int>(i)] = Vector2(cells[i].x, cells[i].y);
		}
		out["cells"] = out_cells;
	}
	return out;
}

int NeoSnakeWorld::canon_len() {
	if (!is_ready()) {
		return 0;
	}
	return static_cast<int>(ns_canon_len(world_));
}

Dictionary NeoSnakeWorld::serialize() {
	Dictionary out;
	if (!is_ready()) {
		out["result"] = NS_ERR_INVALID_ARGUMENT;
		return out;
	}

	size_t len = ns_canon_len(world_);
	std::vector<uint8_t> buf(len);
	size_t written = 0;
	ns_result result = ns_serialize(world_, buf.data(), buf.size(), &written);
	out["result"] = result;
	if (result == NS_OK) {
		PackedByteArray out_bytes;
		out_bytes.resize(static_cast<int>(written));
		std::memcpy(out_bytes.ptrw(), buf.data(), written);
		out["bytes"] = out_bytes;
	}
	return out;
}

int NeoSnakeWorld::deserialize(const PackedByteArray &bytes) {
	if (!is_ready()) {
		return NS_ERR_INVALID_ARGUMENT;
	}
	return ns_deserialize(world_, bytes.ptr(), bytes.size());
}

Dictionary NeoSnakeWorld::checksum(const PackedByteArray &bytes) {
	Dictionary out;
	uint64_t value = 0;
	ns_result result = ns_checksum(bytes.ptr(), bytes.size(), &value);
	out["result"] = result;
	if (result == NS_OK) {
		out["checksum"] = static_cast<int64_t>(value);
	}
	return out;
}

int NeoSnakeWorld::event_count() {
	if (!is_ready()) {
		return 0;
	}
	return static_cast<int>(ns_event_count(world_));
}

Dictionary NeoSnakeWorld::event_drain(int capacity) {
	Dictionary out;
	if (!is_ready()) {
		out["result"] = NS_ERR_INVALID_ARGUMENT;
		return out;
	}

	std::vector<ns_event> events(capacity);
	size_t count = 0;
	ns_result result = ns_event_drain(world_, events.data(), events.size(), &count);
	out["result"] = result;
	if (result == NS_OK) {
		Array out_events;
		for (size_t i = 0; i < count; i++) {
			Dictionary entry;
			entry["tick"] = static_cast<int>(events[i].tick);
			entry["player"] = events[i].player;
			entry["kind"] = events[i].kind;
			out_events.push_back(entry);
		}
		out["events"] = out_events;
		out["count"] = static_cast<int>(count);
	}
	return out;
}

} // namespace godot

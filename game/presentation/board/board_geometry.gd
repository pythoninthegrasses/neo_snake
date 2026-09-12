class_name BoardGeometry
extends RefCounted

## Pure static math with no Node/viewport dependency, so every number here
## is directly pinned by gdUnit4 tests (TASK-032 AC#1) without instantiating
## a scene. All actual draw_*() calls live in board_view.gd instead.

## reference/snake.html's render() back-to-front layering (~snake.html:433-531),
## operationalized as data so board_view.gd's _draw() order can be pinned by
## a test instead of relying on code review alone (AC#4).
const DRAW_LAYER_ORDER := [
	"background", "checkerboard", "grid", "food", "snake", "eyes",
	"particles", "flash", "pause_vignette",
]

## docs/canonical-state.md's status encoding -- reused here (rather than
## re-deriving a NeoSnakeWorld-internal constant board_view.gd isn't allowed
## to reference directly, per game/simulation/world.gd's own header comment)
## since it is already a frozen, documented wire value, not an implementation
## detail.
const STATUS_MENU := 0
const STATUS_PLAYING := 1
const STATUS_PAUSED := 2
const STATUS_DEAD := 3

## docs/canonical-state.md: 0xFFFF marks "no food placed" for both food_x
## and food_y.
const NO_CELL_COORD := 0xFFFF

## Head-first weight: 1.0 at the head (i=0), 0.0 at the tail -- matches
## snake.html's `k = 1 - i / Math.max(1, n - 1)` (snake.html:477).
static func segment_weight(i: int, body_len: int) -> float:
	return 1.0 - float(i) / float(max(1, body_len - 1))

## Matches snake.html's `74 + k*30 | 0` truncate-toward-zero channel math
## (snake.html:481) -- Color8(int(...)), not roundi, per TASK-032 AC#3.
static func segment_color(k: float, base_rgb: Array, delta_rgb: Array) -> Color:
	return Color8(
		int(base_rgb[0] + k * delta_rgb[0]),
		int(base_rgb[1] + k * delta_rgb[1]),
		int(base_rgb[2] + k * delta_rgb[2]),
	)

static func segment_pad(cell: float, k: float, base_fraction: float, amplitude_fraction: float) -> float:
	return cell * (base_fraction + (1.0 - k) * amplitude_fraction)

## snake.html:460-461's `t = performance.now()/pulse_period; pulse = 0.5 +
## 0.5*sin(t)` -- pulse_period_ms is a divisor, not a full 2*PI cycle length,
## kept literal to match the oracle's own formula exactly.
static func food_pulse(elapsed_ms: float, pulse_period_ms: float) -> float:
	return 0.5 + 0.5 * sin(elapsed_ms / pulse_period_ms)

static func food_pad(cell: float, pulse: float, base_fraction: float, amplitude_fraction: float) -> float:
	return cell * (base_fraction - pulse * amplitude_fraction)

static func corner_radius(cell: float, fraction: float) -> float:
	return cell * fraction

## Two eye-center offsets from the head's own center, matching snake.html's
## `perp = {-d.y, d.x}` sideways offset plus a forward offset along `d`
## (snake.html:497-505). Returned in pixels (already multiplied by cell).
static func eye_offsets(dir_x: int, dir_y: int, side_fraction: float, forward_fraction: float, cell: float) -> Array:
	var perp_x := -dir_y
	var perp_y := dir_x
	var side := side_fraction * cell
	var fwd := forward_fraction * cell
	return [
		Vector2(perp_x * side + dir_x * fwd, perp_y * side + dir_y * fwd),
		Vector2(-perp_x * side + dir_x * fwd, -perp_y * side + dir_y * fwd),
	]

static func eye_radius(cell: float, fraction: float, min_px: float) -> float:
	return max(min_px, cell * fraction)

## Interior grid-line offsets for a `count`-cell axis, matching snake.html's
## `Math.round(i * cell) + 0.5` (snake.html:453-454) so 1px lines land on a
## crisp pixel boundary.
static func grid_line_offsets(count: int, cell: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in range(1, count):
		out.append(roundf(i * cell) + 0.5)
	return out

## Bakes the checkerboard into one Image (board_view.gd turns it into a
## single ImageTexture) instead of the oracle's 288 individual fillRect
## calls (snake.html:439-446) -- TASK-032 AC#2. FORMAT_RGBA8 quantizes alpha
## to 8 bits (decision-023), unlike the float Color used for grid lines.
static func build_checkerboard_image(cols: int, rows: int, tile_color: Color, alpha: float) -> Image:
	var image := Image.create(cols, rows, false, Image.FORMAT_RGBA8)
	var painted := Color(tile_color.r, tile_color.g, tile_color.b, alpha)
	var transparent := Color(0.0, 0.0, 0.0, 0.0)
	for y in rows:
		for x in cols:
			image.set_pixel(x, y, painted if ((x + y) & 1) == 0 else transparent)
	return image

## Decodes the fields of docs/canonical-state.md's 44-byte header that
## board_view.gd needs and has no other accessor for (cols/rows/food
## position aren't exposed by SimulationWorld.player_view_get or
## .body_copy). PackedByteArray.decode_u16 is little-endian, matching the
## canonical format's own endianness.
static func decode_canon_header(bytes: PackedByteArray) -> Dictionary:
	return {
		"cols": bytes.decode_u16(10),
		"rows": bytes.decode_u16(12),
		"food_x": bytes.decode_u16(40),
		"food_y": bytes.decode_u16(42),
	}

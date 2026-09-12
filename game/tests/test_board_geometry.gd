extends GdUnitTestSuite

## TASK-032 AC#1: board_geometry.gd is pure static math with no Node/
## viewport dependency, so every number here is pinned directly rather than
## rendered and eyeballed.

func test_segment_weight_is_1_at_head_and_0_at_tail() -> void:
	assert_float(BoardGeometry.segment_weight(0, 3)).is_equal_approx(1.0, 0.0001)
	assert_float(BoardGeometry.segment_weight(1, 3)).is_equal_approx(0.5, 0.0001)
	assert_float(BoardGeometry.segment_weight(2, 3)).is_equal_approx(0.0, 0.0001)
	# A single-segment snake must not divide by zero (max(1, n-1)).
	assert_float(BoardGeometry.segment_weight(0, 1)).is_equal_approx(1.0, 0.0001)


## Matches snake.html's `74 + k*30 | 0` truncate-toward-zero channel math
## (snake.html:481) via Color8(int(...)), not roundi.
func test_segment_color_matches_snake_htmls_truncating_channel_math() -> void:
	var base := [74, 222, 128]
	var delta := [30, -20, 30]
	assert_object(BoardGeometry.segment_color(0.0, base, delta)).is_equal(Color8(74, 222, 128))
	assert_object(BoardGeometry.segment_color(0.5, base, delta)).is_equal(Color8(89, 212, 143))
	assert_object(BoardGeometry.segment_color(1.0, base, delta)).is_equal(Color8(104, 202, 158))


func test_segment_pad() -> void:
	assert_float(BoardGeometry.segment_pad(20.0, 0.5, 0.12, 0.16)).is_equal_approx(4.0, 0.0001)


func test_food_pulse_matches_snake_htmls_sin_formula() -> void:
	assert_float(BoardGeometry.food_pulse(0.0, 260.0)).is_equal_approx(0.5, 0.0001)
	assert_float(BoardGeometry.food_pulse(260.0 * PI / 2.0, 260.0)).is_equal_approx(1.0, 0.0001)


func test_food_pad() -> void:
	assert_float(BoardGeometry.food_pad(20.0, 0.5, 0.2, 0.04)).is_equal_approx(3.6, 0.0001)


func test_corner_radius() -> void:
	assert_float(BoardGeometry.corner_radius(20.0, 0.3)).is_equal_approx(6.0, 0.0001)


## perp = {-d.y, d.x} (snake.html:497) -- pinned for all four directions.
func test_eye_offsets_match_snake_htmls_perpendicular_plus_forward_layout() -> void:
	var right := BoardGeometry.eye_offsets(1, 0, 0.19, 0.16, 20.0)
	assert_vector(right[0]).is_equal_approx(Vector2(3.2, 3.8), Vector2(0.0001, 0.0001))
	assert_vector(right[1]).is_equal_approx(Vector2(3.2, -3.8), Vector2(0.0001, 0.0001))

	var up := BoardGeometry.eye_offsets(0, -1, 0.19, 0.16, 20.0)
	assert_vector(up[0]).is_equal_approx(Vector2(3.8, -3.2), Vector2(0.0001, 0.0001))
	assert_vector(up[1]).is_equal_approx(Vector2(-3.8, -3.2), Vector2(0.0001, 0.0001))


func test_eye_radius_respects_the_minimum() -> void:
	assert_float(BoardGeometry.eye_radius(20.0, 0.072, 1.4)).is_equal_approx(1.44, 0.0001)
	assert_float(BoardGeometry.eye_radius(5.0, 0.072, 1.4)).is_equal_approx(1.4, 0.0001)


func test_grid_line_offsets_land_on_a_crisp_pixel_boundary() -> void:
	var offsets := BoardGeometry.grid_line_offsets(3, 10.0)
	assert_int(offsets.size()).is_equal(2)
	assert_float(offsets[0]).is_equal_approx(10.5, 0.0001)
	assert_float(offsets[1]).is_equal_approx(20.5, 0.0001)


## FORMAT_RGBA8 quantizes each channel to 8 bits, so a 0.5 alpha round-trips
## as 127/255 ~= 0.498 -- approximate rather than exact equality on alpha.
func test_checkerboard_image_paints_only_even_parity_cells() -> void:
	var image := BoardGeometry.build_checkerboard_image(2, 2, Color(1.0, 1.0, 1.0), 0.5)
	var painted_a := image.get_pixel(0, 0)
	assert_float(painted_a.r).is_equal_approx(1.0, 0.004)
	assert_float(painted_a.g).is_equal_approx(1.0, 0.004)
	assert_float(painted_a.b).is_equal_approx(1.0, 0.004)
	assert_float(painted_a.a).is_equal_approx(0.5, 0.004)
	assert_object(image.get_pixel(1, 0)).is_equal(Color(0.0, 0.0, 0.0, 0.0))
	assert_object(image.get_pixel(0, 1)).is_equal(Color(0.0, 0.0, 0.0, 0.0))
	var painted_b := image.get_pixel(1, 1)
	assert_float(painted_b.r).is_equal_approx(1.0, 0.004)
	assert_float(painted_b.g).is_equal_approx(1.0, 0.004)
	assert_float(painted_b.b).is_equal_approx(1.0, 0.004)
	assert_float(painted_b.a).is_equal_approx(0.5, 0.004)


## Hand-built header bytes (docs/canonical-state.md's 44-byte layout) rather
## than a live SimulationWorld -- decode_canon_header's own arithmetic is
## what's under test here, independent of the RNG's food placement.
func test_decode_canon_header_reads_cols_rows_and_food_position() -> void:
	var bytes := PackedByteArray()
	bytes.resize(44)
	bytes.encode_u16(10, 24)
	bytes.encode_u16(12, 24)
	bytes.encode_u16(40, 5)
	bytes.encode_u16(42, 7)
	var header := BoardGeometry.decode_canon_header(bytes)
	assert_int(header.cols).is_equal(24)
	assert_int(header.rows).is_equal(24)
	assert_int(header.food_x).is_equal(5)
	assert_int(header.food_y).is_equal(7)


func test_decode_canon_header_passes_through_no_cell_coord_unchanged() -> void:
	var bytes := PackedByteArray()
	bytes.resize(44)
	bytes.encode_u16(40, 0xFFFF)
	bytes.encode_u16(42, 0xFFFF)
	var header := BoardGeometry.decode_canon_header(bytes)
	assert_int(header.food_x).is_equal(BoardGeometry.NO_CELL_COORD)
	assert_int(header.food_y).is_equal(BoardGeometry.NO_CELL_COORD)


## Operationalizes AC#4 (statement order matches snake.html's back-to-front
## layering) as a pinned data check rather than leaving it to code review.
func test_draw_layer_order_matches_snake_htmls_back_to_front_layering() -> void:
	assert_array(BoardGeometry.DRAW_LAYER_ORDER).is_equal([
		"background", "checkerboard", "grid", "food", "snake", "eyes",
		"particles", "flash", "pause_vignette",
	])

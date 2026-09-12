class_name BoardView
extends Control

## Renders one player's board in a single _draw() call, statement order
## matching reference/snake.html's render() back-to-front layering exactly
## (BoardGeometry.DRAW_LAYER_ORDER, snake.html:433-531 -- TASK-032 AC#4).
## All geometry/color math is pure and lives in board_geometry.gd so it is
## testable without a viewport (AC#1); this file is the only place that
## issues actual draw_*() calls.
##
## No canvas shadow/glow blur (ctx.shadowBlur in the oracle, e.g.
## snake.html:465/485): Godot's 2D CanvasItem has no equivalent without a
## custom shader/backbuffer pass. See backlog/decisions/decision-022 -- fill
## colors, shapes, and layer order all still match.

var world: SimulationWorld
var player: int = 0
var tuning: Dictionary
var palette: Dictionary
var fx := FxState.new()

var _checkerboard_texture: ImageTexture
var _baked_cols := -1
var _baked_rows := -1
var _elapsed_ms := 0.0

func setup(p_world: SimulationWorld, p_tuning: Dictionary, p_palette: Dictionary, p_player: int = 0) -> void:
	world = p_world
	tuning = p_tuning
	palette = p_palette
	player = p_player

## Cell (cell_x, cell_y) was just eaten -- called by whatever drives this
## view's world forward (a future screen/HUD task), not by this file itself,
## matching tick_driver.gd's "inject everything" pattern.
func notify_eat(cell_x: int, cell_y: int) -> void:
	fx.burst(cell_x, cell_y, tuning, palette.board.particle_hues)

func _process(delta: float) -> void:
	if world == null:
		return
	_elapsed_ms += delta * 1000.0
	fx.decay(delta * 1000.0, tuning)
	queue_redraw()

func _draw() -> void:
	if world == null:
		return
	var record: Dictionary = world.serialize()
	if record.result != SimulationWorld.OK:
		return
	var header := BoardGeometry.decode_canon_header(record.bytes)
	var cols: int = header.cols
	var rows: int = header.rows
	if cols <= 0 or rows <= 0:
		return
	var cell: float = size.x / float(cols)

	var view := world.player_view_get(player)
	var body := world.body_copy(player)

	_draw_background(cols, rows, cell)
	_draw_checkerboard(cols, rows, cell)
	_draw_grid(cols, rows, cell)
	_draw_food(header, cell)
	if body.result == SimulationWorld.OK:
		_draw_snake(body.cells, cell)
		if view.result == SimulationWorld.OK:
			_draw_eyes(body.cells, view.dir, cell)
	_draw_particles(cell)
	if view.result == SimulationWorld.OK:
		_draw_flash(view.status)
		_draw_pause_vignette(view.status)

func _draw_background(cols: int, rows: int, cell: float) -> void:
	draw_rect(Rect2(0, 0, cols * cell, rows * cell), Color(palette.board.background))

func _draw_checkerboard(cols: int, rows: int, cell: float) -> void:
	if _checkerboard_texture == null or _baked_cols != cols or _baked_rows != rows:
		var image := BoardGeometry.build_checkerboard_image(
			cols, rows, Color(palette.board.checkerboard_tile), tuning.render.checkerboard_alpha
		)
		_checkerboard_texture = ImageTexture.create_from_image(image)
		_baked_cols = cols
		_baked_rows = rows
	draw_texture_rect(_checkerboard_texture, Rect2(0, 0, cols * cell, rows * cell), false)

func _draw_grid(cols: int, rows: int, cell: float) -> void:
	var color := Color(palette.board.grid_line)
	color.a = tuning.render.grid_line_alpha
	for x in BoardGeometry.grid_line_offsets(cols, cell):
		draw_line(Vector2(x, 0), Vector2(x, rows * cell), color, 1.0)
	for y in BoardGeometry.grid_line_offsets(rows, cell):
		draw_line(Vector2(0, y), Vector2(cols * cell, y), color, 1.0)

func _draw_food(header: Dictionary, cell: float) -> void:
	if header.food_x == BoardGeometry.NO_CELL_COORD:
		return
	var pulse := BoardGeometry.food_pulse(_elapsed_ms, tuning.food.pulse_period_ms)
	var pad := BoardGeometry.food_pad(cell, pulse, tuning.food.pulse_pad_base_fraction, tuning.food.pulse_pad_amplitude_fraction)
	var r := BoardGeometry.corner_radius(cell, tuning.food.corner_radius_fraction)
	_draw_rounded_rect(header.food_x * cell + pad, header.food_y * cell + pad, cell - pad * 2.0, cell - pad * 2.0, r, Color(palette.board.food_fill))

func _draw_snake(cells: PackedVector2Array, cell: float) -> void:
	var n := cells.size()
	for i in range(n - 1, -1, -1):
		var c := cells[i]
		var k := BoardGeometry.segment_weight(i, n)
		var pad := BoardGeometry.segment_pad(cell, k, tuning.snake.body_pad_base_fraction, tuning.snake.body_pad_amplitude_fraction)
		var r := BoardGeometry.corner_radius(cell, tuning.snake.corner_radius_fraction)
		var color: Color = Color(palette.board.snake_head_fill) if i == 0 else BoardGeometry.segment_color(k, palette.board.snake_body_base_rgb, palette.board.snake_body_rgb_delta)
		_draw_rounded_rect(c.x * cell + pad, c.y * cell + pad, cell - pad * 2.0, cell - pad * 2.0, r, color)

func _draw_eyes(cells: PackedVector2Array, dir: int, cell: float) -> void:
	if cells.is_empty():
		return
	var head := cells[0]
	var dir_vec := _dir_to_vector(dir)
	var offsets := BoardGeometry.eye_offsets(dir_vec.x, dir_vec.y, tuning.snake.eye_side_offset_fraction, tuning.snake.eye_forward_offset_fraction, cell)
	var r := BoardGeometry.eye_radius(cell, tuning.snake.eye_radius_fraction, tuning.snake.eye_radius_min_px)
	var center := Vector2((head.x + 0.5) * cell, (head.y + 0.5) * cell)
	var color := Color(palette.board.eye_fill)
	for offset in offsets:
		draw_circle(center + offset, r, color)

func _draw_particles(cell: float) -> void:
	for p in fx.particles:
		var s: float = cell * 0.16 * p.life
		var color := Color(String(p.hue))
		color.a = max(0.0, p.life)
		draw_rect(Rect2(p.x * cell - s / 2.0, p.y * cell - s / 2.0, s, s), color)

func _draw_flash(status: int) -> void:
	if fx.flash <= 0.0:
		return
	var dead := status == BoardGeometry.STATUS_DEAD
	var color := Color(palette.board.flash_dead) if dead else Color(palette.board.flash_eat)
	color.a = fx.flash * (tuning.flash.dead_alpha_factor if dead else tuning.flash.eat_alpha_factor)
	draw_rect(Rect2(0, 0, size.x, size.y), color)

func _draw_pause_vignette(status: int) -> void:
	if status != BoardGeometry.STATUS_PAUSED:
		return
	draw_rect(Rect2(0, 0, size.x, size.y), Color(palette.board.pause_vignette, tuning.render.pause_vignette_alpha))

func _draw_rounded_rect(x: float, y: float, w: float, h: float, radius: float, color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	var r := int(min(radius, w / 2.0, h / 2.0))
	style.corner_radius_top_left = r
	style.corner_radius_top_right = r
	style.corner_radius_bottom_left = r
	style.corner_radius_bottom_right = r
	draw_style_box(style, Rect2(x, y, w, h))

func _dir_to_vector(dir: int) -> Vector2i:
	if dir == SimulationWorld.DIR_UP:
		return Vector2i(0, -1)
	if dir == SimulationWorld.DIR_DOWN:
		return Vector2i(0, 1)
	if dir == SimulationWorld.DIR_LEFT:
		return Vector2i(-1, 0)
	return Vector2i(1, 0)

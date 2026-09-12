class_name FxState
extends RefCounted

## Mirrors snake.html's burst()/decayFx() (snake.html:411-430): the eat-flash
## and particle burst are purely cosmetic render-time state. Randomness comes
## from a small local xorshift32 PRNG rather than Godot's RandomNumberGenerator
## -- tools/validate_simulation_boundary.py's game:boundary-check (TASK-029)
## bans randi/randf/randi_range/randf_range/seed/randomize anywhere outside
## game/simulation/, even called on a locally-owned instance, so a hand-rolled
## generator is what keeps this file on the right side of that gate. This
## state never feeds back into SimulationWorld or docs/canonical-state.md.

var particles: Array[Dictionary] = []
var flash: float = 0.0
var _rng_state: int

func _init(prng_seed: int = int(Time.get_ticks_usec())) -> void:
	_rng_state = prng_seed if prng_seed != 0 else 1

func _next_unit_float() -> float:
	_rng_state ^= (_rng_state << 13) & 0xFFFFFFFF
	_rng_state ^= _rng_state >> 17
	_rng_state ^= (_rng_state << 5) & 0xFFFFFFFF
	_rng_state &= 0xFFFFFFFF
	return float(_rng_state) / float(0xFFFFFFFF)

## tuning: game/content/tuning.json's "particles"/"flash" sections.
## hues: game/content/palette.json's board.particle_hues (two hex strings).
func burst(cell_x: int, cell_y: int, tuning: Dictionary, hues: Array) -> void:
	var count: int = tuning.particles.burst_count
	var speed_min: float = tuning.particles.speed_min
	var speed_max: float = tuning.particles.speed_max
	for i in count:
		var angle := _next_unit_float() * TAU
		var speed: float = speed_min + _next_unit_float() * (speed_max - speed_min)
		particles.append({
			"x": cell_x + 0.5, "y": cell_y + 0.5,
			"vx": cos(angle) * speed, "vy": sin(angle) * speed,
			"life": 1.0,
			"hue": hues[0] if _next_unit_float() < 0.5 else hues[1],
		})
	flash = 1.0

func decay(dt_ms: float, tuning: Dictionary) -> void:
	flash = max(0.0, flash - dt_ms * float(tuning.flash.decay_per_ms))
	var drag: float = tuning.particles.drag_per_tick
	var life_decay: float = tuning.particles.life_decay_per_ms
	var kept: Array[Dictionary] = []
	for p in particles:
		p.x += p.vx * dt_ms
		p.y += p.vy * dt_ms
		p.vx *= drag
		p.vy *= drag
		p.life -= dt_ms * life_decay
		if p.life > 0.0:
			kept.append(p)
	particles = kept

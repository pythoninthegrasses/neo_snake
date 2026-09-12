extends GdUnitTestSuite

## fx_state.gd mirrors snake.html's burst()/decayFx() (snake.html:411-430) --
## cosmetic-only, so these tests check invariants (count, clamping, removal)
## rather than exact particle trajectories, which depend on Godot's own RNG.

const TUNING := {
	"particles": {"burst_count": 14, "speed_min": 0.02, "speed_max": 0.06, "drag_per_tick": 0.94, "life_decay_per_ms": 0.0019230769230769232},
	"flash": {"decay_per_ms": 0.004545454545454545, "dead_alpha_factor": 0.28, "eat_alpha_factor": 0.12},
}
const HUES := ["#f87171", "#fbbf24"]


func test_burst_appends_the_configured_particle_count_and_sets_flash() -> void:
	var fx := FxState.new(1)
	fx.burst(3, 4, TUNING, HUES)
	assert_int(fx.particles.size()).is_equal(14)
	assert_float(fx.flash).is_equal_approx(1.0, 0.0001)
	for p in fx.particles:
		assert_bool(HUES.has(p.hue)).is_true()
		assert_float(p.life).is_equal_approx(1.0, 0.0001)


func test_decay_reduces_flash_and_clamps_at_zero() -> void:
	var fx := FxState.new()
	fx.flash = 1.0
	fx.decay(100.0, TUNING)
	assert_float(fx.flash).is_equal_approx(1.0 - 100.0 * TUNING.flash.decay_per_ms, 0.0001)
	fx.decay(100000.0, TUNING)
	assert_float(fx.flash).is_equal_approx(0.0, 0.0001)


func test_decay_removes_particles_once_their_life_expires() -> void:
	var fx := FxState.new(1)
	fx.burst(0, 0, TUNING, HUES)
	assert_int(fx.particles.size()).is_equal(14)
	fx.decay(100000.0, TUNING)
	assert_int(fx.particles.size()).is_equal(0)

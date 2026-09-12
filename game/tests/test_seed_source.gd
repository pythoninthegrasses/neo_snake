extends GdUnitTestSuite

## Exercises SeedSource (TASK-036) -- the only caller of randi() outside
## game/simulation/'s own boundary-gate exemption that a live orchestrator
## needs, per tools/validate_simulation_boundary.py's global-rng rule.

func test_fresh_returns_a_four_word_array() -> void:
	assert_int(SeedSource.fresh().size()).is_equal(4)


func test_fresh_is_never_all_zero() -> void:
	for i in range(20):
		var words := SeedSource.fresh()
		var all_zero := words[0] == 0 and words[1] == 0 and words[2] == 0 and words[3] == 0
		assert_bool(all_zero).is_false()

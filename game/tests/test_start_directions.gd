extends GdUnitTestSuite

## StartDirections picks each player's heading for a fresh run. Two rules:
## a 1-player game draws freely from every legal direction, and a 2-player
## game never has the two snakes facing each other down the shared column
## they spawn in.
##
## pick() draws from the engine's global RNG, so these assert invariants
## over many draws rather than one fixed outcome -- an invariant that holds
## every time is exactly what "semi-random" has to mean to be testable.

const DRAWS := 300


## A pinned seed reproduces its draw sequence exactly -- the property the
## invariant tests below can't show on their own.

func test_the_same_seed_reproduces_the_same_sequence() -> void:
	StartDirections.set_seed(12345)
	var first := []
	for i in 20:
		first.append(StartDirections.pick(2))
	StartDirections.set_seed(12345)
	var second := []
	for i in 20:
		second.append(StartDirections.pick(2))
	assert_array(second).is_equal(first)


func test_different_seeds_diverge() -> void:
	StartDirections.set_seed(1)
	var first := []
	for i in 20:
		first.append(StartDirections.pick(1))
	StartDirections.set_seed(2)
	var second := []
	for i in 20:
		second.append(StartDirections.pick(1))
	assert_array(second).is_not_equal(first)


func test_left_is_never_a_legal_start_direction() -> void:
	assert_array(StartDirections.LEGAL).not_contains([SimulationWorld.DIR_LEFT])


func test_one_player_draws_every_legal_direction_over_many_runs() -> void:
	var seen := {}
	for i in DRAWS:
		var dirs := StartDirections.pick(1)
		assert_int(dirs.size()).is_equal(1)
		assert_array(StartDirections.LEGAL).contains([dirs[0]])
		seen[dirs[0]] = true
	assert_int(seen.size()).is_equal(StartDirections.LEGAL.size())


func test_two_players_are_never_pointed_at_each_other() -> void:
	for i in DRAWS:
		var dirs := StartDirections.pick(2)
		assert_int(dirs.size()).is_equal(2)
		var head_on: bool = dirs[0] == SimulationWorld.DIR_DOWN and dirs[1] == SimulationWorld.DIR_UP
		assert_bool(head_on).is_false()


func test_two_players_still_reach_every_other_combination() -> void:
	var seen := {}
	for i in DRAWS:
		var dirs := StartDirections.pick(2)
		seen["%d,%d" % [dirs[0], dirs[1]]] = true
	## 3 x 3 combinations minus the one head-on pair.
	assert_int(seen.size()).is_equal(StartDirections.LEGAL.size() * StartDirections.LEGAL.size() - 1)


func test_player_1_may_not_face_up_when_player_0_faces_down() -> void:
	var choices := StartDirections.choices_for(1, SimulationWorld.DIR_DOWN)
	assert_array(choices).not_contains([SimulationWorld.DIR_UP])
	assert_array(choices).contains([SimulationWorld.DIR_DOWN, SimulationWorld.DIR_RIGHT])


func test_player_1_is_unconstrained_when_player_0_does_not_face_down() -> void:
	for p0_dir in [SimulationWorld.DIR_UP, SimulationWorld.DIR_RIGHT]:
		assert_array(StartDirections.choices_for(1, p0_dir)).contains_exactly_in_any_order(StartDirections.LEGAL)


func test_player_0_is_always_unconstrained() -> void:
	assert_array(StartDirections.choices_for(0, SimulationWorld.DIR_DOWN)).contains_exactly_in_any_order(StartDirections.LEGAL)

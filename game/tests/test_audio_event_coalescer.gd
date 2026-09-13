extends GdUnitTestSuite

## AudioEventCoalescer (TASK-041 AC#2): confirms the pure coalescing policy
## collapses any number of EVENT_EAT entries in one frame's drain down to a
## single "eat" cue, matching the exact scenario the AC describes -- six
## ticks advancing in one frame (e.g. after a hitch) must produce one eat
## sound, not six. core/abi.zig's stepOneTick pushes one independent
## NS_EVENT_EAT per tick that ate, so a real six-tick catch-up drain is
## shaped exactly like the six-entry array built here.

func _event(kind: int) -> Dictionary:
	return {"tick": 0, "player": 0, "kind": kind}


func test_six_eat_events_in_one_frame_coalesce_to_one_eat_cue() -> void:
	var events := []
	for i in range(6):
		events.append(_event(SimulationWorld.EVENT_EAT))
	var cues := AudioEventCoalescer.cues_for(events)
	assert_bool(cues["eat"]).is_true()
	assert_bool(cues["die"]).is_false()
	assert_bool(cues["win"]).is_false()


func test_a_single_eat_event_still_plays_the_eat_cue() -> void:
	var cues := AudioEventCoalescer.cues_for([_event(SimulationWorld.EVENT_EAT)])
	assert_bool(cues["eat"]).is_true()


func test_no_events_plays_no_cues() -> void:
	var cues := AudioEventCoalescer.cues_for([])
	assert_bool(cues["eat"]).is_false()
	assert_bool(cues["die"]).is_false()
	assert_bool(cues["win"]).is_false()


func test_a_die_event_among_eat_events_still_coalesces_the_eats() -> void:
	var events := [_event(SimulationWorld.EVENT_EAT), _event(SimulationWorld.EVENT_EAT), _event(SimulationWorld.EVENT_DIE)]
	var cues := AudioEventCoalescer.cues_for(events)
	assert_bool(cues["eat"]).is_true()
	assert_bool(cues["die"]).is_true()
	assert_bool(cues["win"]).is_false()


func test_a_win_event_plays_the_win_cue() -> void:
	var cues := AudioEventCoalescer.cues_for([_event(SimulationWorld.EVENT_WIN)])
	assert_bool(cues["win"]).is_true()
	assert_bool(cues["die"]).is_false()

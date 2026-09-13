class_name AudioEventCoalescer
extends RefCounted

## Pure coalescing policy for GameScreen's per-frame event drain (TASK-041
## AC#2): catch-up after a hitch can make one _process() call drive several
## ticks through TickDriver.advance_frame / world.pump, and core/abi.zig's
## stepOneTick pushes one independent NS_EVENT_EAT per tick that ate -- so a
## naive "sfx.play() per drained event" loop fires the eat cue once per
## tick, not once per frame. This is presentation policy, not simulation
## policy (core/abi.zig never knows audio exists): given one frame's
## drained events, decide which cues fire at most once. No Node/SfxPlayer
## dependency, so it's directly gdUnit4-testable with a synthetic event
## array standing in for a real multi-tick drain.
##
## die/win need no coalescing of their own -- core/abi.zig's pump()
## accumulator loop stops ticking the instant status leaves .playing, so at
## most one of either can ever appear in a single drain -- but they pass
## through this same decision point so GameScreen has one place to read
## "what should this frame sound like" instead of two.

## events is an Array of Dictionaries shaped like SimulationWorld.event_drain's
## "events" entries (each with an int "kind" matching SimulationWorld.EVENT_EAT/
## DIE/WIN). Returns a Dictionary of cue name -> whether it should play this
## frame.
static func cues_for(events: Array) -> Dictionary:
	var ate := false
	var died := false
	var won := false
	for event in events:
		match int(event.kind):
			SimulationWorld.EVENT_EAT:
				ate = true
			SimulationWorld.EVENT_DIE:
				died = true
			SimulationWorld.EVENT_WIN:
				won = true
	return {"eat": ate, "die": died, "win": won}

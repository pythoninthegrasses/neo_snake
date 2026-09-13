extends GdUnitTestSuite

## SfxPlayer (TASK-039): asserts every one of the eight committed cues loads
## a real stream and that play() actually starts playback -- the closest
## automated proxy available in a headless test run to "audibly triggered"
## (AC#3's manual check is what actually confirms a human can hear it).

var _sfx: SfxPlayer


func before_test() -> void:
	_sfx = SfxPlayer.new()
	add_child(_sfx)


func after_test() -> void:
	_sfx.queue_free()


func test_every_cue_loads_a_stream() -> void:
	for cue in SfxPlayer.CUES:
		var player: AudioStreamPlayer = _sfx._players[cue]
		assert_object(player.stream).is_not_null()


func test_play_starts_playback_for_every_cue() -> void:
	for cue in SfxPlayer.CUES:
		_sfx.play(cue)
		var player: AudioStreamPlayer = _sfx._players[cue]
		assert_bool(player.playing).is_true()


func test_play_on_an_unknown_cue_does_not_error() -> void:
	_sfx.play("not_a_real_cue")


func test_ui_cues_route_to_ui_bus() -> void:
	for cue in SfxPlayer.UI_CUES:
		var player: AudioStreamPlayer = _sfx._players[cue]
		assert_str(player.bus).is_equal("UI")


func test_non_ui_cues_route_to_sfx_bus() -> void:
	for cue in SfxPlayer.CUES:
		if cue in SfxPlayer.UI_CUES:
			continue
		var player: AudioStreamPlayer = _sfx._players[cue]
		assert_str(player.bus).is_equal("SFX")


func test_set_replaying_true_suppresses_play() -> void:
	_sfx.set_replaying(true)
	for cue in SfxPlayer.CUES:
		_sfx.play(cue)
		var player: AudioStreamPlayer = _sfx._players[cue]
		assert_bool(player.playing).is_false()


func test_set_replaying_false_restores_play() -> void:
	_sfx.set_replaying(true)
	_sfx.set_replaying(false)
	_sfx.play("eat")
	var player: AudioStreamPlayer = _sfx._players["eat"]
	assert_bool(player.playing).is_true()

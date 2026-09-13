extends GdUnitTestSuite

## MusicPlayer (TASK-040): asserts the committed theme loads a real looping
## stream, routes to the "Music" bus, and that play()/stop() actually
## start/stop playback -- the closest automated proxy available in a
## headless test run to "audibly playing."

var _music: MusicPlayer


func before_test() -> void:
	_music = MusicPlayer.new()
	add_child(_music)


func after_test() -> void:
	_music.queue_free()


func test_theme_loads_a_stream() -> void:
	assert_object(_music._player.stream).is_not_null()


func test_theme_loops() -> void:
	assert_bool(_music._player.stream.loop).is_true()


func test_routes_to_music_bus() -> void:
	assert_str(_music._player.bus).is_equal("Music")


func test_play_starts_playback() -> void:
	_music.play()
	assert_bool(_music.is_playing()).is_true()


func test_stop_stops_playback() -> void:
	_music.play()
	_music.stop()
	assert_bool(_music.is_playing()).is_false()

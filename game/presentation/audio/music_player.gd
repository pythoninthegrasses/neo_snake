class_name MusicPlayer
extends Node

## Plays the offline-rendered chiptune theme (TASK-040) committed at
## game/content/audio/music/theme.ogg -- rendered by tools/render_music.py
## from audio/src/music/theme.fur. Single looping AudioStreamPlayer on the
## "Music" bus (TASK-040 bus layout: Master -> Music/SFX/UI); reference/
## snake.html has no music of its own, so there is no cue-point oracle to
## match -- it simply loops continuously once started.
##
## Lives entirely in presentation (GameScreen owns one) -- core/*.zig never
## references audio in any form, per the milestone's "core never knows
## audio exists" rule (same boundary SfxPlayer already keeps).
##
## set_replaying(true) suppresses play() entirely (TASK-041 AC#3): replay
## and rollback playback must never sound, and the flag lives here in
## presentation, not in the sim, per the same rule.

const MUSIC_PATH := "res://content/audio/music/theme.ogg"

var _player: AudioStreamPlayer
var _replaying := false

func set_replaying(replaying: bool) -> void:
	_replaying = replaying

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	if ResourceLoader.exists(MUSIC_PATH):
		var stream: AudioStream = load(MUSIC_PATH)
		if stream is AudioStreamOggVorbis:
			stream.loop = true
		_player.stream = stream
	else:
		push_error("MusicPlayer: missing %s" % MUSIC_PATH)
	_player.bus = "Music"
	add_child(_player)

func play() -> void:
	if _replaying:
		return
	if _player.stream != null and not _player.playing:
		_player.play()

func stop() -> void:
	_player.stop()

func is_playing() -> bool:
	return _player.playing

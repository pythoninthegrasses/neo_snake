class_name SfxPlayer
extends Node

## Plays the eight offline-rendered chiptune cues (TASK-039) committed at
## game/content/audio/sfx/*.wav -- rendered by tools/render_audio.py from
## audio/src/sfx/*.chip.json (TASK-038). One AudioStreamPlayer per cue: these
## are all short (<=200ms) one-shot cues, so retriggering an already-playing
## cue just restarts it -- no pooling/polyphony needed at this scale.
##
## Lives entirely in presentation (GameScreen owns one, wires play() calls
## into its own event handlers) -- core/*.zig never references audio in any
## form, per the milestone's "core never knows audio exists" rule.

const SFX_DIR := "res://content/audio/sfx/"

const CUES: Array[String] = [
	"eat", "die", "turn", "start", "pause", "win", "ui_move", "ui_confirm",
]

## UI-navigation cues route to the "UI" bus; every other cue is in-game
## feedback and routes to "SFX" (TASK-040 bus layout: Master -> Music/SFX/UI).
const UI_CUES: Array[String] = ["ui_move", "ui_confirm"]

var _players := {}

func _ready() -> void:
	for cue in CUES:
		var player := AudioStreamPlayer.new()
		var path := "%s%s.wav" % [SFX_DIR, cue]
		if ResourceLoader.exists(path):
			player.stream = load(path)
		else:
			push_error("SfxPlayer: missing cue %s" % path)
		player.bus = "UI" if cue in UI_CUES else "SFX"
		add_child(player)
		_players[cue] = player

func play(cue: String) -> void:
	var player: AudioStreamPlayer = _players.get(cue)
	if player != null and player.stream != null:
		player.play()

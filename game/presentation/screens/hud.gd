class_name Hud
extends Control

## Score/best/status HUD (TASK-036 AC#2), scoped to exactly the fields this
## task's own Description calls for -- score, per-mode best, and status
## text -- omitting reference/snake.html's Speed/Length stats
## (snake.html:218-223), which this task's text never asks for. Built in
## code, matching board_view.gd's code-first Control convention: this repo
## has no .tscn precedent to follow instead.

var _score_label := Label.new()
var _best_label := Label.new()
var _status_label := Label.new()

func _ready() -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	add_child(box)
	box.add_child(_score_label)
	box.add_child(_best_label)
	box.add_child(_status_label)
	update(0, 0, "")

## status_text mirrors the S.status equivalent transition currently in
## effect (menu/playing/paused/dead) -- not part of the oracle's own HUD,
## but explicit in this task's Description ("status text matching S.status
## transitions").
func update(score: int, best: int, status_text: String) -> void:
	_score_label.text = "Score %d" % score
	_best_label.text = "Best %d" % best
	_status_label.text = status_text

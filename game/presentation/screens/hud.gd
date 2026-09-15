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

## TASK-051: player 1's own row. No best-score label -- best-score
## persistence stays player-0/mode-scoped only (see backlog/decisions).
var _p2_score_label := Label.new()
var _p2_status_label := Label.new()
var _p2_box: HBoxContainer

func _ready() -> void:
	## Both rows are plain Control children with no shared layout container,
	## so without this VBoxContainer wrapper they both default to (0, 0)
	## and render on top of each other.
	var rows := VBoxContainer.new()
	add_child(rows)

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	rows.add_child(box)
	box.add_child(_score_label)
	box.add_child(_best_label)
	box.add_child(_status_label)
	update(0, 0, "")

	_p2_box = HBoxContainer.new()
	_p2_box.add_theme_constant_override("separation", 16)
	rows.add_child(_p2_box)
	_p2_box.add_child(_p2_score_label)
	_p2_box.add_child(_p2_status_label)
	update_p2(0, "")

## status_text mirrors the S.status equivalent transition currently in
## effect (menu/playing/paused/dead) -- not part of the oracle's own HUD,
## but explicit in this task's Description ("status text matching S.status
## transitions").
func update(score: int, best: int, status_text: String) -> void:
	_score_label.text = "Score %d" % score
	_best_label.text = "Best %d" % best
	_status_label.text = status_text

func update_p2(score: int, status_text: String) -> void:
	_p2_score_label.text = "P2 Score %d" % score
	_p2_status_label.text = status_text

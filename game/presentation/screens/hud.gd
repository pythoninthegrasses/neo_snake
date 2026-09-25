class_name Hud
extends Control

## Score/best/status HUD (TASK-036 AC#2), scoped to exactly the fields this
## task's own Description calls for -- score, per-mode best, and status
## text -- omitting reference/snake.html's Speed/Length stats
## (snake.html:218-223), which this task's text never asks for. Built in
## code, matching board_view.gd's code-first Control convention: this repo
## has no .tscn precedent to follow instead.
##
## Both players' fields share a single HBoxContainer row (game_screen.gd
## sets custom_minimum_size.y to the 25px strip below the board, which only
## fits one text row) rather than the two stacked rows an earlier version
## used.

var _score_label := Label.new()
var _best_label := Label.new()
var _status_label := Label.new()

## TASK-051: player 1's own fields. No best-score label -- best-score
## persistence stays player-0/mode-scoped only (see backlog/decisions).
var _p2_score_label := Label.new()
var _p2_status_label := Label.new()
var _p2_box: HBoxContainer

const _FONT_SIZE := 14

func _ready() -> void:
	custom_minimum_size = Vector2(0, 25)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	add_child(row)
	row.add_child(_score_label)
	row.add_child(_best_label)
	row.add_child(_status_label)
	update(0, 0, "")

	_p2_box = HBoxContainer.new()
	_p2_box.add_theme_constant_override("separation", 16)
	row.add_child(_p2_box)
	_p2_box.add_child(_p2_score_label)
	_p2_box.add_child(_p2_status_label)
	update_p2(0, "")

	for label in [_score_label, _best_label, _status_label, _p2_score_label, _p2_status_label]:
		label.add_theme_font_size_override("font_size", _FONT_SIZE)

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

## Hidden for a 1-player game, where the world has no player 1 to report on.
func set_p2_row_visible(shown: bool) -> void:
	if _p2_box != null:
		_p2_box.visible = shown

func p2_row_visible() -> bool:
	return _p2_box != null and _p2_box.visible

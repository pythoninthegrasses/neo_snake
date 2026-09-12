class_name OverlayPanel
extends Control

## A single reused overlay Control (TASK-036 AC#1), reconfigured per screen
## via configure() rather than four near-identical scenes/nodes -- mirrors
## reference/snake.html's single, permanently-present #overlay div that
## showOverlay()/hideOverlay() reconfigure and toggle rather than swap
## (snake.html:227-241, 545-551). Built in code, not a .tscn: matches
## board_view.gd's code-first Control convention, the only precedent this
## repo has for a hand-authored node tree.
##
## Per backlog/decisions/ (mode-select scoping): the oracle's mode <select>
## sits outside showOverlay()'s title/sub/button text and is structurally
## visible whenever *any* overlay state is shown (menu, paused, and dead
## alike) -- a side effect of reusing one div, not a designed feature. This
## port only ever shows it for the menu screen; see the decision entry for
## why mid-session mode switching isn't preserved.

signal action_pressed
signal mode_selected(mode_id: String)

var _title_label := Label.new()
var _sub_label := Label.new()
var _mode_select := OptionButton.new()
var _action_button := Button.new()
var _mode_ids: Array[String] = []

func _ready() -> void:
	var box := VBoxContainer.new()
	add_child(box)
	box.add_child(_title_label)
	box.add_child(_sub_label)
	box.add_child(_mode_select)
	box.add_child(_action_button)
	_action_button.pressed.connect(func() -> void: action_pressed.emit())
	_mode_select.item_selected.connect(_on_item_selected)

func _on_item_selected(index: int) -> void:
	mode_selected.emit(_mode_ids[index])

## modes: game/content/modes.json's "modes" array shape (Array of
## {id, label, wrap}).
func set_modes(modes: Array, selected_id: String) -> void:
	_mode_select.clear()
	_mode_ids.clear()
	for i in modes.size():
		var mode: Dictionary = modes[i]
		_mode_select.add_item(mode.label)
		_mode_ids.append(mode.id)
		if mode.id == selected_id:
			_mode_select.select(i)

## content: a GameScreenState.overlay_content()-shaped Dictionary, or {} to
## hide the panel entirely (the SCREEN_PLAYING case, which has no overlay).
func configure(content: Dictionary) -> void:
	visible = not content.is_empty()
	if content.is_empty():
		return
	_title_label.text = content.title
	_sub_label.text = content.sub
	_action_button.text = content.button_label
	_mode_select.visible = content.show_mode_select

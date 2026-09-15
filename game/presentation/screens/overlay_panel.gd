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
signal player_count_selected(count: int)
signal return_to_title_requested
signal mode_selected(mode_id: String)
signal settings_requested

var _title_label := Label.new()
var _sub_label := Label.new()
var _mode_select := OptionButton.new()

## The menu's own two entries. Every other overlay screen has one thing to
## do -- resume, or play again -- so it keeps using _action_button and hides
## these; the menu is the only screen where the player is choosing between
## two different games rather than confirming one.
var _one_player_button := Button.new()
var _two_player_button := Button.new()
var _controls_label := Label.new()

var _action_button := Button.new()

## Dead screen only: the way back to the menu, where the player count and
## mode can be changed. Sits below the action button so "Play Again" stays
## the default the overlay focuses.
var _return_button := Button.new()

var _settings_button := Button.new()
var _mode_ids: Array[String] = []

## Tracks the visible->hidden/hidden->visible edge across configure() calls
## (called every _process() frame via game_screen.gd's _refresh_screen(), not
## just on real transitions) so focus is grabbed/released exactly once per
## transition rather than every frame -- the latter would fight a player
## trying to navigate from the action button to Settings with Down.
var _was_visible := false

func _ready() -> void:
	## Left at their default FOCUS_ALL: Enter/Kp Enter "choose the selection"
	## and Up/Down move focus between these controls via Godot's own
	## built-in ui_accept/ui_up/ui_down handling -- this overlay's whole
	## keyboard menu-navigation story. Gameplay arrows/WASD reach
	## input_router.gd's _unhandled_input instead once nothing here has
	## focus (see configure()'s gui_release_focus() call below).
	var box := VBoxContainer.new()
	add_child(box)
	box.add_child(_title_label)
	box.add_child(_sub_label)
	_one_player_button.text = "1 Player Game"
	box.add_child(_one_player_button)
	_two_player_button.text = "2 Player Game"
	box.add_child(_two_player_button)
	box.add_child(_controls_label)
	box.add_child(_mode_select)
	box.add_child(_action_button)
	_return_button.text = "Return to Title"
	box.add_child(_return_button)
	_settings_button.text = "Settings"
	box.add_child(_settings_button)
	_action_button.pressed.connect(func() -> void: action_pressed.emit())
	_return_button.pressed.connect(func() -> void: return_to_title_requested.emit())
	_one_player_button.pressed.connect(func() -> void: player_count_selected.emit(1))
	_two_player_button.pressed.connect(func() -> void: player_count_selected.emit(2))
	_mode_select.item_selected.connect(_on_item_selected)
	_settings_button.pressed.connect(func() -> void: settings_requested.emit())

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
		if _was_visible and is_inside_tree():
			get_viewport().gui_release_focus()
		_was_visible = false
		return
	if not _was_visible:
		var first: Button = _one_player_button if content.show_player_select else _action_button
		first.grab_focus.call_deferred()
	_was_visible = true
	_title_label.text = content.title
	_sub_label.text = content.sub
	_action_button.text = content.button_label
	_action_button.visible = content.button_label != ""
	_one_player_button.visible = content.show_player_select
	_two_player_button.visible = content.show_player_select
	_return_button.visible = content.show_return_to_title
	_controls_label.text = content.controls
	_controls_label.visible = content.controls != ""
	_mode_select.visible = content.show_mode_select

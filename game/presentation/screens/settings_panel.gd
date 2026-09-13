class_name SettingsPanel
extends Control

## Settings screen (TASK-042): per-bus volume sliders (AC#1), a reduce-flash
## toggle (AC#2), and keybind rebinding (AC#3). Built in code, not a .tscn --
## matches overlay_panel.gd/board_view.gd's code-first Control convention,
## this repo's only precedent for a hand-authored node tree.
##
## Pure presentation: this panel only edits values and emits change signals.
## GameScreen is the one that applies a change live (AudioServer bus volume,
## board_view.fx.reduce_flash, KeybindCodec.apply_to_input_map()) and
## persists it via SaveStore -- mirrors how overlay_panel.gd emits
## action_pressed/mode_selected without knowing what GameScreen does with
## them.

signal volume_changed(bus: String, db: float)
signal reduce_flash_changed(enabled: bool)
signal keybind_changed(action: String, encoded: String)
signal closed

const VOLUME_MIN_DB := -40.0
const VOLUME_MAX_DB := 6.0

var _volume_sliders: Dictionary = {}
var _reduce_flash_check := CheckBox.new()
var _keybind_buttons: Dictionary = {}
var _close_button := Button.new()
var _listening_action := ""

func _ready() -> void:
	var box := VBoxContainer.new()
	add_child(box)

	var title := Label.new()
	title.text = "Settings"
	box.add_child(title)

	for bus: String in SaveStore.AUDIO_BUSES:
		var row := HBoxContainer.new()
		box.add_child(row)
		var label := Label.new()
		label.text = bus
		row.add_child(label)
		var slider := HSlider.new()
		slider.min_value = VOLUME_MIN_DB
		slider.max_value = VOLUME_MAX_DB
		slider.step = 1.0
		slider.custom_minimum_size = Vector2(160, 0)
		slider.value_changed.connect(_on_volume_changed.bind(bus))
		row.add_child(slider)
		_volume_sliders[bus] = slider

	_reduce_flash_check.text = "Reduce flash"
	_reduce_flash_check.toggled.connect(_on_reduce_flash_toggled)
	box.add_child(_reduce_flash_check)

	for action: String in InputDefaults.ACTION_PHYSICAL_KEYCODES:
		var row := HBoxContainer.new()
		box.add_child(row)
		var label := Label.new()
		label.text = action
		row.add_child(label)
		var button := Button.new()
		button.pressed.connect(_on_rebind_pressed.bind(action))
		row.add_child(button)
		_keybind_buttons[action] = button

	_close_button.text = "Close"
	_close_button.pressed.connect(func() -> void: closed.emit())
	box.add_child(_close_button)

func _on_volume_changed(value: float, bus: String) -> void:
	volume_changed.emit(bus, value)

func _on_reduce_flash_toggled(enabled: bool) -> void:
	reduce_flash_changed.emit(enabled)

func _on_rebind_pressed(action: String) -> void:
	_listening_action = action
	_keybind_buttons[action].text = "Press a key..."

func _unhandled_key_input(event: InputEvent) -> void:
	if _listening_action == "" or not event is InputEventKey or not event.pressed:
		return
	_capture_key(event as InputEventKey)

## Split out from _unhandled_key_input so a test can drive a rebind
## directly with a synthetic InputEventKey rather than injecting a real
## event through the scene tree's input pipeline.
func _capture_key(event: InputEventKey) -> void:
	var action := _listening_action
	_listening_action = ""
	var encoded := KeybindCodec.encode(event.physical_keycode as Key)
	_keybind_buttons[action].text = OS.get_keycode_string(event.physical_keycode)
	keybind_changed.emit(action, encoded)

## settings: SaveStore's normalized "settings" dict shape (volume_db,
## reduce_flash, keybinds). Uses the *_no_signal setters so applying a
## loaded save doesn't immediately re-emit every value as if the user had
## just edited it.
func set_settings(settings: Dictionary) -> void:
	for bus: String in SaveStore.AUDIO_BUSES:
		if _volume_sliders.has(bus):
			_volume_sliders[bus].set_value_no_signal(settings.volume_db.get(bus, 0.0))
	_reduce_flash_check.set_pressed_no_signal(settings.reduce_flash)
	for action: String in InputDefaults.ACTION_PHYSICAL_KEYCODES:
		var encoded_list: Array = settings.keybinds.get(action, [])
		var label := "Unbound"
		if not encoded_list.is_empty():
			var keycode := KeybindCodec.decode(encoded_list[0])
			if keycode != KEY_NONE:
				label = OS.get_keycode_string(keycode)
		if _keybind_buttons.has(action):
			_keybind_buttons[action].text = label

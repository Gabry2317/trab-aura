extends Control

@onready var slider_volume: HSlider = $Pannello/Contenitore/RigaVolume/SliderVolume
@onready var label_volume: Label = $Pannello/Contenitore/RigaVolume/LabelVolume
@onready var check_fullscreen: CheckButton = $Pannello/Contenitore/CheckFullscreen
@onready var video_hint: Label = $Pannello/Contenitore/LabelVideoHint
@onready var resolution_option: OptionButton = $Pannello/Contenitore/RigaRisoluzione/Risoluzione
@onready var check_effects: CheckButton = $Pannello/Contenitore/CheckEffetti
@onready var check_gore: CheckButton = $Pannello/Contenitore/CheckGore
@onready var reset_keys: Button = $Pannello/Contenitore/ResetTasti
@onready var keyboard_bindings: VBoxContainer = $Pannello/Contenitore/ScrollTasti/ElencoTasti

const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const ACTION_LABELS := {
	"left": "Sinistra", "right": "Destra", "down": "Giù / fatality",
	"jump": "Salto", "run": "Corsa", "attack": "Attacco",
	"secondary": "Potere / blocco", "reload": "Ricarica stamina",
}
var _pending_action: String = ""
var _pending_button: Button
var _binding_buttons: Dictionary = {}


func _ready() -> void:
	slider_volume.value = GameState.master_volume * 100.0
	check_fullscreen.button_pressed = GameState.fullscreen
	video_hint.visible = Engine.is_embedded_in_editor()
	check_effects.button_pressed = GameState.visual_effects
	check_gore.button_pressed = GameState.gore_enabled
	_update_volume_label(slider_volume.value)
	_populate_resolutions()
	_build_key_binding_rows()

	slider_volume.value_changed.connect(_on_volume_changed)
	check_fullscreen.toggled.connect(_on_fullscreen_toggled)
	check_effects.toggled.connect(GameState.set_visual_effects)
	check_gore.toggled.connect(GameState.set_gore_enabled)
	resolution_option.item_selected.connect(_on_resolution_selected)
	reset_keys.pressed.connect(_reset_key_bindings)


func _input(event: InputEvent) -> void:
	if _pending_action.is_empty() or not event is InputEventKey or not event.pressed or event.echo:
		return
	var key_event := event as InputEventKey
	if key_event.keycode == KEY_ESCAPE:
		_finish_rebind(false)
		get_viewport().set_input_as_handled()
		return
	var physical_code: int = key_event.physical_keycode if key_event.physical_keycode != KEY_NONE else key_event.keycode
	if GameState.set_key_binding(_pending_action, physical_code):
		_finish_rebind(true)
	else:
		_pending_button.text = "Tasto già in uso"
	get_viewport().set_input_as_handled()


func _populate_resolutions() -> void:
	var selected_index := 0
	for i in range(RESOLUTIONS.size()):
		var size: Vector2i = RESOLUTIONS[i]
		resolution_option.add_item("%d x %d" % [size.x, size.y])
		resolution_option.set_item_metadata(i, size)
		if size == GameState.window_resolution:
			selected_index = i
	resolution_option.select(selected_index)


func _build_key_binding_rows() -> void:
	for child in keyboard_bindings.get_children():
		child.queue_free()
	_binding_buttons.clear()
	for player_id in [1, 2]:
		var header := Label.new()
		header.text = "Giocatore %d" % player_id
		header.add_theme_color_override("font_color", Color(0.95, 0.78, 0.18))
		keyboard_bindings.add_child(header)
		for action in GameState.DEFAULT_KEY_BINDINGS:
			if not action.begins_with("p%d_" % player_id):
				continue
			var row := HBoxContainer.new()
			var action_name: String = action.trim_prefix("p%d_" % player_id)
			var label := Label.new()
			label.text = ACTION_LABELS.get(action_name, action_name)
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)
			var button := Button.new()
			button.custom_minimum_size = Vector2(170.0, 36.0)
			button.text = GameState.key_name(action)
			button.pressed.connect(_begin_rebind.bind(action, button))
			row.add_child(button)
			keyboard_bindings.add_child(row)
			_binding_buttons[action] = button


func _begin_rebind(action: String, button: Button) -> void:
	if not _pending_action.is_empty():
		_finish_rebind(false)
	_pending_action = action
	_pending_button = button
	button.text = "Premi un tasto…"
	button.grab_focus()


func _finish_rebind(accepted: bool) -> void:
	if not _pending_action.is_empty() and not accepted and is_instance_valid(_pending_button):
		_pending_button.text = GameState.key_name(_pending_action)
	if accepted:
		_refresh_key_labels()
	_pending_action = ""
	_pending_button = null


func _refresh_key_labels() -> void:
	for action in _binding_buttons:
		var button: Button = _binding_buttons[action]
		button.text = GameState.key_name(action)


func _reset_key_bindings() -> void:
	_finish_rebind(false)
	GameState.reset_key_bindings()
	_refresh_key_labels()


func _on_resolution_selected(index: int) -> void:
	GameState.set_window_resolution(resolution_option.get_item_metadata(index))


func _on_volume_changed(value: float) -> void:
	GameState.set_master_volume(value / 100.0)
	_update_volume_label(value)


func _update_volume_label(value: float) -> void:
	label_volume.text = "Volume: %d%%" % int(value)


func _on_fullscreen_toggled(pressed: bool) -> void:
	GameState.set_fullscreen(pressed)

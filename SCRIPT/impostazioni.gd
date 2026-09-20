extends Control

@onready var slider_volume: HSlider = $Pannello/Contenitore/RigaVolume/SliderVolume
@onready var label_volume: Label = $Pannello/Contenitore/RigaVolume/LabelVolume
@onready var check_fullscreen: CheckButton = $Pannello/Contenitore/CheckFullscreen
@onready var btn_indietro: Button = $Pannello/Contenitore/Indietro


func _ready() -> void:
	slider_volume.value = GameState.master_volume * 100.0
	check_fullscreen.button_pressed = GameState.fullscreen
	_update_volume_label(slider_volume.value)

	slider_volume.value_changed.connect(_on_volume_changed)
	check_fullscreen.toggled.connect(_on_fullscreen_toggled)
	btn_indietro.pressed.connect(_on_indietro_pressed)


func _on_volume_changed(value: float) -> void:
	GameState.set_master_volume(value / 100.0)
	_update_volume_label(value)


func _update_volume_label(value: float) -> void:
	label_volume.text = "Volume: %d%%" % int(value)


func _on_fullscreen_toggled(pressed: bool) -> void:
	GameState.set_fullscreen(pressed)


func _on_indietro_pressed() -> void:
	get_tree().change_scene_to_file("res://menu.tscn")

extends Control

@onready var slider_volume: HSlider = $Pannello/Contenitore/RigaVolume/SliderVolume
@onready var label_volume: Label = $Pannello/Contenitore/RigaVolume/LabelVolume
@onready var check_fullscreen: CheckButton = $Pannello/Contenitore/CheckFullscreen


func _ready() -> void:
	slider_volume.value = GameState.master_volume * 100.0
	check_fullscreen.button_pressed = GameState.fullscreen
	_update_volume_label(slider_volume.value)

	slider_volume.value_changed.connect(_on_volume_changed)
	check_fullscreen.toggled.connect(_on_fullscreen_toggled)
	# Il bottone Indietro è collegato direttamente a UI.torna_al_menu()
	# tramite il segnale "pressed" nella scena unificata: non serve più
	# gestirlo qui dentro.


func _on_volume_changed(value: float) -> void:
	GameState.set_master_volume(value / 100.0)
	_update_volume_label(value)


func _update_volume_label(value: float) -> void:
	label_volume.text = "Volume: %d%%" % int(value)


func _on_fullscreen_toggled(pressed: bool) -> void:
	GameState.set_fullscreen(pressed)


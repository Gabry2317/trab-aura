extends Button


func _ready() -> void:
	pressed.connect(_on_pressed)


func _on_pressed() -> void:
	GameState.start_selection()
	get_tree().change_scene_to_file("res://selezione_personaggio.tscn")

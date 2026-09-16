extends Button

func _ready() -> void:
	pressed.connect(_on_pressed)


func _on_pressed() -> void:
	GameState.selected_skin = 2

	get_tree().change_scene_to_file("res://level.tscn")

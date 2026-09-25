extends Button
# toonline.gd — bottone "Online" nel menu principale: porta alla schermata
# di host/join (a differenza di toselect.gd che porta alla partita locale).


func _ready() -> void:
	pressed.connect(_on_pressed)


func _on_pressed() -> void:
	get_tree().change_scene_to_file("res://network_menu.tscn")

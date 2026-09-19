extends Button

# 0 = trab, 1 = iacopo, 2 = ciochins (impostalo nell'Inspector di ogni pulsante)
@export var skin_id: int = 0


func _ready() -> void:
	pressed.connect(_on_pressed)


func _on_pressed() -> void:
	GameState.choose_skin(skin_id)

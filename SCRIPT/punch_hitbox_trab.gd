extends Area2D
class_name Hitbox

@export var damage: int = 10
@export var source: Node = null

var _already_hit: Array[Node] = []

func _ready() -> void:
	area_entered.connect(_on_area_entered)

func _on_area_entered(area: Area2D) -> void:
	if area is Hurtbox and area not in _already_hit:
		_already_hit.append(area)
		area.take_damage(damage, source)

func reset_hits() -> void:
	_already_hit.clear()

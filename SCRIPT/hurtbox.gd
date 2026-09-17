extends Area2D
class_name Hurtbox

signal damaged(amount: int, source: Node)

func take_damage(amount: int, source: Node = null) -> void:
	damaged.emit(amount, source)

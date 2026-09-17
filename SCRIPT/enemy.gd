extends CharacterBody2D

@export var max_health: int = 100
var health: int = max_health

@onready var hurtbox: Hurtbox = %Hurtbox
@onready var health_bar: ProgressBar = $HealthBarAnchor/HealthBar

func _ready() -> void:
	hurtbox.damaged.connect(_on_damaged)
	health = max_health
	health_bar.max_value = max_health
	health_bar.value = health

func _on_damaged(amount: int, source: Node) -> void:
	health -= amount
	health = max(health, 0)
	health_bar.value = health   # <-- qui si abbassa la barra

	if health <= 0:
		die()

func die() -> void:
	queue_free()

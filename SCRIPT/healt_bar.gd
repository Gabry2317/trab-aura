extends TextureProgressBar

@export var player: CharacterBody2D  # o Node, o il class_name del player

func _ready() -> void:
	if player == null:
		push_warning("Player non assegnato nell'inspector")
		return

	max_value = player.max_health
	value = player.current_health
	player.health_changed.connect(update)


func update() -> void:
	value = player.current_health

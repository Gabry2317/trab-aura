extends ProgressBar

@export var player: Player

func _ready() -> void:
	player.health_changed.connect(update)
	max_value = player.max_health
	update()

func update() -> void:
	value = player.current_health * 100.0 / player.max_health

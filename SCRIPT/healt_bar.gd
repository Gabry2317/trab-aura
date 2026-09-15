extends TextureProgressBar

@export var player: Player


func _ready() -> void:
	max_value = player.max_health
	value = player.current_health
	player.health_changed.connect(update)
	await get_tree().create_timer(1.0).timeout
	update()


func update() -> void:
	value = player.current_health
	if player.current_health < 1:
		get_tree().quit()

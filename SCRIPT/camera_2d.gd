extends Camera2D

@export var smoothing_enabled: bool = true
@export var smoothing_speed: float = 5.0

@export var vertical_range: float = 50.0  # quanto può salire/scendere in pixel
@export var vertical_limit_smoothing: float = 8.0  # velocità di "frenata" quando arriva al limite

var target_nodes: Array[Node2D] = []
var base_y: float = 0.0

func _ready() -> void:
	make_current()
	position_smoothing_enabled = smoothing_enabled
	position_smoothing_speed = smoothing_speed

	base_y = global_position.y

	var players = get_tree().get_nodes_in_group("players")
	for p in players:
		if p is Node2D:
			target_nodes.append(p)

func _process(delta: float) -> void:
	if target_nodes.is_empty():
		return

	var avg_position := Vector2.ZERO
	for node in target_nodes:
		avg_position += node.global_position
	avg_position /= target_nodes.size()

	var target_y = clamp(avg_position.y, base_y - vertical_range, base_y + vertical_range)
	var new_y = lerp(global_position.y, target_y, vertical_limit_smoothing * delta)

	global_position = Vector2(avg_position.x, new_y)

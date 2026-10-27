extends ProgressBar

@export var player_id: int = 0

var _player: Player = null


func _ready() -> void:
	max_value = 5.0
	value = max_value
	call_deferred("_find_player")


func _find_player() -> void:
	for candidate in get_tree().get_nodes_in_group("players"):
		if candidate is Player and candidate.player_id == player_id:
			_player = candidate
			visible = _player.secondary_power != null
			return
	visible = false


func _process(_delta: float) -> void:
	if _player == null or _player.secondary_power == null:
		return
	var cooldown: float = clampf(_player.secondary_power.cooldown_left, 0.0, max_value)
	value = max_value - cooldown

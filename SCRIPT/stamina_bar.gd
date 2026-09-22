extends ProgressBar
# Barra della stamina: sta sotto la barra della vita corrispondente (vedi
# level.tscn, HUD/BarraStaminaP1 e P2). Stesso schema di healt_bar.gd: player_id
# esportato (0 = P1, 1 = P2 in scena) per trovare il player giusto nel gruppo
# "players" e seguirne il segnale (qui stamina_changed invece di health_changed).

@export var player_id: int = 0

var _player: Player = null


func _ready() -> void:
	_find_player()
	if _player == null:
		# i player potrebbero non essere ancora nel gruppo al primissimo frame
		call_deferred("_find_player")


func _find_player() -> void:
	if _player != null:
		return
	for p in get_tree().get_nodes_in_group("players"):
		if p.player_id == player_id:
			_player = p
			break
	if _player == null:
		return
	max_value = _player.max_stamina
	value = _player.current_stamina
	_player.stamina_changed.connect(_on_stamina_changed)


func _on_stamina_changed() -> void:
	max_value = _player.max_stamina  # nel caso cambi personaggio/stat a runtime
	value = _player.current_stamina

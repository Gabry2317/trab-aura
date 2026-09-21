extends ProgressBar

@export var player_id: int = 0
var player: Player

func _ready() -> void:
	# I player sono nel gruppo "players". Usiamo player_id per distinguere P1/P2.
	call_deferred("_find_player")

func _find_player() -> void:
	var players := get_tree().get_nodes_in_group("players")

	for candidate in players:
		if candidate is Player and candidate.player_id == player_id:
			player = candidate
			max_value = float(player.max_health)
			value = float(player.current_health)

			if not player.health_changed.is_connected(_on_health_changed):
				player.health_changed.connect(_on_health_changed)
			return

	push_warning("Health bar %s: player_id %d non trovato" % [name, player_id])

func _process(_delta: float) -> void:
	# Aggiornamento diretto: la barra segue sempre la vita reale.
	if player != null:
		max_value = float(player.max_health)
		value = float(player.current_health)

func _on_health_changed() -> void:
	if player != null:
		max_value = float(player.max_health)
		value = float(player.current_health)

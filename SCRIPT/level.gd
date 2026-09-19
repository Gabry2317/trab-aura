extends Node

@onready var fine_partita = $FinePartita

var partita_finita: bool = false


func _ready() -> void:
	# ascolta la morte di ogni player
	for p in get_tree().get_nodes_in_group("players"):
		if p is Player:
			p.died.connect(_on_player_died)


func _on_player_died(morto: Player) -> void:
	if partita_finita:
		return  # se muoiono insieme, conta solo il primo
	partita_finita = true

	# con due player, il vincitore è l'altro
	var vincitore: int = 1 if morto.player_id == 0 else 0
	fine_partita.mostra(vincitore)

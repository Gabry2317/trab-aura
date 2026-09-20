extends Node

@onready var fine_partita = $FinePartita
@onready var label_timer: Label = $HUD/PannelloTimer/LabelTimer

const TEMPO_ROUND: float = 60.0

var partita_finita: bool = false
var tempo_rimasto: float = TEMPO_ROUND
var players_per_id: Dictionary = {}  # player_id -> Player


func _ready() -> void:
	# ascolta la morte di ogni player, indicizzandolo per player_id
	for p in get_tree().get_nodes_in_group("players"):
		if p is Player:
			players_per_id[p.player_id] = p
			p.died.connect(_on_player_died)

	_aggiorna_label_timer()


func _process(delta: float) -> void:
	if partita_finita:
		return

	tempo_rimasto = maxf(tempo_rimasto - delta, 0.0)
	_aggiorna_label_timer()

	if tempo_rimasto <= 0.0:
		_on_tempo_scaduto()


func _aggiorna_label_timer() -> void:
	if label_timer:
		label_timer.text = str(int(ceil(tempo_rimasto)))


func _on_player_died(morto: Player) -> void:
	if partita_finita:
		return  # se muoiono insieme, conta solo il primo
	partita_finita = true

	# con due player, il vincitore è l'altro
	var vincitore: int = 1 if morto.player_id == 0 else 0
	var match_finito: bool = GameState.register_round_win(vincitore)
	fine_partita.mostra(vincitore, match_finito)


func _on_tempo_scaduto() -> void:
	if partita_finita:
		return
	partita_finita = true

	# tempo scaduto: vince chi ha più salute rimasta; a parità è pareggio
	if not players_per_id.has(0) or not players_per_id.has(1):
		return

	var salute_p0: int = players_per_id[0].current_health
	var salute_p1: int = players_per_id[1].current_health

	if salute_p0 == salute_p1:
		fine_partita.mostra_pareggio()
	else:
		var vincitore: int = 0 if salute_p0 > salute_p1 else 1
		var match_finito: bool = GameState.register_round_win(vincitore)
		fine_partita.mostra(vincitore, match_finito)

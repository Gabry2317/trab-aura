extends Node

@onready var fine_partita = $FinePartita
@onready var label_timer: Label = $HUD/PannelloTimer/LabelTimer

const TEMPO_ROUND: float = 300.0

var partita_finita: bool = false
var tempo_rimasto: float = TEMPO_ROUND
var players_per_id: Dictionary = {}  # player_id -> Player


func _ready() -> void:
	_applica_mappa()
	_applica_controlli()

	# ascolta la morte di ogni player, indicizzandolo per player_id
	for p in get_tree().get_nodes_in_group("players"):
		if p is Player:
			players_per_id[p.player_id] = p
			p.died.connect(_on_player_died)

	_aggiorna_label_timer()


# Tiene solo background/tilemap della mappa scelta (definite in data/mappe.cfg)
# e imposta la musica. Se il livello parte da solo (test) usa la prima mappa.
func _applica_mappa() -> void:
	var tutte := SelettoreMappa.carica_mappe()
	if tutte.is_empty():
		return
	var scelta: Dictionary = SelettoreMappa.corrente if not SelettoreMappa.corrente.is_empty() else tutte[0]
	for m in tutte:
		if m.id == scelta.id:
			continue
		for chiave in ["background_node", "tilemap_node"]:
			var n := get_node_or_null(NodePath(m[chiave]))
			if n:
				n.queue_free()
	if scelta.musica != "" and ResourceLoader.exists(scelta.musica):
		var player: AudioStreamPlayer = $AudioStreamPlayer
		player.stop()
		player.stream = load(scelta.musica)
		player.play()


# NUOVO: traduce la configurazione scelta nel pannello "Rilevazione controlli"
# nel device_id che player.gd si aspetta già (-1 = tastiera schema p1_*,
# -2 = tastiera schema p2_*, >=0 = indice del joypad), sovrascrivendo il
# valore fisso impostato in scena. Senza questo, ogni Player usava sempre
# lo stesso dispositivo indipendentemente da chi avesse scelto cosa in
# selezione — da qui i personaggi che risultavano scambiati in partita.
func _applica_controlli() -> void:
	var controlli := Controlli.i()
	print("[DEBUG] assegnazioni: ", controlli.assegnazioni)
	for p in get_tree().get_nodes_in_group("players"):
		if not (p is Player):
			continue
		var assegnazione: Dictionary = controlli.assegnazioni.get(p.player_id, {})
		if assegnazione.is_empty():
			continue
		if assegnazione.tipo == "controller":
			p.device_id = assegnazione.device
		else:
			# player_id 0 -> sempre schema tastiera "p1_*" (WASD)
			# player_id 1 -> sempre schema tastiera "p2_*" (Frecce)
			p.device_id = -1 if p.player_id == 0 else -2
		print("[DEBUG] ", p.name, " -> device_id finale=", p.device_id)


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
	# NUOVO: in rete la decisione la prende solo l'host, poi la manda a
	# entrambi via RPC (_mostra_fine); in locale (nessun peer) invariato
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	partita_finita = true

	# con due player, il vincitore è l'altro
	var vincitore: int = 1 if morto.player_id == 0 else 0
	var match_finito: bool = GameState.register_round_win(vincitore)
	if multiplayer.has_multiplayer_peer():
		_mostra_fine.rpc(vincitore, match_finito)
	else:
		fine_partita.mostra(vincitore, match_finito)


func _on_tempo_scaduto() -> void:
	if partita_finita:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	partita_finita = true

	# tempo scaduto: vince chi ha più salute rimasta; a parità è pareggio
	if not players_per_id.has(0) or not players_per_id.has(1):
		return

	var salute_p0: int = players_per_id[0].current_health
	var salute_p1: int = players_per_id[1].current_health

	if salute_p0 == salute_p1:
		if multiplayer.has_multiplayer_peer():
			_mostra_pareggio.rpc()
		else:
			fine_partita.mostra_pareggio()
	else:
		var vincitore: int = 0 if salute_p0 > salute_p1 else 1
		var match_finito: bool = GameState.register_round_win(vincitore)
		if multiplayer.has_multiplayer_peer():
			_mostra_fine.rpc(vincitore, match_finito)
		else:
			fine_partita.mostra(vincitore, match_finito)


# NUOVO: chiamate dall'host a entrambi (call_local incluso) così la
# schermata di fine round appare uguale su entrambi i PC
@rpc("authority", "call_local", "reliable")
func _mostra_fine(vincitore: int, match_finito: bool) -> void:
	partita_finita = true
	fine_partita.mostra(vincitore, match_finito)


@rpc("authority", "call_local", "reliable")
func _mostra_pareggio() -> void:
	partita_finita = true
	fine_partita.mostra_pareggio()

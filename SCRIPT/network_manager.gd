extends Node
# network_manager.gd — Autoload "Network"
#
# Gestisce la parte di rete "vera": aprire una partita come host oppure
# collegarsi all'host di qualcun altro tramite il suo IP. Usa il sistema di
# multiplayer ad alto livello di Godot (ENet):
#   - l'host apre una porta (serve il port forwarding sul SUO router)
#   - il client si connette all'IP pubblico dell'host su quella porta
#
# Aggiungilo come autoload in Project Settings -> Autoload col nome "Network"
# (deve stare PRIMA di GameState nell'elenco, così quando GameState o i
# Player leggono multiplayer.is_server()/get_unique_id() la connessione è
# già pronta).

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_failed
signal connection_succeeded
signal server_ready  # entrambi i giocatori sono connessi: si può caricare il livello

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 2  # host + 1 client

# peer_id -> true. L'host è sempre peer_id 1 (assegnato automaticamente da Godot).
var players: Dictionary = {}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# Apre la partita come host sulla porta indicata (di default 7777).
# Ricorda: va aperta/fatta port-forward su questa porta (TCP e UDP) nel
# router di chi ospita, e nel firewall di Windows se serve.
func host_game(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_error("Impossibile aprire il server sulla porta %d (errore %d)" % [port, err])
		return err
	multiplayer.multiplayer_peer = peer
	players.clear()
	players[1] = true  # l'host stesso
	return OK


# Si collega all'host all'indirizzo IP indicato (quello pubblico dell'host,
# es. quello che vede su whatismyip.com se il port forwarding è impostato).
func join_game(ip: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(ip, port)
	if err != OK:
		push_error("Impossibile connettersi a %s:%d (errore %d)" % [ip, port, err])
		return err
	multiplayer.multiplayer_peer = peer
	return OK


# Chiude la connessione (da chiamare tornando al menu, o alla fine partita).
func leave_game() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	players.clear()


func _on_peer_connected(id: int) -> void:
	players[id] = true
	player_connected.emit(id)
	# solo l'host decide quando la partita è "pronta" (2 giocatori collegati)
	if multiplayer.is_server() and players.size() == MAX_PLAYERS:
		server_ready.emit()


func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	player_disconnected.emit(id)


func _on_connected_ok() -> void:
	connection_succeeded.emit()


func _on_connected_fail() -> void:
	multiplayer.multiplayer_peer = null
	connection_failed.emit()


func _on_server_disconnected() -> void:
	leave_game()

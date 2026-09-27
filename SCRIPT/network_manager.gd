extends Node
# network_manager.gd — Autoload "Network"
#
# Gestisce la parte di rete "vera": aprire una partita come host oppure
# collegarsi all'host di qualcun altro tramite il suo IP. Usa il sistema di
# multiplayer ad alto livello di Godot (ENet):
#   - l'host apre una porta sulla propria macchina
#   - il client si connette all'IP dell'host su quella porta
#
# Pensato per funzionare in modalità "LAN": stessa rete locale, oppure una
# rete virtuale tipo Hamachi / Radmin VPN / ZeroTier / Tailscale, che dal
# punto di vista di Godot è indistinguibile da una LAN vera (è solo un altro
# indirizzo IP raggiungibile). Chi ospita e chi si unisce devono essere sulla
# stessa rete (fisica o virtuale) PRIMA di premere Ospita/Unisciti: qui non
# c'è nessun tunnel o NAT traversal automatico, la scelta dello strumento
# (Hamachi, Radmin, LAN reale, ecc.) è lasciata ai giocatori.
#
# NOTA: questo file deve essere l'autoload registrato in Project Settings ->
# Autoload col nome "Network" (deve stare PRIMA di GameState nell'elenco,
# così quando GameState o i Player leggono
# multiplayer.is_server()/get_unique_id() la connessione è già pronta).
# Il file Network.gd allegato è uno stub vuoto rimasto da una versione
# precedente: non va usato come autoload, altrimenti questo script (con
# tutta la logica di rete) non gira mai. Rimuovilo o assicurati che
# l'autoload "Network" punti a network_manager.gd.

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
# Funziona su LAN reale o su una rete virtuale (Hamachi, Radmin VPN, ecc.):
# basta che l'altro giocatore sia collegato alla stessa rete. Se Windows
# chiede il permesso al firewall la prima volta, va concesso (rete privata).
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


# Si collega all'host all'indirizzo IP indicato: l'IP locale dell'host se
# siete sulla stessa LAN, oppure l'IP virtuale che gli assegna Hamachi /
# Radmin VPN / ZeroTier / Tailscale se siete su reti fisiche diverse.
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


# Un IP locale rilevato, con un'etichetta leggibile per capire a colpo
# d'occhio da dove viene (LAN reale, Hamachi, Radmin VPN, Tailscale...).
class IpHint:
	var address: String
	var label: String
	func _init(p_address: String, p_label: String) -> void:
		address = p_address
		label = p_label
	func describe() -> String:
		return "%s (%s)" % [address, label]


# Ritorna gli indirizzi IPv4 locali di questo PC con un'etichetta per
# ciascuno, utili da mostrare all'host così sa cosa dettare/incollare
# all'altro giocatore senza doverli indovinare uno per uno. Riconosce:
#   - Hamachi          -> di solito 25.0.0.0/8
#   - Radmin VPN       -> di solito 26.0.0.0/8
#   - Tailscale        -> sempre nel range 100.64.0.0/10 (CGNAT), quindi
#                         100.64.x.x .. 100.127.x.x
#   - LAN privata      -> 192.168.x.x, 10.x.x.x, 172.16-31.x.x
#   - qualsiasi altro adattatore virtuale (Docker, VirtualBox, Hyper-V,
#     WSL, VPN aziendali...) finisce sotto "altro", perché non c'è modo
#     affidabile di riconoscerlo per nome.
func get_local_ip_hints() -> Array[IpHint]:
	var hints: Array[IpHint] = []
	for addr in IP.get_local_addresses():
		if addr.find(":") != -1:  # scarta IPv6
			continue
		if addr.begins_with("127.") or addr.begins_with("169.254."):
			continue
		hints.append(IpHint.new(addr, _label_for_ip(addr)))
	return hints


func _label_for_ip(addr: String) -> String:
	var parts: PackedStringArray = addr.split(".")
	if parts.size() != 4:
		return "altro"
	var a: int = parts[0].to_int()
	var b: int = parts[1].to_int()
	if a == 25:
		return "Hamachi"
	if a == 26:
		return "Radmin VPN"
	if a == 100 and b >= 64 and b <= 127:
		return "Tailscale"
	if a == 192 and b == 168:
		return "rete locale"
	if a == 10:
		return "rete locale"
	if a == 172 and b >= 16 and b <= 31:
		return "rete locale"
	return "altro"

extends Control
# network_menu.gd — schermata "Ospita partita" / "Unisciti a partita".
# Va agganciata alla scena network_menu.tscn allegata (stessi nomi di nodo).

@onready var ip_field: LineEdit = $VBox/IPField
@onready var host_button: Button = $VBox/HostButton
@onready var join_button: Button = $VBox/JoinButton
@onready var status_label: Label = $VBox/StatusLabel

# Scena del livello a cui passare una volta connessi (adatta il path se serve)
const LEVEL_SCENE := "res://level.tscn"


func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)

	Network.player_connected.connect(_on_player_connected)
	Network.server_ready.connect(_on_server_ready)
	Network.connection_succeeded.connect(_on_connection_succeeded)
	Network.connection_failed.connect(_on_connection_failed)


func _on_host_pressed() -> void:
	var err: Error = Network.host_game()
	if err != OK:
		status_label.text = "Errore nell'apertura della partita (porta occupata?)."
		return
	status_label.text = "In attesa dell'altro giocatore... (porta 7777, ricorda il port forwarding)"
	host_button.disabled = true
	join_button.disabled = true


func _on_join_pressed() -> void:
	var ip: String = ip_field.text.strip_edges()
	if ip.is_empty():
		status_label.text = "Inserisci l'IP dell'host."
		return
	var err: Error = Network.join_game(ip)
	if err != OK:
		status_label.text = "IP non valido."
		return
	status_label.text = "Connessione a %s in corso..." % ip
	host_button.disabled = true
	join_button.disabled = true


func _on_player_connected(_id: int) -> void:
	if multiplayer.is_server():
		status_label.text = "Giocatore connesso! Avvio partita..."


func _on_connection_succeeded() -> void:
	status_label.text = "Connesso all'host! Attendo l'inizio partita..."


func _on_connection_failed() -> void:
	status_label.text = "Connessione fallita. Controlla IP e porta."
	host_button.disabled = false
	join_button.disabled = false


# Solo l'host decide quando si parte, e lo dice a tutti (client compreso)
# tramite RPC, così entrambi cambiano scena nello stesso momento.
func _on_server_ready() -> void:
	GameState.reset_match()
	_start_level.rpc()


@rpc("authority", "call_local", "reliable")
func _start_level() -> void:
	get_tree().change_scene_to_file(LEVEL_SCENE)

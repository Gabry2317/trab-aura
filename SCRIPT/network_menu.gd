extends Control
# network_menu.gd — schermata "Ospita partita" / "Unisciti a partita",
# versione Cloudflare Quick Tunnel + HTTP (vedi network_manager.gd).

@onready var ip_field: LineEdit = $VBox/IPField
@onready var host_button: Button = $VBox/HostButton
@onready var join_button: Button = $VBox/JoinButton
@onready var status_label: Label = $VBox/StatusLabel

const LEVEL_SCENE := "res://level.tscn"


func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)

	Network.tunnel_ready.connect(_on_tunnel_ready)
	Network.tunnel_failed.connect(_on_tunnel_failed)
	Network.client_connected.connect(_on_client_connected)
	Network.cloudflared_ready.connect(_on_cloudflared_ready)
	Network.cloudflared_install_failed.connect(_on_cloudflared_install_failed)

	_aggiorna_disponibilita_host()


# NUOVO: riflette nello stato del bottone "Ospita partita" se cloudflared è
# già pronto, si sta ancora installando, o non è disponibile
func _aggiorna_disponibilita_host() -> void:
	if Network.cloudflared_available:
		host_button.disabled = false
	elif Network.installing_cloudflared:
		host_button.disabled = true
		status_label.text = "Sto installando 'cloudflared' (solo la prima volta, un momento)..."
	else:
		host_button.disabled = false  # si potrà comunque tentare: start_host() darà l'errore preciso


func _on_cloudflared_ready() -> void:
	host_button.disabled = false
	if status_label.text.begins_with("Sto installando"):
		status_label.text = "Fatto! Puoi ospitare la partita."


func _on_cloudflared_install_failed(reason: String) -> void:
	status_label.text = reason

	_show_local_ip_hint()


# Mostra subito i possibili IP di questo PC (LAN e/o Hamachi/Radmin VPN/
# ZeroTier/Tailscale se attivi) prima ancora di premere "Ospita partita",
# così chi ospita sa già cosa dettare all'altro giocatore.
func _show_local_ip_hint() -> void:
	var hints: Array = Network.get_local_ip_hints()
	if hints.is_empty():
		status_label.text = "Assicurati di essere sulla stessa rete (LAN, Hamachi, Radmin VPN, Tailscale...) dell'altro giocatore."
	else:
		var parts: PackedStringArray = []
		for hint in hints:
			parts.append(hint.describe())
		status_label.text = "I tuoi indirizzi (dai il giusto all'altro giocatore se ospiti):\n%s" % "\n".join(parts)


func _on_host_pressed() -> void:
	var err: Error = Network.start_host()
	if err != OK:
		status_label.text = "Errore nell'apertura del server locale (porta 8080 occupata, o cloudflared non pronto)."
		return
<<<<<<< HEAD
	var hints: Array = Network.get_local_ip_hints()
	if hints.is_empty():
		status_label.text = "In attesa dell'altro giocatore sulla porta %d..." % Network.DEFAULT_PORT
	else:
		var parts: PackedStringArray = []
		for hint in hints:
			parts.append(hint.describe())
		status_label.text = "In attesa dell'altro giocatore... Digli di inserire:\n%s" % "\n".join(parts)
=======
	status_label.text = "Avvio del tunnel Cloudflare in corso..."
>>>>>>> f657b9b75b04dd68f0e75a3570cd245876ca870c
	host_button.disabled = true
	join_button.disabled = true


func _on_tunnel_ready(url: String) -> void:
	ip_field.text = url
	ip_field.editable = false
	status_label.text = "Manda questo link all'altro giocatore, poi aspetta che si colleghi..."


func _on_tunnel_failed(reason: String) -> void:
	status_label.text = reason
	host_button.disabled = false
	join_button.disabled = false


func _on_client_connected() -> void:
	status_label.text = "Giocatore connesso! Avvio partita..."
	GameState.reset_match()
	get_tree().change_scene_to_file(LEVEL_SCENE)


func _on_join_pressed() -> void:
	var url: String = ip_field.text.strip_edges()
	if url.is_empty():
		status_label.text = "Incolla il link mandato da chi ospita."
		return
	Network.start_client(url)
	status_label.text = "Connessione in corso..."
	get_tree().change_scene_to_file(LEVEL_SCENE)

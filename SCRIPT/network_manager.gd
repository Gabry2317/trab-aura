extends Node
# network_manager.gd — Autoload "Network"
#
# Versione HTTP: non usa più ENet/porte del router. L'host apre un piccolo
# server HTTP locale (fatto a mano con TCPServer, Godot non ne ha uno
# pronto) ed espone quella porta su internet lanciando "cloudflared tunnel
# --url" (Cloudflare Quick Tunnel): niente più port forwarding, cloudflared
# assegna un indirizzo pubblico del tipo https://xxxx.trycloudflare.com.
#
# Il client manda i propri tasti con una richiesta POST /input ogni ~33ms
# (30 volte al secondo) e riceve nella risposta lo stato aggiornato di
# entrambi i personaggi (posizione, animazione, vita, stamina, esito round).
#
# REQUISITI:
#  - sul PC che ospita deve essere installato "cloudflared" e disponibile
#    nel PATH (in alternativa, cambia CLOUDFLARED_EXE sotto con il percorso
#    completo dell'eseguibile)
#  - il client non ha bisogno di installare nulla: gli basta l'URL che
#    l'host gli manda (es. via chat)
#
# Aggiungilo come autoload col nome "Network" (Project Settings -> Autoload).

signal tunnel_ready(url: String)       # l'host: l'URL pubblico è pronto, condividilo
signal tunnel_failed(reason: String)   # l'host: cloudflared non è partito
signal client_connected                # l'host: è arrivata la prima richiesta del client
signal snapshot_received                # il client: è arrivata una risposta dall'host
signal cloudflared_ready                        # NUOVO: cloudflared è (già, o ora) installato e pronto
signal cloudflared_install_failed(reason: String)  # NUOVO: non è stato possibile installarlo da soli

const CLOUDFLARED_EXE: String = "cloudflared"  # deve essere nel PATH
const WINGET_PACKAGE_ID: String = "Cloudflare.cloudflared"  # id del pacchetto su winget
const LOCAL_PORT: int = 8080
const POLL_INTERVAL: float = 1.0 / 30.0  # richieste al secondo mandate dal client

var mode: String = ""      # "" | "host" | "client"
var base_url: String = ""  # host: l'URL pubblico assegnato da cloudflared; client: l'URL incollato dall'utente

# NUOVO: true appena sappiamo che cloudflared è presente (dopo il controllo
# a inizio gioco, o dopo un'installazione riuscita tramite winget)
var cloudflared_available: bool = false
var installing_cloudflared: bool = false
var _install_pid: int = -1

# --- stato condiviso letto/scritto dai Player (vedi player.gd) ---
# lato host: l'ultimo stato dei tasti del client (aggiornato a ogni /input ricevuta)
var remote_input: Dictionary = _empty_input()
# lato host: quello che i Player scrivono ogni frame fisico, spedito come
# risposta alla prossima richiesta HTTP del client
var state_snapshot: Dictionary = {}
# lato client: l'ultima risposta ricevuta dall'host, già decodificata da JSON
var last_snapshot: Dictionary = {}

# --- interno lato host: mini server HTTP ---
var _tcp_server: TCPServer
var _connections: Array = []
var _cloudflared_pid: int = -1
var _log_path: String = ""
var _log_check_timer: float = 0.0
var _got_client: bool = false

# --- interno lato client ---
var _http: HTTPRequest
var _request_in_flight: bool = false
var _send_timer: float = 0.0
var _queued_edges: Dictionary = {"jump": false, "attack": false, "secondary": false}


static func _empty_input() -> Dictionary:
	return {"dir": 0.0, "run": false, "jump": false, "attack": false, "block": false, "secondary": false}


# ================================================ INSTALLAZIONE cloudflared =

# NUOVO: al primo avvio del gioco (questo autoload parte subito) controlla se
# cloudflared è già installato; se manca e siamo su Windows, lo installa da
# solo con winget, senza bisogno che l'utente faccia nulla a mano.
func _ready() -> void:
	if _is_cloudflared_installed():
		cloudflared_available = true
		return

	if OS.get_name() != "Windows":
		push_warning("[Network] cloudflared non trovato: su questo sistema va installato a mano (winget esiste solo su Windows).")
		return

	_install_cloudflared_via_winget()


func _is_cloudflared_installed() -> bool:
	var output: Array = []
	var exit_code: int = OS.execute(CLOUDFLARED_EXE, ["--version"], output)
	return exit_code == 0


func _install_cloudflared_via_winget() -> void:
	var log_path: String = OS.get_user_data_dir().path_join("cloudflared_install_log.txt")
	if FileAccess.file_exists(log_path):
		DirAccess.remove_absolute(log_path)

	var cmd: String = "winget install --id %s -e --silent --accept-package-agreements --accept-source-agreements > \"%s\" 2>&1" % [WINGET_PACKAGE_ID, log_path]
	_install_pid = OS.create_process("cmd.exe", PackedStringArray(["/c", cmd]), false)
	if _install_pid == -1:
		var reason: String = "Non riesco ad avviare winget: installa cloudflared a mano da https://github.com/cloudflare/cloudflared/releases"
		push_warning("[Network] " + reason)
		cloudflared_install_failed.emit(reason)
		return

	installing_cloudflared = true
	print("[Network] cloudflared non trovato: lo installo con winget (succede solo la prima volta)...")


# Chiamata da _process ogni frame finché l'installazione è in corso
func _poll_cloudflared_install() -> void:
	if OS.is_process_running(_install_pid):
		return  # ancora in corso

	installing_cloudflared = false
	if _is_cloudflared_installed():
		cloudflared_available = true
		print("[Network] cloudflared installato correttamente.")
		cloudflared_ready.emit()
	else:
		var reason: String = "Non sono riuscito a installare cloudflared automaticamente. Installalo a mano con 'winget install --id %s' da un terminale, oppure da https://github.com/cloudflare/cloudflared/releases" % WINGET_PACKAGE_ID
		push_warning("[Network] " + reason)
		cloudflared_install_failed.emit(reason)


# ============================================================ HOST ==========

func start_host(port: int = LOCAL_PORT) -> Error:
	if not cloudflared_available:
		tunnel_failed.emit("cloudflared non è ancora pronto (installazione in corso o non riuscita): riprova tra poco.")
		return ERR_UNAVAILABLE

	_tcp_server = TCPServer.new()
	var err: Error = _tcp_server.listen(port)
	if err != OK:
		push_error("Impossibile aprire il server locale sulla porta %d (errore %d)" % [port, err])
		return err
	mode = "host"
	_got_client = false
	state_snapshot = {}
	remote_input = _empty_input()
	_launch_cloudflared(port)
	return OK


func _launch_cloudflared(port: int) -> void:
	_log_path = OS.get_user_data_dir().path_join("cloudflared_log.txt")
	if FileAccess.file_exists(_log_path):
		DirAccess.remove_absolute(_log_path)

	var local_url: String = "http://localhost:%d" % port
	var exe: String
	var args: PackedStringArray
	if OS.get_name() == "Windows":
		exe = "cmd.exe"
		args = PackedStringArray(["/c", "%s tunnel --url %s > \"%s\" 2>&1" % [CLOUDFLARED_EXE, local_url, _log_path]])
	else:
		exe = "/bin/sh"
		args = PackedStringArray(["-c", "%s tunnel --url %s > '%s' 2>&1" % [CLOUDFLARED_EXE, local_url, _log_path]])

	_cloudflared_pid = OS.create_process(exe, args, false)
	if _cloudflared_pid == -1:
		tunnel_failed.emit("Non riesco ad avviare '%s': è installato ed è nel PATH?" % CLOUDFLARED_EXE)
		return
	_log_check_timer = 0.0


func _poll_cloudflared_log(delta: float) -> void:
	if base_url != "":
		return
	_log_check_timer += delta
	if _log_check_timer < 0.5:
		return
	_log_check_timer = 0.0
	if not FileAccess.file_exists(_log_path):
		return
	var f: FileAccess = FileAccess.open(_log_path, FileAccess.READ)
	if f == null:
		return
	var text: String = f.get_as_text()
	f.close()
	var rx := RegEx.new()
	rx.compile("https://[a-zA-Z0-9\\-]+\\.trycloudflare\\.com")
	var m: RegExMatch = rx.search(text)
	if m != null:
		base_url = m.get_string()
		tunnel_ready.emit(base_url)


# --- mini server HTTP fatto a mano (Godot non offre un nodo HTTPServer) ---
func _poll_tcp_server() -> void:
	if _tcp_server == null:
		return

	while _tcp_server.is_connection_available():
		var peer: StreamPeerTCP = _tcp_server.take_connection()
		_connections.append({"peer": peer, "buf": PackedByteArray(), "header_end": -1, "content_length": 0, "path": "/"})

	var i: int = _connections.size() - 1
	while i >= 0:
		var c: Dictionary = _connections[i]
		var peer: StreamPeerTCP = c["peer"]
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_connections.remove_at(i)
			i -= 1
			continue

		var avail: int = peer.get_available_bytes()
		if avail > 0:
			var chunk: Array = peer.get_data(avail)
			if chunk[0] == OK:
				var buf: PackedByteArray = c["buf"]
				buf.append_array(chunk[1])
				c["buf"] = buf

		if c["header_end"] == -1:
			var idx: int = _find_double_crlf(c["buf"])
			if idx != -1:
				c["header_end"] = idx
				var header_text: String = c["buf"].slice(0, idx).get_string_from_utf8()
				c["content_length"] = _extract_content_length(header_text)
				c["path"] = _extract_path(header_text)

		if c["header_end"] != -1:
			var body_start: int = c["header_end"] + 4
			var have_body: int = c["buf"].size() - body_start
			if have_body >= c["content_length"]:
				var body: PackedByteArray = c["buf"].slice(body_start, body_start + c["content_length"])
				_handle_request(peer, c["path"], body)
				_connections.remove_at(i)
				i -= 1
				continue

		_connections[i] = c
		i -= 1


func _find_double_crlf(buf: PackedByteArray) -> int:
	var n: int = buf.size() - 3
	for j in range(n):
		if buf[j] == 13 and buf[j + 1] == 10 and buf[j + 2] == 13 and buf[j + 3] == 10:
			return j
	return -1


func _extract_content_length(header_text: String) -> int:
	for line in header_text.split("\r\n"):
		if line.to_lower().begins_with("content-length:"):
			return int(line.split(":")[1].strip_edges())
	return 0


func _extract_path(header_text: String) -> String:
	var first_line: String = header_text.split("\r\n")[0]
	var parts: PackedStringArray = first_line.split(" ")
	return parts[1] if parts.size() >= 2 else "/"


func _handle_request(peer: StreamPeerTCP, path: String, body: PackedByteArray) -> void:
	var status_line: String = "HTTP/1.1 200 OK"
	var response_body: String = "{}"

	if path.begins_with("/input"):
		var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
		if parsed is Dictionary:
			remote_input = parsed
			if not _got_client:
				_got_client = true
				client_connected.emit()
		response_body = JSON.stringify(state_snapshot)
	else:
		status_line = "HTTP/1.1 404 Not Found"

	var body_bytes: PackedByteArray = response_body.to_utf8_buffer()
	var header: String = "%s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [status_line, body_bytes.size()]
	peer.put_data(header.to_utf8_buffer())
	peer.put_data(body_bytes)


# ============================================================ CLIENT ========

func start_client(url: String) -> void:
	base_url = url.strip_edges()
	if base_url.ends_with("/"):
		base_url = base_url.substr(0, base_url.length() - 1)
	mode = "client"
	last_snapshot = {}
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


func _poll_client(delta: float) -> void:
	if Input.is_action_just_pressed("p1_jump"):
		_queued_edges["jump"] = true
	if Input.is_action_just_pressed("p1_attack"):
		_queued_edges["attack"] = true
	if Input.is_action_just_pressed("p1_secondary"):
		_queued_edges["secondary"] = true

	if base_url == "" or _http == null:
		return
	_send_timer += delta
	if _request_in_flight or _send_timer < POLL_INTERVAL:
		return
	_send_timer = 0.0

	var input: Dictionary = {
		"dir": Input.get_axis("p1_left", "p1_right"),
		"run": Input.is_action_pressed("p1_run"),
		"jump": _queued_edges["jump"],
		"attack": _queued_edges["attack"],
		"block": Input.is_action_pressed("p1_secondary"),
		"secondary": _queued_edges["secondary"],
	}
	_queued_edges["jump"] = false
	_queued_edges["attack"] = false
	_queued_edges["secondary"] = false

	var err: Error = _http.request(
		base_url + "/input",
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(input)
	)
	_request_in_flight = err == OK


func _on_request_completed(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_request_in_flight = false
	if code != 200:
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if parsed is Dictionary:
		last_snapshot = parsed
		snapshot_received.emit()


# ============================================================ comune ========

func _process(delta: float) -> void:
	if installing_cloudflared:
		_poll_cloudflared_install()

	match mode:
		"host":
			_poll_cloudflared_log(delta)
			_poll_tcp_server()
		"client":
			_poll_client(delta)


# Da chiamare tornando al menu, o alla fine di una partita
func stop() -> void:
	if _tcp_server != null:
		_tcp_server.stop()
		_tcp_server = null
	for c in _connections:
		(c["peer"] as StreamPeerTCP).disconnect_from_host()
	_connections.clear()
	if _cloudflared_pid != -1:
		OS.kill(_cloudflared_pid)
		_cloudflared_pid = -1
	if _http != null:
		_http.queue_free()
		_http = null
	mode = ""
	base_url = ""
	_got_client = false
	remote_input = _empty_input()
	state_snapshot = {}
	last_snapshot = {}

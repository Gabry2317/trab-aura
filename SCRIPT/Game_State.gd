extends Node

# Emesso quando cambia il player che sta scegliendo il personaggio
signal selection_changed

const PLAYER_COUNT: int = 2

# --- Impostazioni (volume / schermo intero), salvate su disco ---
const SETTINGS_PATH: String = "user://settings.cfg"
var master_volume: float = 1.0  # 0.0 - 1.0
var fullscreen: bool = false


func _ready() -> void:
	_load_settings()
	_apply_settings()


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		master_volume = cfg.get_value("audio", "master_volume", 1.0)
		fullscreen = cfg.get_value("display", "fullscreen", false)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.save(SETTINGS_PATH)


func _apply_settings() -> void:
	var bus_index: int = AudioServer.get_bus_index("Master")
	if bus_index != -1:
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(clampf(master_volume, 0.0, 1.0)))
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	var bus_index: int = AudioServer.get_bus_index("Master")
	if bus_index != -1:
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(master_volume))
	save_settings()


func set_fullscreen(value: bool) -> void:
	fullscreen = value
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)
	save_settings()

# Configurazione multiplayer: una entry per player, letta da player.gd tramite player_id
# device_id: -1 = tastiera P1, -2 = tastiera P2, >=0 = indice pad
var player_configs: Array = [
	{"skin": 0, "device_id": -1},  # player 1: default trab, tastiera schema 1
	{"skin": 1, "device_id": -2},  # player 2: default iacopo, tastiera schema 2
]

# Mantenuta solo come fallback in player.gd (non viene più scritta dai pulsanti)
var selected_skin: int = 0

# Quale player sta scegliendo adesso nella schermata di selezione (0 = P1, 1 = P2)
var selecting_player: int = 0

# --- Punteggio della partita (al meglio di 3 round) ---
const ROUNDS_TO_WIN: int = 2
var round_wins: Array = [0, 0]


# Azzera il punteggio: da chiamare a inizio partita
func reset_match() -> void:
	round_wins = [0, 0]


# Registra la vittoria di un round per player_id. Ritorna true se con
# questo round il player ha vinto la partita (2 round su 3).
func register_round_win(player_id: int) -> bool:
	round_wins[player_id] += 1
	return round_wins[player_id] >= ROUNDS_TO_WIN


func get_skin_for(player_id: int) -> int:
	if player_id < player_configs.size():
		return player_configs[player_id]["skin"]
	return 0


func get_device_for(player_id: int) -> int:
	if player_id < player_configs.size():
		return player_configs[player_id]["device_id"]
	return -1


func set_player_config(player_id: int, skin: int, device_id: int) -> void:
	while player_configs.size() <= player_id:
		player_configs.append({"skin": 0, "device_id": -1})
	player_configs[player_id] = {"skin": skin, "device_id": device_id}


# Da chiamare quando si entra nella schermata di selezione
func start_selection() -> void:
	reset_match()
	selecting_player = 0
	selection_changed.emit()


# Chiamata dai pulsanti: assegna la skin al player di turno, poi passa al successivo
func choose_skin(skin: int) -> void:
	set_player_config(selecting_player, skin, get_device_for(selecting_player))
	selecting_player += 1
	if selecting_player >= PLAYER_COUNT:
		get_tree().change_scene_to_file("res://level.tscn")
	else:
		selection_changed.emit()

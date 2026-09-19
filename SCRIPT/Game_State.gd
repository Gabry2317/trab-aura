extends Node

# Emesso quando cambia il player che sta scegliendo il personaggio
signal selection_changed

const PLAYER_COUNT: int = 2

# Configurazione multiplayer: una entry per player, letta da hit.gd tramite player_id
# device_id: -1 = tastiera P1, -2 = tastiera P2, >=0 = indice pad
var player_configs: Array = [
	{"skin": 0, "device_id": -1},  # player 1: default trab, tastiera schema 1
	{"skin": 1, "device_id": -2},  # player 2: default iacopo, tastiera schema 2
]

# Mantenuta solo come fallback in hit.gd (non viene più scritta dai pulsanti)
var selected_skin: int = 0

# Quale player sta scegliendo adesso nella schermata di selezione (0 = P1, 1 = P2)
var selecting_player: int = 0


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

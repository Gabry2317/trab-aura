extends CanvasLayer

@onready var titolo: Label = $Contenitore/Titolo
@onready var punteggio: Label = $Contenitore/Punteggio
@onready var rigioca: Button = $Contenitore/Rigioca
@onready var menu: Button = $Contenitore/Menu


func _ready() -> void:
	rigioca.pressed.connect(_on_rigioca_pressed)
	menu.pressed.connect(_on_menu_pressed)


# vincitore: 0 = player 1, 1 = player 2
# match_finito: true se questo round chiude la partita (al meglio di 3)
func mostra(vincitore: int, match_finito: bool) -> void:
	punteggio.text = "Round: %d - %d" % [GameState.round_wins[0], GameState.round_wins[1]]
	visible = true
	get_tree().paused = true  # ferma player e animazioni, questo menu continua a funzionare

	if match_finito:
		titolo.text = "Player %d vince la partita!" % (vincitore + 1)
		rigioca.visible = true
		menu.visible = true

		# per un secondo i pulsanti sono disattivati, così un clic o uno spazio
		# dati durante l'ultimo colpo non fanno ripartire subito la partita
		rigioca.disabled = true
		menu.disabled = true
		await get_tree().create_timer(1.0).timeout
		rigioca.disabled = false
		menu.disabled = false
	else:
		# round vinto ma partita ancora aperta: si mostra solo il messaggio
		# e si passa da soli al round successivo, senza bisogno di cliccare
		titolo.text = "Player %d vince il round!" % (vincitore + 1)
		rigioca.visible = false
		menu.visible = false

		await get_tree().create_timer(1.5).timeout
		get_tree().paused = false
		get_tree().reload_current_scene()  # stessi personaggi, round successivo


# Tempo scaduto e salute identica: nessuno vince il round, si rigioca lo stesso round
func mostra_pareggio() -> void:
	punteggio.text = "Round: %d - %d" % [GameState.round_wins[0], GameState.round_wins[1]]
	titolo.text = "Tempo scaduto: pareggio!"
	rigioca.visible = false
	menu.visible = false
	visible = true
	get_tree().paused = true

	await get_tree().create_timer(1.5).timeout
	get_tree().paused = false
	get_tree().reload_current_scene()  # si rigioca lo stesso round, punteggio invariato


func _on_rigioca_pressed() -> void:
	GameState.reset_match()
	get_tree().paused = false
	get_tree().reload_current_scene()  # stessi personaggi di prima


func _on_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://ui_unificata.tscn")

extends CanvasLayer

@onready var titolo: Label = $Contenitore/Titolo
@onready var rigioca: Button = $Contenitore/Rigioca
@onready var menu: Button = $Contenitore/Menu


func _ready() -> void:
	rigioca.pressed.connect(_on_rigioca_pressed)
	menu.pressed.connect(_on_menu_pressed)


# vincitore: 0 = player 1, 1 = player 2
func mostra(vincitore: int) -> void:
	titolo.text = "Player %d vince!" % (vincitore + 1)
	visible = true
	get_tree().paused = true  # ferma player e animazioni, questo menu continua a funzionare

	# per un secondo i pulsanti sono disattivati, così un clic o uno spazio
	# dati durante l'ultimo colpo non fanno ripartire subito la partita
	rigioca.disabled = true
	menu.disabled = true
	await get_tree().create_timer(1.0).timeout
	rigioca.disabled = false
	menu.disabled = false


func _on_rigioca_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()  # stessi personaggi di prima


func _on_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://menu.tscn")

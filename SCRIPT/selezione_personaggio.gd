extends Node2D

@onready var label: Label = $Label
@onready var cursore: ColorRect = $Cursore

@onready var anteprima_p1: Sprite2D = $AnteprimaP1
@onready var anteprima_p2: Sprite2D = $AnteprimaP2

@onready var bisio_btn: Button = $bisio
@onready var tommaso_btn: Button = $tommaso
@onready var nakakata_btn: Button = $nakakata
@onready var andrix_btn: Button = $andrix

# 0 = trab, 1 = iacopo, 2 = naka
const PREVIEW_TEXTURES := {
	0: preload("res://sprite/Player/proppick/WND_trab_bigprop.png"),
	1: preload("res://sprite/Player/proppick/IACOBISIO_bigprop.png"),
	2: preload("res://sprite/Player/proppick/NAKAKATA_BIG_PRPO.png"),
	3: preload("res://sprite/Player/proppick/andrix_bigprop.png"),
}
# scala per uniformare l'altezza delle 3 immagini (le sorgenti hanno dimensioni diverse)
const PREVIEW_SCALE := {
	0: 1.0,
	1: 1.2528716,
	2: 0.45,
	3: 0.4,
}

# ordine visivo sinistra -> destra dei personaggi selezionabili
var slots: Array = []
var cursor_index: int = 0


func _ready() -> void:
	slots = [
		{"skin": 1, "btn": bisio_btn},
		{"skin": 0, "btn": tommaso_btn},
		{"skin": 2, "btn": nakakata_btn},
		{"skin": 3, "btn": andrix_btn},
	]

	# il mouse continua a funzionare: passandoci sopra sposta anche il cursore a freccette
	bisio_btn.mouse_entered.connect(_hover_to.bind(0))
	tommaso_btn.mouse_entered.connect(_hover_to.bind(1))
	nakakata_btn.mouse_entered.connect(_hover_to.bind(2))
	andrix_btn.mouse_entered.connect(_hover_to.bind(3))

	GameState.selection_changed.connect(_refresh)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left"):
		cursor_index = (cursor_index - 1 + slots.size()) % slots.size()
		_update_cursor()
	elif event.is_action_pressed("ui_right"):
		cursor_index = (cursor_index + 1) % slots.size()
		_update_cursor()
	elif event.is_action_pressed("ui_accept"):
		GameState.choose_skin(slots[cursor_index].skin)


func _hover_to(index: int) -> void:
	cursor_index = index
	_update_cursor()


func _refresh() -> void:
	# se il player 1 ha già scelto, "congela" la sua anteprima sul personaggio scelto
	# (indipendentemente dal fatto che abbia confermato con mouse o tastiera)
	if GameState.selecting_player >= 1:
		_freeze_preview(anteprima_p1, GameState.get_skin_for(0), false)

	# l'anteprima del player 2 resta vuota finché non è davvero il suo turno,
	# così non si vede nessun personaggio prima che inizi a scegliere
	anteprima_p2.visible = GameState.selecting_player >= 1

	label.text = "Player %d: scegli il personaggio" % (GameState.selecting_player + 1)
	cursor_index = 0
	_update_cursor()


func _update_cursor() -> void:
	var pulsante: Button = slots[cursor_index].btn
	cursore.position = pulsante.position - Vector2(6, 6)
	cursore.size = pulsante.size + Vector2(12, 12)
	_aggiorna_anteprima_live(slots[cursor_index].skin)


func _aggiorna_anteprima_live(skin: int) -> void:
	# anteprima a sinistra per il player 1, a destra (specchiata) per il player 2
	var e_player_2: bool = GameState.selecting_player == 1
	var anteprima: Sprite2D = anteprima_p2 if e_player_2 else anteprima_p1
	_freeze_preview(anteprima, skin, e_player_2)


func _freeze_preview(anteprima: Sprite2D, skin: int, specchiata: bool) -> void:
	anteprima.texture = PREVIEW_TEXTURES[skin]
	var s: float = PREVIEW_SCALE[skin]
	anteprima.scale = Vector2(-s, s) if specchiata else Vector2(s, s)

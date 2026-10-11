extends Control
## Logica del selettore mappa. La UI sta nella scena (nodo SelezioneMappa).
## P1 vota, P2 vota -> estrazione tra i 2 voti. Se esce RANDOM -> una delle 7 a caso.

signal mappa_scelta(mappa: Dictionary)

# ───── CONFIGURAZIONE ─────
const MAPPE := [
	{"nome": "Mappa 1", "background": "res://sprite/Maps/bg1.png", "tilemap": "res://scenes/maps/mappa1.tscn", "musica": "res://sound/Music/mappa1.mp3"},
	{"nome": "Mappa 2", "background": "res://sprite/Maps/bg2.png", "tilemap": "res://scenes/maps/mappa2.tscn", "musica": "res://sound/Music/mappa2.mp3"},
	{"nome": "Mappa 3", "background": "res://sprite/Maps/bg3.png", "tilemap": "res://scenes/maps/mappa3.tscn", "musica": "res://sound/Music/mappa3.mp3"},
	{"nome": "Mappa 4", "background": "res://sprite/Maps/bg4.png", "tilemap": "res://scenes/maps/mappa4.tscn", "musica": "res://sound/Music/mappa4.mp3"},
	{"nome": "Mappa 5", "background": "res://sprite/Maps/bg5.png", "tilemap": "res://scenes/maps/mappa5.tscn", "musica": "res://sound/Music/mappa5.mp3"},
	{"nome": "Mappa 6", "background": "res://sprite/Maps/bg6.png", "tilemap": "res://scenes/maps/mappa6.tscn", "musica": "res://sound/Music/mappa6.mp3"},
	{"nome": "Mappa 7", "background": "res://sprite/Maps/bg7.png", "tilemap": "res://scenes/maps/mappa7.tscn", "musica": "res://sound/Music/mappa7.mp3"},
]
const RITARDO_RISULTATO := 1.5
const COLORE_P1 := Color(1, 0.85, 0.2)
const COLORE_P2 := Color(0.4, 0.8, 1)
# ──────────────────────────

const RANDOM_ID := -1

@onready var _titolo: Label = $Titolo
@onready var _griglia: GridContainer = $Griglia

var _voti: Array[int] = []
var _bloccato := false


func _ready() -> void:
	# i primi 7 bottoni = mappe, l'ultimo = random
	var bottoni := _griglia.get_children()
	for i in bottoni.size():
		var id := i if i < MAPPE.size() else RANDOM_ID
		bottoni[i].pressed.connect(_on_voto.bind(id, bottoni[i]))
	visibility_changed.connect(func(): if visible: reset())


func reset() -> void:
	_voti.clear()
	_bloccato = false
	for b in _griglia.get_children():
		b.modulate = Color.WHITE
	_titolo.text = "Giocatore 1: scegli la mappa"


func _on_voto(id: int, btn: Button) -> void:
	if _bloccato:
		return
	_voti.append(id)
	btn.modulate = COLORE_P1 if _voti.size() == 1 else COLORE_P2
	if _voti.size() < 2:
		_titolo.text = "Giocatore 2: scegli la mappa"
		return
	_bloccato = true
	_concludi()


func _concludi() -> void:
	var scelto: int = _voti.pick_random()
	if scelto == RANDOM_ID:
		scelto = randi() % MAPPE.size()
	var mappa: Dictionary = MAPPE[scelto].duplicate()
	mappa["indice"] = scelto
	_titolo.text = "Mappa estratta: %s" % mappa["nome"]
	await get_tree().create_timer(RITARDO_RISULTATO).timeout
	mappa_scelta.emit(mappa)


# Da chiamare nella scena di gioco: bg = TextureRect/Sprite2D, tilemap_parent = Node, musica = AudioStreamPlayer
static func applica_mappa(mappa: Dictionary, bg: Node, tilemap_parent: Node, musica: AudioStreamPlayer) -> void:
	if ResourceLoader.exists(mappa["background"]):
		bg.texture = load(mappa["background"])
	for c in tilemap_parent.get_children():
		c.queue_free()
	if ResourceLoader.exists(mappa["tilemap"]):
		tilemap_parent.add_child(load(mappa["tilemap"]).instantiate())
	if ResourceLoader.exists(mappa["musica"]):
		musica.stream = load(mappa["musica"])
		musica.play()

class_name Player
extends CharacterBody2D

signal health_changed  # <-- serve per healt_bar.gd
signal died(player)  # emesso una sola volta quando la vita arriva a 0 (lo ascolta level.gd)

# --- Statistiche: si modificano in res://data/fighters.cfg, NON qui ---
# (i valori scritti qui sono solo il fallback se il file manca o una chiave non c'è)
var max_health: int = 100
var current_health: int = 100
var attack_damage: int = 10
var attack_delay: float = 0.3  # secondi tra la pressione del tasto e il colpo vero e proprio
var speed: float = 100.0
var run_speed: float = 250.0
var attack_move_speed: float = 10.0
var jump_velocity: float = -300.0
var can_run: bool = true

# --- feedback dei colpi (vedi _play_hit_feedback) ---
var hit_knockback: float = 220.0       # rinculo: velocita' orizzontale della spinta subita
var hit_stun_duration: float = 0.25    # stordimento: per quanti secondi non si risponde ai comandi
var hit_flash_duration: float = 0.12   # per quanti secondi lo sprite resta colorato dopo il colpo
var hit_flash_color: Color = Color(1.0, 0.35, 0.35, 1.0)  # colore del lampo (default: rossastro)
var hit_sound: AudioStream = null      # caricato da hit_sound in fighters.cfg

# --- sangue quando si prende danno (vedi _spawn_blood) ---
var blood_amount: int = 18             # quante particelle per colpo (0 = nessun sangue)
var blood_color: Color = Color(0.75, 0.03, 0.03, 1.0)
var blood_lifetime: float = 0.6        # durata delle particelle (secondi)
var blood_speed_min: float = 60.0
var blood_speed_max: float = 180.0

# --- blocco (guardia): tasti p1_secondary / p2_secondary ---
var block_damage_reduction: float = 0.3  # % di danno ancora subita mentre si blocca (0 = blocco perfetto)

# --- attacco secondario "gancio" (solo iacopo: vedi secondary_attack in fighters.cfg) ---
# sullo stesso tasto "secondary": per chi ha secondary_attack = true quel tasto
# non blocca piu', ma carica/lancia questa mossa (vedi _process_secondary_attack)
var has_secondary_attack: bool = false
var secondary_damage: int = 15
var secondary_range: float = 2000.0        # lunghezza della catena: deve coprire tutta la mappa
var secondary_height: float = 36.0         # altezza dell'area colpita: bassa, per poterla schivare saltando
var secondary_ground_offset: float = 80.0  # quanto in basso rispetto al centro del player (vicino ai piedi)
var secondary_release_delay: float = 0.35  # ritardo tra il rilascio del tasto e l'attivazione del "gancio"
var secondary_hit_delay: float = 0.25      # da quando parte "gancio" a quando la catena e' a piena estensione
var secondary_hit_window: float = 0.15     # per quanti secondi la catena estesa fa danno
var secondary_sheet: String = ""           # foglio sprite del portale/gancio (es. big_chains.png)
var secondary_sheet_hframes: int = 1
var secondary_sheet_vframes: int = 1
var secondary_portal_frames: int = 1       # primi N fotogrammi del foglio = animazione "portale" (loop)

enum SecondaryState {IDLE, CHARGE, WAIT, REACH, STRIKE, COOLDOWN}
var _sec_state: SecondaryState = SecondaryState.IDLE
var _sec_timer: float = 0.0
var _secondary_sprite: AnimatedSprite2D
var _secondary_hitbox: Hitbox

# --- NUOVO: identità e schema di controllo del player ---
@export var player_id: int = 0
# device_id:
#   -1 = tastiera Player 1 (azioni p1_*)
#   -2 = tastiera Player 2 (azioni p2_*)
#   >=0 = indice del pad (letto via codice, es. Input.get_connected_joypads()[0])
@export var device_id: int = -1
# skin_override: -1 = usa GameState, altrimenti forza la skin per questo player
@export var skin_override: int = -1

var isHurt: bool = false  # true mentre dura lo stordimento da colpo subito (vedi hurt_stun_left)
var isAttacking: bool = false
var hitbox_delay_left: float = 0.0  # secondi che mancano all'attivazione della hitbox
var hurt_stun_left: float = 0.0  # secondi di stordimento rimanenti dopo un colpo subito
var is_blocking: bool = false  # true mentre il player tiene premuto il tasto "secondary"

@onready var hit_sfx: AudioStreamPlayer = AudioStreamPlayer.new()  # riprodotto a ogni colpo subito

const FIGHTERS_PATH := "res://data/fighters.cfg"
static var _cfg: ConfigFile
# elenco dei personaggi: letto direttamente da fighters.cfg (tutte le sezioni
# tranne [base]), nell'ordine in cui compaiono nel file. L'indice = skin.
# Per aggiungere un personaggio nuovo basta aggiungere una sezione al file:
# questo script non va toccato.
static var _fighter_names: Array = []

var skin: int = 0
var fighter_name: String = ""  # nome della sezione in fighters.cfg per la skin attuale

@onready var chain_sprite: AnimatedSprite2D = $Iaco_Spto/Chain  # arma speciale di iacopo
@onready var hurtbox: Hurtbox = $Hurtbox

# sprite e hitbox di ogni personaggio, indicizzati per nome (vedi _ready):
# se il nodo esiste gia' in scena (personaggio disegnato a mano) viene
# riusato, altrimenti viene costruito a runtime dai dati in fighters.cfg
var _sprites: Dictionary = {}
var _hitboxes: Dictionary = {}

var current_sprite: AnimatedSprite2D
var current_hitbox: Hitbox
var chain_base_x: float

# --- dimensioni sprite ---
# scala dello sprite cosi' come e' impostata nella scena (WND_trab.tscn):
# e' il riferimento, model_scale di fighters.cfg la moltiplica soltanto
var _base_scale: Vector2 = Vector2.ONE
var _model_scale: float = 1.0
# altezza (px) del fotogramma idle: tutte le altre animazioni vengono
# riscalate per apparire grandi quanto l'idle
var _idle_frame_height: float = 0.0
var current_hitbox_shape: CollisionShape2D  # shape della hitbox attiva (viene specchiata)
var hitbox_base_x: float  # X originale della shape (in editor)


func _enter_tree() -> void:
	# skin e statistiche si decidono qui, prima di qualsiasi _ready():
	# così la barra della vita legge già il max_health giusto
	# se skin_override non è impostato, usa la config del GameState per questo player_id
	if skin_override != -1:
		skin = skin_override
	elif GameState.has_method("get_skin_for"):
		skin = GameState.get_skin_for(player_id)
	else:
		skin = GameState.selected_skin  # fallback compatibile col vecchio sistema

	var fighters: Array = _get_fighter_names()
	if skin < 0 or skin >= fighters.size():
		push_warning("Skin non valida: %s" % skin)
		skin = 0
	fighter_name = fighters[skin]

	_load_stats()


# --- Lettura di res://data/fighters.cfg ---
static func _get_cfg() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		var err: int = _cfg.load(FIGHTERS_PATH)
		if err != OK:
			push_warning("fighters.cfg non caricato (errore %d): uso i valori di default" % err)
	return _cfg


# Elenco dei personaggi = sezioni del file (tranne [base]), nell'ordine in
# cui compaiono. Calcolato una sola volta e condiviso da tutti i Player.
static func _get_fighter_names() -> Array:
	if _fighter_names.is_empty():
		for section in _get_cfg().get_sections():
			if section != "base":
				_fighter_names.append(section)
	return _fighter_names


# Cerca la chiave nella sezione del personaggio, poi in [base], poi usa il fallback
func _stat(key: String, fallback: Variant) -> Variant:
	var cfg: ConfigFile = _get_cfg()
	if fighter_name != "" and cfg.has_section_key(fighter_name, key):
		return cfg.get_value(fighter_name, key)
	return cfg.get_value("base", key, fallback)


# Costruisce a runtime un AnimatedSprite2D per un personaggio che non ha
# ancora un nodo pronto nella scena: legge da fighters.cfg i fogli sprite
# (spritesheet, un quadrato di model_frame_size px per fotogramma) e li
# affetta in animazioni idle/walk/run/hit.
func _build_dynamic_sprite(fighter: String, node_name: String) -> AnimatedSprite2D:
	var cfg: ConfigFile = _get_cfg()
	var sprite := AnimatedSprite2D.new()
	sprite.name = node_name

	var frame_size: int = int(cfg.get_value(fighter, "model_frame_size", 256))
	var frames := SpriteFrames.new()
	frames.remove_animation("default")

	for anim in ["idle", "walk", "run", "hit", "hurt"]:
		var sheet_path: String = cfg.get_value(fighter, "model_sheet_%s" % anim, "")
		if sheet_path == "":
			continue  # questo personaggio non ha un foglio per questa animazione

		var texture: Texture2D = load(sheet_path)
		var hframes: int = int(cfg.get_value(fighter, "model_hframes_%s" % anim, 1))
		var vframes: int = int(cfg.get_value(fighter, "model_vframes_%s" % anim, 1))
		var frame_count: int = int(cfg.get_value(fighter, "model_frames_%s" % anim, hframes * vframes))

		frames.add_animation(anim)
		frames.set_animation_loop(anim, anim != "hit" and anim != "hurt")  # "hit" e "hurt" non vanno in loop
		frames.set_animation_speed(anim, 10.0)

		var added: int = 0
		for row in range(vframes):
			for col in range(hframes):
				if added >= frame_count:
					break
				var atlas := AtlasTexture.new()
				atlas.atlas = texture
				atlas.region = Rect2(col * frame_size, row * frame_size, frame_size, frame_size)
				frames.add_frame(anim, atlas)
				added += 1

	sprite.sprite_frames = frames
	sprite.animation = "idle"
	return sprite


# Trova lo sprite del personaggio se esiste gia' in scena (personaggio
# disegnato a mano nell'editor, con animazioni proprie); altrimenti lo
# costruisce a runtime dai dati di fighters.cfg. Cosi' un personaggio nuovo
# senza nodo in scena funziona comunque, senza toccare questo script.
func _get_or_build_sprite(fighter: String) -> AnimatedSprite2D:
	var cfg: ConfigFile = _get_cfg()
	var node_name: String = str(cfg.get_value(fighter, "model_node", fighter + "_Sprite"))

	var existing: Node = get_node_or_null(node_name)
	if existing is AnimatedSprite2D:
		return existing
	if existing != null:
		push_warning("'%s' esiste ma non e' un AnimatedSprite2D: lo ignoro e ne costruisco uno nuovo per %s" % [node_name, fighter])
	elif get_node_or_null(node_name.to_lower()) != null or get_node_or_null(node_name.to_upper()) != null:
		# I nomi dei nodi in Godot fanno differenza tra maiuscole e minuscole:
		# se esiste un nodo con lo stesso nome ma maiuscole/minuscole diverse,
		# molto probabilmente e' un refuso in model_node dentro fighters.cfg.
		# In tal caso quel nodo NON viene ne' usato ne' nascosto, e resta
		# visibile per sbaglio sopra al personaggio giusto.
		push_warning("model_node '%s' per %s non trovato per esatta corrispondenza di maiuscole/minuscole: controlla il nome del nodo in scena o la chiave model_node in fighters.cfg" % [node_name, fighter])

	var built: AnimatedSprite2D = _build_dynamic_sprite(fighter, node_name)
	add_child(built)  # gli sprite gia' in scena ci sono di default, questi vanno aggiunti a mano
	return built


# Trova la hitbox del pugno del personaggio se esiste gia' sotto il suo
# sprite; altrimenti ne crea una copiando hitbox_template_node e applicando
# gli eventuali hitbox_offset_x/y, hitbox_width/height da fighters.cfg.
func _get_or_build_hitbox(fighter: String, sprite: AnimatedSprite2D) -> Hitbox:
	var cfg: ConfigFile = _get_cfg()
	var hitbox_node_name: String = str(_stat_of(fighter, "hitbox_node", "PunchHitbox"))

	var existing: Node = sprite.get_node_or_null(hitbox_node_name)
	if existing is Hitbox:
		return existing

	var template_path: String = str(cfg.get_value("base", "hitbox_template_node", "TRAB_Sprite2D/PunchHitbox"))
	var template: Node = get_node_or_null(template_path)
	if not (template is Hitbox):
		push_warning("hitbox_template_node '%s' non trovata: %s non avra' una hitbox" % [template_path, fighter])
		return null

	var hitbox: Hitbox = template.duplicate()
	hitbox.name = hitbox_node_name.get_file()  # se hitbox_node e' un percorso tipo "Chain/PunchHitbox"
	sprite.add_child(hitbox)

	var shape_node: CollisionShape2D = hitbox.get_node("CollisionShape2D")
	shape_node.position = Vector2(
		float(cfg.get_value(fighter, "hitbox_offset_x", shape_node.position.x)),
		float(cfg.get_value(fighter, "hitbox_offset_y", shape_node.position.y))
	)

	if cfg.has_section_key(fighter, "hitbox_width") or cfg.has_section_key(fighter, "hitbox_height"):
		var shape: Shape2D = shape_node.shape
		if shape is RectangleShape2D:
			var new_shape: RectangleShape2D = shape.duplicate()
			new_shape.size = Vector2(
				float(cfg.get_value(fighter, "hitbox_width", shape.size.x)),
				float(cfg.get_value(fighter, "hitbox_height", shape.size.y))
			)
			shape_node.shape = new_shape

	return hitbox


# Costruisce (se secondary_sheet e' impostato per questo personaggio) lo sprite
# del portale/gancio: stesso principio di _build_dynamic_sprite, ma i primi
# secondary_portal_frames fotogrammi del foglio diventano l'animazione "portale"
# (in loop, mostrata mentre si carica) e il resto l'animazione "gancio" (una
# volta sola, mostrata quando si rilascia il tasto). Il foglio e' pensato in
# verticale (la catena cresce verso il basso): lo sprite viene ruotato di 90°
# a runtime per farla crescere in orizzontale (vedi _fire_secondary_attack).
func _build_secondary_sprite() -> AnimatedSprite2D:
	if secondary_sheet == "":
		return null

	var texture: Texture2D = load(secondary_sheet)
	if texture == null:
		push_warning("secondary_sheet '%s' non trovato: niente attacco secondario per %s" % [secondary_sheet, fighter_name])
		return null

	var hframes: int = maxi(secondary_sheet_hframes, 1)
	var vframes: int = maxi(secondary_sheet_vframes, 1)
	var total_frames: int = hframes * vframes
	var portal_frames: int = clampi(secondary_portal_frames, 1, total_frames)

	var cell_w: float = texture.get_width() / float(hframes)
	var cell_h: float = texture.get_height() / float(vframes)

	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("portale")
	frames.set_animation_loop("portale", true)
	frames.set_animation_speed("portale", 4.0)
	frames.add_animation("gancio")
	frames.set_animation_loop("gancio", false)
	frames.set_animation_speed("gancio", 14.0)

	var idx: int = 0
	for row in range(vframes):
		for col in range(hframes):
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(col * cell_w, row * cell_h, cell_w, cell_h)
			frames.add_frame("portale" if idx < portal_frames else "gancio", atlas)
			idx += 1

	var sprite := AnimatedSprite2D.new()
	sprite.name = "SecondaryChain"
	sprite.sprite_frames = frames
	# non centrato: l'origine (0,0) resta sul portale (in cima al foglio), cosi'
	# la catena si allunga a partire da li' invece che dal centro del fotogramma
	sprite.centered = false
	sprite.offset = Vector2(-cell_w / 2.0, 0.0)
	# il foglio e' ~cell_w x cell_h px: lo scaliamo perche' a piena estensione
	# (asse Y locale, che dopo la rotazione diventa l'orizzontale) la catena
	# arrivi esattamente a secondary_range, ed sia spessa secondary_height
	sprite.scale = Vector2(secondary_height / cell_w, secondary_range / cell_h)
	sprite.visible = false
	sprite.z_index = -1  # dietro al personaggio, come la Chain di iacopo
	return sprite


# Costruisce la hitbox (bassa e lunga) dell'attacco secondario, copiando lo
# stesso template usato per il pugno (cosi' eredita layer/mask corretti) e
# sostituendone solo la forma. Resta disabilitata finche' non si colpisce
# (vedi _fire_secondary_attack / _process_secondary_attack).
func _build_secondary_hitbox() -> Hitbox:
	var cfg: ConfigFile = _get_cfg()
	var template_path: String = str(cfg.get_value("base", "hitbox_template_node", "TRAB_Sprite2D/PunchHitbox"))
	var template: Node = get_node_or_null(template_path)
	if not (template is Hitbox):
		push_warning("hitbox_template_node '%s' non trovata: %s non avra' l'attacco secondario" % [template_path, fighter_name])
		return null

	var hitbox: Hitbox = template.duplicate()
	hitbox.name = "SecondaryHitbox"
	add_child(hitbox)
	hitbox.damage = secondary_damage
	hitbox.source = self

	var shape_node: CollisionShape2D = hitbox.get_node("CollisionShape2D")
	shape_node.position = Vector2.ZERO
	var new_shape := RectangleShape2D.new()
	new_shape.size = Vector2(secondary_range, secondary_height)
	shape_node.shape = new_shape
	shape_node.disabled = true

	return hitbox


# Come _stat(), ma per un personaggio qualsiasi (non necessariamente quello
# di questa istanza) - usata quando serve leggere dati prima che fighter_name
# sia impostato per il personaggio in questione.
func _stat_of(fighter: String, key: String, fallback: Variant) -> Variant:
	var cfg: ConfigFile = _get_cfg()
	if cfg.has_section_key(fighter, key):
		return cfg.get_value(fighter, key)
	return cfg.get_value("base", key, fallback)


func _load_stats() -> void:
	max_health = int(_stat("max_health", max_health))
	current_health = max_health
	attack_damage = int(_stat("attack_damage", attack_damage))
	attack_delay = float(_stat("attack_delay", attack_delay))
	speed = float(_stat("speed", speed))
	run_speed = float(_stat("run_speed", run_speed))
	attack_move_speed = float(_stat("attack_move_speed", attack_move_speed))
	jump_velocity = float(_stat("jump_velocity", jump_velocity))
	can_run = bool(_stat("can_run", can_run))

	hit_knockback = float(_stat("hit_knockback", hit_knockback))
	hit_stun_duration = float(_stat("hit_stun_duration", hit_stun_duration))
	hit_flash_duration = float(_stat("hit_flash_duration", hit_flash_duration))
	hit_flash_color = _stat("hit_flash_color", hit_flash_color)
	var hit_sound_path: String = str(_stat("hit_sound", ""))
	hit_sound = load(hit_sound_path) if hit_sound_path != "" else null

	blood_amount = int(_stat("blood_amount", blood_amount))
	blood_color = _stat("blood_color", blood_color)
	blood_lifetime = float(_stat("blood_lifetime", blood_lifetime))
	blood_speed_min = float(_stat("blood_speed_min", blood_speed_min))
	blood_speed_max = float(_stat("blood_speed_max", blood_speed_max))

	block_damage_reduction = clampf(float(_stat("block_damage_reduction", block_damage_reduction)), 0.0, 1.0)

	has_secondary_attack = bool(_stat("secondary_attack", has_secondary_attack))
	secondary_damage = int(_stat("secondary_damage", secondary_damage))
	secondary_range = float(_stat("secondary_range", secondary_range))
	secondary_height = float(_stat("secondary_height", secondary_height))
	secondary_ground_offset = float(_stat("secondary_ground_offset", secondary_ground_offset))
	secondary_release_delay = float(_stat("secondary_release_delay", secondary_release_delay))
	secondary_hit_delay = float(_stat("secondary_hit_delay", secondary_hit_delay))
	secondary_hit_window = float(_stat("secondary_hit_window", secondary_hit_window))
	secondary_sheet = str(_stat("secondary_sheet", secondary_sheet))
	secondary_sheet_hframes = int(_stat("secondary_sheet_hframes", secondary_sheet_hframes))
	secondary_sheet_vframes = int(_stat("secondary_sheet_vframes", secondary_sheet_vframes))
	secondary_portal_frames = int(_stat("secondary_portal_frames", secondary_portal_frames))


func _ready() -> void:
	hurtbox.damaged.connect(_on_damaged)

	hit_sfx.name = "HitSfx"
	hit_sfx.bus = "Master"
	add_child(hit_sfx)

	var fighters: Array = _get_fighter_names()

	for fighter in fighters:
		var sprite: AnimatedSprite2D = _get_or_build_sprite(fighter)
		sprite.visible = false
		_sprites[fighter] = sprite
		sprite.animation_finished.connect(_on_animation_finished)

		var hitbox: Hitbox = _get_or_build_hitbox(fighter, sprite)
		if hitbox:
			_set_hitbox_disabled(hitbox, true)
			hitbox.damage = attack_damage
			hitbox.source = self
		_hitboxes[fighter] = hitbox

	chain_sprite.visible = false
	chain_base_x = chain_sprite.position.x
	chain_sprite.animation_finished.connect(_on_chain_animation_finished)

	if has_secondary_attack:
		_secondary_sprite = _build_secondary_sprite()
		if _secondary_sprite:
			add_child(_secondary_sprite)
		_secondary_hitbox = _build_secondary_hitbox()

	current_sprite = _sprites[fighter_name]
	current_sprite.visible = true
	current_hitbox = _hitboxes[fighter_name]

	current_hitbox_shape = current_hitbox.get_node("CollisionShape2D")
	hitbox_base_x = current_hitbox_shape.position.x

	# la scala impostata in scena (es. Naka 0.74 x 0.94, Andrix 1.2 x 1.11) va
	# mantenuta: model_scale in fighters.cfg la moltiplica (1.0 = misura della scena).
	# In piu' ogni animazione viene portata alla stessa dimensione dell'idle.
	_base_scale = current_sprite.scale
	_model_scale = float(_stat("model_scale", 1.0))
	_idle_frame_height = _get_frame_height(current_sprite, &"idle", 0)
	current_sprite.animation_changed.connect(_update_sprite_scale)
	current_sprite.frame_changed.connect(_update_sprite_scale)
	_update_sprite_scale()

	# il player 2 parte specchiato: guarda a sinistra, verso il player 1
	_set_facing(player_id == 1)


# Altezza in pixel di un fotogramma di un'animazione (0.0 se non esiste)
func _get_frame_height(sprite: AnimatedSprite2D, anim: StringName, frame: int) -> float:
	var frames: SpriteFrames = sprite.sprite_frames
	if frames == null or not frames.has_animation(anim):
		return 0.0
	if frame < 0 or frame >= frames.get_frame_count(anim):
		return 0.0
	var tex: Texture2D = frames.get_frame_texture(anim, frame)
	return tex.get_size().y if tex != null else 0.0


# Scala dello sprite = scala della scena * model_scale * (altezza idle / altezza
# del fotogramma attuale): cosi' walk, run, hit... hanno la stessa grandezza dell'idle
func _update_sprite_scale() -> void:
	var factor: float = 1.0
	var frame_h: float = _get_frame_height(current_sprite, current_sprite.animation, current_sprite.frame)
	if frame_h > 0.0 and _idle_frame_height > 0.0:
		factor = _idle_frame_height / frame_h
	current_sprite.scale = _base_scale * _model_scale * factor
	# la hitbox e' figlia dello sprite: compensa il fattore cosi' la portata del
	# pugno non cambia quando cambia il fotogramma
	if current_hitbox != null:
		current_hitbox.scale = Vector2.ONE / factor


func _set_hitbox_disabled(hitbox: Hitbox, value: bool) -> void:
	var shape: CollisionShape2D = hitbox.get_node("CollisionShape2D")
	shape.disabled = value


# Gira il personaggio: sprite, Chain di Iacopo e hitbox del pugno
func _set_facing(left: bool) -> void:
	current_sprite.flip_h = left
	chain_sprite.flip_h = left
	chain_sprite.position.x = -abs(chain_base_x) if left else abs(chain_base_x)
	current_hitbox_shape.position.x = -abs(hitbox_base_x) if left else abs(hitbox_base_x)


# --- NUOVO: helper di input, isolati per device_id ---
func _get_direction() -> float:
	match device_id:
		-1:
			return Input.get_axis("p1_left", "p1_right")
		-2:
			return Input.get_axis("p2_left", "p2_right")
		_:
			return Input.get_joy_axis(device_id, JOY_AXIS_LEFT_X)


func _jump_just_pressed() -> bool:
	match device_id:
		-1:
			return Input.is_action_just_pressed("p1_jump")
		-2:
			return Input.is_action_just_pressed("p2_jump")
		_:
			return Input.is_joy_button_pressed(device_id, JOY_BUTTON_A)


func _attack_just_pressed() -> bool:
	match device_id:
		-1:
			return Input.is_action_just_pressed("p1_attack")
		-2:
			return Input.is_action_just_pressed("p2_attack")
		_:
			return Input.is_joy_button_pressed(device_id, JOY_BUTTON_RIGHT_SHOULDER)


func _is_running() -> bool:
	match device_id:
		-1:
			return Input.is_action_pressed("p1_run")
		-2:
			return Input.is_action_pressed("p2_run")
		_:
			return Input.is_joy_button_pressed(device_id, JOY_BUTTON_LEFT_SHOULDER)


# tasto "secondary" (p1_secondary / p2_secondary in project.godot): tenuto
# premuto attiva il blocco (vedi is_blocking in _physics_process)
func _block_pressed() -> bool:
	match device_id:
		-1:
			return Input.is_action_pressed("p1_secondary")
		-2:
			return Input.is_action_pressed("p2_secondary")
		_:
			return Input.is_joy_button_pressed(device_id, JOY_BUTTON_X)


# Macchina a stati dell'attacco secondario (portale -> gancio), avanzata ogni
# frame da _physics_process solo per chi ha has_secondary_attack = true:
#   IDLE    -> tasto premuto: appare il "portale" (loop) e resta finche' non si rilascia
#   CHARGE  -> tasto rilasciato: si passa a WAIT
#   WAIT    -> dopo secondary_release_delay secondi, la direzione viene fissata
#              e parte l'animazione "gancio"
#   REACH   -> la catena si sta ancora allungando: dopo secondary_hit_delay
#              secondi la hitbox si attiva (piena estensione)
#   STRIKE  -> la hitbox resta attiva per secondary_hit_window secondi, poi si disattiva
#   COOLDOWN-> si aspetta che l'animazione "gancio" finisca del tutto prima di
#              tornare a IDLE (portale nascosto, si puo' ricaricare)
func _process_secondary_attack(delta: float) -> void:
	if _secondary_sprite == null:
		return

	var held: bool = _block_pressed()

	match _sec_state:
		SecondaryState.IDLE:
			if held and not isAttacking and is_on_floor():
				_sec_state = SecondaryState.CHARGE
				_secondary_sprite.visible = true
				_secondary_sprite.play("portale")
				_update_secondary_facing()

		SecondaryState.CHARGE:
			_update_secondary_facing()
			if not held:
				_sec_state = SecondaryState.WAIT
				_sec_timer = secondary_release_delay

		SecondaryState.WAIT:
			_update_secondary_facing()
			_sec_timer -= delta
			if _sec_timer <= 0.0:
				_sec_state = SecondaryState.REACH
				_sec_timer = secondary_hit_delay
				_fire_secondary_attack()

		SecondaryState.REACH:
			_sec_timer -= delta
			if _sec_timer <= 0.0:
				_sec_state = SecondaryState.STRIKE
				_sec_timer = secondary_hit_window
				if _secondary_hitbox:
					_secondary_hitbox.reset_hits()
					_set_hitbox_disabled(_secondary_hitbox, false)

		SecondaryState.STRIKE:
			_sec_timer -= delta
			if _sec_timer <= 0.0:
				if _secondary_hitbox:
					_set_hitbox_disabled(_secondary_hitbox, true)
				_sec_state = SecondaryState.COOLDOWN

		SecondaryState.COOLDOWN:
			if not _secondary_sprite.is_playing():
				_sec_state = SecondaryState.IDLE
				_secondary_sprite.visible = false


# Aggiorna la rotazione del portale in base a dove guarda il personaggio
# (chiamata durante CHARGE/WAIT: se ci si gira, il portale segue; una volta
# lanciato il gancio la direzione resta fissa, vedi _fire_secondary_attack)
func _update_secondary_facing() -> void:
	_secondary_sprite.position = Vector2(0.0, secondary_ground_offset)
	_secondary_sprite.rotation_degrees = 90.0 if current_sprite.flip_h else -90.0


# Fissa la direzione, fa partire l'animazione "gancio" e posiziona la hitbox
# (bassa e lunga quanto secondary_range) dal personaggio verso quella direzione.
func _fire_secondary_attack() -> void:
	_update_secondary_facing()
	_secondary_sprite.play("gancio")

	if _secondary_hitbox:
		var facing_sign: float = -1.0 if current_sprite.flip_h else 1.0
		_secondary_hitbox.position = Vector2(facing_sign * secondary_range / 2.0, secondary_ground_offset)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	# stordimento da colpo subito: durante hurt_stun_left il player non
	# risponde ai comandi, ma gravita' e rinculo continuano normalmente
	if hurt_stun_left > 0.0:
		hurt_stun_left = maxf(hurt_stun_left - delta, 0.0)
		isHurt = hurt_stun_left > 0.0
		velocity.x = move_toward(velocity.x, 0, hit_knockback * delta * 2.0)
		move_and_slide()
		return

	# blocco: tenendo "secondary" fermi, non si può attaccare né saltare
	# (non si può iniziare a bloccare a metà di un attacco)
	# chi ha un attacco secondario dedicato (es. iacopo) non blocca: quel
	# tasto carica/lancia la sua mossa (vedi _process_secondary_attack)
	if has_secondary_attack:
		is_blocking = false
		_process_secondary_attack(delta)
	else:
		is_blocking = _block_pressed() and is_on_floor() and not isAttacking

	# mentre carica/lancia l'attacco secondario non si puo' saltare ne' tirare
	# il pugno normale (evita di sovrapporre due mosse contemporaneamente)
	var secondary_locked: bool = has_secondary_attack and _sec_state != SecondaryState.IDLE

	if not is_blocking and not secondary_locked:
		if _jump_just_pressed() and is_on_floor():
			velocity.y = jump_velocity

		if _attack_just_pressed():
			attack()

	# la hitbox si attiva solo quando scade il ritardo dell'attacco
	if hitbox_delay_left > 0.0:
		hitbox_delay_left -= delta
		if hitbox_delay_left <= 0.0 and isAttacking:
			_set_hitbox_disabled(current_hitbox, false)

	# chi ha can_run = false in fighters.cfg non può correre
	var is_running: bool = _is_running() and can_run
	var current_speed: float = run_speed if is_running else speed

	if isAttacking:
		current_speed = attack_move_speed

	# mentre si blocca si resta fermi sul posto
	var direction := 0.0 if is_blocking else _get_direction()

	if direction:
		velocity.x = direction * current_speed
		_set_facing(direction < 0)
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)

	if not isAttacking:
		if direction:
			if is_running:
				current_sprite.play("run")
			else:
				current_sprite.play("walk")
		else:
			current_sprite.play("idle")

	move_and_slide()


func attack() -> void:
	if isAttacking:
		return
	isAttacking = true

	current_hitbox.reset_hits()
	if attack_delay <= 0.0:
		_set_hitbox_disabled(current_hitbox, false)
	else:
		hitbox_delay_left = attack_delay

	if fighter_name == "iacopo":
		chain_sprite.visible = true
		chain_sprite.play("hit")
	else:
		current_sprite.play("hit")


func _on_animation_finished() -> void:
	if current_sprite.animation == "hit":
		isAttacking = false
		hitbox_delay_left = 0.0
		_set_hitbox_disabled(current_hitbox, true)


func _on_chain_animation_finished() -> void:
	if chain_sprite.animation == "hit":
		isAttacking = false
		hitbox_delay_left = 0.0
		chain_sprite.visible = false
		_set_hitbox_disabled(current_hitbox, true)


func _on_damaged(amount: int, source: Node) -> void:
	if source == self or current_health <= 0:
		return  # un player non può colpire se stesso, né essere colpito da morto

	# bloccando si subisce solo una frazione del danno (block_damage_reduction)
	var applied_damage: int = amount
	if is_blocking:
		applied_damage = int(round(amount * block_damage_reduction))

	current_health = maxi(current_health - applied_damage, 0)
	health_changed.emit()  # aggiorna la barra vita

	_play_hit_feedback(source, is_blocking)

	if current_health <= 0:
		died.emit(self)


# Rinculo + stordimento breve + lampo sullo sprite + suono d'impatto.
# Se il colpo e' stato bloccato: rinculo ridotto e niente stordimento.
func _play_hit_feedback(source: Node, blocked: bool) -> void:
	# direzione della spinta = lontano da chi ha colpito
	var push_dir: float = 1.0 if current_sprite.flip_h else -1.0
	if source is Node2D:
		var d: float = signf(global_position.x - source.global_position.x)
		if d != 0.0:
			push_dir = d
		velocity.x = push_dir * hit_knockback * (0.4 if blocked else 1.0)

	if not blocked:
		hurt_stun_left = hit_stun_duration
		isHurt = true
		_cancel_attack()  # il colpo subito interrompe il pugno in corso
		_cancel_secondary_attack()  # ...e anche l'eventuale portale/gancio di iacopo
		_play_hurt_animation()

	_flash_sprite()
	_spawn_blood(push_dir, blocked)

	if hit_sound:
		hit_sfx.stream = hit_sound
		hit_sfx.play()


# Interrompe l'attacco in corso (senza questo, se "hurt" sostituisce l'animazione
# "hit" a meta', animation_finished non arriva e isAttacking resterebbe true per sempre)
func _cancel_attack() -> void:
	if not isAttacking:
		return
	isAttacking = false
	hitbox_delay_left = 0.0
	_set_hitbox_disabled(current_hitbox, true)
	if chain_sprite.visible:
		chain_sprite.stop()
		chain_sprite.visible = false


# Interrompe portale/gancio in corso (a qualunque punto della macchina a stati)
func _cancel_secondary_attack() -> void:
	if not has_secondary_attack or _sec_state == SecondaryState.IDLE:
		return
	_sec_state = SecondaryState.IDLE
	_sec_timer = 0.0
	if _secondary_sprite:
		_secondary_sprite.stop()
		_secondary_sprite.visible = false
	if _secondary_hitbox:
		_set_hitbox_disabled(_secondary_hitbox, true)


# Animazione "hurt": se lo sprite del personaggio non ce l'ha ancora, viene saltata
# (resta il lampo rosso) senza errori
func _play_hurt_animation() -> void:
	var frames: SpriteFrames = current_sprite.sprite_frames
	if frames == null or not frames.has_animation("hurt"):
		return
	current_sprite.stop()  # riparte da capo anche se si viene colpiti di nuovo
	current_sprite.play("hurt")


# Schizzi di sangue: particelle rosse che partono dal punto colpito, spinte via
# da chi ha colpito e poi cadono per gravita'. Bloccando ne escono meno.
func _spawn_blood(push_dir: float, blocked: bool) -> void:
	if blood_amount <= 0:
		return
	var amount: int = maxi(int(round(blood_amount * (0.3 if blocked else 1.0))), 1)

	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = blood_lifetime
	p.local_coords = false  # le particelle restano nel mondo, non seguono il player
	p.direction = Vector2(push_dir, -0.6)
	p.spread = 55.0
	p.initial_velocity_min = blood_speed_min
	p.initial_velocity_max = blood_speed_max
	p.gravity = Vector2(0, 600)
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.5
	p.color = blood_color
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	p.z_index = 10

	# aggiunta alla scena (non al player) cosi' non viene girata/scalata con lo sprite
	get_parent().add_child(p)
	p.global_position = hurtbox.global_position  # punto colpito (torace)
	p.restart()
	get_tree().create_timer(blood_lifetime + 0.2).timeout.connect(p.queue_free)


func _flash_sprite() -> void:
	if hit_flash_duration <= 0.0:
		return
	current_sprite.modulate = hit_flash_color
	var tween: Tween = create_tween()
	tween.tween_property(current_sprite, "modulate", Color.WHITE, hit_flash_duration)

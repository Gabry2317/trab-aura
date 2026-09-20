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

# --- NUOVO: identità e schema di controllo del player ---
@export var player_id: int = 0
# device_id:
#   -1 = tastiera Player 1 (azioni p1_*)
#   -2 = tastiera Player 2 (azioni p2_*)
#   >=0 = indice del pad (letto via codice, es. Input.get_connected_joypads()[0])
@export var device_id: int = -1
# skin_override: -1 = usa GameState, altrimenti forza la skin per questo player
@export var skin_override: int = -1

var isHurt: bool = false
var isAttacking: bool = false
var hitbox_delay_left: float = 0.0  # secondi che mancano all'attivazione della hitbox

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

	for anim in ["idle", "walk", "run", "hit"]:
		var sheet_path: String = cfg.get_value(fighter, "model_sheet_%s" % anim, "")
		if sheet_path == "":
			continue  # questo personaggio non ha un foglio per questa animazione

		var texture: Texture2D = load(sheet_path)
		var hframes: int = int(cfg.get_value(fighter, "model_hframes_%s" % anim, 1))
		var vframes: int = int(cfg.get_value(fighter, "model_vframes_%s" % anim, 1))
		var frame_count: int = int(cfg.get_value(fighter, "model_frames_%s" % anim, hframes * vframes))

		frames.add_animation(anim)
		frames.set_animation_loop(anim, anim != "hit")  # "hit" non va in loop
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


func _ready() -> void:
	hurtbox.damaged.connect(_on_damaged)

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

	current_sprite = _sprites[fighter_name]
	current_sprite.visible = true
	current_hitbox = _hitboxes[fighter_name]

	current_hitbox_shape = current_hitbox.get_node("CollisionShape2D")
	hitbox_base_x = current_hitbox_shape.position.x

	# model_scale in fighters.cfg permette di rimpicciolire/ingrandire lo sprite
	# senza toccare la scena (la hitbox resta invariata: aggiustarla a mano se serve)
	var model_scale: float = float(_stat("model_scale", 1.0))
	current_sprite.scale = Vector2.ONE * model_scale

	# il player 2 parte specchiato: guarda a sinistra, verso il player 1
	_set_facing(player_id == 1)


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


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

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

	var direction := _get_direction()

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
	current_health = maxi(current_health - amount, 0)
	health_changed.emit()  # aggiorna la barra vita
	if current_health <= 0:
		died.emit(self)

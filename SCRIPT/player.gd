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
@onready var iaco_root: Node2D = $Iaco_Spto  # radice del modello di iacopo (serve per l'attacco secondario)
@onready var hurtbox: Hurtbox = $Hurtbox

# --- Attacco secondario di iacopo: "catena gigante" (tasto destro) ---
# 1) parte l'animazione "chains" (foglio chains.png) accanto al personaggio, bassa
# 2) al termine, parte il fascio "big-chain" (foglio big_chains.png) che si allunga
#    in orizzontale lungo tutto il terreno, basso (si schiva saltando)
# Tutto costruito a runtime affettando i fogli sprite, come _build_dynamic_sprite
# fa già per Andrix: non serve modificare la scena WND_trab.tscn.
const BIG_CHAIN_CAST_TEXTURE := preload("res://sprite/Player/Iacobisio/Secondary/chains.png")
const BIG_CHAIN_BEAM_TEXTURE := preload("res://sprite/Player/Iacobisio/Secondary/big_chains.png")
const BIG_CHAIN_CAST_HFRAMES := 4
const BIG_CHAIN_CAST_VFRAMES := 4
const BIG_CHAIN_CAST_FRAMES := 16
const BIG_CHAIN_CAST_FPS := 20.0
const BIG_CHAIN_BEAM_HFRAMES := 6
const BIG_CHAIN_BEAM_VFRAMES := 2
const BIG_CHAIN_BEAM_FRAME_INDEX := 4   # fotogramma con la catena doppia completamente distesa
const BIG_CHAIN_MAX_LENGTH := 3000.0    # abbastanza lunga da coprire qualunque mappa
const BIG_CHAIN_GROW_TIME := 0.55       # secondi impiegati a percorrere BIG_CHAIN_MAX_LENGTH
const BIG_CHAIN_HEIGHT := 36.0          # altezza della hitbox/del fascio: bassa, si schiva saltando
const BIG_CHAIN_Y_OFFSET := 70.0        # quanto sta in basso rispetto all'origine del player (vicino ai piedi)

var big_chain_cast: AnimatedSprite2D    # sprite dell'animazione "chains" (creato a runtime, vedi _setup_big_chain)
var isAttackingSecondary: bool = false  # true durante l'animazione "chains" dell'attacco secondario
var big_chain_cooldown_left: float = 0.0
var secondary_damage: int = 15
var secondary_attack_cooldown: float = 1.5

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

	secondary_damage = int(_stat("secondary_damage", secondary_damage))
	secondary_attack_cooldown = float(_stat("secondary_attack_cooldown", secondary_attack_cooldown))


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

	_setup_big_chain()

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
	if big_chain_cast:
		big_chain_cast.flip_h = left
		big_chain_cast.position.x = -abs(chain_base_x) if left else abs(chain_base_x)


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


# pressione singola del tasto "secondary" (tasto destro / p1_secondary,
# p2_secondary): usata per lanciare l'attacco secondario di iacopo, a
# differenza di _block_pressed() che invece lo legge "tenuto premuto"
func _secondary_just_pressed() -> bool:
	match device_id:
		-1:
			return Input.is_action_just_pressed("p1_secondary")
		-2:
			return Input.is_action_just_pressed("p2_secondary")
		_:
			return false  # non ancora supportato da joypad


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

	if big_chain_cooldown_left > 0.0:
		big_chain_cooldown_left = maxf(big_chain_cooldown_left - delta, 0.0)

	# attacco secondario di iacopo ("catena gigante"): un tocco del tasto
	# "secondary" (tasto destro) lo lancia, a differenza del blocco che
	# richiede di tenerlo premuto (vedi _block_pressed più sotto)
	if fighter_name == "iacopo" and _secondary_just_pressed() and is_on_floor() \
			and not isAttacking and not isAttackingSecondary and big_chain_cooldown_left <= 0.0:
		_start_big_chain_attack()

	# blocco: tenendo "secondary" fermi, non si può attaccare né saltare
	# (non si può iniziare a bloccare a metà di un attacco o della catena gigante)
	is_blocking = _block_pressed() and is_on_floor() and not isAttacking and not isAttackingSecondary

	if not is_blocking and not isAttackingSecondary:
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
	elif isAttackingSecondary:
		current_speed = 0.0  # fermo mentre lancia la catena gigante

	# mentre si blocca o si lancia la catena gigante si resta fermi sul posto
	var direction := 0.0 if (is_blocking or isAttackingSecondary) else _get_direction()

	if direction:
		velocity.x = direction * current_speed
		_set_facing(direction < 0)
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)

	if not isAttacking and not isAttackingSecondary:
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


# Crea a runtime lo sprite dell'animazione "chains" (il lancio della catena
# gigante), affettando res://.../Secondary/chains.png. Fatto in codice, come
# _build_dynamic_sprite, così non serve toccare la scena WND_trab.tscn.
func _setup_big_chain() -> void:
	big_chain_cast = AnimatedSprite2D.new()
	big_chain_cast.name = "BigChainCast"

	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	_add_sliced_animation(frames, &"chains", BIG_CHAIN_CAST_TEXTURE,
		BIG_CHAIN_CAST_HFRAMES, BIG_CHAIN_CAST_VFRAMES, BIG_CHAIN_CAST_FRAMES, BIG_CHAIN_CAST_FPS, false)

	big_chain_cast.sprite_frames = frames
	big_chain_cast.animation = "chains"
	big_chain_cast.visible = false
	big_chain_cast.position = Vector2(chain_base_x, BIG_CHAIN_Y_OFFSET)  # affianco al personaggio, in basso
	big_chain_cast.animation_finished.connect(_on_big_chain_cast_finished)

	iaco_root.add_child(big_chain_cast)


# Affetta un foglio sprite in hframes x vframes fotogrammi e li aggiunge come
# una nuova animazione a "frames". Stessa idea di _build_dynamic_sprite,
# isolata qui per essere riusata dall'attacco secondario.
func _add_sliced_animation(frames: SpriteFrames, anim: StringName, texture: Texture2D,
		hframes: int, vframes: int, frame_count: int, fps: float, loop: bool) -> void:
	frames.add_animation(anim)
	frames.set_animation_loop(anim, loop)
	frames.set_animation_speed(anim, fps)

	var tex_size: Vector2 = texture.get_size()
	var fw: float = tex_size.x / hframes
	var fh: float = tex_size.y / vframes

	var added := 0
	for row in range(vframes):
		for col in range(hframes):
			if added >= frame_count:
				break
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(col * fw, row * fh, fw, fh)
			frames.add_frame(anim, atlas)
			added += 1


# Avvia l'attacco secondario di iacopo: parte l'animazione "chains" accanto
# al personaggio; quando finisce (_on_big_chain_cast_finished) parte il
# fascio che scorre lungo la mappa (_spawn_big_chain_beam).
func _start_big_chain_attack() -> void:
	isAttackingSecondary = true
	big_chain_cooldown_left = secondary_attack_cooldown
	velocity.x = 0.0

	big_chain_cast.flip_h = current_sprite.flip_h
	big_chain_cast.position.x = -abs(chain_base_x) if current_sprite.flip_h else abs(chain_base_x)
	big_chain_cast.visible = true
	big_chain_cast.frame = 0
	big_chain_cast.play("chains")


func _on_big_chain_cast_finished() -> void:
	if big_chain_cast.animation != "chains":
		return
	big_chain_cast.visible = false

	# se nel frattempo un colpo subito ha annullato l'attacco (vedi
	# _cancel_attack), il fascio non deve partire
	if isAttackingSecondary:
		_spawn_big_chain_beam()
		isAttackingSecondary = false


# Crea il fascio della catena gigante: un'area (Hitbox, la stessa classe usata
# dal pugno) che nasce accanto a iacopo e si allunga in orizzontale, bassa,
# finché non copre tutta la mappa. Viene aggiunta al livello (non al player)
# così continua anche se iacopo nel frattempo si muove o attacca di nuovo -
# stesso principio usato in _spawn_blood per le particelle di sangue.
func _spawn_big_chain_beam() -> void:
	var dir: float = -1.0 if current_sprite.flip_h else 1.0
	var origin: Vector2 = global_position + Vector2(dir * abs(chain_base_x), BIG_CHAIN_Y_OFFSET)

	var beam := Area2D.new()
	beam.name = "BigChainBeam"
	beam.set_script(load("res://SCRIPT/punch_hitbox_trab.gd"))
	beam.collision_layer = current_hitbox.collision_layer
	beam.collision_mask = current_hitbox.collision_mask
	beam.damage = secondary_damage
	beam.source = self

	# hitbox: un rettangolo basso che parte largo 0 e cresce in orizzontale
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(1.0, BIG_CHAIN_HEIGHT)
	shape.shape = rect
	beam.add_child(shape)

	# visuale: il fotogramma "big-chain" completamente disteso, ruotato in
	# orizzontale e allungato in lunghezza dallo stesso tween della hitbox
	var tex_size: Vector2 = BIG_CHAIN_BEAM_TEXTURE.get_size()
	var fw: float = tex_size.x / BIG_CHAIN_BEAM_HFRAMES
	var fh: float = tex_size.y / BIG_CHAIN_BEAM_VFRAMES
	var col: int = BIG_CHAIN_BEAM_FRAME_INDEX % BIG_CHAIN_BEAM_HFRAMES
	var row: int = BIG_CHAIN_BEAM_FRAME_INDEX / BIG_CHAIN_BEAM_HFRAMES
	var atlas := AtlasTexture.new()
	atlas.atlas = BIG_CHAIN_BEAM_TEXTURE
	atlas.region = Rect2(col * fw, row * fh, fw, fh)

	var sprite := Sprite2D.new()
	sprite.texture = atlas
	sprite.centered = false
	sprite.offset = Vector2(-fw / 2.0, 0.0)  # centra lo spessore sulla linea bassa della catena
	sprite.scale = Vector2(BIG_CHAIN_HEIGHT / fw, 0.0)
	sprite.rotation_degrees = -90.0 if dir > 0.0 else 90.0
	beam.add_child(sprite)

	get_parent().add_child(beam)
	beam.global_position = origin

	# callback del tween: ad ogni passo allunga sia la hitbox che il fascio
	var update_beam := func(length: float) -> void:
		if not is_instance_valid(beam):
			return
		rect.size.x = maxf(length, 1.0)
		shape.position.x = dir * length / 2.0
		sprite.scale.y = length / fh

	var tween := create_tween()
	tween.tween_method(update_beam, 0.0, BIG_CHAIN_MAX_LENGTH, BIG_CHAIN_GROW_TIME)
	tween.tween_callback(beam.queue_free)


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
		_play_hurt_animation()

	_flash_sprite()
	_spawn_blood(push_dir, blocked)

	if hit_sound:
		hit_sfx.stream = hit_sound
		hit_sfx.play()


# Interrompe l'attacco in corso (senza questo, se "hurt" sostituisce l'animazione
# "hit" a meta', animation_finished non arriva e isAttacking resterebbe true per sempre)
func _cancel_attack() -> void:
	if isAttackingSecondary:
		isAttackingSecondary = false
		big_chain_cast.stop()
		big_chain_cast.visible = false
		# nota: se il fascio è già partito (_spawn_big_chain_beam), continua
		# comunque per conto suo: è ormai un'entità indipendente del livello

	if not isAttacking:
		return
	isAttacking = false
	hitbox_delay_left = 0.0
	_set_hitbox_disabled(current_hitbox, true)
	if chain_sprite.visible:
		chain_sprite.stop()
		chain_sprite.visible = false


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

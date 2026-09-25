class_name Player
extends CharacterBody2D

signal health_changed  # <-- serve per healt_bar.gd
signal stamina_changed  # <-- serve per stamina_bar.gd
signal died(player)  # emesso una sola volta quando la vita arriva a 0 (lo ascolta level.gd)

# --- Statistiche: si modificano in res://data/fighters/ (base.cfg + un .cfg per personaggio), NON qui ---
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

# --- NUOVO: stamina (barra sotto quella della vita) ---
# usata dal potere secondario (ogni potere ha il suo stamina_cost/stamina_min,
# vedi fighter_power.gd): si consuma lanciandolo, si recupera nel tempo (di
# piu' correndo) e colpendo a segno col pugno normale.
var max_stamina: float = 100.0
var current_stamina: float = 100.0
var stamina_regen_rate: float = 8.0       # recuperata al secondo, sempre
var stamina_regen_run_bonus: float = 12.0  # in piu' al secondo mentre si corre
var stamina_hit_gain: float = 8.0          # guadagnata quando il pugno normale va a segno

# --- feedback dei colpi (vedi _play_hit_feedback) ---
var hit_knockback: float = 220.0       # rinculo: velocita' orizzontale della spinta subita
var hit_stun_duration: float = 0.25    # stordimento: per quanti secondi non si risponde ai comandi
var hit_flash_duration: float = 0.12   # per quanti secondi lo sprite resta colorato dopo il colpo
var hit_flash_color: Color = Color(1.0, 0.35, 0.35, 1.0)  # colore del lampo (default: rossastro)
var hit_sound: AudioStream = null      # caricato da hit_sound nei file .cfg

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

# --- NUOVO: multiplayer online (vedi network_manager.gd) ---
var is_networked: bool = false  # true se la partita gira online (deciso da solo in _enter_tree)
var is_local: bool = true       # true se questo Player è quello di QUESTO PC (rilevante solo se is_networked)
var synced_animation: String = "idle"  # replicata al client per mostrare l'animazione giusta
var synced_flip_h: bool = false        # replicato al client per il verso giusto
# ultimo stato tasti ricevuto dal PC remoto (letto dall'host per simulare il player non suo)
var _remote_input: Dictionary = {"dir": 0.0, "run": false, "jump": false, "attack": false, "block": false, "secondary": false}

# --- NUOVO: attacco caricato del potere secondario (vedi fighter_power.has_charged_attack) ---
var _secondary_hold_time: float = 0.0  # da quanto e' tenuto premuto "secondary"
var _secondary_charging: bool = false  # true mentre la carica e' attiva (dopo la soglia)

@onready var hit_sfx: AudioStreamPlayer = AudioStreamPlayer.new()  # riprodotto a ogni colpo subito

const FIGHTERS_DIR := "res://data/fighters/"
# base.cfg = valori comuni. Ogni altro .cfg della cartella = un personaggio:
# il nome del file e' il nome del personaggio, [character] skin = N il suo
# numero di skin. Per aggiungere un personaggio basta aggiungere un file:
# questo script non va toccato.
static var _base_cfg: ConfigFile
static var _fighter_cfgs: Dictionary = {}   # nome -> ConfigFile
static var _skins: Dictionary = {}          # numero di skin -> nome
static var _fighter_names: Array = []       # ordinati per skin
static var _power_hint_shown: Dictionary = {}

var skin: int = 0
var fighter_name: String = ""  # nome della sezione nei file .cfg per la skin attuale

var chain_sprite: AnimatedSprite2D = null  # effetto del pugno (opzionale): [model] attack_fx_node nel .cfg
@onready var hurtbox: Hurtbox = $Hurtbox

# --- Potere secondario: si collega da [secondary] nel .cfg del personaggio ---
var secondary_power = null  # potere collegato (script che estende fighter_power.gd), senza tipo per non creare dipendenze circolari

# sprite e hitbox di ogni personaggio, indicizzati per nome (vedi _ready):
# se il nodo esiste gia' in scena (personaggio disegnato a mano) viene
# riusato, altrimenti viene costruito a runtime dai dati nei file .cfg
var _sprites: Dictionary = {}
var _hitboxes: Dictionary = {}

var current_sprite: AnimatedSprite2D
var current_hitbox: Hitbox
var chain_base_x: float

# --- dimensioni sprite ---
# scala dello sprite cosi' come e' impostata nella scena (WND_trab.tscn):
# e' il riferimento, model_scale dei file .cfg la moltiplica soltanto
var _base_scale: Vector2 = Vector2.ONE
var _model_scale: float = 1.0
# altezza (px) del fotogramma idle: tutte le altre animazioni vengono
# riscalate per apparire grandi quanto l'idle
var _idle_frame_height: float = 0.0
var current_hitbox_shape: CollisionShape2D  # shape della hitbox attiva (viene specchiata)
var hitbox_base_x: float  # X originale della shape (in editor)


func _enter_tree() -> void:
	# NUOVO: capisce da solo se la partita è online e se questo player_id è
	# quello controllato da QUESTO PC (host = sempre player_id 0)
	is_networked = multiplayer.has_multiplayer_peer()
	if is_networked:
		is_local = (player_id == 0) == multiplayer.is_server()

	# skin e statistiche si decidono qui, prima di qualsiasi _ready():
	# così la barra della vita legge già il max_health giusto
	# se skin_override non è impostato, usa la config del GameState per questo player_id
	if skin_override != -1:
		skin = skin_override
	elif GameState.has_method("get_skin_for"):
		skin = GameState.get_skin_for(player_id)
	else:
		skin = GameState.selected_skin  # fallback compatibile col vecchio sistema

	_load_fighters()
	if _skins.is_empty():
		return  # nessun personaggio caricato: l'errore e' gia' stato stampato da _load_fighters
	if not _skins.has(skin):
		push_warning("Skin non valida: %s" % skin)
		skin = int(_skins.keys().min())
	fighter_name = _skins[skin]

	_load_stats()


# --- NUOVO: funzioni di rete ---

# Crea a runtime un MultiplayerSynchronizer che replica dall'host (sempre
# autorevole) a chi si connette: posizione, vita, stamina e le due variabili
# "synced_*" che tengono animazione e verso allineati sul client.
func _setup_networking() -> void:
	if not is_networked:
		return
	set_multiplayer_authority(1)  # l'host (peer 1) simula la fisica per entrambi i player

	var config := SceneReplicationConfig.new()
	config.add_property(NodePath(".:global_position"))
	config.add_property(NodePath(".:current_health"))
	config.add_property(NodePath(".:current_stamina"))
	config.add_property(NodePath(".:synced_animation"))
	config.add_property(NodePath(".:synced_flip_h"))

	var sync := MultiplayerSynchronizer.new()
	sync.name = "MultiplayerSynchronizer"
	sync.replication_config = config
	add_child(sync)


# Sul client questo Player non è autorevole: non simula nulla, si limita a
# mostrare l'animazione/il verso arrivati sincronizzati dall'host.
func _process(_delta: float) -> void:
	if not is_networked or is_multiplayer_authority():
		return
	if current_sprite == null:
		return
	if current_sprite.animation != synced_animation and current_sprite.sprite_frames != null \
			and current_sprite.sprite_frames.has_animation(synced_animation):
		current_sprite.play(synced_animation)
	current_sprite.flip_h = synced_flip_h
	if chain_sprite != null:
		chain_sprite.flip_h = synced_flip_h


# Chiamata solo dal PC che controlla davvero questo player (is_local): manda
# all'host (rpc_id(1, ...)) lo stato attuale dei propri tasti. L'host, se è
# lui stesso il player locale, non ne ha bisogno (legge l'Input direttamente).
func _send_local_input() -> void:
	if multiplayer.is_server():
		return
	_receive_input.rpc_id(1, {
		"dir": Input.get_axis("p1_left", "p1_right"),
		"run": Input.is_action_pressed("p1_run"),
		"jump": Input.is_action_just_pressed("p1_jump"),
		"attack": Input.is_action_just_pressed("p1_attack"),
		"block": Input.is_action_pressed("p1_secondary"),
		"secondary": Input.is_action_just_pressed("p1_secondary"),
	})


@rpc("any_peer", "unreliable_ordered")
func _receive_input(input: Dictionary) -> void:
	_remote_input = input


# Legge (e consuma) un tasto "a pressione singola" arrivato dal client: si
# azzera subito dopo la lettura così un solo invio non viene contato più
# volte nei fotogrammi fisici dell'host in cui non arriva un aggiornamento.
func _remote_consume(key: String) -> bool:
	var v: bool = bool(_remote_input.get(key, false))
	if v:
		_remote_input[key] = false
	return v


# --- Lettura di res://data/fighters/ ---
# base.cfg = valori comuni; ogni altro .cfg della cartella = un personaggio.
# Il numero di skin e' la chiave "skin" dentro [character] di ogni file.
static func _load_cfg(path: String) -> ConfigFile:
	var cfg := ConfigFile.new()
	var err: int = cfg.load(path)
	if err != OK:
		push_warning("%s non caricato (errore %d)" % [path, err])
	return cfg


static func _load_fighters() -> void:
	if not _fighter_names.is_empty():
		return
	if not DirAccess.dir_exists_absolute(FIGHTERS_DIR):
		push_error("Cartella %s non trovata: crea la cartella data/fighters nel progetto e copiaci dentro base.cfg e i .cfg dei personaggi (trab, iacopo, naka, andrix)" % FIGHTERS_DIR)
		_base_cfg = ConfigFile.new()
		return
	_base_cfg = _load_cfg(FIGHTERS_DIR + "base.cfg")

	var entries: Array = []  # [skin, nome]
	for file in DirAccess.get_files_at(FIGHTERS_DIR):
		if file.get_extension() != "cfg" or file == "base.cfg":
			continue
		var fname: String = file.get_basename()
		var cfg: ConfigFile = _load_cfg(FIGHTERS_DIR + file)
		_fighter_cfgs[fname] = cfg
		entries.append([int(cfg.get_value("character", "skin", 9999)), fname])

	entries.sort_custom(func(a, b): return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])
	for e in entries:
		if _skins.has(e[0]):
			push_warning("skin %d assegnata sia a '%s' che a '%s': tengo la prima" % [e[0], _skins[e[0]], e[1]])
			continue
		_skins[e[0]] = e[1]
		_fighter_names.append(e[1])

	if _fighter_names.is_empty():
		push_error("Nessun personaggio trovato in %s (servono file .cfg con [character] skin = N)" % FIGHTERS_DIR)


# Elenco dei personaggi, ordinati per skin. Calcolato una sola volta.
static func _get_fighter_names() -> Array:
	_load_fighters()
	return _fighter_names


# Valore di un personaggio qualsiasi: prima il suo file, poi base.cfg, poi il fallback
static func _stat_of(fighter: String, section: String, key: String, fallback: Variant) -> Variant:
	var cfg: ConfigFile = _fighter_cfgs.get(fighter)
	if cfg != null and cfg.has_section_key(section, key):
		return cfg.get_value(section, key)
	return _base_cfg.get_value(section, key, fallback)


# Come _stat_of, per il personaggio di questa istanza
func _stat(section: String, key: String, fallback: Variant) -> Variant:
	return _stat_of(fighter_name, section, key, fallback)


# Costruisce a runtime un AnimatedSprite2D dalle sezioni [anim_<nome>] del file
# del personaggio (idle, walk, run, hit, hurt...): ogni sezione descrive un
# foglio sprite (sheet, hframes, vframes, frames, fps, loop) che viene affettato.
static func _build_dynamic_sprite(fighter: String, node_name: String) -> AnimatedSprite2D:
	var cfg: ConfigFile = _fighter_cfgs[fighter]
	var sprite := AnimatedSprite2D.new()
	sprite.name = node_name

	var default_size: int = int(_stat_of(fighter, "model", "frame_size", 256))
	var frames := SpriteFrames.new()
	frames.remove_animation("default")

	for section in cfg.get_sections():
		if not section.begins_with("anim_"):
			continue
		var anim: String = section.trim_prefix("anim_")
		var sheet_path: String = str(cfg.get_value(section, "sheet", ""))
		if sheet_path == "":
			continue
		var texture: Texture2D = load(sheet_path)
		if texture == null:
			push_warning("[%s] %s: foglio '%s' non trovato" % [fighter, section, sheet_path])
			continue

		var hframes: int = int(cfg.get_value(section, "hframes", 1))
		var vframes: int = int(cfg.get_value(section, "vframes", 1))
		var frame_count: int = int(cfg.get_value(section, "frames", hframes * vframes))
		var fw: int = int(cfg.get_value(section, "frame_width", cfg.get_value(section, "frame_size", default_size)))
		var fh: int = int(cfg.get_value(section, "frame_height", cfg.get_value(section, "frame_size", default_size)))

		frames.add_animation(anim)
		frames.set_animation_loop(anim, bool(cfg.get_value(section, "loop", anim != "hit" and anim != "hurt")))
		frames.set_animation_speed(anim, float(cfg.get_value(section, "fps", 10.0)))

		var added: int = 0
		for row in range(vframes):
			for col in range(hframes):
				if added >= frame_count:
					break
				var atlas := AtlasTexture.new()
				atlas.atlas = texture
				atlas.region = Rect2(col * fw, row * fh, fw, fh)
				frames.add_frame(anim, atlas)
				added += 1

	sprite.sprite_frames = frames
	if frames.has_animation("idle"):
		sprite.animation = "idle"
	return sprite


# Trova lo sprite del personaggio se esiste gia' in scena (personaggio
# disegnato a mano nell'editor); altrimenti lo costruisce dalle sezioni
# [anim_*] del suo file. Un personaggio nuovo non richiede nodi in scena.
func _get_or_build_sprite(fighter: String) -> AnimatedSprite2D:
	var node_name: String = str(_stat_of(fighter, "model", "node", fighter + "_Sprite"))

	var existing: Node = get_node_or_null(node_name)
	if existing is AnimatedSprite2D:
		return existing
	if existing != null:
		push_warning("'%s' esiste ma non e' un AnimatedSprite2D: lo ignoro e ne costruisco uno nuovo per %s" % [node_name, fighter])
	elif get_node_or_null(node_name.to_lower()) != null or get_node_or_null(node_name.to_upper()) != null:
		# i nomi dei nodi distinguono maiuscole/minuscole: probabile refuso in [model] node
		push_warning("[model] node '%s' di %s non trovato per esatta corrispondenza di maiuscole/minuscole: controlla il nome del nodo in scena" % [node_name, fighter])

	var built: AnimatedSprite2D = _build_dynamic_sprite(fighter, node_name)
	add_child(built)  # gli sprite gia' in scena ci sono di default, questi vanno aggiunti a mano
	return built


# Trova la hitbox del pugno se esiste gia' sotto lo sprite; altrimenti la crea
# copiando hitbox_template_node (base.cfg) con gli eventuali hitbox_offset_x/y,
# hitbox_width/height del file del personaggio ([model]).
func _get_or_build_hitbox(fighter: String, sprite: AnimatedSprite2D) -> Hitbox:
	var cfg: ConfigFile = _fighter_cfgs[fighter]
	var hitbox_node_name: String = str(_stat_of(fighter, "model", "hitbox_node", "PunchHitbox"))

	var existing: Node = sprite.get_node_or_null(hitbox_node_name)
	if existing is Hitbox:
		return existing

	var template_path: String = str(_stat_of(fighter, "model", "hitbox_template_node", "TRAB_Sprite2D/PunchHitbox"))
	var template: Node = get_node_or_null(template_path)
	if not (template is Hitbox):
		push_warning("hitbox_template_node '%s' non trovata: %s non avra' una hitbox" % [template_path, fighter])
		return null

	var hitbox: Hitbox = template.duplicate()
	hitbox.name = hitbox_node_name.get_file()  # se hitbox_node e' un percorso tipo "Chain/PunchHitbox"
	sprite.add_child(hitbox)

	var shape_node: CollisionShape2D = hitbox.get_node("CollisionShape2D")
	shape_node.position = Vector2(
		float(cfg.get_value("model", "hitbox_offset_x", shape_node.position.x)),
		float(cfg.get_value("model", "hitbox_offset_y", shape_node.position.y))
	)

	if cfg.has_section_key("model", "hitbox_width") or cfg.has_section_key("model", "hitbox_height"):
		var shape: Shape2D = shape_node.shape
		if shape is RectangleShape2D:
			var new_shape: RectangleShape2D = shape.duplicate()
			new_shape.size = Vector2(
				float(cfg.get_value("model", "hitbox_width", shape.size.x)),
				float(cfg.get_value("model", "hitbox_height", shape.size.y))
			)
			shape_node.shape = new_shape

	return hitbox


func _load_stats() -> void:
	max_health = int(_stat("stats", "max_health", max_health))
	current_health = max_health
	attack_damage = int(_stat("stats", "attack_damage", attack_damage))
	attack_delay = float(_stat("stats", "attack_delay", attack_delay))
	speed = float(_stat("stats", "speed", speed))
	run_speed = float(_stat("stats", "run_speed", run_speed))
	attack_move_speed = float(_stat("stats", "attack_move_speed", attack_move_speed))
	jump_velocity = float(_stat("stats", "jump_velocity", jump_velocity))
	can_run = bool(_stat("stats", "can_run", can_run))
	block_damage_reduction = clampf(float(_stat("stats", "block_damage_reduction", block_damage_reduction)), 0.0, 1.0)

	max_stamina = float(_stat("stats", "max_stamina", max_stamina))
	current_stamina = max_stamina
	stamina_regen_rate = float(_stat("stats", "stamina_regen_rate", stamina_regen_rate))
	stamina_regen_run_bonus = float(_stat("stats", "stamina_regen_run_bonus", stamina_regen_run_bonus))
	stamina_hit_gain = float(_stat("stats", "stamina_hit_gain", stamina_hit_gain))

	hit_knockback = float(_stat("feedback", "hit_knockback", hit_knockback))
	hit_stun_duration = float(_stat("feedback", "hit_stun_duration", hit_stun_duration))
	hit_flash_duration = float(_stat("feedback", "hit_flash_duration", hit_flash_duration))
	hit_flash_color = _stat("feedback", "hit_flash_color", hit_flash_color)
	var hit_sound_path: String = str(_stat("feedback", "hit_sound", ""))
	hit_sound = load(hit_sound_path) if hit_sound_path != "" else null

	blood_amount = int(_stat("feedback", "blood_amount", blood_amount))
	blood_color = _stat("feedback", "blood_color", blood_color)
	blood_lifetime = float(_stat("feedback", "blood_lifetime", blood_lifetime))
	blood_speed_min = float(_stat("feedback", "blood_speed_min", blood_speed_min))
	blood_speed_max = float(_stat("feedback", "blood_speed_max", blood_speed_max))


# --- Potere secondario (tasto secondary) ---
# Nel file del personaggio la sezione [secondary] collega uno script con
#     script = "res://SCRIPT/powers/xxx.gd"
# Lo script (che estende fighter_power.gd) elenca i suoi settings con i valori di
# default (default_params); qui vengono uniti a quelli scritti nel file.
# Chiavi sconosciute -> avviso; chiavi mancanti -> in debug la console stampa
# il blocco completo da incollare nel .cfg, con tutti i settings disponibili.
func _setup_secondary_power() -> void:
	var script_path: String = str(_stat("secondary", "script", ""))
	if script_path == "":
		return
	var script: GDScript = load(script_path) as GDScript
	if script == null:
		push_warning("[%s] secondary: script '%s' non trovato" % [fighter_name, script_path])
		return
	var power = script.new()
	if not power.has_method("default_params"):
		push_warning("[%s] secondary: '%s' non estende fighter_power.gd" % [fighter_name, script_path])
		return

	var cfg: ConfigFile = _fighter_cfgs[fighter_name]
	var defaults: Dictionary = power.default_params()
	var params: Dictionary = defaults.duplicate()
	if cfg.has_section("secondary"):
		for key in cfg.get_section_keys("secondary"):
			if key == "script":
				continue
			if defaults.has(key):
				params[key] = cfg.get_value("secondary", key)
			else:
				push_warning("[%s] secondary: chiave sconosciuta '%s' (settings di %s: %s)" % [fighter_name, key, script_path.get_file(), ", ".join(defaults.keys())])

	if OS.is_debug_build() and not _power_hint_shown.has(fighter_name):
		_power_hint_shown[fighter_name] = true
		var missing: Array = []
		for key in defaults:
			if not cfg.has_section_key("secondary", key):
				missing.append("%s = %s" % [key, var_to_str(defaults[key])])
		if not missing.is_empty():
			print("[%s] settings di %s non scritti nel .cfg (uso i default). Da incollare sotto [secondary]:\n%s" % [fighter_name, script_path.get_file(), "\n".join(missing)])

	power.name = "SecondaryPower"
	add_child(power)
	power.setup(self, params)
	secondary_power = power


func _power_busy() -> bool:
	return secondary_power != null and secondary_power.is_busy()


# Aggiunge/toglie stamina (clampata tra 0 e max_stamina) ed emette stamina_changed
# per la barra. Usate dal potere secondario per il costo/gate di ogni mossa
# (vedi fighter_power.gd) e da _on_damaged per il recupero sui pugni normali.
func gain_stamina(amount: float) -> void:
	if amount == 0.0:
		return
	current_stamina = clampf(current_stamina + amount, 0.0, max_stamina)
	stamina_changed.emit()


func spend_stamina(amount: float) -> void:
	gain_stamina(-amount)


# Altezza visibile del personaggio in pixel di mondo (serve ai poteri per scalarsi)
func get_visual_height() -> float:
	var local_y: float = maxf(absf(current_sprite.scale.y), 0.0001)
	var world_scale: float = absf(current_sprite.global_scale.y) / local_y
	return _idle_frame_height * _base_scale.y * _model_scale * world_scale


# +1 = guarda a destra, -1 = guarda a sinistra
func get_facing_dir() -> float:
	return -1.0 if current_sprite.flip_h else 1.0


func _ready() -> void:
	_setup_networking()

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

	current_sprite = _sprites[fighter_name]
	current_sprite.visible = true

	# effetto del pugno (es. la catena di iacopo): [model] attack_fx_node, percorso relativo al modello
	var fx_path: String = str(_stat("model", "attack_fx_node", ""))
	if fx_path != "":
		chain_sprite = current_sprite.get_node_or_null(fx_path) as AnimatedSprite2D
		if chain_sprite == null:
			push_warning("[%s] attack_fx_node '%s' non trovato sotto il modello" % [fighter_name, fx_path])
		else:
			chain_sprite.visible = false
			chain_base_x = chain_sprite.position.x
			chain_sprite.animation_finished.connect(_on_chain_animation_finished)
	current_hitbox = _hitboxes[fighter_name]

	current_hitbox_shape = current_hitbox.get_node("CollisionShape2D")
	hitbox_base_x = current_hitbox_shape.position.x

	# la scala impostata in scena (es. Naka 0.74 x 0.94, Andrix 1.2 x 1.11) va
	# mantenuta: model_scale nei file .cfg la moltiplica (1.0 = misura della scena).
	# In piu' ogni animazione viene portata alla stessa dimensione dell'idle.
	_base_scale = current_sprite.scale
	_model_scale = float(_stat("model", "scale", 1.0))
	_idle_frame_height = _get_frame_height(current_sprite, &"idle", 0)
	current_sprite.animation_changed.connect(_update_sprite_scale)
	current_sprite.frame_changed.connect(_update_sprite_scale)
	_update_sprite_scale()

	# il player 2 parte specchiato: guarda a sinistra, verso il player 1
	_set_facing(player_id == 1)

	_setup_secondary_power()


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
	synced_flip_h = left
	current_sprite.flip_h = left
	if chain_sprite != null:
		chain_sprite.flip_h = left
		chain_sprite.position.x = -abs(chain_base_x) if left else abs(chain_base_x)
	current_hitbox_shape.position.x = -abs(hitbox_base_x) if left else abs(hitbox_base_x)


# --- NUOVO: helper di input, isolati per device_id (o per rete se is_networked) ---
# In rete ogni PC usa sempre lo schema "p1_*" (WASD/spazio/click) sulla
# propria tastiera: non serve più dividere la tastiera in due, ognuno ha la
# sua. Il player non locale (quello dell'altro PC, simulato dall'host) legge
# invece l'ultimo stato ricevuto via RPC (_remote_input).
func _get_direction() -> float:
	if is_networked:
		return Input.get_axis("p1_left", "p1_right") if is_local else float(_remote_input.get("dir", 0.0))
	match device_id:
		-1:
			return Input.get_axis("p1_left", "p1_right")
		-2:
			return Input.get_axis("p2_left", "p2_right")
		_:
			return Input.get_joy_axis(device_id, JOY_AXIS_LEFT_X)


func _jump_just_pressed() -> bool:
	if is_networked:
		return Input.is_action_just_pressed("p1_jump") if is_local else _remote_consume("jump")
	match device_id:
		-1:
			return Input.is_action_just_pressed("p1_jump")
		-2:
			return Input.is_action_just_pressed("p2_jump")
		_:
			return Input.is_joy_button_pressed(device_id, JOY_BUTTON_A)


func _attack_just_pressed() -> bool:
	if is_networked:
		return Input.is_action_just_pressed("p1_attack") if is_local else _remote_consume("attack")
	match device_id:
		-1:
			return Input.is_action_just_pressed("p1_attack")
		-2:
			return Input.is_action_just_pressed("p2_attack")
		_:
			return Input.is_joy_button_pressed(device_id, JOY_BUTTON_RIGHT_SHOULDER)


# pressione singola del tasto "secondary" (tasto destro / p1_secondary,
# p2_secondary): usata per lanciare il potere secondario, a
# differenza di _block_pressed() che invece lo legge "tenuto premuto"
func _secondary_just_pressed() -> bool:
	if is_networked:
		return Input.is_action_just_pressed("p1_secondary") if is_local else _remote_consume("secondary")
	match device_id:
		-1:
			return Input.is_action_just_pressed("p1_secondary")
		-2:
			return Input.is_action_just_pressed("p2_secondary")
		_:
			return false  # non ancora supportato da joypad


func _is_running() -> bool:
	if is_networked:
		return Input.is_action_pressed("p1_run") if is_local else bool(_remote_input.get("run", false))
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
	if is_networked:
		return Input.is_action_pressed("p1_secondary") if is_local else bool(_remote_input.get("block", false))
	match device_id:
		-1:
			return Input.is_action_pressed("p1_secondary")
		-2:
			return Input.is_action_pressed("p2_secondary")
		_:
			return Input.is_joy_button_pressed(device_id, JOY_BUTTON_X)


# Gestisce il tasto "secondary" per i poteri con attacco caricato (vedi
# fighter_power.has_charged_attack()): tenuto premuto oltre charge_time()
# avvia la carica (start_charge/update_charge); il rilascio la conclude
# (release_charge). Un tocco più breve della soglia resta un uso normale
# del potere (use()), come per i poteri senza carica.
func _update_charged_secondary(delta: float) -> void:
	var held: bool = _block_pressed()  # stesso tasto del blocco, letto "tenuto premuto"

	if held:
		_secondary_hold_time += delta
		if _secondary_charging:
			secondary_power.update_charge(delta)
		elif _secondary_hold_time >= secondary_power.charge_time() and is_on_floor() \
				and not isAttacking and secondary_power.can_use():
			_secondary_charging = secondary_power.start_charge()  # puo' fallire (es. stamina): si ritenta ogni frame
	else:
		if _secondary_charging:
			_secondary_charging = false
			secondary_power.release_charge()
		elif _secondary_hold_time > 0.0 and is_on_floor() and not isAttacking \
				and secondary_power.can_use():
			secondary_power.use()  # pressione breve: attacco normale (sotto la soglia di carica)
		_secondary_hold_time = 0.0


func _physics_process(delta: float) -> void:
	if is_networked:
		if is_local:
			_send_local_input()
		if not is_multiplayer_authority():
			return  # il client non simula: aspetta la posizione sincronizzata dall'host

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

	# potere secondario (se il personaggio ne ha uno in [secondary]).
	# Due modalità, decise dal potere stesso (has_charged_attack()):
	#  - normale: un tocco del tasto "secondary" lo lancia subito
	#  - caricato: tenendo premuto "secondary" oltre charge_time() secondi parte
	#    la carica (es. il pointer di Bisio); un rilascio più rapido della soglia
	#    resta un tocco normale. Per questi poteri il blocco viene disattivato:
	#    lo stesso tasto serve per mirare/rilasciare (vedi _update_charged_secondary)
	var chargeable: bool = secondary_power != null and secondary_power.has_charged_attack()
	if chargeable:
		_update_charged_secondary(delta)
	elif secondary_power != null and _secondary_just_pressed() and is_on_floor() \
			and not isAttacking and secondary_power.can_use():
		secondary_power.use()
	var power_busy: bool = _power_busy()

	# blocco: tenendo "secondary" fermi, non si può attaccare né saltare
	# (non si può iniziare a bloccare a metà di un attacco o del potere secondario)
	is_blocking = not chargeable and _block_pressed() and is_on_floor() and not isAttacking and not power_busy

	if not is_blocking and not power_busy:
		if _jump_just_pressed() and is_on_floor():
			velocity.y = jump_velocity

		if _attack_just_pressed():
			attack()

	# la hitbox si attiva solo quando scade il ritardo dell'attacco
	if hitbox_delay_left > 0.0:
		hitbox_delay_left -= delta
		if hitbox_delay_left <= 0.0 and isAttacking:
			_set_hitbox_disabled(current_hitbox, false)

	# chi ha can_run = false nel suo .cfg non può correre
	var is_running: bool = _is_running() and can_run
	var current_speed: float = run_speed if is_running else speed

	# stamina: si recupera sempre nel tempo, di piu' mentre si corre
	# (il consumo, invece, e' nel potere: vedi fighter_power.gd use()/start_charge())
	if current_stamina < max_stamina:
		var regen: float = stamina_regen_rate + (stamina_regen_run_bonus if is_running else 0.0)
		gain_stamina(regen * delta)

	if isAttacking:
		current_speed = attack_move_speed
	elif power_busy:
		current_speed = 0.0  # fermo mentre lancia il potere secondario

	# mentre si blocca o si lancia il potere secondario si resta fermi sul posto
	var direction := 0.0 if (is_blocking or power_busy) else _get_direction()

	if direction:
		velocity.x = direction * current_speed
		_set_facing(direction < 0)
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)

	if not isAttacking and not power_busy:
		if direction:
			if is_running:
				current_sprite.play("run")
				synced_animation = "run"
			else:
				current_sprite.play("walk")
				synced_animation = "walk"
		else:
			current_sprite.play("idle")
			synced_animation = "idle"

	move_and_slide()


func attack() -> void:
	if isAttacking:
		return
	isAttacking = true
	synced_animation = "hit"

	current_hitbox.reset_hits()
	if attack_delay <= 0.0:
		_set_hitbox_disabled(current_hitbox, false)
	else:
		hitbox_delay_left = attack_delay

	if chain_sprite != null:
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
	if is_networked and not is_multiplayer_authority():
		return  # in rete solo l'host applica i danni: il client vede solo il risultato sincronizzato
	if source == self or current_health <= 0:
		return  # un player non può colpire se stesso, né essere colpito da morto

	# bloccando si subisce solo una frazione del danno (block_damage_reduction)
	var applied_damage: int = amount
	if is_blocking:
		applied_damage = int(round(amount * block_damage_reduction))

	current_health = maxi(current_health - applied_damage, 0)
	health_changed.emit()  # aggiorna la barra vita

	# il pugno normale (non un potere) va a segno: un po' di stamina a chi ha colpito
	# (source.isAttacking e' vero solo durante la hitbox del pugno base, non dei poteri)
	if source is Player and source != self and source.isAttacking:
		source.gain_stamina(source.stamina_hit_gain)

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
	if secondary_power != null:
		secondary_power.on_player_hit()  # es. la catena in spawn si ritira, o la carica si annulla
	_secondary_charging = false
	_secondary_hold_time = 0.0

	if not isAttacking:
		return
	isAttacking = false
	hitbox_delay_left = 0.0
	_set_hitbox_disabled(current_hitbox, true)
	if chain_sprite != null and chain_sprite.visible:
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
	synced_animation = "hurt"


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

extends Node
# ============================================================
#  FATALITY MANAGER  (autoload - registrato in project.godot)
# ============================================================
#  Come funziona, in breve:
#
#  1) Quando un player sta per andare a 0 HP, invece di morire si
#     ferma a `settings.downed_health` HP (default 1) ed entra in
#     stato "downed" -> player.gd chiama FatalityManager.mark_downed().
#
#  2) Da quel momento, la vittima puo' essere finita in due modi:
#       a) un QUALSIASI altro colpo (se settings.any_hit_finishes)
#          -> player.gd chiama FatalityManager.downed_player_hit()
#          -> e' un K.O. normale: NIENTE camera/slowmo/letterbox/animazione
#             speciale, solo una breve pausa (fallback_freeze_duration) e poi
#             "died" come sempre.
#       b) l'avversario esegue la COMBO specifica del proprio
#          personaggio, letta dalla sezione [fatality] nel suo file
#          .cfg (es. data/fighters/iacopo.cfg):
#
#              [fatality]
#              combo = "down,down,attack,secondary"
#              combo_window = 1.4
#
#          I nomi validi per i passi della combo sono i suffissi delle
#          action di Input Map gia' presenti nel progetto: down, left,
#          right, jump, run, attack (= tasto/pulsante "quadrato"),
#          secondary (= tasto/pulsante "cerchio").
#          -> SOLO questo percorso fa scattare la cinematica completa
#             (slowmo, camera che zooma sulla vittima, letterbox,
#             animazione "<vittima>_<killer>"): e' la vera "fatality",
#             riservata a chi indovina la combo giusta.
#
#  3) Con la combo parte _run_sequence() in modalita' completa: slowmo
#     breve, camera che si sposta/zooma sulla vittima (letterbox nera),
#     viene cercata e riprodotta l'animazione "<vittima>_<killer>" (es.
#     "iacopo_trab" se Trab uccide Iacopo) dentro lo SpriteFrames del
#     personaggio -- basta aggiungerla come una normalissima sezione
#     [anim_iacopo_trab] nel .cfg, esattamente come [anim_idle] ecc.,
#     il caricamento e' automatico (vedi player.gd _build_dynamic_sprite).
#     Se l'animazione non esiste, resta un fermo immagine per
#     settings.fallback_freeze_duration secondi.
#
#  4) A fine cinematica viene ripristinata la camera, sbloccati i
#     player, ed emesso il segnale ORIGINALE `died` sulla vittima —
#     quindi tutta la logica di fine round che avevi gia' (in
#     level.gd o dove lo ascolti) continua a funzionare come prima,
#     semplicemente arriva un po' piu' tardi (dopo la cinematica).
#
#  TUTTI I PARAMETRI regolabili sono in fatality_settings.gd / nella
#  risorsa .tres assegnata a `settings_path` qui sotto.
# ============================================================

const FIGHTERS_DIR := "res://data/fighters/"

## Percorso della risorsa FatalityCombatSettings. Se non esiste, si usano i default.
@export var settings_path: String = "res://data/fatality_settings.tres"

var settings: FatalityCombatSettings

var _fatality_active: bool = false
# player_id (0/1) -> array di {action:String, time:float}
var _input_buffer: Dictionary = {}
# player_id del player "downed" attualmente in attesa del colpo di grazia -> {victim, last_source}
var _downed_players: Dictionary = {}

# elenco delle action da ascoltare per il riconoscimento combo
const _COMBO_SUFFIXES := ["down", "left", "right", "jump", "run", "attack", "secondary"]

var _letterbox: CanvasLayer
var _top_bar: ColorRect
var _bottom_bar: ColorRect

# stato camera nativo salvato durante la cinematica, cosi' _force_recover()
# (watchdog) puo' ripristinarlo anche se _run_sequence si e' inceppato
var _camera_smoothing_was_enabled: bool = true
var _camera_drag_h_was_enabled: bool = false
var _camera_drag_v_was_enabled: bool = false

# vittima della fatality in corso: usata da _force_recover() (watchdog) per
# completare comunque la "morte" (died) se _run_sequence si e' inceppato,
# invece di lasciare tutto a meta' senza che il round finisca mai.
var _current_victim: Player = null


func _ready() -> void:
	if ResourceLoader.exists(settings_path):
		settings = ResourceLoader.load(settings_path) as FatalityCombatSettings
	if settings == null:
		settings = FatalityCombatSettings.new()
	print("[Fatality] settings caricati da '%s' (esiste: %s) - camera_zoom_multiplier = %s" % [settings_path, ResourceLoader.exists(settings_path), settings.camera_zoom_multiplier])
	_build_letterbox()


func _build_letterbox() -> void:
	_letterbox = CanvasLayer.new()
	_letterbox.layer = 100
	_letterbox.visible = false

	_top_bar = ColorRect.new()
	_bottom_bar = ColorRect.new()
	for bar in [_top_bar, _bottom_bar]:
		bar.color = settings.letterbox_color
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_letterbox.add_child(bar)

	call_deferred("_attach_letterbox")


func _attach_letterbox() -> void:
	get_tree().root.add_child(_letterbox)
	_reset_letterbox_hidden()


# Posiziona le barre appena fuori schermo (nascoste), da chiamare una sola
# volta all'avvio: _show_letterbox() poi le anima SOLO da qui in poi,
# senza mai piu' "teletrasportarle" a meta' animazione.
func _reset_letterbox_hidden() -> void:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	_top_bar.size = Vector2(vp_size.x, settings.letterbox_height)
	_bottom_bar.size = Vector2(vp_size.x, settings.letterbox_height)
	_top_bar.position = Vector2(0, -settings.letterbox_height)
	_bottom_bar.position = Vector2(0, vp_size.y)


# ============================================================
#  API chiamata da player.gd
# ============================================================

# Un player e' appena passato a "downed" (ultimo HP) invece di morire.
func mark_downed(victim: Player, source: Node) -> void:
	if _fatality_active:
		return
	_downed_players[victim.player_id] = {"victim": victim, "last_source": source}
	_input_buffer[victim.player_id] = []
	_input_buffer[1 - victim.player_id] = []


# Il player downed ha appena subito un altro colpo qualsiasi -> lo finisce.
func downed_player_hit(victim: Player, source: Node) -> void:
	if _fatality_active or not _downed_players.has(victim.player_id):
		return
	if not settings.any_hit_finishes:
		return
	_trigger(source, victim, false)


# True se questo player_id e' *davvero* registrato come "downed" qui dentro
# (fonte di verita'). Usata da player.gd per non fidarsi ciecamente del suo
# flag locale is_downed, che puo' restare "agganciato" da un round precedente
# se e' finito (es. per timeout) mentre il player era downed ma non ancora
# finito: vedi clear_downed().
func is_player_downed(pid: int) -> bool:
	return _downed_players.has(pid)


# Da chiamare quando un player viene "rimesso in piedi" per un nuovo round
# (player.gd lo fa in _load_stats()): dimentica qualunque stato "downed"
# residuo per questo player_id, cosi' non resta bloccato in quello stato
# se il round precedente e' finito prima del colpo di grazia.
func clear_downed(pid: int) -> void:
	_downed_players.erase(pid)
	_input_buffer.erase(pid)


# ============================================================
#  Riconoscimento combo
# ============================================================

func _unhandled_input(event: InputEvent) -> void:
	if _fatality_active or _downed_players.is_empty():
		return
	for pid in [0, 1]:
		var downed_info = _downed_players.get(1 - pid, null)
		if downed_info == null:
			continue  # l'avversario di "pid" non e' downed, quindi "pid" non puo' fare la combo ora
		var action_suffix: String = _match_action(pid, event)
		if action_suffix == "":
			continue
		_push_input(pid, action_suffix)
		_check_combo(pid, downed_info["victim"])


func _match_action(pid: int, event: InputEvent) -> String:
	var prefix: String = "p1_" if pid == 0 else "p2_"
	for suffix in _COMBO_SUFFIXES:
		var action: String = prefix + suffix
		if InputMap.has_action(action) and event.is_action_pressed(action):
			return suffix
	return ""


func _push_input(pid: int, action: String) -> void:
	var buf: Array = _input_buffer.get(pid, [])
	buf.append({"action": action, "time": Time.get_ticks_msec() / 1000.0})
	_input_buffer[pid] = buf


func _check_combo(pid: int, victim: Player) -> void:
	var attacker: Player = _find_player(pid)
	if attacker == null:
		return
	var combo: Array = _get_combo(attacker.fighter_name)
	if combo.is_empty():
		return  # questo personaggio non ha una combo fatality definita nel .cfg

	var window: float = _get_combo_window(attacker.fighter_name)
	var buf: Array = _input_buffer.get(pid, [])
	var now: float = Time.get_ticks_msec() / 1000.0
	while buf.size() > 0 and now - buf[0]["time"] > window:
		buf.pop_front()
	_input_buffer[pid] = buf

	if buf.size() < combo.size():
		return
	var tail: Array = buf.slice(buf.size() - combo.size(), buf.size())
	for i in range(combo.size()):
		if tail[i]["action"] != combo[i]:
			return

	_input_buffer[pid] = []
	_trigger(attacker, victim, true)


func _get_combo(fighter: String) -> Array:
	var cfg := ConfigFile.new()
	if cfg.load(FIGHTERS_DIR + fighter + ".cfg") != OK:
		return []
	if not cfg.has_section_key("fatality", "combo"):
		return []
	var raw: String = str(cfg.get_value("fatality", "combo", ""))
	var parts: Array = []
	for p in raw.split(",", false):
		parts.append(p.strip_edges())
	return parts


func _get_combo_window(fighter: String) -> float:
	var cfg := ConfigFile.new()
	if cfg.load(FIGHTERS_DIR + fighter + ".cfg") != OK:
		return settings.combo_input_window
	return float(cfg.get_value("fatality", "combo_window", settings.combo_input_window))


func _find_player(pid: int) -> Player:
	for p in get_tree().get_nodes_in_group("players"):
		if p.player_id == pid:
			return p
	return null


# Legge la sezione [anim_<anim_name>] dal .cfg della VITTIMA e, se non è già
# presente, la costruisce e la aggiunge allo SpriteFrames che il personaggio
# sta gia' usando in questo momento — sia che provenga da un nodo disegnato
# a mano in scena (Trab, Iacopo, Naka: in quel caso player.gd NON legge MAI
# le sezioni [anim_*] del .cfg, perche' _get_or_build_sprite() trova il nodo
# gia' in scena e si ferma li'), sia che provenga da uno sprite costruito
# dinamicamente dal .cfg (Andrix). Ritorna true se l'animazione e' pronta.
func _ensure_fatality_animation(victim: Player, anim_name: String) -> bool:
	var frames: SpriteFrames = victim.current_sprite.sprite_frames
	if frames == null:
		return false
	if frames.has_animation(anim_name):
		return true

	var cfg := ConfigFile.new()
	if cfg.load(FIGHTERS_DIR + victim.fighter_name + ".cfg") != OK:
		return false
	var section: String = "anim_" + anim_name
	if not cfg.has_section(section):
		return false

	var sheet_path: String = str(cfg.get_value(section, "sheet", ""))
	if sheet_path == "":
		return false
	var texture: Texture2D = load(sheet_path)
	if texture == null:
		push_warning("[Fatality] foglio '%s' non trovato (sezione [%s] di %s.cfg)" % [sheet_path, section, victim.fighter_name])
		return false

	var default_size: int = int(cfg.get_value("model", "frame_size", 256))
	var hframes: int = int(cfg.get_value(section, "hframes", 1))
	var vframes: int = int(cfg.get_value(section, "vframes", 1))
	var frame_count: int = int(cfg.get_value(section, "frames", hframes * vframes))
	var fw: int = int(cfg.get_value(section, "frame_width", cfg.get_value(section, "frame_size", default_size)))
	var fh: int = int(cfg.get_value(section, "frame_height", cfg.get_value(section, "frame_size", default_size)))

	frames.add_animation(anim_name)
	frames.set_animation_loop(anim_name, bool(cfg.get_value(section, "loop", false)))
	frames.set_animation_speed(anim_name, float(cfg.get_value(section, "fps", 10.0)))

	var added: int = 0
	for row in range(vframes):
		for col in range(hframes):
			if added >= frame_count:
				break
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(col * fw, row * fh, fw, fh)
			frames.add_frame(anim_name, atlas)
			added += 1

	if added == 0:
		push_warning("[Fatality] la sezione [%s] di %s.cfg non ha prodotto nessun fotogramma (controlla hframes/vframes/frames)" % [section, victim.fighter_name])
		frames.remove_animation(anim_name)
		return false

	return true


# ============================================================
#  Cinematica
# ============================================================

func trigger_fatality(killer: Node, victim: Player) -> void:
	_trigger(killer, victim, true)


func _trigger(killer: Node, victim: Player, via_combo: bool) -> void:
	if _fatality_active:
		return
	_fatality_active = true
	_current_victim = victim
	_downed_players.clear()
	_input_buffer.clear()
	_run_sequence(killer, victim, via_combo)
	_watchdog()


# Rete di sicurezza: se _run_sequence si inceppa da qualche parte (un errore
# a runtime interrompe silenziosamente la coroutine), dopo watchdog_timeout
# secondi REALI si sblocca tutto comunque, invece di restare "inchiodato".
func _watchdog() -> void:
	var timeout: float = settings.watchdog_timeout if settings else 8.0
	await get_tree().create_timer(timeout, true, false, true).timeout
	if _fatality_active:
		push_warning("[Fatality] la cinematica ha superato %ss senza completarsi: sblocco forzato. Controlla il pannello Debugger > Errors per capire cosa si e' inceppato." % timeout)
		_force_recover()


func _force_recover() -> void:
	Engine.time_scale = 1.0
	if _letterbox:
		_letterbox.visible = false
	var camera: Camera2D = get_viewport().get_camera_2d()
	if camera:
		camera.position_smoothing_enabled = _camera_smoothing_was_enabled
		camera.drag_horizontal_enabled = _camera_drag_h_was_enabled
		camera.drag_vertical_enabled = _camera_drag_v_was_enabled
		camera.set_process(true)
		camera.set_physics_process(true)
	for p in get_tree().get_nodes_in_group("players"):
		p.combat_locked = false
		p.is_downed = false
	_fatality_active = false
	# La cinematica si e' inceppata: se avevamo gia' una vittima designata,
	# completiamo comunque la "morte" (died) invece di lasciare il round
	# bloccato per sempre senza che nessuno muoia mai.
	if _current_victim != null:
		_current_victim.current_health = 0
		_current_victim.is_dead = true
		_current_victim.health_changed.emit()
		_current_victim.died.emit(_current_victim)
		_current_victim = null


func _run_sequence(killer: Node, victim: Player, via_combo: bool) -> void:
	if settings.lock_input_during_cinematic:
		for p in get_tree().get_nodes_in_group("players"):
			p.combat_locked = true

	if not via_combo:
		# Finito con un colpo QUALSIASI (settings.any_hit_finishes), non con
		# la combo specifica: niente scenografia (camera/slowmo/letterbox) e
		# niente animazione unica "<vittima>_<killer>" -- quella e' la vera
		# "fatality" ed e' riservata a chi fa la combo giusta. Qui e' solo un
		# K.O. normale: una breve pausa e via.
		if settings.fallback_freeze_duration > 0.0:
			await get_tree().create_timer(settings.fallback_freeze_duration, true, false, true).timeout
		for p in get_tree().get_nodes_in_group("players"):
			p.combat_locked = false
		_fatality_active = false
		victim.is_downed = false
		victim.current_health = 0
		victim.is_dead = true
		victim.health_changed.emit()
		victim.died.emit(victim)
		_current_victim = null
		return

	_play_oneshot(settings.trigger_sound)

	if settings.use_slowmo_on_trigger:
		Engine.time_scale = settings.slowmo_time_scale
		await get_tree().create_timer(settings.slowmo_duration, true, false, true).timeout
		Engine.time_scale = 1.0

	var camera: Camera2D = get_viewport().get_camera_2d()
	var camera_was_processing: bool = false
	var camera_original_zoom: Vector2 = Vector2.ONE
	var camera_original_position: Vector2 = Vector2.ZERO
	var camera_smoothing_was_enabled: bool = false
	var camera_drag_h_was_enabled: bool = false
	var camera_drag_v_was_enabled: bool = false
	if camera:
		camera_was_processing = camera.is_processing() or camera.is_physics_processing()
		camera_original_zoom = camera.zoom          # per tornare esattamente allo zoom di gioco normale
		camera_original_position = camera.global_position
		camera_smoothing_was_enabled = camera.position_smoothing_enabled
		camera_drag_h_was_enabled = camera.drag_horizontal_enabled
		camera_drag_v_was_enabled = camera.drag_vertical_enabled
		_camera_smoothing_was_enabled = camera_smoothing_was_enabled
		_camera_drag_h_was_enabled = camera_drag_h_was_enabled
		_camera_drag_v_was_enabled = camera_drag_v_was_enabled
		camera.set_process(false)
		camera.set_physics_process(false)
		# IMPORTANTE: lo smoothing/drag NATIVI di Camera2D (position_smoothing_enabled,
		# drag_horizontal/vertical_enabled) sono applicati dal motore ad ogni frame
		# INDIPENDENTEMENTE dallo script della camera: set_process()/set_physics_process()
		# NON li disattiva. Se la tua camera_2d.gd li usa per seguire i due lottatori,
		# continuerebbero a "tirare" la camera verso di loro durante il nostro tween,
		# vanificandolo e facendo sembrare che la camera "torni indietro" invece di
		# restare ferma sullo zoom/posizione della vittima. Li spegniamo qui e li
		# ripristiniamo esattamente come erano a fine cinematica.
		camera.position_smoothing_enabled = false
		camera.drag_horizontal_enabled = false
		camera.drag_vertical_enabled = false

	if settings.use_letterbox:
		_show_letterbox(true)

	if camera:
		var target: Vector2 = victim.global_position + settings.camera_offset
		var target_zoom: Vector2 = camera_original_zoom * settings.camera_zoom_multiplier
		print("[Fatality] zoom camera: da %s a %s (moltiplicatore %s) in %ss" % [camera_original_zoom, target_zoom, settings.camera_zoom_multiplier, settings.camera_pan_time])
		var tw := create_tween()
		tw.set_parallel(true)
		tw.set_trans(settings.camera_pan_trans)
		tw.set_ease(settings.camera_pan_ease)
		tw.tween_property(camera, "global_position", target, settings.camera_pan_time)
		tw.tween_property(camera, "zoom", target_zoom, settings.camera_pan_time)
		await tw.finished

	var killer_name: String = killer.fighter_name if (killer is Player) else "unknown"
	var anim_name: String = "%s_%s" % [victim.fighter_name, killer_name]
	var has_anim: bool = _ensure_fatality_animation(victim, anim_name)

	if has_anim:
		var frames: SpriteFrames = victim.current_sprite.sprite_frames
		if settings.animation_fps_override > 0.0:
			frames.set_animation_speed(anim_name, settings.animation_fps_override)
		# forzato a false: se il .cfg non scrive "loop = false" esplicitamente, di default
		# le animazioni diverse da hit/hurt vengono costruite in loop, e un'animazione in
		# loop non emette mai "animation_finished".
		frames.set_animation_loop(anim_name, false)
		victim.current_sprite.stop()
		victim.current_sprite.play(anim_name)
		await _await_first(victim.current_sprite.animation_finished, get_tree().create_timer(settings.max_animation_duration).timeout)
	else:
		push_warning("[Fatality] Nessuna animazione '%s' trovata: aggiungi una sezione [anim_%s] nel .cfg di %s per personalizzarla. Uso un fermo immagine." % [anim_name, anim_name, victim.fighter_name])
		await get_tree().create_timer(settings.fallback_freeze_duration).timeout

	_play_oneshot(settings.finish_sound)

	if settings.use_letterbox:
		_show_letterbox(false)
		await get_tree().create_timer(settings.letterbox_fade_time).timeout

	if camera:
		var tw2 := create_tween()
		tw2.set_parallel(true)
		tw2.set_trans(settings.camera_pan_trans)
		tw2.set_ease(settings.camera_pan_ease)
		tw2.tween_property(camera, "zoom", camera_original_zoom, settings.camera_return_time)
		tw2.tween_property(camera, "global_position", camera_original_position, settings.camera_return_time)
		await tw2.finished
		camera.position_smoothing_enabled = camera_smoothing_was_enabled
		camera.drag_horizontal_enabled = camera_drag_h_was_enabled
		camera.drag_vertical_enabled = camera_drag_v_was_enabled
		camera.set_process(camera_was_processing)
		camera.set_physics_process(camera_was_processing)

	for p in get_tree().get_nodes_in_group("players"):
		p.combat_locked = false

	_fatality_active = false
	victim.is_downed = false
	victim.current_health = 0
	victim.is_dead = true  # resta fermo nella posa finale finche' level.gd non resetta il round (_load_stats())
	victim.health_changed.emit()
	victim.died.emit(victim)
	_current_victim = null


func _play_oneshot(stream: AudioStream) -> void:
	if stream == null:
		return
	var sfx := AudioStreamPlayer.new()
	sfx.stream = stream
	add_child(sfx)
	sfx.play()
	sfx.finished.connect(sfx.queue_free)


func _await_first(sig_a: Signal, sig_b: Signal) -> void:
	var done := false
	var mark := func(): done = true
	sig_a.connect(mark, CONNECT_ONE_SHOT)
	sig_b.connect(mark, CONNECT_ONE_SHOT)
	while not done:
		await get_tree().process_frame


func _show_letterbox(show_bars: bool) -> void:
	_letterbox.visible = true
	var vp_size: Vector2 = get_viewport().get_visible_rect().size

	var tw := create_tween()
	tw.set_parallel(true)
	if show_bars:
		tw.tween_property(_top_bar, "position:y", 0.0, settings.letterbox_fade_time)
		tw.tween_property(_bottom_bar, "position:y", vp_size.y - settings.letterbox_height, settings.letterbox_fade_time)
	else:
		tw.tween_property(_top_bar, "position:y", -settings.letterbox_height, settings.letterbox_fade_time)
		tw.tween_property(_bottom_bar, "position:y", vp_size.y, settings.letterbox_fade_time)
		tw.finished.connect(func(): _letterbox.visible = false)

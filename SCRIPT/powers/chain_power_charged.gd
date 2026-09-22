extends "res://SCRIPT/powers/chain_power.gd"
# Attacco caricato di Bisio: estende chain_power.gd (la catena veloce a
# tocco) aggiungendo la mira caricata sullo stesso tasto "secondary".
#
#  - tocco veloce (sotto charge_time)  -> catena veloce (ereditata da chain_power.gd)
#  - tenuto premuto oltre charge_time  -> nasce un pointer trasparente
#    (pointer_sheet) che avanza da solo (non e' controllabile dal player)
#    nella direzione in cui il player guardava all'inizio della carica;
#    rilasciando il tasto il pointer sparisce e al suo posto nasce una
#    colonna (big_chain) che danneggia chi tocca e resta li' come area
#    denial per column_duration secondi, colpendo di nuovo chi rimane
#    dentro ogni column_tick_interval. Se il pointer avanza troppo senza
#    che il tasto venga rilasciato (pointer_max_distance) la carica si
#    annulla da sola, senza colonna.

var _pointer: Sprite2D = null    # catena trasparente che avanza durante la carica
var _pointer_x: float = 0.0      # posizione (mondo, X) del pointer durante la carica
var _charge_dir: float = 1.0     # direzione (fissa) in cui il pointer avanza, presa a inizio carica
var _charging: bool = false      # true mentre il player tiene premuto e il pointer avanza
var _columns: Array = []         # colonne big_chain attive (area denial in corso)


func default_params() -> Dictionary:
	var params: Dictionary = super.default_params()  # tutti i settings della catena veloce
	var charge_params: Dictionary = {
		# --- soglia di carica ---
		"charge_time": 0.5,           # secondi da tenere premuto prima che parta la carica

		# --- pointer (mira automatica, non controllabile) ---
		"pointer_sheet": "res://sprite/Player/Iacobisio/Secondary/pointer.png",  # catena trasparente di mira
		"pointer_alpha": 0.55,        # trasparenza del pointer (0-1)
		"pointer_height_ratio": 0.3,  # altezza del pointer rispetto al player
		"pointer_start_x": 40.0,      # distanza orizzontale dal player a cui nasce il pointer
		"pointer_feet_y": 70.0,       # quota dei piedi del pointer rispetto all'origine del player
		"pointer_speed": 300.0,       # px/s: velocita' a cui il pointer avanza da solo mentre si carica
		"pointer_max_distance": 500.0,  # oltre questa distanza percorsa la carica si annulla da sola

		# --- colonna (big_chain, area denial) ---
		"column_sheet": "res://sprite/Player/Iacobisio/Secondary/big_chains.png",  # foglio dedicato della colonna (rune + catena)
		"column_hframes": 7,          # colonne del foglio (7x2 = 14 fotogrammi)
		"column_vframes": 2,          # righe del foglio
		"column_frames": -1,          # fotogrammi da usare; -1 = tutti quelli del foglio (hframes*vframes)
		"column_ground_margin": 105.0,  # px (nel foglio originale) di spazio vuoto sotto il disegno nel
										# fotogramma "ancorato": senza questo la colonna resta sospesa,
										# perche' il fotogramma e' piu' alto del disegno vero e proprio.
										# Se cambi column_hold_frame o il foglio, ritocca questo valore
										# a occhio finche' la base tocca terra.
		"column_fps": 20.0,           # velocita' di crescita/ritiro della colonna
		"column_height_ratio": 3.8,   # altezza della colonna rispetto al player
		"column_feet_y": 70.0,        # quota dei piedi della colonna rispetto all'origine del player
									  # (separata da pointer_feet_y: regola qui se il pilastro non tocca terra)
		"column_hold_frame": 6,      # fotogramma (indice nel foglio) su cui la colonna resta ancorata
									  # dopo la crescita, finche' dura l'area denial. -1 = automatico
									  # (meta' foglio: col catena.png fornito e' il fotogramma "ancorata")
		"column_hitbox_w": 0.7,       # larghezza hitbox della colonna (frazione della sprite)
		"column_hitbox_h": 0.9,       # altezza hitbox della colonna (frazione della sprite)
		"column_damage": 10,          # danno per ogni "tick" della colonna
		"column_duration": 5.0,       # secondi in cui la colonna resta attiva (area denial)
		"column_tick_interval": 0.4,  # ogni quanti secondi la colonna puo' colpire di nuovo chi resta dentro
		"column_hitbox_script": "res://SCRIPT/punch_hitbox_trab.gd",  # script della hitbox della colonna
	}
	for key in charge_params:
		params[key] = charge_params[key]
	return params


func is_busy() -> bool:
	return super.is_busy() or _charging


# Il player e' stato colpito: se stava caricando, annulla la carica (niente
# colonna); altrimenti lascia gestire alla catena veloce (classe base)
func on_player_hit() -> void:
	if _charging:
		_cancel_charge()
		return
	super.on_player_hit()


func has_charged_attack() -> bool:
	return true


func charge_time() -> float:
	return float(params["charge_time"])


# Il player ha tenuto premuto "secondary" oltre charge_time(): nasce il pointer
func start_charge() -> void:
	var tex: Texture2D = load(str(params["pointer_sheet"]))
	if tex == null:
		push_warning("chain_power_charged: pointer '%s' non trovato" % params["pointer_sheet"])
		return
	_charging = true
	player.velocity.x = 0.0
	_charge_dir = player.get_facing_dir()  # fissata qui: il pointer non si controlla piu' dopo

	var sprite := Sprite2D.new()
	sprite.name = "ChainPointer"
	sprite.texture = tex
	sprite.centered = false
	sprite.offset = Vector2(-tex.get_size().x / 2.0, -tex.get_size().y)
	var scale_factor: float = (player.get_visual_height() * float(params["pointer_height_ratio"])) / tex.get_size().y
	sprite.scale = Vector2.ONE * scale_factor
	sprite.flip_h = _charge_dir < 0.0
	sprite.modulate = Color(1.0, 1.0, 1.0, clampf(float(params["pointer_alpha"]), 0.0, 1.0))

	player.get_parent().add_child(sprite)
	_pointer = sprite
	_pointer_x = player.global_position.x + _charge_dir * float(params["pointer_start_x"])
	_update_pointer_position()


# Chiamata ogni frame mentre "secondary" resta premuto dopo la soglia: il
# pointer avanza da solo (non e' controllabile) nella direzione fissata a
# inizio carica; se percorre troppa strada senza essere rilasciato, la
# carica si annulla da sola
func update_charge(delta: float) -> void:
	if not is_instance_valid(_pointer):
		return

	_pointer_x += _charge_dir * float(params["pointer_speed"]) * delta
	_update_pointer_position()

	var distance: float = absf(_pointer_x - player.global_position.x)
	if distance >= float(params["pointer_max_distance"]):
		if bool(params["debug"]):
			print("[ChainCharged] pointer troppo lontano: carica annullata")
		_cancel_charge()


func _update_pointer_position() -> void:
	if is_instance_valid(_pointer):
		_pointer.global_position = Vector2(_pointer_x, player.global_position.y + float(params["pointer_feet_y"]))


# Il player ha rilasciato "secondary" dopo aver caricato: il pointer sparisce
# e al suo posto si abbatte la colonna (big_chain), a terra (column_feet_y)
func release_charge() -> void:
	if not _charging:
		return
	_charging = false
	if is_instance_valid(_pointer):
		var col_pos: Vector2 = Vector2(_pointer_x, player.global_position.y + float(params["column_feet_y"]))
		_despawn_pointer()
		_spawn_column(col_pos)
	cooldown_left = float(params["cooldown"])


# Carica interrotta (colpo subito o pointer troppo lontano): niente colonna
func _cancel_charge() -> void:
	_charging = false
	_despawn_pointer()
	cooldown_left = float(params["cooldown"])


func _despawn_pointer() -> void:
	if is_instance_valid(_pointer):
		_pointer.queue_free()
	_pointer = null


# Crea la colonna (big_chain) sul punto mirato: cresce dal foglio dedicato
# (rune + catena), resta ANCORATA sul fotogramma di column_hold_frame per
# column_duration secondi facendo danno a chi tocca (area denial, con un
# "tick" ogni column_tick_interval per chi resta dentro), poi si ritira
# riproducendo il resto del foglio ed elimina la colonna.
func _spawn_column(pos: Vector2) -> void:
	var tex: Texture2D = load(str(params["column_sheet"]))
	if tex == null:
		push_warning("chain_power_charged: colonna '%s' non trovata" % params["column_sheet"])
		return

	var hframes: int = int(params["column_hframes"])
	var vframes: int = int(params["column_vframes"])
	var fw: float = tex.get_size().x / hframes
	var fh: float = tex.get_size().y / vframes

	# affetta tutto il foglio in ordine (riga per riga, come _add_sliced_animation)
	var atlases: Array = []
	for row in range(vframes):
		for col in range(hframes):
			var atlas := AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = Rect2(col * fw, row * fh, fw, fh)
			atlases.append(atlas)

	var total: int = int(params["column_frames"])
	if total < 0 or total > atlases.size():
		total = atlases.size()

	# fotogramma su cui la colonna resta ferma (ancorata) durante l'area denial:
	# -1 = automatico, a meta' foglio (dove il foglio fornito mostra la catena
	# gia' formata e ancorata, prima di ritirarsi nella seconda meta')
	var hold_frame: int = int(params["column_hold_frame"])
	if hold_frame < 0:
		hold_frame = total / 2
	hold_frame = clampi(hold_frame, 0, total - 1)

	var column = Area2D.new()  # senza tipo: damage/source arrivano dallo script assegnato sotto
	column.name = "BigChainColumn"
	column.set_script(load(str(params["column_hitbox_script"])))
	column.collision_layer = player.current_hitbox.collision_layer
	column.collision_mask = player.current_hitbox.collision_mask
	column.damage = int(params["column_damage"])
	column.source = player

	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var fps: float = float(params["column_fps"])

	frames.add_animation(&"grow")
	frames.set_animation_loop(&"grow", false)
	frames.set_animation_speed(&"grow", fps)
	for i in range(hold_frame + 1):
		frames.add_frame(&"grow", atlases[i])

	frames.add_animation(&"retract")
	frames.set_animation_loop(&"retract", false)
	frames.set_animation_speed(&"retract", fps)
	for i in range(hold_frame, total):
		frames.add_frame(&"retract", atlases[i])

	var col_scale: float = (player.get_visual_height() * float(params["column_height_ratio"])) / fh

	var sprite := AnimatedSprite2D.new()
	sprite.name = "Sprite"
	sprite.sprite_frames = frames
	sprite.centered = false
	# ancorato non al bordo del fotogramma ma al fondo del disegno vero e proprio
	# (fh - column_ground_margin): altrimenti lo spazio vuoto sotto il disegno
	# nel foglio lascia la colonna sospesa in aria
	sprite.offset = Vector2(-fw / 2.0, -(fh - float(params["column_ground_margin"])))
	sprite.scale = Vector2.ONE * col_scale
	column.add_child(sprite)

	var rect := RectangleShape2D.new()
	rect.size = Vector2(fw * col_scale * float(params["column_hitbox_w"]), fh * col_scale * float(params["column_hitbox_h"]))
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	shape.shape = rect
	shape.position = Vector2(0.0, -rect.size.y / 2.0)
	shape.disabled = true  # si accende solo a crescita finita (colonna ancorata)
	column.add_child(shape)

	player.get_parent().add_child(column)
	column.global_position = pos

	var entry: Dictionary = {
		"node": column,
		"shape": shape,
		"formed": false,               # true da quando la colonna e' ancorata (fine di "grow")
		"retracting": false,           # true da quando e' partito il ritiro (evita di rilanciarlo ogni frame)
		"time_left": float(params["column_duration"]),
		"tick_left": float(params["column_tick_interval"]),
	}
	_columns.append(entry)

	# "grow" finita -> la colonna resta ferma sul fotogramma ancorato (comportamento
	# di default di un'animazione non in loop) e la hitbox si accende: da qui parte
	# davvero il conteggio dell'area denial. "retract" finita -> la colonna sparisce.
	sprite.animation_finished.connect(func():
		if sprite.animation == &"grow":
			entry["formed"] = true
			shape.disabled = false
			if bool(params["debug"]):
				print("[ChainCharged] colonna ancorata in ", pos)
		elif sprite.animation == &"retract":
			_columns.erase(entry)
			column.queue_free()
	)
	sprite.play(&"grow")


# Avvia il ritiro (riproduce il resto del foglio dal fotogramma ancorato in
# poi); la colonna viene rimossa dal callback animation_finished di _spawn_column
func _retract_column(entry: Dictionary) -> void:
	var column: Area2D = entry["node"]
	if not is_instance_valid(column):
		_columns.erase(entry)
		return
	var shape: CollisionShape2D = entry["shape"]
	if is_instance_valid(shape):
		shape.set_deferred("disabled", true)
	var sprite := column.get_node("Sprite") as AnimatedSprite2D
	if is_instance_valid(sprite):
		sprite.play(&"retract")
	else:
		_columns.erase(entry)
		column.queue_free()


# Riabilita per un istante la hitbox della colonna: forza il motore fisico a
# ricontrollare le sovrapposizioni cosi' chi e' rimasto dentro viene colpito
# di nuovo (e azzera i colpi gia' registrati dalla hitbox, se supportato)
func _retrigger_column_hits(column: Area2D, shape: CollisionShape2D) -> void:
	if not is_instance_valid(shape) or not is_instance_valid(column):
		return
	if column.has_method("reset_hits"):
		column.reset_hits()
	shape.disabled = true
	var t := get_tree().create_timer(0.02)
	t.timeout.connect(func():
		if is_instance_valid(shape):
			shape.disabled = false
	)


# Oltre a far avanzare la catena veloce (classe base), fa "ticchettare" le
# colonne big_chain attive (solo una volta ancorate, cioe' a "grow" finita)
# e avvia il ritiro a fine durata
func _update_power(delta: float) -> void:
	super._update_power(delta)

	for entry in _columns.duplicate():
		if not is_instance_valid(entry["node"]):
			_columns.erase(entry)
			continue
		if not entry["formed"] or entry["retracting"]:
			continue  # sta ancora crescendo, o il ritiro e' gia' partito: niente da fare qui
		entry["time_left"] -= delta
		entry["tick_left"] -= delta
		if entry["tick_left"] <= 0.0:
			entry["tick_left"] = float(params["column_tick_interval"])
			_retrigger_column_hits(entry["node"], entry["shape"])
		if entry["time_left"] <= 0.0:
			entry["retracting"] = true
			_retract_column(entry)

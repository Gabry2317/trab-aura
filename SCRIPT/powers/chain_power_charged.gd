extends "res://SCRIPT/powers/chain_power.gd"
# Attacco caricato di Bisio: estende chain_power.gd (la catena veloce a
# tocco) aggiungendo la mira caricata sullo stesso tasto "secondary".
#
#  - tocco veloce (sotto charge_time)  -> catena veloce (ereditata da chain_power.gd)
#  - tenuto premuto oltre charge_time  -> nasce un pointer trasparente
#    (pointer_sheet) che segue l'input orizzontale del player; rilasciando
#    il tasto il pointer sparisce e al suo posto nasce una colonna
#    (big_chain) che danneggia chi tocca e resta li' come area denial per
#    column_duration secondi, colpendo di nuovo chi rimane dentro ogni
#    column_tick_interval. Se il pointer si allontana troppo dal player
#    (pointer_max_distance) la carica si annulla da sola, senza colonna.

var _pointer: Sprite2D = null    # catena trasparente che segue la mira durante la carica
var _pointer_x: float = 0.0      # posizione (mondo, X) del pointer durante la carica
var _charging: bool = false      # true mentre il player tiene premuto e mira
var _columns: Array = []         # colonne big_chain attive (area denial in corso)


func default_params() -> Dictionary:
	var params: Dictionary = super.default_params()  # tutti i settings della catena veloce
	var charge_params: Dictionary = {
		# --- soglia di carica ---
		"charge_time": 0.5,           # secondi da tenere premuto prima che parta la carica

		# --- pointer (mira) ---
		"pointer_sheet": "res://sprite/Player/Iacobisio/Secondary/pointer.png",  # catena trasparente di mira
		"pointer_alpha": 1,        # trasparenza del pointer (0-1)
		"pointer_height_ratio": 1,  # altezza del pointer rispetto al player
		"pointer_start_x": 40.0,      # distanza orizzontale dal player a cui nasce il pointer
		"pointer_feet_y": 70.0,       # quota dei piedi del pointer rispetto all'origine del player
		"pointer_speed": 300.0,       # px/s: velocita' con cui si sposta il pointer mentre si mira
		"pointer_max_distance": 500.0,  # oltre questa distanza dal player la carica si annulla

		# --- colonna (big_chain, area denial) ---
		"column_sheet": "res://sprite/Player/Iacobisio/Secondary/big_chains.png",  # foglio della colonna
		"column_hframes": 7,          # colonne del foglio della colonna
		"column_vframes": 2,          # righe del foglio della colonna
		"column_frames": 14,          # fotogrammi usati per l'animazione di comparsa
		"column_fps": 24.0,           # velocita' dell'animazione di comparsa della colonna
		"column_height_ratio": 1.4,   # altezza della colonna rispetto al player
		"column_hitbox_w": 0.7,       # larghezza hitbox della colonna (frazione della sprite)
		"column_hitbox_h": 0.9,       # altezza hitbox della colonna (frazione della sprite)
		"column_damage": 10,          # danno per ogni "tick" della colonna
		"column_duration": 5.0,       # secondi in cui la colonna resta attiva (area denial)
		"column_tick_interval": 0.4,  # ogni quanti secondi la colonna puo' colpire di nuovo chi resta dentro
		"column_fade_out": 0.3,       # secondi di dissolvenza quando la colonna scompare
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

	var dir: float = player.get_facing_dir()
	var sprite := Sprite2D.new()
	sprite.name = "ChainPointer"
	sprite.texture = tex
	sprite.centered = false
	sprite.offset = Vector2(-tex.get_size().x / 2.0, -tex.get_size().y)
	var scale_factor: float = (player.get_visual_height() * float(params["pointer_height_ratio"])) / tex.get_size().y
	sprite.scale = Vector2.ONE * scale_factor
	sprite.flip_h = dir < 0.0
	sprite.modulate = Color(1.0, 1.0, 1.0, clampf(float(params["pointer_alpha"]), 0.0, 1.0))

	player.get_parent().add_child(sprite)
	_pointer = sprite
	_pointer_x = player.global_position.x + dir * float(params["pointer_start_x"])
	_update_pointer_position()


# Chiamata ogni frame mentre "secondary" resta premuto dopo la soglia: il
# pointer si sposta con l'input orizzontale del player (mira libera), ma se
# si allontana troppo dal player la carica si annulla da sola
func update_charge(delta: float) -> void:
	if not is_instance_valid(_pointer):
		return

	var input_dir: float = player.get_input_direction()
	_pointer_x += input_dir * float(params["pointer_speed"]) * delta
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
# e al suo posto si abbatte la colonna (big_chain)
func release_charge() -> void:
	if not _charging:
		return
	_charging = false
	if is_instance_valid(_pointer):
		var col_pos: Vector2 = _pointer.global_position
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


# Crea la colonna (big_chain) sul punto mirato: fa danno a chi tocca e resta
# li' come area denial per column_duration secondi, colpendo di nuovo ogni
# column_tick_interval chi rimane dentro
func _spawn_column(pos: Vector2) -> void:
	var tex: Texture2D = load(str(params["column_sheet"]))
	if tex == null:
		push_warning("chain_power_charged: colonna '%s' non trovata" % params["column_sheet"])
		return

	var hframes: int = int(params["column_hframes"])
	var vframes: int = int(params["column_vframes"])

	var column = Area2D.new()  # senza tipo: damage/source arrivano dallo script assegnato sotto
	column.name = "BigChainColumn"
	column.set_script(load(str(params["column_hitbox_script"])))
	column.collision_layer = player.current_hitbox.collision_layer
	column.collision_mask = player.current_hitbox.collision_mask
	column.damage = int(params["column_damage"])
	column.source = player

	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	_add_sliced_animation(frames, &"column", tex, hframes, vframes, int(params["column_frames"]), float(params["column_fps"]), false)
	var fw: float = tex.get_size().x / hframes
	var fh: float = tex.get_size().y / vframes
	var col_scale: float = (player.get_visual_height() * float(params["column_height_ratio"])) / fh

	var sprite := AnimatedSprite2D.new()
	sprite.name = "Sprite"
	sprite.sprite_frames = frames
	sprite.centered = false
	sprite.offset = Vector2(-fw / 2.0, -fh)
	sprite.scale = Vector2.ONE * col_scale
	column.add_child(sprite)

	var rect := RectangleShape2D.new()
	rect.size = Vector2(fw * col_scale * float(params["column_hitbox_w"]), fh * col_scale * float(params["column_hitbox_h"]))
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	shape.shape = rect
	shape.position = Vector2(0.0, -rect.size.y / 2.0)
	column.add_child(shape)

	player.get_parent().add_child(column)
	column.global_position = pos
	sprite.play(&"column")

	if bool(params["debug"]):
		print("[ChainCharged] colonna creata in ", pos)

	_columns.append({
		"node": column,
		"shape": shape,
		"time_left": float(params["column_duration"]),
		"tick_left": float(params["column_tick_interval"]),
	})


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


# Dissolvenza e rimozione della colonna a fine durata
func _despawn_column(entry: Dictionary) -> void:
	_columns.erase(entry)
	var column: Area2D = entry["node"]
	var shape: CollisionShape2D = entry["shape"]
	if not is_instance_valid(column):
		return
	if is_instance_valid(shape):
		shape.set_deferred("disabled", true)
	var fade: float = float(params["column_fade_out"])
	if fade <= 0.0:
		column.queue_free()
		return
	var tween: Tween = column.create_tween()
	tween.tween_property(column, "modulate:a", 0.0, fade)
	tween.tween_callback(column.queue_free)


# Oltre a far avanzare la catena veloce (classe base), fa "ticchettare" le
# colonne big_chain attive e le rimuove a fine durata
func _update_power(delta: float) -> void:
	super._update_power(delta)

	for entry in _columns.duplicate():
		if not is_instance_valid(entry["node"]):
			_columns.erase(entry)
			continue
		entry["time_left"] -= delta
		entry["tick_left"] -= delta
		if entry["tick_left"] <= 0.0:
			entry["tick_left"] = float(params["column_tick_interval"])
			_retrigger_column_hits(entry["node"], entry["shape"])
		if entry["time_left"] <= 0.0:
			_despawn_column(entry)

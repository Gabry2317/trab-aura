extends "res://SCRIPT/powers/fighter_power.gd"
# Rosa di coltelli (secondaria di Andrix, tasto destro).
# 1) premendo il tasto parte un ventaglio di "knife_count" coltelli, aperto di
#    "spread_angle" gradi in totale (centrato nella direzione in cui guarda il player)
# 2) ogni coltello vola in linea retta a velocita' costante attraverso il livello
# 3) se tocca l'avversario (Hurtbox) gli toglie "damage" e sparisce; se non colpisce
#    nessuno sparisce quando esce dallo schermo o supera "max_distance"
# Ogni coltello e' una hitbox a se': piu' coltelli a segno = piu' danni.

var _texture: Texture2D
var _knives: Array = []          # coltelli in volo
var _cast_left: float = 0.0      # secondi in cui il player resta fermo dopo il lancio


func default_params() -> Dictionary:
	return {
		"damage": 1,                 # danno di OGNI coltello che colpisce l'avversario
		"cooldown": 1.5,              # secondi tra un lancio e il successivo
		"stamina_min": 25.0,          # stamina minima per poter lanciare
		"stamina_cost": 25.0,         # stamina consumata a ogni lancio
		"sprite": "res://sprite/Player/Andrix/coltello/coltello.png",
		"sprite_points_left": true,   # true = nell'immagine la punta del coltello e' a sinistra
		"sprite_offset_y": 10.0,      # px (dell'immagine) per centrare il coltello sul punto di origine
		"size_ratio": 0.3,            # larghezza dell'immagine rispetto all'altezza del player (0.3 = 30%)
		"knife_count": 5,             # quanti coltelli nella rosa
		"spread_angle": 30.0,         # apertura totale del ventaglio in gradi (0 = tutti in fila)
		"speed": 600.0,               # px/s
		"max_distance": 5000.0,       # oltre questa distanza sparisce comunque
		"offscreen_margin": 150.0,    # margine oltre lo schermo prima che sparisca
		"start_x": 40.0,              # distanza orizzontale dal player a cui nascono
		"spawn_y": 0.0,               # scostamento verticale rispetto al torace del player
		"cast_time": 0.2,             # secondi in cui il player resta fermo dopo il lancio
		"hitbox_w": 0.8,              # larghezza hitbox (frazione della larghezza dell'immagine)
		"hitbox_h": 0.3,              # altezza hitbox (frazione dell'altezza dell'immagine)
		"hitbox_script": "res://SCRIPT/punch_hitbox_trab.gd",  # script della hitbox che infligge il danno
		"debug": false,               # true = stampa in console cosa tocca un coltello
	}


func _on_setup() -> void:
	_texture = load(str(params["sprite"]))
	if _texture == null:
		push_warning("knife_power: immagine '%s' non trovata" % params["sprite"])


func is_busy() -> bool:
	return _cast_left > 0.0


func can_use() -> bool:
	return _texture != null and super.can_use()


func use() -> void:
	super.use()
	_cast_left = float(params["cast_time"])
	player.velocity.x = 0.0
	_throw_knives()


# Il player e' stato colpito subito dopo il lancio: torna libero (i coltelli gia' partiti continuano)
func on_player_hit() -> void:
	_cast_left = 0.0


func _throw_knives() -> void:
	var dir: float = player.get_facing_dir()
	var count: int = maxi(int(params["knife_count"]), 1)
	var spread: float = deg_to_rad(float(params["spread_angle"]))
	# origine: all'altezza del torace (la hurtbox), un po' davanti al player
	var origin := Vector2(
		player.global_position.x + dir * float(params["start_x"]),
		player.hurtbox.global_position.y + float(params["spawn_y"])
	)
	for i in range(count):
		var angle: float = 0.0
		if count > 1:
			angle = lerpf(-spread / 2.0, spread / 2.0, float(i) / float(count - 1))
		_spawn_knife(origin, dir, angle)


func _spawn_knife(origin: Vector2, dir: float, angle: float) -> void:
	var knife = Area2D.new()  # senza tipo: damage/source arrivano dallo script assegnato sotto
	knife.name = "Knife"
	knife.set_script(load(str(params["hitbox_script"])))
	knife.collision_layer = player.current_hitbox.collision_layer
	knife.collision_mask = player.current_hitbox.collision_mask
	knife.damage = int(params["damage"])
	knife.source = player
	# rotazione = direzione di volo (angle positivo = verso il basso)
	knife.rotation = angle * dir
	knife.set_meta("vel", Vector2(cos(angle) * dir, sin(angle)) * float(params["speed"]))
	knife.set_meta("start", origin)

	var tex_w: float = _texture.get_size().x
	var tex_h: float = _texture.get_size().y
	# dimensione proporzionata al player, qualunque sia la sua scala
	var knife_scale: float = (player.get_visual_height() * float(params["size_ratio"])) / tex_w

	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = _texture
	sprite.offset = Vector2(0.0, float(params["sprite_offset_y"]))
	sprite.scale = Vector2.ONE * knife_scale
	# la punta deve guardare nella direzione di volo
	sprite.flip_h = bool(params["sprite_points_left"]) == (dir > 0.0)
	knife.add_child(sprite)

	var rect := RectangleShape2D.new()
	rect.size = Vector2(tex_w * knife_scale * float(params["hitbox_w"]), tex_h * knife_scale * float(params["hitbox_h"]))
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	shape.shape = rect
	knife.add_child(shape)

	# aggiunto al livello (non al player): il coltello prosegue anche se il player si muove
	player.get_parent().add_child(knife)
	knife.global_position = origin
	knife.area_entered.connect(_on_hit.bind(knife))
	_knives.append(knife)


# Sparisce solo se tocca un avversario (Hurtbox): il player stesso e i suoi nodi figli,
# pavimento, muri e hitbox varie si ignorano. Il danno lo infligge lo script della hitbox.
func _on_hit(other: Node, knife: Area2D) -> void:
	if not is_instance_valid(knife) or knife.is_queued_for_deletion():
		return
	if other == player or player.is_ancestor_of(other):
		return
	if bool(params["debug"]):
		print("[Knife] tocca: ", other.get_path(), " (", other.get_class(), ")")
	if other is Hurtbox:
		(knife.get_node("CollisionShape2D") as CollisionShape2D).set_deferred("disabled", true)
		_remove_knife(knife)


func _remove_knife(knife: Area2D) -> void:
	_knives.erase(knife)
	if is_instance_valid(knife):
		knife.queue_free()


# Volo: ogni coltello avanza a velocita' costante finche' non esce dallo schermo
func _update_power(delta: float) -> void:
	_cast_left = maxf(_cast_left - delta, 0.0)
	if _knives.is_empty():
		return

	var vp := get_viewport()
	var view: Rect2 = vp.get_canvas_transform().affine_inverse() * vp.get_visible_rect()
	view = view.grow(float(params["offscreen_margin"]))

	for knife in _knives.duplicate():
		if not is_instance_valid(knife):
			_knives.erase(knife)
			continue
		knife.global_position += knife.get_meta("vel") * delta
		var travelled: float = knife.global_position.distance_to(knife.get_meta("start"))
		if travelled >= float(params["max_distance"]) or not view.has_point(knife.global_position):
			_remove_knife(knife)

extends "res://SCRIPT/powers/fighter_power.gd"
# Attacco secondario di Nakakata: usa i primi 12 frame del foglio pugno,
# raggiunge il nemico alle spalle e infligge una percentuale della sua vita massima.

const ANIMATION_NAME := &"secondary_shadow_strike"

var _busy_left: float = 0.0
var _animation_duration: float = 0.8


func default_params() -> Dictionary:
	return {
		"cooldown": 5.0,
		"stamina_min": 40.0,
		"stamina_cost": 40.0,
		"damage_ratio": 0.45,
		"animation_fps": 15.0,
		"teleport_offset": 70.0,
		"sprite": "res://sprite/Player/Nakakata/punc/nakakata-punch.png",
		"hframes": 5,
		"frame_width": 256,
		"frame_height": 256,
		"frame_count": 12,
	}


func _on_setup() -> void:
	var sprite_frames: SpriteFrames = player.current_sprite.sprite_frames
	if sprite_frames == null:
		push_warning("Nakakata: SpriteFrames mancanti per l'attacco secondario")
		return

	var fps: float = maxf(float(params["animation_fps"]), 1.0)
	_animation_duration = float(params["frame_count"]) / fps
	if not sprite_frames.has_animation(ANIMATION_NAME):
		var texture: Texture2D = load(str(params["sprite"]))
		if texture == null:
			push_warning("Nakakata: foglio attacco non trovato: %s" % params["sprite"])
			return
		sprite_frames.add_animation(ANIMATION_NAME)
		sprite_frames.set_animation_loop(ANIMATION_NAME, false)
		sprite_frames.set_animation_speed(ANIMATION_NAME, fps)
		var columns: int = int(params["hframes"])
		var frame_width: int = int(params["frame_width"])
		var frame_height: int = int(params["frame_height"])
		for frame_index in range(int(params["frame_count"])):
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2((frame_index % columns) * frame_width, (frame_index / columns) * frame_height, frame_width, frame_height)
			sprite_frames.add_frame(ANIMATION_NAME, atlas)


func can_use() -> bool:
	return player.current_sprite.sprite_frames.has_animation(ANIMATION_NAME) and super.can_use()


func is_busy() -> bool:
	return _busy_left > 0.0


func use() -> void:
	var target: Player = _find_opponent()
	if target == null:
		return

	super.use()
	_busy_left = _animation_duration
	player.velocity = Vector2.ZERO
	player.is_blocking = false
	player.current_sprite.play(ANIMATION_NAME)
	player.synced_animation = ANIMATION_NAME

	# Attraversa il bersaglio: apparendo sul lato opposto a quello di partenza,
	# la mossa può concludersi sia alla sua destra sia alla sua sinistra.
	var destination_side: float = 1.0 if player.global_position.x < target.global_position.x else -1.0
	player.global_position = target.global_position + Vector2(destination_side * float(params["teleport_offset"]), 0.0)
	player._set_facing(target.global_position.x < player.global_position.x)
	var damage: int = maxi(roundi(float(target.max_health) * float(params["damage_ratio"])), 1)
	target.hurtbox.take_damage(damage, player)


func _find_opponent() -> Player:
	var closest: Player = null
	var closest_distance: float = INF
	for node in player.get_parent().get_children():
		if node is Player and node != player and not node.is_dead and node.current_health > 0:
			var distance: float = player.global_position.distance_squared_to(node.global_position)
			if distance < closest_distance:
				closest = node
				closest_distance = distance
	return closest


func _update_power(delta: float) -> void:
	_busy_left = maxf(_busy_left - delta, 0.0)
	if _busy_left == 0.0 and player.current_sprite.animation == ANIMATION_NAME:
		player.current_sprite.play("idle")
		player.synced_animation = "idle"

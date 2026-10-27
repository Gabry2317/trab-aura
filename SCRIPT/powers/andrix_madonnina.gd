extends "res://SCRIPT/powers/knife_power.gd"
# Secondaria di Andrix: un tocco lancia i coltelli; tenere premuto carica la
# Madonnina, che parte al rilascio dopo la soglia.

var _madonna_texture: Texture2D
var _target: Player
var _overlay_layer: CanvasLayer
var _statue: TextureRect
var _flash: ColorRect
var _poison_cloud: Node2D
var _poison_area: Area2D
var _phase: String = ""
var _phase_left: float = 0.0
var _charging: bool = false
var _fall_start_y: float = 0.0
var _fall_end_y: float = 0.0
var _impact_position: Vector2 = Vector2.ZERO
var _poison_left: float = 0.0
var _poison_tick_left: float = 0.0
var _rng := RandomNumberGenerator.new()


func default_params() -> Dictionary:
	var values: Dictionary = super.default_params()
	values.merge({
		"statue_sprite": "res://sprite/Player/Andrix/madonnina.png",
		"statue_time": 3.0,
		"flash_time": 0.3,
		"fall_time": 0.55,
		"statue_width": 280.0,
		"statue_height": 280.0,
		"hold_time": 0.5,
		"poison_duration": 4.0,
		"poison_tick_interval": 0.5,
		"poison_damage": 3,
		"poison_radius": 250.0,
		"poison_particle_amount": 72,
		"knife_effect_time": 1.0,
		"madonna_stamina_min": 100.0,
		"madonna_stamina_cost": 100.0,
	}, true)
	return values


func _on_setup() -> void:
	super._on_setup()
	_rng.randomize()
	_madonna_texture = load(str(params["statue_sprite"]))
	if _madonna_texture == null:
		push_warning("Andrix: immagine della Madonnina non trovata: %s" % params["statue_sprite"])


func can_use() -> bool:
	if _madonna_texture == null or not _phase.is_empty() or not super.can_use():
		return false
	if player._secondary_hold_time >= charge_time():
		return _has_stamina(float(params["madonna_stamina_min"]))
	return true


func is_busy() -> bool:
	return super.is_busy() or _charging


func has_charged_attack() -> bool:
	return true


func charge_time() -> float:
	return maxf(float(params["hold_time"]), 0.0)


func start_charge() -> bool:
	if not _has_stamina(float(params["madonna_stamina_min"])):
		return false
	_charging = true
	return true


func release_charge() -> void:
	if not _charging:
		return
	_charging = false
	_start_madonnina()


func on_player_hit() -> void:
	if _charging:
		_charging = false
		return
	super.on_player_hit()


func _start_madonnina() -> void:
	cooldown_left = float(params["cooldown"])
	_spend_stamina(float(params["madonna_stamina_cost"]))
	_target = _find_opponent()
	_impact_position = _get_map_center_ground()
	_create_effects()
	_phase = "statue"
	_phase_left = maxf(float(params["statue_time"]), 0.0)


func _create_effects() -> void:
	var scene_root: Node = player.get_tree().current_scene
	if scene_root == null:
		scene_root = player.get_tree().root

	_overlay_layer = CanvasLayer.new()
	_overlay_layer.name = "AndrixMadonninaEffect"
	_overlay_layer.layer = 100
	scene_root.add_child(_overlay_layer)

	var screen := Control.new()
	screen.name = "ScreenEffects"
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_layer.add_child(screen)

	_statue = TextureRect.new()
	_statue.name = "Madonnina"
	_statue.texture = _madonna_texture
	_statue.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_statue.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_statue.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_statue.offset_left = -float(params["statue_width"]) / 2.0
	_statue.offset_right = float(params["statue_width"]) / 2.0
	_statue.offset_top = 8.0
	_statue.offset_bottom = 8.0 + float(params["statue_height"])
	_statue.pivot_offset = Vector2(float(params["statue_width"]) / 2.0, float(params["statue_height"]) / 2.0)
	screen.add_child(_statue)

	_flash = ColorRect.new()
	_flash.name = "WhiteFlash"
	_flash.color = Color.WHITE
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.visible = false
	screen.add_child(_flash)


func _get_map_center_ground() -> Vector2:
	var viewport: Viewport = player.get_viewport()
	var view_size: Vector2 = viewport.get_visible_rect().size
	var inverse_transform: Transform2D = viewport.get_canvas_transform().affine_inverse()
	var map_center: Vector2 = inverse_transform * Vector2(view_size.x * 0.5, view_size.y * 0.5)
	var floor_y: float = player.global_position.y
	if is_instance_valid(_target):
		floor_y = maxf(floor_y, _target.global_position.y)
	return Vector2(map_center.x, floor_y)


func _find_opponent() -> Player:
	var closest: Player = null
	var closest_distance: float = INF
	for candidate in player.get_tree().get_nodes_in_group("players"):
		if candidate is Player and candidate != player and not candidate.is_dead and candidate.current_health > 0:
			var distance: float = player.global_position.distance_squared_to(candidate.global_position)
			if distance < closest_distance:
				closest = candidate
				closest_distance = distance
	return closest


func _update_power(delta: float) -> void:
	super._update_power(delta)
	_update_poison(delta)
	var remaining: float = delta
	while remaining > 0.0 and not _phase.is_empty():
		if _phase == "fall":
			var fall_step: float = minf(remaining, _phase_left)
			_phase_left -= fall_step
			remaining -= fall_step
			var fall_duration: float = maxf(float(params["fall_time"]), 0.001)
			var progress: float = 1.0 - _phase_left / fall_duration
			_statue.offset_top = lerpf(_fall_start_y, _fall_end_y, progress)
			_statue.offset_bottom = _statue.offset_top + float(params["statue_height"])
			_statue.rotation = progress * PI * 0.5
			if _phase_left <= 0.0:
				_advance_phase()
			continue
		if remaining < _phase_left:
			_phase_left -= remaining
			break
		remaining -= _phase_left
		_advance_phase()


func _advance_phase() -> void:
	match _phase:
		"statue":
			_flash.visible = true
			_phase = "flash"
			_phase_left = maxf(float(params["flash_time"]), 0.0)
		"flash":
			_flash.visible = false
			_phase = "fall"
			_phase_left = maxf(float(params["fall_time"]), 0.001)
			_fall_start_y = _statue.offset_top
			var floor_screen: Vector2 = player.get_viewport().get_canvas_transform() * _impact_position
			_fall_end_y = floor_screen.y - float(params["statue_height"]) / 2.0
		"fall":
			if _rng.randi_range(0, 1) == 0:
				_spawn_poison_cloud()
				_phase = "poison"
				_phase_left = float(params["poison_duration"])
			else:
				_throw_impact_rose()
				_phase = "knife_effect"
				_phase_left = float(params["knife_effect_time"])
		"poison", "knife_effect":
			_clear_effects()
			_phase = ""
			_phase_left = 0.0


func _throw_impact_rose() -> void:
	var direction: float = player.get_facing_dir()
	if is_instance_valid(_target):
		var dx: float = _target.global_position.x - _impact_position.x
		if not is_zero_approx(dx):
			direction = signf(dx)
	var count: int = maxi(int(params["knife_count"]), 1)
	var spread: float = deg_to_rad(float(params["spread_angle"]))
	for i in range(count):
		var angle: float = 0.0
		if count > 1:
			angle = lerpf(-spread / 2.0, spread / 2.0, float(i) / float(count - 1))
		_spawn_knife(_impact_position, direction, angle)
	_statue.visible = false


func _spawn_poison_cloud() -> void:
	var scene_root: Node = player.get_tree().current_scene
	if scene_root == null:
		scene_root = player.get_tree().root
	_poison_cloud = Node2D.new()
	_poison_cloud.name = "MadonninaPoisonCloud"
	_poison_cloud.global_position = _impact_position
	scene_root.add_child(_poison_cloud)

	var particles := CPUParticles2D.new()
	particles.name = "PoisonParticles"
	particles.amount = int(params["poison_particle_amount"])
	particles.lifetime = 1.1
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = Vector2(float(params["poison_radius"]) * 0.8, 45.0)
	particles.direction = Vector2(0.0, -1.0)
	particles.spread = 35.0
	particles.gravity = Vector2(0.0, -14.0)
	particles.initial_velocity_min = 12.0
	particles.initial_velocity_max = 48.0
	particles.scale_amount_min = 1.4
	particles.scale_amount_max = 2.8
	particles.color = Color(0.35, 0.95, 0.16, 0.58)
	particles.texture = _make_soft_particle_texture()
	particles.position = Vector2(0.0, -float(params["poison_radius"]) * 0.35)
	_poison_cloud.add_child(particles)

	_poison_area = Area2D.new()
	_poison_area.name = "PoisonArea"
	_poison_area.collision_layer = player.current_hitbox.collision_layer
	_poison_area.collision_mask = player.current_hitbox.collision_mask
	_poison_area.monitoring = true
	_poison_cloud.add_child(_poison_area)
	var shape := CircleShape2D.new()
	shape.radius = float(params["poison_radius"])
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = Vector2(0.0, -float(params["poison_radius"]) * 0.35)
	_poison_area.add_child(collision)
	_poison_left = float(params["poison_duration"])
	_poison_tick_left = float(params["poison_tick_interval"])


func _make_soft_particle_texture() -> Texture2D:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var distance: float = Vector2(x - 31.5, y - 31.5).length() / 31.5
			var alpha: float = pow(clampf(1.0 - distance, 0.0, 1.0), 2.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)


func _update_poison(delta: float) -> void:
	if _poison_left <= 0.0:
		return
	_poison_left = maxf(_poison_left - delta, 0.0)
	_poison_tick_left -= delta
	if _poison_tick_left <= 0.0 and is_instance_valid(_poison_area):
		_poison_tick_left = float(params["poison_tick_interval"])
		for area in _poison_area.get_overlapping_areas():
			if area is Hurtbox and area != player.hurtbox:
				area.take_damage(int(params["poison_damage"]), player)
	if _poison_left == 0.0:
		if is_instance_valid(_poison_cloud):
			_poison_cloud.queue_free()
		_poison_cloud = null
		_poison_area = null


func _clear_effects() -> void:
	if is_instance_valid(_overlay_layer):
		_overlay_layer.queue_free()
	if is_instance_valid(_poison_cloud):
		_poison_cloud.queue_free()
	_overlay_layer = null
	_statue = null
	_flash = null
	_poison_cloud = null
	_poison_area = null
	_target = null

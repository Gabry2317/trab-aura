extends "res://SCRIPT/powers/knife_power.gd"
# Secondaria di Andrix: un tocco lancia i coltelli; tenere premuto carica la
# Madonnina, che parte al rilascio dopo la soglia.

var _madonna_texture: Texture2D
var _target: Player
var _overlay_layer: CanvasLayer
var _statue: TextureRect
var _flash: ColorRect
var _phase: String = ""
var _phase_left: float = 0.0
var _charging: bool = false


func default_params() -> Dictionary:
	var values: Dictionary = super.default_params()
	values.merge({
		"statue_sprite": "res://sprite/Player/Andrix/madonnina.png",
		"statue_time": 3.0,
		"flash_time": 0.3,
		"freeze_time": 7.0,
		"statue_width": 280.0,
		"statue_height": 280.0,
		"hold_time": 0.5,
	}, true)
	return values


func _on_setup() -> void:
	super._on_setup()
	_madonna_texture = load(str(params["statue_sprite"]))
	if _madonna_texture == null:
		push_warning("Andrix: immagine della Madonnina non trovata: %s" % params["statue_sprite"])


func can_use() -> bool:
	return _madonna_texture != null and _phase.is_empty() and super.can_use()


func is_busy() -> bool:
	return super.is_busy() or _charging


func has_charged_attack() -> bool:
	return true


func charge_time() -> float:
	return maxf(float(params["hold_time"]), 0.0)


func start_charge() -> bool:
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
	_spend_stamina(float(params["stamina_cost"]))
	_target = _find_opponent()
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
	screen.add_child(_statue)

	_flash = ColorRect.new()
	_flash.name = "WhiteFlash"
	_flash.color = Color.WHITE
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.visible = false
	screen.add_child(_flash)


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
	var remaining: float = delta
	while remaining > 0.0 and not _phase.is_empty():
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
			_statue.visible = false
			_flash.visible = false
			if is_instance_valid(_target) and not _target.is_dead and _target.current_health > 0:
				_target.freeze_for(float(params["freeze_time"]))
			_phase = "freeze"
			_phase_left = maxf(float(params["freeze_time"]), 0.0)
		"freeze":
			_clear_effects()
			_phase = ""
			_phase_left = 0.0


func _clear_effects() -> void:
	if is_instance_valid(_overlay_layer):
		_overlay_layer.queue_free()
	_overlay_layer = null
	_statue = null
	_flash = null
	_target = null

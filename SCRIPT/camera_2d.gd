extends Camera2D

const MARGIN_X := 100
const MARGIN_Y := 60
const MIN_ZOOM := 0.5
const MAX_ZOOM := 3.0
const ZOOM_SPEED := 4.0

@export var vertical_range: float = 50.0
@export var vertical_limit_smoothing: float = 8.0

var target_nodes: Array[Node2D] = []
var base_y: float = 0.0
var _shake_strength: float = 0.0
var _shake_time: float = 0.0
var _shake_duration: float = 0.16
var _shake_offset: Vector2 = Vector2.ZERO
var _cinematic_target: Node2D
var _cinematic_zoom: float = 2.15
var _cinematic_offset: Vector2 = Vector2(0.0, -28.0)

func _ready() -> void:
	make_current()
	position_smoothing_enabled = true
	position_smoothing_speed = 5.0
	base_y = global_position.y
	for p in get_tree().get_nodes_in_group("players"):
		if p is Node2D:
			target_nodes.append(p)
	_update_camera(1.0, 1.0)
	reset_smoothing()

func _process(delta: float) -> void:
	_update_camera(vertical_limit_smoothing * delta, ZOOM_SPEED * delta)
	_update_shake(delta)

func set_cinematic_focus(target: Node2D, zoom_value: float = 2.15, focus_offset: Vector2 = Vector2(0.0, -28.0)) -> void:
	_cinematic_target = target
	_cinematic_zoom = zoom_value
	_cinematic_offset = focus_offset

func clear_cinematic_focus() -> void:
	_cinematic_target = null
	_cinematic_offset = Vector2(0.0, -28.0)

func shake(strength: float = 8.0, duration: float = 0.16) -> void:
	_shake_strength = maxf(_shake_strength, strength)
	_shake_duration = maxf(_shake_duration, duration)
	_shake_time = maxf(_shake_time, duration)

func _update_shake(delta: float) -> void:
	if _shake_offset != Vector2.ZERO:
		offset -= _shake_offset
	if _shake_time <= 0.0:
		_shake_offset = Vector2.ZERO
		return
	_shake_time = maxf(_shake_time - delta, 0.0)
	var fade := _shake_time / _shake_duration
	_shake_offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_strength * fade
	offset += _shake_offset
	if _shake_time <= 0.0:
		_shake_strength = 0.0
		_shake_duration = 0.16

func _update_camera(pos_t: float, zoom_t: float) -> void:
	if is_instance_valid(_cinematic_target):
		global_position = global_position.lerp(_cinematic_target.global_position + _cinematic_offset, pos_t)
		zoom = zoom.lerp(Vector2(_cinematic_zoom, _cinematic_zoom), zoom_t)
		return
	if target_nodes.is_empty():
		return
	var rect := Rect2(target_nodes[0].global_position, Vector2.ZERO)
	for n in target_nodes:
		rect = rect.expand(n.global_position)
	var center := rect.get_center()
	var target_y = clamp(center.y, base_y - vertical_range, base_y + vertical_range)
	global_position = Vector2(center.x, lerp(global_position.y, target_y, pos_t))
	var needed := Vector2(max(rect.size.x + MARGIN_X * 2.0, 1.0), max(rect.size.y + MARGIN_Y * 2.0, 1.0))
	var vp := get_viewport_rect().size
	var z = clampf(min(vp.x / needed.x, vp.y / needed.y), MIN_ZOOM, MAX_ZOOM)
	zoom = zoom.lerp(Vector2(z, z), zoom_t)
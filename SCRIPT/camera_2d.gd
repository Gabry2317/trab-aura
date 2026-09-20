extends Camera2D

const MARGIN_X := 100       # pixel oltre le schiene dei player
const MARGIN_Y := 60
const MIN_ZOOM := 0.5        # non si allontana mai oltre lo zoom 1:1
const MAX_ZOOM := 3.0
const ZOOM_SPEED := 4.0

@export var vertical_range: float = 50.0
@export var vertical_limit_smoothing: float = 8.0

var target_nodes: Array[Node2D] = []
var base_y: float = 0.0

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

func _update_camera(pos_t: float, zoom_t: float) -> void:
	if target_nodes.is_empty():
		return

	var rect := Rect2(target_nodes[0].global_position, Vector2.ZERO)
	for n in target_nodes:
		rect = rect.expand(n.global_position)

	var center := rect.get_center()
	var target_y = clamp(center.y, base_y - vertical_range, base_y + vertical_range)
	global_position = Vector2(center.x, lerp(global_position.y, target_y, pos_t))

	var needed := Vector2(
		max(rect.size.x + MARGIN_X * 2.0, 1.0),
		max(rect.size.y + MARGIN_Y * 2.0, 1.0)
	)
	var vp := get_viewport_rect().size
	var z = clampf(min(vp.x / needed.x, vp.y / needed.y), MIN_ZOOM, MAX_ZOOM)
	zoom = zoom.lerp(Vector2(z, z), zoom_t)

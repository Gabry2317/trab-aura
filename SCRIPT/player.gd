extends CharacterBody2D
class_name Player

signal health_changed

@export var max_health: int = 100
@onready var current_health: int = max_health

var isHurt: bool = false

const SPEED = 100.0
const RUNSPEED = 250.0
const JUMP_VELOCITY = -300.0

# 0 = trab, 1 = iacopo
const skin = 1

@onready var animated_sprite = $TRAB_Sprite2D
@onready var animated_sprite2 = $Iaco_Spto

var current_sprite: AnimatedSprite2D


func _ready() -> void:
	if skin == 0:
		current_sprite = animated_sprite
		animated_sprite2.visible = false
	elif skin == 1:
		current_sprite = animated_sprite2
		animated_sprite.visible = false


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		jumphurt()

	var is_running := Input.is_key_pressed(KEY_SHIFT)
	var current_speed := RUNSPEED if is_running else SPEED

	var direction := Input.get_axis("ui_left", "ui_right")

	if direction:
		velocity.x = direction * current_speed
		current_sprite.flip_h = direction < 0
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	if not is_on_floor():
		if velocity.y < 0:
			current_sprite.play("jump")
		else:
			current_sprite.play("fall")
	elif direction:
		if is_running:
			current_sprite.play("run")
		else:
			current_sprite.play("walk")
	else:
		current_sprite.play("idle")

	move_and_slide()


func jumphurt() -> void:
	current_health -= 10
	current_health = max(current_health, 0)
	isHurt = true
	health_changed.emit()

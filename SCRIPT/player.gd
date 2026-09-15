extends CharacterBody2D

const SPEED = 150.0
const RUNSPEED = 250.0
const JUMP_VELOCITY = -300.0

@onready var animated_sprite = $AnimatedSprite2D


func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Check if running (Shift held).
	var is_running := Input.is_key_pressed(KEY_SHIFT)
	var current_speed := RUNSPEED if is_running else SPEED

	# Get the input direction and handle the movement/deceleration.
	var direction := Input.get_axis("ui_left", "ui_right")
	if direction:
		velocity.x = direction * current_speed
		if is_running:
			animated_sprite.play("run")
		else:
			animated_sprite.play("walk")
		animated_sprite.flip_h = direction < 0
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		animated_sprite.play("idle")

	move_and_slide()

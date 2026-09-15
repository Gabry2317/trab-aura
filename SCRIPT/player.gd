class_name Player
extends CharacterBody2D

signal health_changed

@export var max_health: int = 100
var current_health: int = max_health:
	set(value):
		current_health = clampi(value, 0, max_health)
		health_changed.emit()

@onready var state_machine: StateMachine = $StateMachine
@onready var animation: AnimationPlayer = $AnimationPlayer

@export var speed: float = 200.0
@export var jump_velocity: float = -400.0
@export var gravity: float = 980.0

func _ready() -> void:
	state_machine.init(self)

func _process(delta: float) -> void:
	state_machine.process_frame(delta)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = jump_velocity

	var direction := Input.get_axis("ui_left", "ui_right")
	velocity.x = direction * speed

	move_and_slide()
	state_machine.process_physics(delta)

func _input(event: InputEvent) -> void:
	state_machine.process_input(event)

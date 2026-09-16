class_name Player
extends CharacterBody2D

signal health_changed  # <-- serve per healt_bar.gd

@export var max_health: int = 100
@onready var current_health: int = max_health

var isHurt: bool = false
var isAttacking: bool = false  # <-- blocca il cambio animazione durante l'attacco

const SPEED = 100.0
const RUNSPEED = 250.0
const ATTACK_SPEED = 10.0  # <-- velocità ridotta durante l'attacco
const JUMP_VELOCITY = -300.0

# 0 = trab, 1 = iacopo, 2= ciochins
var skin: int = GameState.selected_skin

@onready var animated_sprite = $TRAB_Sprite2D
@onready var animated_sprite2 = $Iaco_Spto
@onready var animated_sprite3 = $Naka_Sprite

var current_sprite: AnimatedSprite2D
func _ready() -> void:
	animated_sprite.visible = false
	animated_sprite2.visible = false
	animated_sprite3.visible = false

	match skin:
		0:
			current_sprite = animated_sprite
			animated_sprite.visible = true
		1:
			current_sprite = animated_sprite2
			animated_sprite2.visible = true
		2:
			current_sprite = animated_sprite3
			animated_sprite3.visible = true
		_:
			push_warning("Skin non valida: %s" % skin)
			current_sprite = animated_sprite
			animated_sprite.visible = true

	# collega il segnale di fine animazione per entrambi gli sprite
	animated_sprite.animation_finished.connect(_on_animation_finished)
	animated_sprite2.animation_finished.connect(_on_animation_finished)
	animated_sprite3.animation_finished.connect(_on_animation_finished)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		jumphurt()

	if Input.is_action_just_pressed("attack"):  # <-- click sx mouse
		attack()

	# skin 1 (iacopo) non può correre
	var is_running: bool = Input.is_key_pressed(KEY_SHIFT) and skin != 1
	var current_speed: float = RUNSPEED if is_running else SPEED

	# durante l'attacco la velocità è fissa e ridotta
	if isAttacking:
		current_speed = ATTACK_SPEED

	var direction := Input.get_axis("ui_left", "ui_right")

	if direction:
		velocity.x = direction * current_speed
		current_sprite.flip_h = direction < 0
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)

	# se sta attaccando, non sovrascrivere l'animazione "hit"
	if not isAttacking:
		if not is_on_floor():
			if velocity.y < 0:
				print("dsd")
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


func attack() -> void:
	if isAttacking:
		return
	isAttacking = true
	current_sprite.play("hit")


func _on_animation_finished() -> void:
	if current_sprite.animation == "hit":
		isAttacking = false


func jumphurt() -> void:
	current_health -= 10
	current_health = max(current_health, 0)
	isHurt = true
	health_changed.emit()  # <-- notifica la barra vita

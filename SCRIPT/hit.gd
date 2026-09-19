class_name Player
extends CharacterBody2D

signal health_changed  # <-- serve per healt_bar.gd
signal died(player)  # emesso una sola volta quando la vita arriva a 0 (lo ascolta level.gd)

@export var max_health: int = 100
@onready var current_health: int = max_health

@export var attack_damage: int = 10
# secondi tra la pressione del tasto e il momento in cui il pugno colpisce davvero
@export var attack_delay: float = 0.3

# --- NUOVO: identità e schema di controllo del player ---
@export var player_id: int = 0
# device_id:
#   -1 = tastiera Player 1 (azioni p1_*)
#   -2 = tastiera Player 2 (azioni p2_*)
#   >=0 = indice del pad (letto via codice, es. Input.get_connected_joypads()[0])
@export var device_id: int = -1
# skin_override: -1 = usa GameState, altrimenti forza la skin per questo player
@export var skin_override: int = -1

var isHurt: bool = false
var isAttacking: bool = false
var hitbox_delay_left: float = 0.0  # secondi che mancano all'attivazione della hitbox

const SPEED = 100.0
const RUNSPEED = 250.0
const ATTACK_SPEED = 10.0
const JUMP_VELOCITY = -300.0

# 0 = trab, 1 = iacopo, 2 = ciochins
var skin: int = 0

@onready var animated_sprite = $TRAB_Sprite2D
@onready var animated_sprite2 = $Iaco_Spto
@onready var animated_sprite3 = $Naka_Sprite
@onready var chain_sprite: AnimatedSprite2D = $Iaco_Spto/Chain
@onready var hurtbox: Hurtbox = $Hurtbox

@onready var punch_hitbox_0: Hitbox = $TRAB_Sprite2D/PunchHitbox
@onready var punch_hitbox_1: Hitbox = $Iaco_Spto/Chain/PunchHitbox
@onready var punch_hitbox_2: Hitbox = $Naka_Sprite/PunchHitbox

var current_sprite: AnimatedSprite2D
var current_hitbox: Hitbox
var chain_base_x: float
var current_hitbox_shape: CollisionShape2D  # shape della hitbox attiva (viene specchiata)
var hitbox_base_x: float  # X originale della shape (in editor)


func _ready() -> void:
	# se skin_override non è impostato, usa la config del GameState per questo player_id
	if skin_override != -1:
		skin = skin_override
	elif GameState.has_method("get_skin_for"):
		skin = GameState.get_skin_for(player_id)
	else:
		skin = GameState.selected_skin  # fallback compatibile col vecchio sistema

	hurtbox.damaged.connect(_on_damaged)

	animated_sprite.visible = false
	animated_sprite2.visible = false
	animated_sprite3.visible = false
	chain_sprite.visible = false

	chain_base_x = chain_sprite.position.x

	_set_hitbox_disabled(punch_hitbox_0, true)
	_set_hitbox_disabled(punch_hitbox_1, true)
	_set_hitbox_disabled(punch_hitbox_2, true)

	punch_hitbox_0.damage = attack_damage
	punch_hitbox_1.damage = attack_damage
	punch_hitbox_2.damage = attack_damage

	punch_hitbox_0.source = self
	punch_hitbox_1.source = self
	punch_hitbox_2.source = self

	match skin:
		0:
			current_sprite = animated_sprite
			animated_sprite.visible = true
			current_hitbox = punch_hitbox_0
		1:
			current_sprite = animated_sprite2
			animated_sprite2.visible = true
			current_hitbox = punch_hitbox_1
		2:
			current_sprite = animated_sprite3
			animated_sprite3.visible = true
			current_hitbox = punch_hitbox_2
		_:
			push_warning("Skin non valida: %s" % skin)
			current_sprite = animated_sprite
			animated_sprite.visible = true
			current_hitbox = punch_hitbox_0

	current_hitbox_shape = current_hitbox.get_node("CollisionShape2D")
	hitbox_base_x = current_hitbox_shape.position.x

	# il player 2 parte specchiato: guarda a sinistra, verso il player 1
	_set_facing(player_id == 1)

	animated_sprite.animation_finished.connect(_on_animation_finished)
	animated_sprite2.animation_finished.connect(_on_animation_finished)
	animated_sprite3.animation_finished.connect(_on_animation_finished)
	chain_sprite.animation_finished.connect(_on_chain_animation_finished)


func _set_hitbox_disabled(hitbox: Hitbox, value: bool) -> void:
	var shape: CollisionShape2D = hitbox.get_node("CollisionShape2D")
	shape.disabled = value


# Gira il personaggio: sprite, Chain di Iacopo e hitbox del pugno
func _set_facing(left: bool) -> void:
	current_sprite.flip_h = left
	chain_sprite.flip_h = left
	chain_sprite.position.x = -abs(chain_base_x) if left else abs(chain_base_x)
	current_hitbox_shape.position.x = -abs(hitbox_base_x) if left else abs(hitbox_base_x)


# --- NUOVO: helper di input, isolati per device_id ---
func _get_direction() -> float:
	match device_id:
		-1:
			return Input.get_axis("p1_left", "p1_right")
		-2:
			return Input.get_axis("p2_left", "p2_right")
		_:
			return Input.get_joy_axis(device_id, JOY_AXIS_LEFT_X)


func _jump_just_pressed() -> bool:
	match device_id:
		-1:
			return Input.is_action_just_pressed("p1_jump")
		-2:
			return Input.is_action_just_pressed("p2_jump")
		_:
			return Input.is_joy_button_pressed(device_id, JOY_BUTTON_A)


func _attack_just_pressed() -> bool:
	match device_id:
		-1:
			return Input.is_action_just_pressed("p1_attack")
		-2:
			return Input.is_action_just_pressed("p2_attack")
		_:
			return Input.is_joy_button_pressed(device_id, JOY_BUTTON_RIGHT_SHOULDER)


func _is_running() -> bool:
	match device_id:
		-1:
			return Input.is_action_pressed("p1_run")
		-2:
			return Input.is_action_pressed("p2_run")
		_:
			return Input.is_joy_button_pressed(device_id, JOY_BUTTON_LEFT_SHOULDER)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if _jump_just_pressed() and is_on_floor():
		velocity.y = JUMP_VELOCITY

	if _attack_just_pressed():
		attack()

	# la hitbox si attiva solo quando scade il ritardo dell'attacco
	if hitbox_delay_left > 0.0:
		hitbox_delay_left -= delta
		if hitbox_delay_left <= 0.0 and isAttacking:
			_set_hitbox_disabled(current_hitbox, false)

	# skin 1 (iacopo) non può correre
	var is_running: bool = _is_running() and skin != 1
	var current_speed: float = RUNSPEED if is_running else SPEED

	if isAttacking:
		current_speed = ATTACK_SPEED

	var direction := _get_direction()

	if direction:
		velocity.x = direction * current_speed
		_set_facing(direction < 0)
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)

	if not isAttacking:
		if direction:
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

	current_hitbox.reset_hits()
	if attack_delay <= 0.0:
		_set_hitbox_disabled(current_hitbox, false)
	else:
		hitbox_delay_left = attack_delay

	if skin == 1:
		chain_sprite.visible = true
		chain_sprite.play("hit")
	else:
		current_sprite.play("hit")


func _on_animation_finished() -> void:
	if current_sprite.animation == "hit":
		isAttacking = false
		hitbox_delay_left = 0.0
		_set_hitbox_disabled(current_hitbox, true)


func _on_chain_animation_finished() -> void:
	if chain_sprite.animation == "hit":
		isAttacking = false
		hitbox_delay_left = 0.0
		chain_sprite.visible = false
		_set_hitbox_disabled(current_hitbox, true)


func _on_damaged(amount: int, source: Node) -> void:
	if source == self or current_health <= 0:
		return  # un player non può colpire se stesso, né essere colpito da morto
	current_health = maxi(current_health - amount, 0)
	health_changed.emit()  # aggiorna la barra vita
	if current_health <= 0:
		died.emit(self)

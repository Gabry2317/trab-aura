class_name Player
extends CharacterBody2D

signal health_changed  # <-- serve per healt_bar.gd

@export var max_health: int = 100
@onready var current_health: int = max_health

@export var attack_damage: int = 10  # <-- NUOVO: danno del pugno

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
@onready var chain_sprite: AnimatedSprite2D = $Iaco_Spto/Chain  # <-- sottoclasse di iacopo usata per l'attacco

# --- NUOVO: riferimenti alle Hitbox del pugno, una per skin ---
@onready var punch_hitbox_0: Hitbox = $TRAB_Sprite2D/PunchHitbox
@onready var punch_hitbox_1: Hitbox = $Iaco_Spto/Chain/PunchHitbox
@onready var punch_hitbox_2: Hitbox = $Naka_Sprite/PunchHitbox

var current_sprite: AnimatedSprite2D
var current_hitbox: Hitbox          # <-- NUOVO: hitbox attiva in base alla skin selezionata
var chain_base_x: float  # <-- posizione X originale di Chain (in editor)


func _ready() -> void:
	animated_sprite.visible = false
	animated_sprite2.visible = false
	animated_sprite3.visible = false
	chain_sprite.visible = false

	chain_base_x = chain_sprite.position.x  # <-- salva la X di partenza

	# --- NUOVO: disabilita tutte le hitbox di default e configura danno/source ---
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

	# collega il segnale di fine animazione per tutti gli sprite
	animated_sprite.animation_finished.connect(_on_animation_finished)
	animated_sprite2.animation_finished.connect(_on_animation_finished)
	animated_sprite3.animation_finished.connect(_on_animation_finished)
	chain_sprite.animation_finished.connect(_on_chain_animation_finished)  # <-- gestione separata per Chain


# --- NUOVO: helper per abilitare/disabilitare una hitbox ---
func _set_hitbox_disabled(hitbox: Hitbox, value: bool) -> void:
	var shape: CollisionShape2D = hitbox.get_node("CollisionShape2D")
	shape.disabled = value


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
		chain_sprite.flip_h = direction < 0

		# specchia anche la posizione X di Chain, non solo la grafica
		if direction < 0:
			chain_sprite.position.x = -abs(chain_base_x)
		else:
			chain_sprite.position.x = abs(chain_base_x)
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)

	# se sta attaccando, non sovrascrivere l'animazione "hit"
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

	# --- NUOVO: attiva la hitbox corrispondente alla skin corrente ---
	current_hitbox.reset_hits()
	_set_hitbox_disabled(current_hitbox, false)

	if skin == 1:
		# iacopo attacca con l'animazione della sua sottoclasse "Chain"
		chain_sprite.visible = true
		chain_sprite.play("hit")
	else:
		current_sprite.play("hit")


func _on_animation_finished() -> void:
	if current_sprite.animation == "hit":
		isAttacking = false
		_set_hitbox_disabled(current_hitbox, true)  # <-- NUOVO: disattiva la hitbox a fine attacco


func _on_chain_animation_finished() -> void:
	if chain_sprite.animation == "hit":
		isAttacking = false
		chain_sprite.visible = false  # torna nascosta finché non riattacca
		_set_hitbox_disabled(current_hitbox, true)  # <-- NUOVO: disattiva la hitbox a fine attacco


func jumphurt() -> void:
	current_health -= 10
	current_health = max(current_health, 0)
	isHurt = true
	health_changed.emit()  # <-- notifica la barra vita

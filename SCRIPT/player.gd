extends CharacterBody2D

var isAttacking: bool = false

@onready var current_sprite: AnimatedSprite2D = $TRAB_Sprite2D  # <-- adatta al tuo nodo sprite attivo


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("attack"):  # <-- azione mappata su click sx del mouse
		attack()


func attack() -> void:
	if isAttacking:
		return
	isAttacking = true
	current_sprite.play("hit")


func _on_animation_finished() -> void:
	if current_sprite.animation == "hit":
		isAttacking = false

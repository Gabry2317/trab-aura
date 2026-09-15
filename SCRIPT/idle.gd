class_name PlayerIdleState
extends PlayerState

func enter() -> void:
	player.animation.play(idle_anim)

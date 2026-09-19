extends Node2D

@onready var label: Label = $Label


func _ready() -> void:
	GameState.selection_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	label.text = "Player %d: scegli il personaggio" % (GameState.selecting_player + 1)

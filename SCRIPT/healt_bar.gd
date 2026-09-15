extends ProgressBar
@export var player: Player

func _ready():
	player.healtChanged.connect(update)
	max_value = player.maxhealth
	update()

func update():
	value = player.currenthealth * 100 / player.maxhealth

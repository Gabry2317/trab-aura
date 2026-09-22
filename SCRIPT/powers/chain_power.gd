extends "res://SCRIPT/powers/fighter_power.gd"
# Catena gigante (secondaria di Iacopo/Bisio).
# 1) ai piedi del player nasce la catena (foglio "sheet", animazione di spawn)
# 2) finita la spawn resta STATICA sull'ultimo fotogramma e scorre sul terreno
# 3) se tocca un avversario (o esce dallo schermo / finisce la corsa) despawna
#    riproducendo la spawn al contrario

var _texture: Texture2D
var _chains: Array = []               # catene in traversata
var _spawning: Area2D = null          # catena in fase di spawn
var _busy: bool = false               # true durante lo spawn: il player resta fermo


func default_params() -> Dictionary:
	return {
		"damage": 15,                 # danno alla catena quando colpisce
		"cooldown": 1.5,              # secondi tra un lancio e il successivo
		"stamina_min": 25.0,          # stamina minima per poter lanciare la catena
		"stamina_cost": 25.0,         # stamina consumata a ogni lancio
		"sheet": "res://sprite/Player/Iacobisio/Secondary/chains.png",
		"hframes": 4,                 # colonne del foglio
		"vframes": 4,                 # righe del foglio
		"frames": 16,                 # fotogrammi usati
		"fps": 20.0,                  # velocita' dell'animazione di spawn
		"height_ratio": 0.3,          # altezza della catena rispetto al player (0.3 = 30%)
		"feet_y": 70.0,               # quota dei piedi rispetto all'origine del player
		"start_x": 40.0,              # distanza orizzontale dal player a cui nasce
		"speed": 450.0,               # px/s durante la traversata
		"max_distance": 2000.0,       # oltre questa distanza despawna comunque
		"offscreen_margin": 150.0,    # margine oltre lo schermo prima del despawn
		"hitbox_w": 0.6,              # larghezza hitbox (frazione della catena visibile)
		"hitbox_h": 0.8,              # altezza hitbox (frazione della catena visibile)
		"hitbox_script": "res://SCRIPT/punch_hitbox_trab.gd",  # script della hitbox che infligge il danno
		"debug": false,               # true = stampa in console cosa tocca la catena
	}


func _on_setup() -> void:
	_texture = load(str(params["sheet"]))
	if _texture == null:
		push_warning("chain_power: foglio '%s' non trovato" % params["sheet"])


func is_busy() -> bool:
	return _busy


func can_use() -> bool:
	return _texture != null and super.can_use()


func use() -> void:
	super.use()
	_busy = true
	player.velocity.x = 0.0
	_spawning = _spawn_chain()


# Il player e' stato colpito durante lo spawn: la catena si ritira
func on_player_hit() -> void:
	if not _busy:
		return
	_busy = false
	if is_instance_valid(_spawning):
		_despawn(_spawning, false)
	_spawning = null


func _spawn_chain() -> Area2D:
	var dir: float = player.get_facing_dir()
	var hframes: int = int(params["hframes"])
	var vframes: int = int(params["vframes"])

	var chain = Area2D.new()  # senza tipo: damage/source arrivano dallo script assegnato sotto
	chain.name = "BigChain"
	chain.set_script(load(str(params["hitbox_script"])))
	chain.collision_layer = player.current_hitbox.collision_layer
	chain.collision_mask = player.current_hitbox.collision_mask
	chain.damage = int(params["damage"])
	chain.source = player
	chain.set_meta("state", "spawning")
	chain.set_meta("dir", dir)
	chain.set_meta("start_x", player.global_position.x + dir * float(params["start_x"]))

	# sprite: origine = centro-basso del fotogramma (il cerchio poggia ai piedi)
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	_add_sliced_animation(frames, &"chains", _texture, hframes, vframes, int(params["frames"]), float(params["fps"]), false)
	var fw: float = _texture.get_size().x / hframes
	var fh: float = _texture.get_size().y / vframes

	# altezza = height_ratio volte il player: resta proporzionata a qualunque scala
	var chain_scale: float = (player.get_visual_height() * float(params["height_ratio"])) / fh

	var sprite := AnimatedSprite2D.new()
	sprite.name = "Sprite"
	sprite.sprite_frames = frames
	sprite.centered = false
	sprite.offset = Vector2(-fw / 2.0, -fh)
	sprite.scale = Vector2.ONE * chain_scale
	sprite.flip_h = dir < 0.0
	sprite.animation_finished.connect(_on_animation_finished.bind(chain))
	chain.add_child(sprite)

	# hitbox proporzionata alla catena visibile, spenta durante lo spawn
	var rect := RectangleShape2D.new()
	rect.size = Vector2(fw * chain_scale * float(params["hitbox_w"]), fh * chain_scale * float(params["hitbox_h"]))
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	shape.shape = rect
	shape.position = Vector2(0.0, -rect.size.y / 2.0)
	shape.disabled = true
	chain.add_child(shape)

	# aggiunta al livello (non al player): continua anche se il player si muove
	player.get_parent().add_child(chain)
	chain.global_position = Vector2(chain.get_meta("start_x"), player.global_position.y + float(params["feet_y"]))

	chain.area_entered.connect(_on_hit.bind(chain))
	chain.body_entered.connect(_on_hit.bind(chain))

	sprite.play(&"chains")
	return chain


# Affetta un foglio sprite in hframes x vframes fotogrammi come nuova animazione
func _add_sliced_animation(frames: SpriteFrames, anim: StringName, texture: Texture2D,
		hframes: int, vframes: int, frame_count: int, fps: float, loop: bool) -> void:
	frames.add_animation(anim)
	frames.set_animation_loop(anim, loop)
	frames.set_animation_speed(anim, fps)

	var fw: float = texture.get_size().x / hframes
	var fh: float = texture.get_size().y / vframes
	var added: int = 0
	for row in range(vframes):
		for col in range(hframes):
			if added >= frame_count:
				break
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(col * fw, row * fh, fw, fh)
			frames.add_frame(anim, atlas)
			added += 1


# Fine di un'animazione: spawn finita -> parte la traversata (catena ferma
# sull'ultimo fotogramma); despawn finito -> sparisce.
func _on_animation_finished(chain: Area2D) -> void:
	if not is_instance_valid(chain):
		return
	match chain.get_meta("state"):
		"spawning":
			chain.set_meta("state", "travel")
			if _spawning == chain:
				_spawning = null
				_busy = false  # il player torna libero
			(chain.get_node("CollisionShape2D") as CollisionShape2D).disabled = false
			_chains.append(chain)
		"despawning":
			chain.queue_free()


# Despawna solo se tocca un avversario (hurtbox o corpo di un altro player):
# il player stesso e i suoi nodi figli, pavimento, muri e hitbox varie si ignorano.
func _on_hit(other: Node, chain: Area2D) -> void:
	if not is_instance_valid(chain) or chain.get_meta("state") != "travel":
		return
	if other == player or player.is_ancestor_of(other):
		return
	if bool(params["debug"]):
		print("[BigChain] tocca: ", other.get_path(), " (", other.get_class(), ")")
	if other is Hurtbox or other is CharacterBody2D:
		_despawn(chain, true)


# Ferma la catena, spegne la hitbox e riproduce la spawn al contrario.
# from_end = true se la spawn era completa; false se e' ritirata a meta' spawn.
func _despawn(chain: Area2D, from_end: bool) -> void:
	if not is_instance_valid(chain) or chain.get_meta("state") == "despawning":
		return
	chain.set_meta("state", "despawning")
	_chains.erase(chain)
	(chain.get_node("CollisionShape2D") as CollisionShape2D).set_deferred("disabled", true)
	(chain.get_node("Sprite") as AnimatedSprite2D).play(&"chains", -1.0, from_end)


# Traversata: ogni catena in stato "travel" avanza a velocita' costante
func _update_power(delta: float) -> void:
	var vp := get_viewport()
	var view: Rect2 = vp.get_canvas_transform().affine_inverse() * vp.get_visible_rect()
	view = view.grow(float(params["offscreen_margin"]))

	for chain in _chains.duplicate():
		if not is_instance_valid(chain):
			_chains.erase(chain)
			continue
		var dir: float = chain.get_meta("dir")
		chain.global_position.x += dir * float(params["speed"]) * delta
		var travelled: float = absf(chain.global_position.x - float(chain.get_meta("start_x")))
		if travelled >= float(params["max_distance"]) or not view.has_point(chain.global_position):
			_despawn(chain, true)

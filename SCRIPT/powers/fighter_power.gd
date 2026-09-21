extends Node
# Classe base dei poteri dei personaggi (attacco secondario ecc.).
#
# Come si crea un potere nuovo:
#   1) nuovo script in res://SCRIPT/powers/ che estende fighter_power.gd
#   2) override di default_params(): elenco dei settings e dei valori di default
#   3) override di use() (e se serve is_busy, on_player_hit, _update_power)
#   4) nel .cfg del personaggio:
#          [secondary]
#          script = "res://SCRIPT/powers/il_tuo_potere.gd"
#      Avviando il gioco dall'editor la console stampa tutti i settings
#      disponibili, pronti da incollare sotto [secondary].
#
# I settings finiti in "params" sono gia' uniti ai default: nello script si
# leggono con params["nome"].

var player  # il Player che possiede il potere (senza tipo: niente dipendenza circolare con player.gd)
var params: Dictionary = {}
var cooldown_left: float = 0.0


# Settings del potere: nome -> valore di default. Ogni chiave qui e' una chiave
# valida in [secondary] del .cfg. "cooldown" (secondi) e' gestito dalla base.
func default_params() -> Dictionary:
	return {"cooldown": 1.0}


func setup(owner_player, values: Dictionary) -> void:
	player = owner_player
	params = values
	_on_setup()


# Chiamata una volta, quando params e player sono pronti
func _on_setup() -> void:
	pass


# Il player puo' lanciare il potere adesso?
func can_use() -> bool:
	return cooldown_left <= 0.0 and not is_busy()


# Lancia il potere (il player ha premuto il tasto)
func use() -> void:
	cooldown_left = float(params.get("cooldown", 1.0))


# true finche' il player deve restare fermo/bloccato a causa del potere
func is_busy() -> bool:
	return false


# Il player ha subito un colpo (stordimento): interrompi quello che stai facendo
func on_player_hit() -> void:
	pass


# --- Attacco caricato (opzionale) ---
# Un potere che vuole un attacco caricato (tenere premuto "secondary" invece
# del solito tocco) ritorna true da has_charged_attack(): a quel punto
# player.gd, invece del tocco singolo -> use(), gestisce il tasto cosi':
#   - tenuto premuto oltre charge_time() secondi -> start_charge(), poi
#     update_charge(delta) ogni frame finche' resta premuto
#   - rilasciato dopo la carica -> release_charge()
#   - rilasciato prima della soglia -> resta un tocco normale (use())
# Il blocco (tenere "secondary" fermi) viene disattivato per questi poteri:
# lo stesso tasto serve per caricare/rilasciare.
func has_charged_attack() -> bool:
	return false


# Secondi di pressione richiesti prima che la carica parta
func charge_time() -> float:
	return 0.5


# Il player ha iniziato a tenere premuto oltre charge_time()
func start_charge() -> void:
	pass


# Chiamata ogni frame (anche a player fermo) finche' la carica e' attiva
func update_charge(_delta: float) -> void:
	pass


# Il player ha rilasciato il tasto dopo aver caricato
func release_charge() -> void:
	pass


# Da sovrascrivere per logica per-frame (girano anche se il player e' stordito)
func _update_power(_delta: float) -> void:
	pass


func _physics_process(delta: float) -> void:
	cooldown_left = maxf(cooldown_left - delta, 0.0)
	_update_power(delta)

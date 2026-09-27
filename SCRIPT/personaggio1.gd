extends Button

# Script storico, ora disattivato: la scelta del personaggio passa
# interamente da selezione_personaggio.gd (turni, dispositivo assegnato,
# mouse soft-lock ecc). Questo script chiamava GameState.choose_skin()
# per conto suo, bypassando i turni — da qui il "salta il player 2".
# Lasciato attaccato al nodo solo per non dover modificare la scena a mano;
# non fa più nulla.

@export var skin_id: int = 0

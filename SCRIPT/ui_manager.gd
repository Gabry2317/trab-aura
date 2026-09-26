extends Control

# Script "regista" della UI unificata.
# Sostituisce toselect.gd / quit.gd / apri_impostazioni.gd / toonline.gd:
# invece di cambiare scena, mostra/nasconde i pannelli figli di questo nodo.

@onready var menu_principale: Node2D = $MenuPrincipale
@onready var impostazioni: Control = $Impostazioni
@onready var selezione_personaggio: Node2D = $SelezionePersonaggio
@onready var network_menu: Control = $NetworkMenu

func _ready() -> void:
	_mostra_solo(menu_principale)

func mostra_menu_principale() -> void:
	_mostra_solo(menu_principale)

func mostra_selezione_personaggio() -> void:
	# toselect.gd inizializzava lo stato tramite l'autoload GameState
	# prima di mostrare la schermata: manteniamo lo stesso comportamento.
	GameState.start_selection()
	_mostra_solo(selezione_personaggio)

func mostra_network_menu() -> void:
	_mostra_solo(network_menu)

func mostra_impostazioni() -> void:
	_mostra_solo(impostazioni)

func torna_al_menu() -> void:
	# Se si torna al menu dalla schermata di rete con una connessione avviata
	# (host o client), la chiudiamo: Network.leave_game() non fa nulla se
	# non c'era nessuna connessione attiva.
	Network.leave_game()
	_mostra_solo(menu_principale)

func esci_gioco() -> void:
	get_tree().quit()

func _mostra_solo(pannello_da_mostrare: Node) -> void:
	for pannello in [menu_principale, impostazioni, selezione_personaggio, network_menu]:
		pannello.visible = (pannello == pannello_da_mostrare)

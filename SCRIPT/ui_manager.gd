extends Control

# Script "regista" della UI unificata.
# Sostituisce toselect.gd / quit.gd / apri_impostazioni.gd / toonline.gd:
# invece di cambiare scena, mostra/nasconde i pannelli figli di questo nodo.

@onready var menu_principale: Node2D = $MenuPrincipale
@onready var impostazioni: Control = $Impostazioni
@onready var selezione_personaggio: Node2D = $SelezionePersonaggio
@onready var network_menu: Control = $NetworkMenu
@onready var selezione_controlli: Control = $SelezioneControlli
@onready var selezione_mappa: Control = $SelezioneMappa

func _ready() -> void:
	GameState.selection_finished.connect(mostra_selezione_mappa)
	selezione_mappa.mappa_scelta.connect(_on_mappa_scelta)
	_mostra_solo(menu_principale)

func mostra_menu_principale() -> void:
	_mostra_solo(menu_principale)

func mostra_selezione_controlli() -> void:
	_mostra_solo(selezione_controlli)

func mostra_selezione_personaggio() -> void:
	# toselect.gd inizializzava lo stato tramite l'autoload GameState
	# prima di mostrare la schermata: manteniamo lo stesso comportamento.
	GameState.start_selection()
	_mostra_solo(selezione_personaggio)

func mostra_selezione_mappa() -> void:
	_mostra_solo(selezione_mappa)

func _on_mappa_scelta(_mappa: Dictionary) -> void:
	# la mappa resta in SelettoreMappa.corrente, da leggere nel livello
	get_tree().change_scene_to_file("res://level.tscn")

func mostra_network_menu() -> void:
	_mostra_solo(network_menu)

func mostra_impostazioni() -> void:
	_mostra_solo(impostazioni)

func torna_al_menu() -> void:
	# Se si torna al menu dalla schermata di rete con una connessione avviata
	# (host o client), la chiudiamo: Network.stop() non fa nulla se
	# non c'era nessuna connessione attiva.
	Network.stop()
	_mostra_solo(menu_principale)

func esci_gioco() -> void:
	get_tree().quit()

func _mostra_solo(pannello_da_mostrare: Node) -> void:
	for pannello in [menu_principale, impostazioni, selezione_personaggio, network_menu, selezione_controlli, selezione_mappa]:
		pannello.visible = (pannello == pannello_da_mostrare)

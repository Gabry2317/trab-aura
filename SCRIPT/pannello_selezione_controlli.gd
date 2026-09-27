extends Control
## Script per PannelloControlli.tscn.
## Mostra i dispositivi rilevati, evidenzia la configurazione consigliata
## e lascia comunque scegliere manualmente le altre.
##
## Qui, e solo qui, viene creata l'istanza di Controlli (con Controlli.i()):
## non gira nulla in background finché questo pannello non si apre.

signal configurazione_scelta

@onready var label_stato: Label = $Pannello/Contenitore/LabelStato
@onready var btn_doppio: Button = $Pannello/Contenitore/BtnDoppioController
@onready var btn_misto: Button = $Pannello/Contenitore/BtnTastieraController
@onready var btn_tastiera: Button = $Pannello/Contenitore/BtnDoppiaTastiera
@onready var btn_conferma: Button = $Pannello/Contenitore/BtnConferma

const COLORE_ORO := Color(0.94902, 0.784314, 0.184314)
const TESTO_BASE := {
	"doppio": "Doppio controller",
	"misto": "Tastiera + controller",
	"tastiera": "Doppia tastiera (WASD / Frecce)",
}

var _controlli: Controlli
var _config_selezionata: int = -1
var _scelta_manuale: bool = false  # true appena l'utente clicca un'opzione lui stesso


func _ready() -> void:
	_controlli = Controlli.i()  # creata/riusata solo ora che il pannello è aperto
	_controlli.dispositivi_cambiati.connect(_aggiorna)
	btn_doppio.pressed.connect(_scegli_doppio)
	btn_misto.pressed.connect(_scegli_misto)
	btn_tastiera.pressed.connect(_scegli_tastiera)
	btn_conferma.pressed.connect(_conferma)
	visibility_changed.connect(_on_visibility_changed)
	_aggiorna()


func _scegli_doppio() -> void:
	_scelta_manuale = true
	_seleziona(Controlli.Config.DOPPIO_CONTROLLER)


func _scegli_misto() -> void:
	_scelta_manuale = true
	_seleziona(Controlli.Config.TASTIERA_E_CONTROLLER)


func _scegli_tastiera() -> void:
	_scelta_manuale = true
	_seleziona(Controlli.Config.DOPPIA_TASTIERA)


func _on_visibility_changed() -> void:
	# Senza questo, con tastiera/mouse va bene, ma il tasto "conferma" del
	# controller non fa nulla perché nessun bottone ha mai il focus.
	if visible:
		_scelta_manuale = false  # ogni apertura riparte dal suggerimento automatico
		_dai_focus_iniziale()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventJoypadButton and event.pressed:
		# Di default Godot fa confermare solo il tasto A (ui_accept).
		# Qui aggiungiamo anche X, così funzionano entrambi.
		if event.button_index == JOY_BUTTON_A or event.button_index == JOY_BUTTON_X:
			var focus := get_viewport().gui_get_focus_owner()
			if focus is Button:
				focus.pressed.emit()
				get_viewport().set_input_as_handled()


func _dai_focus_iniziale() -> void:
	for b in [btn_doppio, btn_misto, btn_tastiera]:
		if not b.disabled:
			b.grab_focus()
			return


func _aggiorna() -> void:
	label_stato.text = _controlli.descrizione_dispositivi()

	var n := _controlli.numero_controller()
	btn_doppio.disabled = n < 2
	btn_misto.disabled = n < 1

	# Se l'utente ha già scelto lui stesso, non sovrascriviamo la sua scelta
	# solo perché un controller si è ricollegato/scollegato — a meno che
	# l'opzione scelta sia diventata impossibile (es. era "doppio controller"
	# ma un pad si è disconnesso).
	var scelta_diventata_impossibile := (
		(_config_selezionata == Controlli.Config.DOPPIO_CONTROLLER and btn_doppio.disabled)
		or (_config_selezionata == Controlli.Config.TASTIERA_E_CONTROLLER and btn_misto.disabled)
	)
	if not _scelta_manuale or scelta_diventata_impossibile:
		_seleziona(_controlli.suggerisci_configurazione())
	else:
		# solo aggiorna l'evidenziazione/testo, senza cambiare la scelta
		_seleziona(_config_selezionata)


func _seleziona(config: int) -> void:
	_config_selezionata = config

	btn_doppio.text = TESTO_BASE["doppio"]
	btn_misto.text = TESTO_BASE["misto"]
	btn_tastiera.text = TESTO_BASE["tastiera"]
	for b in [btn_doppio, btn_misto, btn_tastiera]:
		b.remove_theme_color_override("font_color")

	var mappa := {
		Controlli.Config.DOPPIO_CONTROLLER: btn_doppio,
		Controlli.Config.TASTIERA_E_CONTROLLER: btn_misto,
		Controlli.Config.DOPPIA_TASTIERA: btn_tastiera,
	}
	var scelto: Button = mappa[config]
	scelto.add_theme_color_override("font_color", COLORE_ORO)


func _conferma() -> void:
	if _config_selezionata == -1:
		_config_selezionata = _controlli.suggerisci_configurazione()
	_controlli.applica_configurazione(_config_selezionata)
	configurazione_scelta.emit()

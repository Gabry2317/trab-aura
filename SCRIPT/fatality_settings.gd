class_name FatalityCombatSettings
extends Resource

# ============================================================
#  FATALITY SETTINGS - tutti i parametri della cinematica
# ============================================================
#  Questa e' una Resource: puoi creare la tua istanza da
#  FileSystem -> tasto destro -> New Resource -> FatalityCombatSettings,
#  salvarla come res://data/fatality_settings.tres e modificare i
#  valori dall'Inspector, SENZA toccare il codice.
#  Se il file non esiste, FatalityManager usa questi default.
# ============================================================

@export_group("Camera cinematica")
## Zoom della camera sulla vittima, RELATIVO allo zoom che la camera ha nel
## momento esatto in cui scatta la fatality (non un valore assoluto): la tua
## camera_2d.gd sembra allontanarsi/avvicinarsi dinamicamente in base alla
## distanza tra i due lottatori, quindi un valore fisso avrebbe fatto scatti
## bruschi e diversi ogni volta. Es. 0.35 = 3x piu' vicino di quanto era un
## istante prima; 1.0 = nessun cambiamento; 2.0 = si allontana ancora di piu'.
@export_range(0.05, 3.0, 0.01) var camera_zoom_multiplier: float = 0.55
## Secondi impiegati dalla camera per spostarsi/zoomare sulla vittima
@export var camera_pan_time: float = 0.5
## Offset (px) dalla posizione della vittima che la camera deve inquadrare
@export var camera_offset: Vector2 = Vector2(0, -40)
## Secondi impiegati dalla camera per tornare normale a fine fatality
@export var camera_return_time: float = 0.6
@export var camera_pan_trans: Tween.TransitionType = Tween.TRANS_CUBIC
@export var camera_pan_ease: Tween.EaseType = Tween.EASE_OUT

@export_group("Slow motion")
## Se true, appena scatta la fatality il gioco rallenta per un istante prima della cinematica
@export var use_slowmo_on_trigger: bool = true
@export_range(0.05, 1.0, 0.01) var slowmo_time_scale: float = 0.25
## Durata REALE (non rallentata) dello slowmo, in secondi
@export var slowmo_duration: float = 0.35

@export_group("Animazione")
## FPS forzato per l'animazione fatality. -1 = usa quello scritto nel .cfg del personaggio (fps sotto [anim_<vittima>_<killer>])
@export var animation_fps_override: float = -1.0
## Tempo massimo di attesa per l'animazione (fallback se "animation_finished" non arriva mai).
## Deve essere >= (numero di frame / fps) dell'animazione fatality piu' lunga che hai,
## altrimenti la cinematica viene tagliata un istante prima della fine.
@export var max_animation_duration: float = 4.0
## Se il personaggio NON ha l'animazione fatality specifica (vittima_killer), resta fermo per questo tempo
@export var fallback_freeze_duration: float = 1.4

@export_group("Letterbox (barre nere cinematiche)")
@export var use_letterbox: bool = true
@export var letterbox_height: float = 70.0
@export var letterbox_color: Color = Color(0, 0, 0, 1)
@export var letterbox_fade_time: float = 0.25

@export_group("Combo")
## Secondi entro cui completare la sequenza di tasti, se il personaggio non lo sovrascrive con
## "combo_window" nella sezione [fatality] del proprio .cfg
@export var combo_input_window: float = 1.4
## Se true la combo del "colpo di grazia" funziona solo quando l'avversario e' gia' "downed" (ultimo HP)
@export var combo_only_while_opponent_downed: bool = true

@export_group("Audio")
@export var trigger_sound: AudioStream = null   # suonato appena la fatality scatta (prima della camera)
@export var finish_sound: AudioStream = null    # suonato alla fine dell'animazione

@export_group("Regole del knock-down")
## HP a cui il personaggio si "blocca" invece di morire subito (il "quasi morto")
@export_range(1, 20, 1) var downed_health: int = 1
## Se true, un QUALSIASI colpo successivo (di qualunque tipo) finisce la vittima downed
@export var any_hit_finishes: bool = true
## Se true, i player non rispondono ai comandi normali durante la cinematica
@export var lock_input_during_cinematic: bool = true
## Tempo massimo (secondi REALI) che la cinematica puo' durare in totale prima
## che il sistema si sblocchi da solo forzatamente (rete di sicurezza contro
## blocchi imprevisti: se scatta, guarda il pannello Debugger > Errors per
## capire cosa si e' inceppato).
@export var watchdog_timeout: float = 8.0

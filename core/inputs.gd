extends RefCounted
## LES COMMANDES — le CLAVIER (touches PHYSIQUES : W A S D = Z Q S D sur un clavier AZERTY) et la MANETTE (dénomination
## Xbox : A B X Y, LB RB, Back), déclarées ici plutôt que dans project.godot : une seule liste, lisible, que l'on
## remappera plus tard depuis un menu d'options.
##
##                    clavier / souris          manette
##   se déplacer      W A S D, flèches          stick gauche
##   courir           Maj                       clic du stick gauche, RB
##   sauter           Espace                    A
##   parler / partir  E                         X
##   fermer           Échap                     B
##   torche           T                         Y
##   dormir           F                         LB
##   la barre         1 à 8, clic               croix ← → pour choisir, A pour valider
##   la vue           clic droit + souris       stick droit ← → (troisième personne)
##   zoom             molette                   stick droit ↑ ↓
##   vue haute        Ctrl + molette            Back
##
## `pad` dit le DERNIER appareil touché (la présentation montre « E » ou « X » selon lui) : `note()` le tient à jour.

const KEYS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"run": [KEY_SHIFT],
	"jump": [KEY_SPACE],
	"interact": [KEY_E],
	"sleep": [KEY_F],
	"torch": [KEY_T],
	"cancel": [KEY_ESCAPE],
	"quicksave": [KEY_F5],
	"quickload": [KEY_F9],
	"choice_1": [KEY_1], "choice_2": [KEY_2], "choice_3": [KEY_3], "choice_4": [KEY_4],
	"choice_5": [KEY_5], "choice_6": [KEY_6], "choice_7": [KEY_7], "choice_8": [KEY_8],
	"bar_prev": [], "bar_next": [], "bar_confirm": [], "high_view": [],
	"camera_left": [], "camera_right": [], "zoom_in": [], "zoom_out": [],
	# La triche (core/triche.gd) : sans effet quand elle est éteinte.
	"cheat_fly": [KEY_F1], "cheat_ghost": [KEY_F2], "cheat_speed": [KEY_F3], "cheat_time": [KEY_F4], "fly_down": [KEY_C],
}

const PAD_BUTTONS := {
	"run": [JOY_BUTTON_LEFT_STICK, JOY_BUTTON_RIGHT_SHOULDER],
	"jump": [JOY_BUTTON_A],
	"interact": [JOY_BUTTON_X],
	"cancel": [JOY_BUTTON_B],
	"torch": [JOY_BUTTON_Y],
	"sleep": [JOY_BUTTON_LEFT_SHOULDER],
	"bar_prev": [JOY_BUTTON_DPAD_LEFT],
	"bar_next": [JOY_BUTTON_DPAD_RIGHT],
	"bar_confirm": [JOY_BUTTON_A],
	"high_view": [JOY_BUTTON_BACK],
	"cheat_fly": [JOY_BUTTON_START],
	"cheat_speed": [JOY_BUTTON_RIGHT_STICK],
}

## action -> [axe, sens]
const PAD_AXES := {
	"move_forward": [JOY_AXIS_LEFT_Y, -1.0],
	"move_back": [JOY_AXIS_LEFT_Y, 1.0],
	"move_left": [JOY_AXIS_LEFT_X, -1.0],
	"move_right": [JOY_AXIS_LEFT_X, 1.0],
	"camera_left": [JOY_AXIS_RIGHT_X, -1.0],
	"camera_right": [JOY_AXIS_RIGHT_X, 1.0],
	"zoom_in": [JOY_AXIS_RIGHT_Y, -1.0],
	"zoom_out": [JOY_AXIS_RIGHT_Y, 1.0],
	"fly_down": [JOY_AXIS_TRIGGER_LEFT, 1.0],
}

## Ce que l'on montre à l'écran, par appareil : [clavier, manette].
const LABELS := {
	"interact": ["E", "X"], "cancel": ["Échap", "B"], "jump": ["Espace", "A"], "sleep": ["F", "LB"],
	"torch": ["T", "Y"], "bar_confirm": ["1–8", "A"],
}

const DEADZONE := 0.25

static var pad := false


static func ensure() -> void:
	for action: String in KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, DEADZONE)
		for k: Key in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
		for b: JoyButton in PAD_BUTTONS.get(action, []):
			var jb := InputEventJoypadButton.new()
			jb.button_index = b
			jb.device = -1  # toutes les manettes
			InputMap.action_add_event(action, jb)
		if PAD_AXES.has(action):
			var jm := InputEventJoypadMotion.new()
			jm.axis = PAD_AXES[action][0]
			jm.axis_value = PAD_AXES[action][1]
			jm.device = -1
			InputMap.action_add_event(action, jm)


## Retient le dernier appareil touché (un stick qui bouge à peine ne compte pas). Rend vrai s'il a changé.
static func note(event: InputEvent) -> bool:
	var was := pad
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		pad = false
	return was != pad


## Le nom à montrer pour une action, selon le dernier appareil.
static func label(action: String) -> String:
	var l: Array = LABELS.get(action, ["?", "?"])
	return l[1] if pad else l[0]

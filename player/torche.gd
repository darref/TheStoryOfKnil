extends OmniLight3D
## LA TORCHE DU JOUEUR — allumée d'elle-même quand il fait sombre (aube, crépuscule, nuit) et dans un intérieur
## (grotte, maison) ; T la force : allumée, éteinte, puis rend la main à l'automatique. Elle vacille un peu.
## Elle ne décide rien du jeu : c'est de la présentation (le jour où la torche sera un objet du patrimoine, son
## état viendra du GameState).

enum Mode { AUTO, ON, OFF }

@export var mode := Mode.AUTO
@export var base_energy := 1.6
## L'amplitude du vacillement (part de l'énergie).
@export var flicker := 0.12
## Le temps pour s'allumer / s'éteindre.
@export var fade_time := 0.6

var _level := 0.0
var _t := 0.0


func _ready() -> void:
	light_energy = 0.0
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("torch"):
		mode = ((mode + 1) % Mode.size()) as Mode


func wanted() -> bool:
	match mode:
		Mode.ON:
			return true
		Mode.OFF:
			return false
	return GameClock.phase() != "jour" or Interior.is_inside()


func _process(delta: float) -> void:
	_t += delta
	_level = move_toward(_level, 1.0 if wanted() else 0.0, delta / maxf(fade_time, 0.01))
	var wobble := 1.0 + flicker * (sin(_t * 13.0) * 0.5 + sin(_t * 7.3 + 1.7) * 0.3 + sin(_t * 23.0) * 0.2)
	light_energy = base_energy * _level * wobble
	visible = _level > 0.001

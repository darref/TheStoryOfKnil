extends Cell
class_name GameCell

## LA CELLULE DE JEU — le monde de Knil (`scenes/main.tscn`) dans le SubViewport de la cellule. Agrandie : on joue.
## Réduite (Échap, Start, la touche de coin MNU) : le livre s'ouvre et LE JEU SE MET EN PAUSE (`get_tree().paused`) —
## le livre, lui, tourne toujours (PROCESS_MODE_ALWAYS), et la vignette montre le monde arrêté derrière « Jouer ».
##
## Échap en dialogue ferme d'ABORD le dialogue (le Player le lit dans le SubViewport, avant le livre) : le livre ne
## s'ouvre qu'à l'appui suivant. B, à la manette, reste au jeu (fermer) ; c'est Start qui ouvre le livre.
##
## Le pendant de `GameCell` de Spirit3D (`D:/Spirit3D/BOOKS/scripts/GameCell.gd`) : là-bas il cachait le HUD, possédait
## le personnage et relançait la musique ; ici il cache le HUD et tient la pause.

## Le HUD du jeu (un CanvasLayer dans le SubViewport) : caché livre ouvert, il déborderait de la vignette.
@export var hud: CanvasLayer

## Un dialogue est-il ouvert ? Et à quelle image s'est-il fermé (le même appui d'Échap ne doit pas aussi ouvrir le livre).
var _talking := false
var _closed_frame := -1


func is_game_cell() -> bool:
	return true


func _ready() -> void:
	# Le monde se fige avec la pause ; la cellule (le livre) non.
	if subviewport != null:
		subviewport.process_mode = Node.PROCESS_MODE_PAUSABLE
	# La vignette du jeu montre le monde : pas le fond gris des autres cellules.
	var bg := find_child("PreviewBackground", true, false) as CanvasItem
	if bg != null:
		bg.visible = false
	EventBus.dialogue_shown.connect(func(_s: String, _t: String) -> void: _talking = true)
	EventBus.dialogue_closed.connect(func() -> void:
		_talking = false
		_closed_frame = Engine.get_process_frames())
	super._ready()


func _is_reduce_event(event: InputEvent) -> bool:
	if event.is_action_pressed("menu"):
		return true
	return event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_ESCAPE


func _should_reset_on_escape() -> bool:
	return not _talking and Engine.get_process_frames() != _closed_frame


func key_overlay_text() -> String:
	return "START" if Inputs.pad else "MNU"


func _enlarge_cell_impl(skip_animation: bool) -> void:
	super._enlarge_cell_impl(skip_animation)
	if not enlarged:
		return
	get_tree().paused = false
	if hud != null:
		hud.visible = true


func reset_cell() -> void:
	super.reset_cell()
	if hud != null:
		hud.visible = false
	# Au tout premier reset (cellule pas encore ouverte), on ne fige rien : le jeu démarre agrandi.
	if is_node_ready():
		get_tree().paused = true

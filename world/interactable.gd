class_name Interactable
extends Area3D
## CE À QUOI ON PARLE — un personnage, un animal, un objet, un lieu (un panneau, un puits).
##
## Il DÉCLARE ce qu'il dit (`lines`) ; `interact()` montre la réplique suivante (par l'EventBus : la boîte de
## dialogue l'écoute), et après la dernière, ferme. Son état qui dure (combien de fois on lui a parlé…) vit dans le
## GameState sous son `entity_id` — un id STABLE, qui survit aux sauvegardes.

@export var entity_id := ""
@export var display_name := ""
@export_enum("personne", "animal", "objet", "lieu") var kind := "personne"
## Ce qu'il dit, dans l'ordre.
@export_multiline var lines: PackedStringArray = []

var _line := -1


func _ready() -> void:
	add_to_group("interactables")
	collision_layer = 4  # les interactables : le « sens » du joueur les trouve
	collision_mask = 0
	monitoring = false
	if entity_id == "":
		push_warning("Interactable sans entity_id : %s" % get_path())


func title() -> String:
	return display_name if display_name != "" else entity_id


func is_talking() -> bool:
	return _line >= 0


## La réplique suivante ; après la dernière, la boîte se ferme. Rend vrai tant qu'il parle.
func interact() -> bool:
	_line += 1
	if _line >= lines.size():
		close()
		return false
	if _line == 0:
		var e := GameState.entity(entity_id)
		e["talks"] = int(e.get("talks", 0)) + 1
	EventBus.dialogue_shown.emit(title(), lines[_line])
	return true


func close() -> void:
	if _line >= 0:
		_line = -1
		EventBus.dialogue_closed.emit()

class_name Interactable
extends Area3D
## L'OBJET D'UNE DÉCISION — un personnage, un animal, un objet ou un lieu (un puits, un lac, une forêt).
##
## Il ne décide rien : il DÉCLARE ce qu'il est (`describe()`), le moteur de décision fait le reste. Son état
## qui dure (son problème, sa disposition envers le joueur) vit dans le GameState sous son `entity_id` — un id
## STABLE : c'est lui qui relie nos rencontres d'un jour à l'autre, et d'une sauvegarde à l'autre.

@export var entity_id := ""
@export var display_name := ""
@export_enum("personne", "animal", "objet", "lieu") var kind := "personne"
## Ce qu'il est, pour les conditions des données : « marchand », « aubergiste », « pauvre », « habitant »,
## « artisan », « criminel », « sacre »…
@export var tags: PackedStringArray = []
## Ses traits libres, lus sous `target.traits.*`.
@export var traits: Dictionary = {}
## Sa chance d'avoir un problème quand on le rencontre un jour où il n'en a pas.
@export_range(0.0, 1.0) var problem_chance := 0.6


func _ready() -> void:
	add_to_group("interactables")
	collision_layer = 4  # les interactables : le « sens » du joueur les trouve
	collision_mask = 0
	monitoring = false
	if entity_id == "":
		push_warning("Interactable sans entity_id : %s" % get_path())


func describe() -> Dictionary:
	return {"id": entity_id, "name": display_name if display_name != "" else entity_id, "kind": kind,
		"tags": Array(tags), "traits": traits, "problem_chance": problem_chance}


## Son problème du moment, tel que le GameState le tient ({} : aucun).
func current_problem() -> Dictionary:
	var p: Dictionary = GameState.entity(entity_id).get("problem", {})
	return {} if p.is_empty() or p.get("resolved", false) else p

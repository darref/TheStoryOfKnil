class_name SleepSpot
extends Area3D
## UN COUCHAGE — un lit chez soi, un lit d'auberge, le lit d'un autre, un campement. C'est là qu'il est
## préconisé de dormir ; le système de sommeil le trouve quand le joueur est à portée, et les règles de réveil
## s'en servent comme destinations (`nearest:lit_auberge`, `tag:prison`, `home`).

@export var spot_id := ""
@export_enum("lit_maison", "lit_auberge", "lit_autre", "camp") var spot_kind := "lit_auberge"
## Des étiquettes pour les règles de réveil (`tag:prison`…).
@export var tags: PackedStringArray = []
## Le propriétaire (entity_id) d'un « lit_autre » : il faut son accord (hospitalité ou bonne disposition).
@export var owner_id := ""
## Pour l'essai : ce lit devient le foyer du joueur au début de la partie.
@export var is_player_home := false


func _ready() -> void:
	add_to_group(SleepSystem.SPOT_GROUP)
	collision_layer = 8  # les couchages
	collision_mask = 0
	monitoring = false
	if is_player_home:
		GameState.set_value("player.home.spot_id", spot_id)
		spot_kind = "lit_maison"


## Le joueur y dort-il « normalement » ? Sinon le couchage compte comme le sol pour les règles de réveil.
func is_usable() -> bool:
	match spot_kind:
		"lit_maison":
			return GameState.get_value("player.home.spot_id", "") == spot_id
		"lit_auberge":
			var paid := int(GameState.get_value("flags.chambre_louee_jour", -99))
			return GameClock.day() - paid <= 1
		"lit_autre":
			return "hospitalite" in GameState.get_value("player.wealth.properties", []) \
				or float(GameState.entity(owner_id).get("disposition", 0)) >= 3
	return true

extends Node
## L'ÉTAT DE LA PARTIE — tout ce qu'une sauvegarde garde.
##
## Rangé en arbre de Dictionary, lu et écrit par CHEMINS (« player.money ») : les données (data/*.json) désignent une
## valeur sans qu'aucun code ne la connaisse.
##
##   seed       le germe de la partie (les tirages du monde)
##   player     Knil : sa vie (en demi-cœurs), son argent, ses objets
##   place      où il est (région, intérieur, position) — tenu par les zones du monde et le joueur
##   entities   l'état propre de chaque personnage / objet du monde (un coffre ouvert, un PNJ rossé…)
##   flags      les faits du monde, libres

const Inputs := preload("res://core/inputs.gd")

var data: Dictionary = {}


func _enter_tree() -> void:
	Inputs.ensure()
	new_game(randi())


func new_game(seed_value: int) -> void:
	data = {
		"seed": seed_value,
		"player": {"name": "Knil", "health": 6, "max_health": 6, "money": 0, "items": {}},
		"place": {"region_id": "", "region_type": "sauvage", "interior": false,
			"interior_id": "", "interior_type": "", "position": [0.0, 0.0, 0.0]},
		"entities": {},
		"flags": {},
	}
	EventBus.game_started.emit(seed_value)


# --- Lecture / écriture par chemins ------------------------------------------------------------------------

func get_value(path: String, default: Variant = null) -> Variant:
	var node: Variant = data
	for part in path.split("."):
		if node is Dictionary and (node as Dictionary).has(part):
			node = node[part]
		else:
			return default
	return node


func set_value(path: String, value: Variant) -> void:
	var parts := path.split(".")
	var node: Dictionary = data
	for i in parts.size() - 1:
		if not node.has(parts[i]) or not node[parts[i]] is Dictionary:
			node[parts[i]] = {}
		node = node[parts[i]]
	node[parts[-1]] = value
	EventBus.state_changed.emit(path, value)


func add_value(path: String, amount: float) -> void:
	set_value(path, float(get_value(path, 0.0)) + amount)


## L'état persistant d'une entité du monde (créé au premier besoin).
func entity(id: String) -> Dictionary:
	var all: Dictionary = data["entities"]
	if not all.has(id):
		all[id] = {}
	return all[id]


func to_save() -> Dictionary:
	return data.duplicate(true)


func from_save(d: Dictionary) -> void:
	data = d.duplicate(true)
	EventBus.game_loaded.emit()

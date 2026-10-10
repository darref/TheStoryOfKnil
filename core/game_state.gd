extends Node
## L'ÉTAT DE LA PARTIE — tout ce que le moteur de décision peut lire, et tout ce qu'une sauvegarde garde.
##
## Rangé en arbre de Dictionary, lu et écrit par CHEMINS (« player.wealth.gold ») : une condition ou un effet
## des données (data/*.json) désigne une valeur sans qu'aucun code ne la connaisse.
##
##   seed       le germe de la partie — deux parties, deux germes : jamais la même partie
##   player     qui je suis (identity), mon patrimoine (wealth), mon foyer (home)
##   place      où je suis (région, intérieur) — tenu par les zones du monde
##   entities   l'état propre de chaque personnage / objet rencontré (son problème, sa disposition envers moi)
##   flags      les faits du monde, libres
##   history    chaque décision prise, dans l'ordre (voir `record_interaction`)

const Inputs := preload("res://core/inputs.gd")

var data: Dictionary = {}


func _enter_tree() -> void:
	Inputs.ensure()
	new_game(randi())


func new_game(seed_value: int) -> void:
	data = {
		"seed": seed_value,
		"player": {
			"identity": {"name": "Voyageur", "origin": "inconnu", "profession": "vagabond",
				"traits": [], "reputation": 0},
			"wealth": {"gold": 20, "properties": [], "items": {}},
			"home": {"spot_id": "", "region_id": ""},
		},
		"place": {"region_id": "", "region_type": "sauvage", "interior": false,
			"interior_id": "", "interior_type": "", "position": [0.0, 0.0, 0.0]},
		"entities": {},
		"flags": {},
		"history": [],
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


# --- Entités ------------------------------------------------------------------------------------------------

## L'état persistant d'une entité, créé à la première rencontre depuis ce que l'Interactable déclare.
func entity(id: String, defaults: Dictionary = {}) -> Dictionary:
	var all: Dictionary = data["entities"]
	if not all.has(id):
		var e := {"disposition": 0, "problem": {}, "state": {}}
		e.merge(defaults.duplicate(true), true)
		all[id] = e
	return all[id]


# --- Historique ---------------------------------------------------------------------------------------------

func record_interaction(target_id: String, action: Dictionary) -> Dictionary:
	var rec := {
		"target": target_id,
		"action": action.get("id", ""),
		"category": action.get("category", ""),
		"minutes": GameClock.minutes,
		"day": GameClock.day(),
		"hour": GameClock.hour(),
		"region_id": get_value("place.region_id", ""),
		"interior_id": get_value("place.interior_id", ""),
	}
	(data["history"] as Array).append(rec)
	return rec


## Ce que le moteur lit sous `history.*` pour UNE cible : le résumé de nos rencontres passées avec elle.
func history_with(target_id: String) -> Dictionary:
	var count := 0
	var by_action := {}
	var by_category := {}
	var last: Dictionary = {}
	for rec: Dictionary in data["history"]:
		if rec["target"] != target_id:
			continue
		count += 1
		by_action[rec["action"]] = int(by_action.get(rec["action"], 0)) + 1
		by_category[rec["category"]] = int(by_category.get(rec["category"], 0)) + 1
		last = rec
	return {
		"count": count,
		"actions": by_action,
		"categories": by_category,
		"last_action": last.get("action", ""),
		"last_category": last.get("category", ""),
		"days_since_last": GameClock.day() - int(last["day"]) if not last.is_empty() else -1,
		"disposition": entity(target_id).get("disposition", 0),
	}


## Le bilan de toute la partie, sous `karma.*` : combien de fois on a aidé, méprisé… (par catégorie d'action).
func karma() -> Dictionary:
	var by_category := {}
	for rec: Dictionary in data["history"]:
		by_category[rec["category"]] = int(by_category.get(rec["category"], 0)) + 1
	var total: int = (data["history"] as Array).size()
	return {"total": total, "categories": by_category,
		"help": int(by_category.get("aide", 0)), "despise": int(by_category.get("mepris", 0))}


func to_save() -> Dictionary:
	return data.duplicate(true)


func from_save(d: Dictionary) -> void:
	data = d.duplicate(true)
	EventBus.game_loaded.emit()

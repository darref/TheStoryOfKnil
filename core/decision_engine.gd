extends Node
## LE MOTEUR DE DÉCISION — pour une rencontre, il calcule la barre d'actions ; pour une action, il l'applique.
##
## Il lit le CONTEXTE (qui je suis, mon patrimoine, où nous sommes, quand, et notre histoire commune), filtre les
## actions des données (data/actions.json) par leurs conditions, les pondère, et en tire au plus `max_choices`
## par un tirage DÉTERMINISTE (germe de la partie, cible, jour, nombre de rencontres). « Mépriser » est
## TOUJOURS là, en dernier : la barre n'est jamais vide.
##
## Il donne aussi aux entités leurs PROBLÈMES (data/problems.json) : tirés au même germe, ils naissent, durent,
## et s'ils ne sont pas résolus à temps, laissent leurs conséquences. Deux parties ne se ressemblent pas, par
## construction, sans qu'aucun scénario ne soit écrit.

const Rules := preload("res://core/rules.gd")
const ACTIONS_FILE := "res://data/actions.json"
const PROBLEMS_FILE := "res://data/problems.json"
const DESPISE_ID := "mepriser"

@export var max_choices := 6

var actions: Array = []
var problems: Array = []
var _open_target := ""
## L'image (physique) où la dernière rencontre s'est fermée : le joueur ne saute pas sur le même appui (A choisit ET
## saute sur une manette).
var closed_frame := -100
var _open_actions: Array = []


func _ready() -> void:
	actions = _load_list(ACTIONS_FILE, "actions")
	problems = _load_list(PROBLEMS_FILE, "problems")
	EventBus.day_changed.connect(func(_d: int) -> void: _expire_problems())


# --- Contexte ----------------------------------------------------------------------------------------------

## `target` : ce qu'un Interactable déclare (`describe()`) — id, kind, tags, traits, et ses valeurs par défaut.
func build_context(target: Dictionary) -> Dictionary:
	var id := str(target.get("id", ""))
	var ent := GameState.entity(id, target.get("defaults", {}))
	var t := target.duplicate(true)
	t.merge(ent, true)
	return {
		"player": GameState.get_value("player", {}),
		"place": GameState.get_value("place", {}),
		"time": GameClock.snapshot(),
		"target": t,
		"history": GameState.history_with(id),
		"karma": GameState.karma(),
		"flags": GameState.get_value("flags", {}),
	}


# --- Proposer ----------------------------------------------------------------------------------------------

## La barre d'une rencontre : un tableau d'actions (Dictionary des données), « Mépriser » en dernier.
func propose(target: Dictionary) -> Array:
	var id := str(target.get("id", ""))
	refresh_problem(target)
	var ctx := build_context(target)
	var pool: Array = []
	var weights: Array = []
	var despise: Dictionary = {}
	for a: Dictionary in actions:
		if a.get("id") == DESPISE_ID:
			despise = a
			continue
		if not Rules.matches(a.get("when"), ctx):
			continue
		var w := float(a.get("weight", 1.0))
		for m: Dictionary in a.get("weight_mods", []):
			if Rules.matches(m.get("when"), ctx):
				w *= float(m.get("mul", 1.0))
		if w > 0.0:
			pool.append(a)
			weights.append(w)
	var rng := Rules.rng_for([GameState.get_value("seed"), id, GameClock.day(), ctx["history"]["count"]])
	var chosen: Array = []
	while not pool.is_empty() and chosen.size() < max_choices - 1:
		var i := _weighted_index(weights, rng)
		chosen.append(pool[i])
		pool.remove_at(i)
		weights.remove_at(i)
	chosen.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("order", 50)) < int(b.get("order", 50)))
	chosen.append(despise if not despise.is_empty() else {"id": DESPISE_ID, "label": "Mépriser", "category": "mepris"})
	return chosen


func open_encounter(target: Dictionary) -> Array:
	_open_target = str(target.get("id", ""))
	_open_actions = propose(target)
	EventBus.encounter_opened.emit(_open_target, _open_actions)
	return _open_actions


func close_encounter() -> void:
	if _open_target != "":
		closed_frame = Engine.get_physics_frames()
		var id := _open_target
		_open_target = ""
		_open_actions = []
		EventBus.encounter_closed.emit(id)


func is_open() -> bool:
	return _open_target != ""


## Choisit l'action n° `index` de la rencontre ouverte.
func choose(index: int) -> Dictionary:
	if index < 0 or index >= _open_actions.size():
		return {}
	var target_id := _open_target
	var action: Dictionary = _open_actions[index]
	close_encounter()
	return resolve(target_id, action)


## Applique une action à une cible : ses effets, puis l'historique. Ce que la présentation joue ensuite
## (animation, dialogue, son) écoute `action_resolved`.
func resolve(target_id: String, action: Dictionary) -> Dictionary:
	Rules.apply_effects(action.get("effects", []), target_id)
	var rec := GameState.record_interaction(target_id, action)
	EventBus.action_resolved.emit(target_id, str(action.get("id", "")), rec)
	return rec


# --- Problèmes ---------------------------------------------------------------------------------------------

## Donne un problème à une entité qui n'en a pas (ou plus), si le tirage du jour le veut.
func refresh_problem(target: Dictionary) -> void:
	var id := str(target.get("id", ""))
	var ent := GameState.entity(id, target.get("defaults", {}))
	var current: Dictionary = ent.get("problem", {})
	if not current.is_empty() and not current.get("resolved", false):
		return
	var since := int(current.get("resolved_day", current.get("expired_day", -999)))
	if GameClock.day() - since < 1:
		return
	var ctx := build_context(target)
	var rng := Rules.rng_for([GameState.get_value("seed"), id, GameClock.day(), "probleme"])
	var pool: Array = []
	var weights: Array = []
	for p: Dictionary in problems:
		if Rules.matches(p.get("when"), ctx):
			pool.append(p)
			weights.append(float(p.get("weight", 1.0)))
	if pool.is_empty() or rng.randf() > float(target.get("problem_chance", 0.6)):
		return
	var p: Dictionary = pool[_weighted_index(weights, rng)]
	ent["problem"] = {"id": p["id"], "type": p.get("type", ""), "label": p.get("label", ""),
		"severity": int(p.get("severity", 1)), "since_day": GameClock.day(),
		"until_day": GameClock.day() + int(p.get("duration_days", 3)), "resolved": false}


## Les problèmes laissés sans réponse expirent et laissent leurs conséquences (effets des données).
func _expire_problems() -> void:
	var by_id := {}
	for p: Dictionary in problems:
		by_id[p["id"]] = p
	var all: Dictionary = GameState.get_value("entities", {})
	for id: String in all:
		var prob: Dictionary = all[id].get("problem", {})
		if prob.is_empty() or prob.get("resolved", false) or GameClock.day() <= int(prob.get("until_day", 0)):
			continue
		Rules.apply_effects(by_id.get(prob["id"], {}).get("on_expire", []), id)
		all[id]["problem"] = {"expired_day": GameClock.day(), "resolved": true, "expired": prob["id"]}


# --- Outils ------------------------------------------------------------------------------------------------

static func _weighted_index(weights: Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for w: float in weights:
		total += w
	var r := rng.randf() * total
	for i in weights.size():
		r -= weights[i]
		if r <= 0.0:
			return i
	return weights.size() - 1


static func _load_list(path: String, key: String) -> Array:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		push_error("DecisionEngine: %s illisible (ligne %d)" % [path, json.get_error_line()])
		return []
	return json.data.get(key, [])

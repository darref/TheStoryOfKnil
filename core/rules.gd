extends RefCounted
## LE LANGAGE DES DONNÉES — conditions et effets, écrits dans data/*.json, lus ici et nulle part ailleurs.
##
## CONDITION  {"path": "time.phase", "op": "in", "value": ["nuit", "crepuscule"]}
##            ops : == != < <= > >= in not_in has not_has exists missing
##            {"any": [cond, …]}  au moins une ;  {"not": cond}  la négation ;  une liste = toutes.
## CHEMIN     lu dans le CONTEXTE d'une rencontre : player.* place.* time.* target.* history.* karma.* flags.*
## EFFET      {"op": "add", "path": "player.wealth.gold", "value": -5}
##            ops : add set push (ajout unique à une liste) erase stamp (le jour courant) resolve_problem
##            Un chemin `target.*` désigne l'état persistant de la cible (GameState.entities[id]).


static func read(ctx: Dictionary, path: String) -> Variant:
	var node: Variant = ctx
	for part in path.split("."):
		if node is Dictionary and (node as Dictionary).has(part):
			node = node[part]
		else:
			return null
	return node


static func matches(conds: Variant, ctx: Dictionary) -> bool:
	if conds == null:
		return true
	if conds is Array:
		for c: Variant in conds:
			if not matches(c, ctx):
				return false
		return true
	var c: Dictionary = conds
	if c.has("any"):
		for sub: Variant in c["any"]:
			if matches(sub, ctx):
				return true
		return false
	if c.has("not"):
		return not matches(c["not"], ctx)
	return _test(read(ctx, str(c.get("path", ""))), str(c.get("op", "==")), c.get("value"))


static func _test(v: Variant, op: String, ref: Variant) -> bool:
	match op:
		"exists": return v != null
		"missing": return v == null
		"==": return v != null and _same(v, ref)
		"!=": return v == null or not _same(v, ref)
		"<": return _num(v) < _num(ref)
		"<=": return _num(v) <= _num(ref)
		">": return _num(v) > _num(ref)
		">=": return _num(v) >= _num(ref)
		"in": return ref is Array and _contains(ref, v)
		"not_in": return not (ref is Array and _contains(ref, v))
		"has": return (v is Array and _contains(v, ref)) or (v is Dictionary and (v as Dictionary).has(ref))
		"not_has": return not ((v is Array and _contains(v, ref)) or (v is Dictionary and (v as Dictionary).has(ref)))
	push_warning("Rules: opérateur inconnu « %s »" % op)
	return false


## Le JSON rend tous les nombres en float : 3 et 3.0 sont la même valeur.
static func _same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	return a == b


static func _contains(list: Array, v: Variant) -> bool:
	for x: Variant in list:
		if _same(x, v):
			return true
	return false


static func _num(v: Variant) -> float:
	return float(v) if (v is int or v is float or v is bool) else 0.0


## Applique les effets d'une action au GameState. `target_id` résout les chemins `target.*`.
static func apply_effects(effects: Array, target_id: String) -> void:
	for e: Dictionary in effects:
		var path := str(e.get("path", ""))
		if path.begins_with("target."):
			GameState.entity(target_id)
			path = "entities.%s.%s" % [target_id, path.trim_prefix("target.")]
		match str(e.get("op", "")):
			"add":
				GameState.add_value(path, float(e.get("value", 0)))
			"set":
				GameState.set_value(path, e.get("value"))
			"stamp":
				GameState.set_value(path, GameClock.day())
			"push":
				var list: Array = GameState.get_value(path, [])
				if not _contains(list, e.get("value")):
					list = list.duplicate()
					list.append(e.get("value"))
					GameState.set_value(path, list)
			"erase":
				var list2: Array = (GameState.get_value(path, []) as Array).duplicate()
				list2.erase(e.get("value"))
				GameState.set_value(path, list2)
			"resolve_problem":
				var ent := GameState.entity(target_id)
				if not (ent["problem"] as Dictionary).is_empty():
					ent["problem"]["resolved"] = true
					ent["problem"]["resolved_day"] = GameClock.day()
			_:
				push_warning("Rules: effet inconnu %s" % str(e))


## Un tirage DÉTERMINISTE : même partie, même cible, même moment → même tirage. Une autre partie (un autre
## germe) tire autrement : c'est la divergence gratuite.
static func rng_for(parts: Array) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(parts))
	return rng

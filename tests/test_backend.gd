extends Node
## LES ÉPREUVES DU BACKEND — headless :
##   Godot --headless --path D:/Resolve res://tests/test_backend.tscn
## Sort avec le code 0 si tout est vert, 1 sinon.

var _fails := 0
var _checks := 0


func _ready() -> void:
	await get_tree().process_frame
	_test_despise_always_last()
	_test_determinism_and_divergence()
	_test_context_drives_choices()
	_test_resolve_and_history()
	_test_problem_expiry()
	_test_sleep_forced_and_wake()
	_test_save_roundtrip()
	print("ÉPREUVES : %d vérifications, %d échecs" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		printerr("ÉCHEC : " + what)


func _target(id: String, kind := "personne", tags: Array = []) -> Dictionary:
	return {"id": id, "kind": kind, "tags": tags, "traits": {}, "problem_chance": 0.7}


func _ids(actions: Array) -> Array:
	return actions.map(func(a: Dictionary) -> String: return a["id"])


func _test_despise_always_last() -> void:
	GameState.new_game(1)
	for i in 40:
		var tags: Array = [["marchand"], ["pauvre"], ["aubergiste"], [], ["sacre", "habitant"]][i % 5]
		var kind: String = ["personne", "lieu", "objet", "animal"][i % 4]
		var acts := DecisionEngine.propose(_target("e%d" % i, kind, tags))
		check(not acts.is_empty() and acts.back()["id"] == DecisionEngine.DESPISE_ID, "Mépriser en dernier (%d)" % i)
		check(acts.size() <= DecisionEngine.max_choices, "pas plus de max_choices (%d)" % i)
		check(_ids(acts).count(DecisionEngine.DESPISE_ID) == 1, "Mépriser une seule fois (%d)" % i)


func _test_determinism_and_divergence() -> void:
	var runs: Array = []
	for s in [11, 11, 12]:
		GameState.new_game(s)
		GameClock.from_save({"minutes": 8 * 60})
		var out: Array = []
		for i in 30:
			out.append(_ids(DecisionEngine.propose(_target("pnj%d" % i, "personne", ["marchand", "habitant"]))))
			out.append(GameState.entity("pnj%d" % i)["problem"].get("id", ""))
		runs.append(out)
	check(runs[0] == runs[1], "même germe, même partie")
	check(runs[0] != runs[2], "autre germe, autre partie")


func _test_context_drives_choices() -> void:
	GameState.new_game(5)
	GameState.set_value("player.wealth.gold", 50)
	var rich := _ids(DecisionEngine.propose(_target("aub", "personne", ["aubergiste"])))
	GameState.set_value("player.wealth.gold", 0)
	var poor := _ids(DecisionEngine.propose(_target("aub2", "personne", ["aubergiste"])))
	check("louer_chambre" in rich, "assez d'or : louer une chambre est proposé")
	check(not "louer_chambre" in poor, "sans or : pas de chambre")
	check(not "donner" in poor, "sans or : pas de don")


func _test_resolve_and_history() -> void:
	GameState.new_game(9)
	var t := _target("vieux", "personne", ["pauvre"])
	DecisionEngine.open_encounter(t)
	var acts: Array = DecisionEngine._open_actions
	var rec := DecisionEngine.choose(acts.size() - 1)
	check(rec.get("action") == DecisionEngine.DESPISE_ID, "le choix est enregistré")
	var h := GameState.history_with("vieux")
	check(h["count"] == 1 and h["last_action"] == DecisionEngine.DESPISE_ID, "historique de la cible")
	check(float(h["disposition"]) < 0.0, "mépriser baisse la disposition")
	check(not DecisionEngine.is_open(), "la rencontre est fermée")


func _test_problem_expiry() -> void:
	GameState.new_game(3)
	GameClock.from_save({"minutes": 8 * 60})
	var ent := GameState.entity("malade")
	ent["problem"] = {"id": "fievre", "type": "maladie", "until_day": 1, "resolved": false}
	GameClock.advance(3 * GameClock.MINUTES_PER_DAY)
	var p: Dictionary = GameState.entity("malade")["problem"]
	check(p.get("expired", "") == "fievre", "le problème expire")
	check("fievre_passee" in GameState.entity("malade")["state"].get("marques", []), "il laisse sa conséquence")


func _test_sleep_forced_and_wake() -> void:
	GameState.new_game(4)
	GameClock.from_save({"minutes": 8 * 60})
	SleepSystem._reset_wake()
	var outcome := {}
	var on_wake := func(o: Dictionary) -> void: outcome.merge(o)
	EventBus.sleep_finished.connect(on_wake)
	GameClock.advance(71 * 60)
	check(not SleepSystem.sleeping, "éveillé à 71 h")
	GameClock.advance(60 + 1)
	check(SleepSystem.sleeping, "effondré à 72 h")
	GameClock._process(1000.0)
	check(not SleepSystem.sleeping and not outcome.is_empty(), "réveillé")
	check(SleepSystem.awake_hours() < 0.1, "la fatigue repart de zéro")
	check(outcome.get("sleep", {}).get("forced", false), "le réveil sait que c'était forcé")
	EventBus.sleep_finished.disconnect(on_wake)


func _test_save_roundtrip() -> void:
	GameState.new_game(77)
	GameState.set_value("player.wealth.gold", 123)
	DecisionEngine.resolve("x", {"id": "aider", "category": "aide"})
	check(SaveSystem.save("epreuve"), "sauvegarde écrite")
	GameState.new_game(1)
	check(SaveSystem.load_slot("epreuve"), "sauvegarde relue")
	check(int(GameState.get_value("player.wealth.gold")) == 123, "l'or revient")
	check(GameState.history_with("x")["count"] == 1, "l'historique revient")
	check(int(GameState.get_value("seed")) == 77, "le germe revient")
	DirAccess.remove_absolute(SaveSystem.path_of("epreuve"))

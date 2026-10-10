extends Node
## LE SOMMEIL — le rythme du jeu. On doit dormir au plus tous les `limit_hours` (3 jours) : au-delà, on
## s'effondre là où l'on est. Pendant le sommeil l'horloge défile en accéléré (le cycle jour / nuit se voit),
## puis les règles de réveil (data/sleep.json) disent OÙ l'on se réveille : au même endroit, chez soi, à
## l'auberge, en prison… selon le couchage, et selon tout ce que l'on a fait dans la partie.
##
## Le backend ne déplace personne : il dit `sleep_finished(outcome)` avec la destination (un SleepSpot, ou
## rien = sur place), et la présentation (le Player) s'y rend.

const Rules := preload("res://core/rules.gd")
const SLEEP_FILE := "res://data/sleep.json"
const SPOT_GROUP := "sleep_spots"

var config: Dictionary = {}
var sleeping := false
var _warned: Array = []
var _pending: Dictionary = {}


func _ready() -> void:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(SLEEP_FILE)) == OK:
		config = json.data
	else:
		push_error("SleepSystem: %s illisible" % SLEEP_FILE)
	EventBus.hour_changed.connect(_on_hour)
	EventBus.game_started.connect(func(_s: int) -> void: _reset_wake())
	_reset_wake()


func limit_hours() -> float:
	return float(config.get("limit_hours", 72))


func awake_hours() -> float:
	return (GameClock.minutes - float(GameState.get_value("player.last_wake_minutes", 0.0))) / 60.0


func can_sleep() -> bool:
	return not sleeping and awake_hours() >= float(config.get("min_awake_hours", 10))


## S'endormir sur un couchage (`spot` : un SleepSpot, ou null = à même le sol). `forced` : l'effondrement.
func sleep(spot: Node = null, forced := false) -> void:
	if sleeping:
		return
	sleeping = true
	var kind: String = spot.spot_kind if spot != null else "sol"
	var info: Dictionary = config.get("spots", {}).get(kind, {"quality": 0, "normal": false})
	if spot != null and spot.has_method("is_usable") and not spot.is_usable():
		info = info.duplicate()
		info["normal"] = false  # un lit d'auberge non payé, le lit d'un inconnu hostile : ce n'est pas « normal »
	var hours := float(config.get("forced_sleep_hours" if forced else "sleep_hours", 8))
	var target := GameClock.minutes + hours * 60.0
	if not forced:
		target = maxf(target, minf(GameClock.next_time_at(int(config.get("wake_hour", 7))), GameClock.minutes + 14 * 60.0))
	_pending = {"spot_kind": kind, "spot_id": spot.spot_id if spot != null else "", "quality": info.get("quality", 0),
		"normal": info.get("normal", false), "forced": forced, "awake_hours": awake_hours()}
	DecisionEngine.close_encounter()
	EventBus.sleep_started.emit(kind, forced)
	GameClock.fast_forward(target, float(config.get("real_seconds", 8)), _wake)


func _wake() -> void:
	var outcome := resolve_wake(_pending)
	_reset_wake()
	sleeping = false
	_pending = {}
	EventBus.sleep_finished.emit(outcome)


## La règle de réveil qui s'applique : {rule, message, destination (SleepSpot ou null), wake}.
func resolve_wake(sleep_ctx: Dictionary) -> Dictionary:
	var ctx := DecisionEngine.build_context({"id": "_sommeil", "kind": "soi"})
	ctx["sleep"] = sleep_ctx
	var rng := Rules.rng_for([GameState.get_value("seed"), "reveil", GameClock.day()])
	for r: Dictionary in config.get("wake_rules", []):
		if not Rules.matches(r.get("when"), ctx):
			continue
		if rng.randf() > float(r.get("chance", 1.0)):
			continue
		var dest := find_destination(str(r.get("wake", "same")))
		if dest == null and str(r.get("wake", "same")) != "same":
			continue  # la règle veut un lieu que ce monde n'a pas (pas de prison ici) : la suivante
		Rules.apply_effects(r.get("effects", []), "_sommeil")
		return {"rule": r.get("id", ""), "message": r.get("message", ""), "destination": dest,
			"wake": r.get("wake", "same"), "sleep": sleep_ctx}
	return {"rule": "", "message": "", "destination": null, "wake": "same", "sleep": sleep_ctx}


func find_destination(wake: String) -> Node:
	if wake == "same":
		return null
	var spots := get_tree().get_nodes_in_group(SPOT_GROUP)
	if wake == "home":
		var home := str(GameState.get_value("player.home.spot_id", ""))
		for s in spots:
			if s.spot_id == home:
				return s
		return null
	var p: Array = GameState.get_value("place.position", [0, 0, 0])
	var here := Vector3(p[0], p[1], p[2])
	var best: Node = null
	var best_d := INF
	for s: Node3D in spots:
		var ok: bool = (wake.begins_with("nearest:") and s.spot_kind == wake.trim_prefix("nearest:")) \
			or (wake.begins_with("tag:") and wake.trim_prefix("tag:") in s.tags)
		if ok and s.global_position.distance_squared_to(here) < best_d:
			best = s
			best_d = s.global_position.distance_squared_to(here)
	return best


func _on_hour(_day: int, _hour: int) -> void:
	if sleeping:
		return
	var h := awake_hours()
	EventBus.fatigue_changed.emit(h, limit_hours())
	for w: float in config.get("warnings", []):
		if h >= w and not _warned.has(w):
			_warned.append(w)
			EventBus.sleep_warning.emit(limit_hours() - h)
	if h >= limit_hours():
		sleep(null, true)


func _reset_wake() -> void:
	GameState.set_value("player.last_wake_minutes", GameClock.minutes)
	_warned = []

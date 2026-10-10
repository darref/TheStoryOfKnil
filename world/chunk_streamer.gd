class_name ChunkStreamer
extends Node3D
## LE MONDE EN MORCEAUX — charge, autour de la cible (le joueur), les morceaux cuits par `tools/cuisson/`, et
## décharge ceux qui s'éloignent. UNE PISTE PAR RÔLE de couche (`tools/cuisson/couches.json`), chacune sa distance :
##   sol (le relief, l'eau, le feuillage) ~56 · obstacles (les massifs des chemins) ~72 · gros (un volcan) ~400 ·
##   batiments ~64 · collision (la forme et le SOUS-SOL du morceau) ~20 seulement.
## Les distances viennent de monde.json ; `distances` les remplace piste par piste.
##
## Tout se fait EN FOND : la lecture (`ResourceLoader.load_threaded_request`), puis l'INSTANCIATION dans un fil de
## travail ; sur le fil principal ne reste que l'entrée dans l'arbre (~0,1 ms), au plus `max_spawn_per_frame` par image.
## ⚠ MESURÉ (8 octobre 2026, 256² colonnes, traversée en courant, RTX 2060) : la collision concave est ce qui fait
## les à-coups — 46 images > 33 ms avec la forme pleine dans chaque morceau visible, 0 sans collision. D'où la forme
## simplifiée (cuisson), la piste à part et courte, et l'instanciation en fond.
##
## SOUS TERRE : le sous-sol du morceau de collision sous la cible dit si elle est dans de l'air ENFOUI (une galerie) ;
## alors `Interior.set_underground(true)` — caméra en troisième personne, torche, ambiante d'intérieur — et les tuiles
## « Souterrain » des morceaux se montrent (cachées sinon : vues de dessus, elles ne servent à rien).
##
## Au départ (et après un saut : réveil ailleurs, sauvegarde relue), `load_around_now` charge D'UN COUP ce qui est
## sous la cible : le joueur ne tombe jamais dans un trou pas encore chargé.

signal chunk_loaded(track: String, key: Vector2i)
signal chunk_unloaded(track: String, key: Vector2i)

enum UndergroundView { WHEN_UNDERGROUND, ALWAYS }

const COLLISION_TRACK := "collision"

## Le dossier d'un monde cuit (celui qui porte monde.json).
@export_dir var baked_dir := ""
@export var target: Node3D
## Piste -> distance, pour remplacer celles de monde.json (ex. {"gros": 600}).
@export var distances: Dictionary = {}
## Déchargé au-delà de la distance + cette marge (l'écart évite de charger / décharger en boucle).
@export var unload_margin := 16.0
@export var max_spawn_per_frame := 1
## Au plus tant de lectures en fond à la fois (les plus proches d'abord) : leurs envois à la carte graphique ne se
## télescopent plus. ⚠ MESURÉ : toutes lancées d'un coup (8), elles faisaient des à-coups groupés.
@export var max_loading := 2
## Le temps, par image, donné à faire des formes de collision (`_build_shapes`).
@export var shape_budget_ms := 2.0
@export var underground_view := UndergroundView.WHEN_UNDERGROUND
## Sous terre / à l'air : l'état doit tenir ce temps avant de basculer (une galerie traversée d'un pas ne fait pas
## clignoter la caméra).
@export var underground_hold := 0.25
## Au-delà de ce saut de la cible (en une image), on recharge d'un coup autour d'elle.
@export var teleport_threshold := 40.0
## LA VUE : quand la caméra voit plus loin (zoom, vue haute — `EventBus.view_radius_changed`), les pistes VISIBLES
## chargent jusqu'à `view_margin` × ce rayon + `view_ahead` (la collision, non : elle reste près du joueur).
@export var view_margin := 1.3
@export var view_ahead := 24.0

var manifest: Dictionary = {}
## piste -> Vector2i -> {"file", "rect", "node", "task", "built",
##   "state": "off" | "wanted" | "loading" | "abandoned" | "instancing" | "on"}
var _tracks := {}
var _reach := {}
var _queue: Array = []  # [piste, clé] en cours de lecture ou d'instanciation
var _last_pos := Vector3.INF
var _tick := 0.0
var _chunk := 32
var _under_since := 0.0
var _view_radius := 0.0
## Ce que la dernière image a coûté ici, en ms, par poste (lu par les bancs : où passent les à-coups).
var last_costs := {}
## Les transitions du monde : le matériau partagé par tous les morceaux, et ses données (gardés : le cache des
## ressources les rend aux morceaux qui le chargent ensuite).
var _transitions_mat: ShaderMaterial = null
var _transitions_data: Resource = null
## Les limites de la zone jouable (x, z), si le monde cuit les donne : murs invisibles, et la cible tenue en dedans.
var play_bounds := Rect2()
var _base_reach := {}


func _ready() -> void:
	if not load_manifest():
		return
	EventBus.view_radius_changed.connect(_on_view_radius)
	_warn_if_stale.call_deferred()
	EventBus.interior_entered.connect(func(_i: String, _t: String) -> void: _apply_underground())
	EventBus.interior_exited.connect(func(_i: String) -> void: _apply_underground())
	if target:
		load_around_now(target.global_position)
		# ⚠ Le point de départ est retenu : une cible déplacée avant le premier passage (une téléportation dès l'entrée
		# en jeu) est alors vue comme un SAUT — vu : sans cela, rien ne se chargeait là où elle arrivait.
		_last_pos = target.global_position


func load_manifest() -> bool:
	var path := baked_dir.path_join("monde.json")
	var json := JSON.new()
	if not FileAccess.file_exists(path) or json.parse(FileAccess.get_file_as_string(path)) != OK:
		push_error("ChunkStreamer : %s illisible — le monde a-t-il été cuit ?" % path)
		return false
	manifest = json.data
	if int(manifest.get("version", 0)) < 2:
		push_error("ChunkStreamer : %s est une cuisson ancienne (v%d) — recuire" % [path, int(manifest.get("version", 0))])
		return false
	_chunk = int(manifest["chunk"])
	# LES LIMITES : quatre murs invisibles, très hauts ; et la cible (le joueur) tenue en dedans — `Player.world_bounds`.
	var pb: Dictionary = manifest.get("play_bounds", {})
	if not pb.is_empty():
		play_bounds = Rect2(Vector2(pb["min"][0], pb["min"][1]),
			Vector2(pb["max"][0] - pb["min"][0], pb["max"][1] - pb["min"][1]))
		_build_walls()
		if target != null and "world_bounds" in target:
			target.world_bounds = play_bounds
	# LES TRANSITIONS : leurs textures rebâties UNE fois sur le matériau partagé (`world/transitions_cuites.gd`).
	var tr: Dictionary = manifest.get("transitions", {})
	if not tr.is_empty():
		_transitions_mat = load(baked_dir.path_join(tr["material"])) as ShaderMaterial
		_transitions_data = load(baked_dir.path_join(tr["data"]))
		if _transitions_mat != null and _transitions_data != null:
			_transitions_data.apply(_transitions_mat)
		else:
			push_error("ChunkStreamer : les transitions de %s ne se lisent pas" % baked_dir)
	_tracks = {}
	_reach = {}
	for t: String in manifest["tracks"]:
		_tracks[t] = {}
		_base_reach[t] = float(distances.get(t, manifest["tracks"][t]["distance"]))
		_reach[t] = _base_reach[t]
	for c: Dictionary in manifest["chunks"]:
		var key := Vector2i(int(c["key"][0]), int(c["key"][1]))
		for t: String in c["files"]:
			var b: Array = c["aabb"][t]
			_tracks[t][key] = {"file": baked_dir.path_join(c["files"][t]), "rect": Rect2(b[0], b[2], b[3], b[5]),
				"node": null, "task": -1, "built": null, "state": "off"}
	return true


func _process(delta: float) -> void:
	if target == null or _tracks.is_empty():
		return
	var p := target.global_position
	if _last_pos != Vector3.INF and p.distance_to(_last_pos) > teleport_threshold:
		load_around_now(p)
	_last_pos = p
	_tick -= delta
	last_costs = {"update": 0.0, "get": 0.0, "enter": 0.0, "free": 0.0, "ensure": 0.0, "n_enter": 0, "n_free": 0}
	var t0 := Time.get_ticks_usec()
	if _tick <= 0.0:
		_tick = 0.2
		_update_wanted(p)
	last_costs["update"] = (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	_poll()
	last_costs["poll"] = (Time.get_ticks_usec() - t0) / 1000.0
	last_costs["queue"] = _queue.size()
	t0 = Time.get_ticks_usec()
	_ensure_under(p)
	last_costs["ensure"] = (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	_build_shapes()
	last_costs["shapes"] = (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	_detect_underground(p, delta)
	last_costs["under"] = (Time.get_ticks_usec() - t0) / 1000.0


## Charge tout de suite (bloquant) ce qui est à portée de `p` — au départ, après un saut.
func load_around_now(p: Vector3) -> void:
	for track: String in _tracks:
		for key: Vector2i in _tracks[track]:
			var c: Dictionary = _tracks[track][key]
			if _distance(c["rect"], p) <= _reach[track] and c["state"] != "on":
				_enter(track, key, (load(c["file"]) as PackedScene).instantiate())
	_update_wanted(p)
	_under_since = underground_hold  # après un saut, l'état sous terre se décide tout de suite


func loaded_count(track := "sol") -> int:
	if not _tracks.has(track):
		return 0
	return _tracks[track].values().filter(func(c: Dictionary) -> bool: return c["state"] == "on").size()


func state_of(key: Vector2i, track := "sol") -> String:
	return _tracks[track][key]["state"] if _tracks.has(track) and _tracks[track].has(key) else ""


func _on_view_radius(r: float) -> void:
	_view_radius = r
	for t: String in _base_reach:
		_reach[t] = _base_reach[t] if t == COLLISION_TRACK else maxf(_base_reach[t], r * view_margin + view_ahead)
	_tick = 0.0  # on revoit tout de suite ce qu'il faut charger


## Le morceau SOUS la cible (sa collision, son sol) est là, quoi qu'il arrive : s'il manque, il est chargé tout de suite,
## sur ce fil. ⚠ VU : un saut de 39 m (sous le seuil de 40) laissait le joueur tomber le temps que la collision arrive
## en fond. Une image un peu longue vaut mieux qu'une chute à travers le monde.
func _ensure_under(p: Vector3) -> void:
	var key := Vector2i(floori(p.x / float(_chunk)), floori(p.z / float(_chunk)))
	for track: String in [COLLISION_TRACK, str(manifest.get("underground_role", "sol"))]:
		var c: Dictionary = _tracks.get(track, {}).get(key, {})
		if not c.is_empty() and c["state"] != "on":
			_enter(track, key, (load(c["file"]) as PackedScene).instantiate())
		elif not c.is_empty() and c["node"] != null:
			# Là, mais ses formes pas toutes bâties : le sol sous les pieds, tout de suite.
			var f := (c["node"] as Node).get_node_or_null("Formes")
			if f != null and f.pending():
				f.build_all()


## Le point `p` est-il dans de l'air enfoui ? (Faux tant que le sous-sol de son morceau n'est pas chargé.)
func is_underground_at(p: Vector3) -> bool:
	var cell := Vector3i(floori(p.x), floori(p.y + 0.5), floori(p.z))
	var key := Vector2i(floori(cell.x / float(_chunk)), floori(cell.z / float(_chunk)))
	var c: Dictionary = _tracks.get(COLLISION_TRACK, {}).get(key, {})
	if c.is_empty() or c["node"] == null:
		return false
	var under := (c["node"] as Node).get_node_or_null("SousSol")
	return under != null and under.contains(cell)


func _detect_underground(p: Vector3, delta: float) -> void:
	var now := is_underground_at(p)
	if now == Interior.is_underground():
		_under_since = 0.0
		return
	_under_since += delta
	if _under_since >= underground_hold:
		_under_since = 0.0
		Interior.set_underground(now)


func _update_wanted(p: Vector3) -> void:
	for track: String in _tracks:
		var reach: float = _reach[track]
		for key: Vector2i in _tracks[track]:
			var c: Dictionary = _tracks[track][key]
			var d := _distance(c["rect"], p)
			if d <= reach and c["state"] == "abandoned":
				c["state"] = "loading"  # revenu à portée avant la fin de sa lecture : on le reprend
			elif d <= reach and c["state"] == "off":
				c["state"] = "wanted"
				_queue.append([track, key])
			elif d > reach + unload_margin:
				if c["state"] == "wanted":
					c["state"] = "off"
				elif c["state"] == "on":
					var tf := Time.get_ticks_usec()
					c["node"].queue_free()
					if not last_costs.is_empty():
						last_costs["free"] += (Time.get_ticks_usec() - tf) / 1000.0
						last_costs["n_free"] += 1
					c["node"] = null
					c["state"] = "off"
					chunk_unloaded.emit(track, key)
				elif c["state"] == "loading":
					c["state"] = "abandoned"  # il finira de se lire en fond, puis sera jeté


func _poll() -> void:
	# Les lectures à lancer : les plus proches de la cible d'abord, tant que moins de `max_loading` sont en cours.
	var loading := 0
	var waiting: Array = []
	for q in _queue:
		var st: String = _tracks[q[0]][q[1]]["state"]
		if st == "loading" or st == "abandoned" or st == "instancing":
			loading += 1
		elif st == "wanted":
			waiting.append(q)
	if loading < max_loading and not waiting.is_empty() and target != null:
		var p := target.global_position
		waiting.sort_custom(func(a: Array, b: Array) -> bool:
			return _distance(_tracks[a[0]][a[1]]["rect"], p) < _distance(_tracks[b[0]][b[1]]["rect"], p))
		for q in waiting.slice(0, max_loading - loading):
			var c: Dictionary = _tracks[q[0]][q[1]]
			c["state"] = "loading"
			# Sans sous-fils : mesuré, moins d'à-coups (29 images > 33 ms au lieu de 32).
			ResourceLoader.load_threaded_request(c["file"], "PackedScene", false)
	var spawned := 0
	var i := 0
	while i < _queue.size():
		var track: String = _queue[i][0]
		var key: Vector2i = _queue[i][1]
		var c: Dictionary = _tracks[track][key]
		match c["state"]:
			"loading", "abandoned":
				var status := ResourceLoader.load_threaded_get_status(c["file"])
				if status == ResourceLoader.THREAD_LOAD_LOADED:
					var tg := Time.get_ticks_usec()
					var packed: PackedScene = ResourceLoader.load_threaded_get(c["file"])
					if not last_costs.is_empty():
						last_costs["get"] += (Time.get_ticks_usec() - tg) / 1000.0
					if c["state"] == "abandoned":
						c["state"] = "off"  # on n'en veut plus : relu, jeté
						_queue.remove_at(i)
						continue
					c["state"] = "instancing"
					c["built"] = null
					c["task"] = WorkerThreadPool.add_task(func() -> void: c["built"] = packed.instantiate(),
						false, "morceau %s %s" % [track, key])
				elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
					c["state"] = "off"
					_queue.remove_at(i)
					push_error("ChunkStreamer : %s ne se charge pas" % c["file"])
					continue
			"instancing":
				if WorkerThreadPool.is_task_completed(c["task"]) and spawned < max_spawn_per_frame:
					WorkerThreadPool.wait_for_task_completion(c["task"])
					var n: Node = c["built"]
					c["built"] = null
					c["state"] = "loading"  # _enter le passe à « on »
					var formes := n.get_node_or_null("Formes") if n != null else null
					if formes != null:
						formes.budgeted = true  # bâtie à petites doses (`_build_shapes`)
					_enter(track, key, n)
					_queue.remove_at(i)
					spawned += 1
					continue
			"wanted":
				pass  # attend son tour (ci-dessus)
			_:
				# Déchargé, ou déjà là (chargé d'un coup par load_around_now) pendant qu'il se lisait en fond.
				_queue.remove_at(i)
				continue
		i += 1


## UNE CUISSON PÉRIMÉE SE DIT : l'export de MB (`source`) est plus récent que la cuisson — la carte a été repeinte et
## réexportée, pas recuite (`recuire.bat`). Rien n'est refusé : le jeu montre l'ancienne carte, et le dit.
func _warn_if_stale() -> void:
	var src := str(manifest.get("source", ""))
	if src == "" or not FileAccess.file_exists(src) or not manifest.has("source_mtime"):
		return
	if FileAccess.get_modified_time(src) > int(manifest["source_mtime"]):
		var msg := "La carte a changé dans MB depuis la cuisson : lance recuire.bat (D:\\Resolve) pour la voir en jeu."
		push_warning("ChunkStreamer : " + msg)
		EventBus.notice.emit(msg, 12.0)


## LES FORMES DE COLLISION À PETITES DOSES (`world/collision_morceau.gd`) : chaque image, les pièces des morceaux de
## collision chargés en fond, les plus proches de la cible d'abord, tant que `shape_budget_ms` n'est pas dépensé (au
## moins une pièce). Le morceau sous la cible, lui, se bâtit d'un coup (`_ensure_under`).
func _build_shapes() -> void:
	var todo: Array = []
	for key: Vector2i in _tracks.get(COLLISION_TRACK, {}):
		var c: Dictionary = _tracks[COLLISION_TRACK][key]
		if c["node"] != null:
			var f := (c["node"] as Node).get_node_or_null("Formes")
			if f != null and f.pending():
				todo.append([_distance(c["rect"], target.global_position), f])
	if todo.is_empty():
		return
	todo.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var t0 := Time.get_ticks_usec()
	for it: Array in todo:
		while it[1].pending():
			it[1].build_next()
			if (Time.get_ticks_usec() - t0) / 1000.0 >= shape_budget_ms:
				return


func _enter(track: String, key: Vector2i, n: Node) -> void:
	var c: Dictionary = _tracks[track][key]
	if c["state"] == "on" or n == null:
		if n:
			n.queue_free()
		return
	var te := Time.get_ticks_usec()
	add_child(n)
	if not last_costs.is_empty():
		var ms := (Time.get_ticks_usec() - te) / 1000.0
		last_costs["enter"] += ms
		last_costs["n_enter"] += 1
		if ms > float(last_costs.get("enter_max", 0.0)):
			last_costs["enter_max"] = ms
			last_costs["enter_track"] = "%s %d_%d" % [track, key.x, key.y]
			# Ce qui se lisait en même temps (le diagnostic des entrées lentes) : « piste:état » par morceau en cours.
			var busy: Array = []
			for q in _queue:
				var st: String = _tracks[q[0]][q[1]]["state"]
				if st != "wanted" and not (q[0] == track and q[1] == key):
					busy.append("%s:%s" % [q[0], st])
			last_costs["busy"] = ",".join(busy)
	c["node"] = n
	c["state"] = "on"
	_apply_underground_to(n)
	chunk_loaded.emit(track, key)


func _apply_underground() -> void:
	for t: String in _tracks:
		for c: Dictionary in _tracks[t].values():
			if c["node"] != null:
				_apply_underground_to(c["node"])


func _apply_underground_to(n: Node) -> void:
	var under := n.get_node_or_null("Souterrain") as Node3D
	if under:
		under.visible = underground_view == UndergroundView.ALWAYS or Interior.is_underground()


func _build_walls() -> void:
	var old := get_node_or_null("Limites")
	if old:
		old.free()
	var body := StaticBody3D.new()
	body.name = "Limites"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var r := play_bounds
	var c := r.get_center()
	for w: Array in [[Vector2(c.x, r.position.y - 1.0), Vector2(r.size.x + 4.0, 2.0)],
			[Vector2(c.x, r.end.y + 1.0), Vector2(r.size.x + 4.0, 2.0)],
			[Vector2(r.position.x - 1.0, c.y), Vector2(2.0, r.size.y + 4.0)],
			[Vector2(r.end.x + 1.0, c.y), Vector2(2.0, r.size.y + 4.0)]]:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(w[1].x, 600.0, w[1].y)
		cs.shape = box
		cs.position = Vector3(w[0].x, 200.0, w[0].y)
		body.add_child(cs)


## La distance, vue de dessus, de `p` à la boîte d'un morceau (0 dedans).
static func _distance(r: Rect2, p: Vector3) -> float:
	var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.z, r.position.y, r.end.y))
	return q.distance_to(Vector2(p.x, p.z))

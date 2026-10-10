extends RefCounted
## LA CUISSON D'UN MONDE — un `.mbworld` exporté par le logiciel MarchingBlocks devient des MORCEAUX prêts à charger.
##
## ⚠ RIEN N'EST RÉÉCRIT : la pose des tuiles est celle du greffon (`Rule.placements_layered`, la référence des trois
## greffons, sur les tuiles que charge `Tileset.load_tileset`), l'eau son nœud `MarchingBlocksWater`, le feuillage
## son `instances()`. On récolte ce qu'il poserait — l'épreuve le compare, triangle pour triangle, au monde bâti par le
## greffon lui-même (`WorldFile.build`). Le jeu livré ne charge que les morceaux : ni le greffon, ni la règle.
##
## LES COUCHES ONT UN RÔLE (`couches.json`) : le monde de Resolve est UN .mbworld à plusieurs couches — Sol (le relief
## et ses galeries), Obstacles (les massifs des chemins et des places), GrosObstacles (un volcan…), Batiments (l'atelier
## Houses de MB 1.0.0). La règle les lit ENSEMBLE (aucun mur où elles se touchent) ; la cuisson les RANGE à part :
## chaque rôle a sa piste de chargement et sa distance d'affichage.
##
## PAR FENÊTRES : le monde se pose fenêtre par fenêtre (`window` × `window` morceaux), avec une case de marge — un
## sommet v ne lit que les cases v..v+1 et leurs colonnes, toutes entières dans la fenêtre. La mémoire reste celle d'une
## fenêtre : c'est ce qui rend cuisable un sol de 2048² (si le .mbworld lui-même se lit — voir CLAUDE.md, OUVERT).
##
## Un MORCEAU = `chunk` × `chunk` colonnes, toute la hauteur. Par rôle, une scène `<rôle>/m_<x>_<z>.scn` :
##   Surface     les tuiles du rôle, fusionnées : UNE surface par matériau, avec LOD
##   Souterrain  (rôle « souterrain ») les tuiles ENFOUIES — dont toutes les cases vides ont au moins
##               `deep` cases pleines au-dessus : les galeries ; une arche, un surplomb, l'entrée d'une grotte restent
##               en Surface. Le jeu ne les montre que sous terre.
##   Eau, Feuillage  (rôle par défaut) la nappe découpée par triangle ; les plants en DONNÉES (`feuillage_morceau.gd`)
## Et `collision/c_<x>_<z>.scn` : un corps statique (toutes les couches, sur un LOD simplifié) et le SOUS-SOL du
## morceau (`souterrain_morceau.gd`) — chargés près du joueur seulement.
## Le partagé (matériaux, textures, shaders, maillages des plants) est écrit UNE fois dans `partage/`.
## `monde.json` : les pistes et leurs distances, les morceaux, leurs boîtes, leurs comptes, l'empreinte de la source.

const WorldFile := preload("res://addons/marchingblocks_paint/mb_world_file.gd")
const Rule := preload("res://addons/marchingblocks_paint/mb_rule.gd")
const Tileset := preload("res://addons/marchingblocks_paint/mb_tileset.gd")
const Trans := preload("res://addons/marchingblocks_paint/mb_transitions.gd")
const Anim := preload("res://addons/marchingblocks_paint/mb_animation.gd")
const FoliageChunk := preload("res://world/feuillage_morceau.gd")
const CollisionChunk := preload("res://world/collision_morceau.gd")
const TransitionsData := preload("res://world/transitions_cuites.gd")
const UndergroundChunk := preload("res://world/souterrain_morceau.gd")
const CONFIG := "res://tools/cuisson/couches.json"
const FORMAT := "resolve-monde-cuit"
const VERSION := 2
const COLLISION_TRACK := "collision"

## ⚠ 16 et non 32 (MESURÉ, 9 octobre 2026, le Val, traversée en courant) : un morceau de 32 envoie ~15 Mo à la carte
## graphique d'un coup, et c'étaient les à-coups (23 à 25 images > 33 ms, pire 168 ms) ; en 16, avec au plus deux
## lectures à la fois (ChunkStreamer.max_loading) : AUCUNE image > 33 ms. 460 appels de dessin au lieu de 206.
var chunk := 16
## Une fenêtre = window × window morceaux posés d'un coup (0 : la valeur de couches.json).
var window := 0
var lod := true
var foliage_range := 80.0
## Positions, normales, UV sur 16 bits, dans la boîte de CHAQUE morceau. ⚠ MESURÉ sur le témoin : ~1 mm d'écart, des
## fentes possibles entre deux morceaux (deux boîtes, deux arrondis), et 26 → 25 Mo seulement : éteint par défaut.
var compress := false
## La collision des tuiles (couche physique 1).
var collision := true
## La collision se bâtit sur le LOD le plus simple dont l'ERREUR reste sous cette distance (en mètres ; 0 : le maillage
## plein). ⚠ MESURÉ (256², témoin) : la forme concave PLEINE d'un morceau coûte ~55 ms à construire au chargement, et
## elle bloque le fil principal même bâtie en fond — d'où une forme simplifiée. ⚠ MAIS PAS PAR UNE PART DE TRIANGLES :
## « au plus 25 % » a SUPPRIMÉ le sol d'une galerie de deux cases (vu sur le Val de Résolve, 8 octobre 2026 : le joueur
## passait au travers, le rendu, lui, avait son sol). L'erreur de chaque LOD est bornée, pas son nombre de triangles.
var collision_max_error := 0.05

var config := {}
var _deep := 2
var _roles: Array = []          # par couche : son rôle (Dictionary de couches.json)
var _default_role := "sol"
var _underground_role := ""     # le rôle dont les tuiles enfouies vont à part
var _arrays_cache := {}
var _mat_by_key := {}
var _mat_seen := {}
var _saved := {}
var _out := ""
var _report := {}
var _pending := {}              # Vector2i -> l'eau et le feuillage d'un morceau, en attendant son écriture
var _written := {}              # Vector2i -> l'entrée du manifeste
var _aabbs := {}
## LE CENTRE DE CHAQUE TUILE, porté par ses sommets (CUSTOM0) : les shaders de TRANSITIONS et d'ANIMATION du greffon le
## lisent dans la matrice de la tuile (`MODEL_MATRIX`), que la fusion efface ; leurs copies cuites le lisent là.
var _need_centre := false
var _patched := {}            # Shader du greffon -> sa copie cuite (qui lit CUSTOM0)
var _transitions: ShaderMaterial = null
var _transitions_data: Resource = null
## Les troncs des arbres, par morceau : Vector2i -> [[centre, rayon, hauteur], …] — des cylindres dans la collision.
var _trunks := {}
var _trunk_shapes := {}       # « rayon|hauteur » -> CylinderShape3D (partagés)


## Cuit `world_json` dans `out_dir` (res://…). `host` : un nœud DANS l'arbre (l'eau et le feuillage du greffon ont
## besoin de `_ready`). Rend le rapport (comptes, durées) ou {"error"}.
func cuire(host: Node, world_json: String, out_dir: String) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	_out = out_dir
	_report = {"tiles": 0, "triangles_in": 0, "materials_in": 0, "water_triangles": 0, "plants": 0, "windows": 0,
		"by_role": {}}
	config = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	_deep = int(config.get("profondeur_souterrain", 2))
	if window <= 0:
		window = int(config.get("fenetre_morceaux", 4))
	_default_role = str(config.get("defaut", "sol"))
	for r: Dictionary in config["roles"]:
		if r.get("souterrain", false):
			_underground_role = r["id"]

	var w := WorldFile.load_world(world_json)
	if w.has("error"):
		return w
	var base := world_json.get_base_dir()
	var t_read := Time.get_ticks_msec()

	# 1. Les couches : leur rôle, leurs tuiles (chargées par le greffon), leurs cases rangées par fenêtre.
	var layers: Array = w["layers"]
	var tilesets: Array = []
	var rule: Dictionary = {}
	for layer: Dictionary in layers:
		_roles.append(_role_of(str(layer["name"])))
		var ts := {}
		if layer["tileset"] != null:
			ts = Tileset.load_tileset(_resolve(base, str(layer["tileset"])))
			if ts.has("error"):
				return {"error": "couche %s : %s" % [layer["name"], ts["error"]]}
			if rule.is_empty():
				rule = ts["manifest"]
		tilesets.append(ts)
	if rule.is_empty():
		return {"error": "aucune couche n'a de tuiles"}
	# LES TRANSITIONS (l'atelier Transitions de MB) : le matériau du greffon, bâti comme son nœud le bâtit, posé en passe
	# suivante sur TOUS les matériaux des tuiles ; les shaders animés lisent eux aussi le centre de la tuile.
	_transitions = _transitions_material(w, layers, base)
	for ts: Dictionary in tilesets:
		if ts.is_empty():
			continue
		var lib: MeshLibrary = ts["library"]
		for id in lib.get_item_list():
			var mesh := lib.get_item_mesh(id)
			for si in mesh.get_surface_count():
				var m := mesh.surface_get_material(si)
				if m == null:
					continue
				_patch_material(m)
				if _transitions != null and m.next_pass == null:
					m.next_pass = _transitions
	var span := chunk * window
	var buckets := {}  # Vector2i fenêtre -> [ par couche : Array de Vector3i ]
	for li in layers.size():
		if not layers[li]["visible"]:
			continue  # une couche cachée quitte le monde (la règle, étape 7)
		for c: Array in layers[li]["cells"]:
			var x := int(c[0])
			var z := int(c[2])
			var cell := Vector3i(x, int(c[1]), z)
			# La case sert à sa fenêtre ET à celles dont elle borde la marge (une case de chaque côté).
			for wx in range(floori((x - 1) / float(span)), floori((x + 1) / float(span)) + 1):
				for wz in range(floori((z - 1) / float(span)), floori((z + 1) / float(span)) + 1):
					var wk := Vector2i(wx, wz)
					if not buckets.has(wk):
						var per_layer: Array = []
						for _i in layers.size():
							per_layer.append([])
						buckets[wk] = per_layer
					buckets[wk][li].append(cell)
	var cell_size := 1.0

	# 2. L'eau et le feuillage, une fois pour tout le monde (ils attendent l'écriture de leur morceau).
	var root := Node3D.new()
	root.name = "CuissonHorsEcran"
	host.add_child(root)
	_harvest_water(w, base, root, cell_size)
	_harvest_foliage(w, base, root, cell_size)
	var t_extras := Time.get_ticks_msec()

	for d in [COLLISION_TRACK, "partage"]:
		_clear_dir(_out.path_join(d))
	for r: Dictionary in config["roles"]:
		_clear_dir(_out.path_join(r["id"]))

	# 3. Fenêtre par fenêtre : la règle UNE fois pour toutes les couches, la récolte, l'écriture.
	var ms_rule := 0
	# ⚠ Une fenêtre qui n'a que des cases de MARGE se pose aussi : les sommets du bord du monde (devant la première
	# case, en x − 1) sont à elle — vu : sautée, le pourtour du monde perdait ses tuiles.
	for wk: Vector2i in buckets:
		var described: Array = []
		var union := {}
		for li in layers.size():
			var cells := {}
			for c: Vector3i in buckets[wk][li]:
				cells[c] = true
				union[c] = true
			var ts: Dictionary = tilesets[li]
			described.append({"cells": cells, "visible": layers[li]["visible"],
				"tiles": ts["manifest"].get("tiles", {}) if not ts.is_empty() else {},
				"variants": ts["manifest"].get("variants", {}) if not ts.is_empty() else {},
				"weights": layers[li].get("variant_weights", {}), "choices": _choices_of(layers[li])})
		_report["windows"] += 1
		var tr := Time.get_ticks_msec()
		var outs := Rule.placements_layered(described, rule)
		ms_rule += Time.get_ticks_msec() - tr
		var columns := _columns(union)
		var chunks := {}
		for li in layers.size():
			if tilesets[li].is_empty():
				continue
			_harvest_layer(outs[li], tilesets[li], _roles[li], union, columns, wk, span, cell_size, chunks)
		for key: Vector2i in chunks:
			_write_chunk(key, chunks[key], columns)
	# Les morceaux qui n'ont que de l'eau ou des plants (ou des troncs).
	for key: Vector2i in _pending.keys():
		_write_chunk(key, {}, {})
	for key: Vector2i in _trunks.keys():
		_write_chunk(key, {}, {})
	root.queue_free()

	var transitions_entry := {}
	if _transitions != null and _transitions_data != null:
		var data_file := "partage/transitions.res"
		ResourceSaver.save(_transitions_data, _out.path_join(data_file), ResourceSaver.FLAG_COMPRESS)
		_shared(_transitions)
		transitions_entry = {"data": data_file, "material": _transitions.resource_path.trim_prefix(_out + "/")}
	var tracks := {COLLISION_TRACK: {"distance": float(config.get("collision", {}).get("distance", 20))}}
	for r: Dictionary in config["roles"]:
		tracks[r["id"]] = {"distance": float(r.get("distance", 56))}
	if int(_report.get("tiles_missing", 0)) > 0:
		_add_warning("%d tuile(s) manquent au jeu de tuiles (des trous) : un contact diagonal, ou une clé absente" 			% _report["tiles_missing"])
	var list: Array = _written.values()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["key"] < b["key"])
	_report.merge({"chunks": list.size(), "materials_out": _mat_by_key.size(), "ms_read": t_read - t0,
		"ms_extras": t_extras - t_read, "ms_rule": ms_rule, "ms_total": Time.get_ticks_msec() - t0,
		"memory_peak_mb": OS.get_static_memory_peak_usage() / 1048576})
	var manifest := {"format": FORMAT, "version": VERSION, "source": world_json,
		"source_md5": FileAccess.get_md5(world_json), "source_mtime": FileAccess.get_modified_time(world_json), "chunk": chunk, "window": window, "cell_size": cell_size,
		"deep": _deep, "underground_role": _underground_role, "tracks": tracks, "transitions": transitions_entry,
		"play_bounds": _play_bounds(base),
		"chunks": list, "report": _report}
	var f := FileAccess.open(_out.path_join("monde.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "\t"))
	return _report


## Un chemin du monde : relatif à son dossier, ou déjà absolu.
static func _resolve(base: String, p: String) -> String:
	return p if p.is_absolute_path() else base.path_join(p).simplify_path()


## Les limites de la zone jouable, si le monde les donne (`resolve_limites.json`, écrit par le générateur du Val) :
## {"min": [x, z], "max": [x, z]} en mètres — le joueur n'en sort jamais. {} : aucune.
static func _play_bounds(base: String) -> Dictionary:
	# `mondes/<nom>.limites.json`, À CÔTÉ du dossier `.mbworld` (MB le réécrit à chaque export) ; l'ancienne place, dedans.
	var f := base.get_base_dir().path_join(base.get_file().get_basename() + ".limites.json")
	if not FileAccess.file_exists(f):
		f = base.path_join("resolve_limites.json")
	if not FileAccess.file_exists(f):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(f))
	return d if d is Dictionary else {}


func _role_of(layer_name: String) -> Dictionary:
	var n := layer_name.to_lower().replace(" ", "").replace("_", "").replace("-", "")
	for r: Dictionary in config["roles"]:
		for alias: String in r.get("noms", []):
			if n == alias.to_lower().replace(" ", "").replace("_", "").replace("-", ""):
				return r
	push_warning("Cuisson : la couche « %s » n'a pas de rôle dans couches.json — rôle « %s »" % [layer_name, _default_role])
	_add_warning("couche sans rôle : %s → %s" % [layer_name, _default_role])
	for r: Dictionary in config["roles"]:
		if r["id"] == _default_role:
			return r
	return config["roles"][0]


static func _choices_of(layer: Dictionary) -> Dictionary:
	var d := {}
	for c in layer.get("variant_choices", []):
		d[Vector3i(int(c[0]), int(c[1]), int(c[2]))] = int(c[3])
	return d


## Les colonnes d'une fenêtre : (x, z) -> les y pleins, triés (toutes les couches visibles ensemble).
static func _columns(union: Dictionary) -> Dictionary:
	var cols := {}
	for c: Vector3i in union:
		var k := Vector2i(c.x, c.z)
		if not cols.has(k):
			cols[k] = []
		cols[k].append(c.y)
	for k in cols:
		var a: Array = cols[k]
		a.sort()
		cols[k] = PackedInt32Array(a)
	return cols


## Combien de cases pleines au-dessus de (x, y, z) dans sa colonne.
static func _cover(columns: Dictionary, x: int, y: int, z: int) -> int:
	var ys: PackedInt32Array = columns.get(Vector2i(x, z), PackedInt32Array())
	return ys.size() - ys.bsearch(y, false)


# --- Récolte --------------------------------------------------------------------------------------------------

func _harvest_layer(placed: Array, ts: Dictionary, role: Dictionary, union: Dictionary, columns: Dictionary,
		wk: Vector2i, span: int, cell_size: float, chunks: Dictionary) -> void:
	var lib: MeshLibrary = ts["library"]
	var manifest: Dictionary = ts["manifest"]
	var meshes := {}
	for id in lib.get_item_list():
		meshes[lib.get_item_name(id)] = lib.get_item_mesh(id)
	var o: Array = manifest.get("piece_offset", [1, 1, 1])
	var offset := Vector3(float(o[0]), float(o[1]), float(o[2]))
	var corners: Array = []
	for c in manifest["corners"]:
		corners.append(Vector3i(int(c[0]), int(c[1]), int(c[2])))
	var split: bool = role.get("souterrain", false)
	var role_id: String = role["id"]
	for p: Array in placed:
		var v := Vector3i(p[0], p[1], p[2])
		if floori(v.x / float(span)) != wk.x or floori(v.z / float(span)) != wk.y:
			continue  # dans la marge : sa fenêtre le pose
		if p[3] == null or not meshes.has(p[3]):
			# Une tuile qui manque : le greffon montre un cube rouge, le jeu un TROU — compté, et dit.
			_report["tiles_missing"] = int(_report.get("tiles_missing", 0)) + 1
			continue
		var mesh: Mesh = meshes[p[3]]
		# La pose même du GridMap du greffon : item v à (v + piece_offset) × case, tourné de quarts autour de +Y.
		var xf := Transform3D(Basis(Vector3.UP, (int(p[4]) % 4) * PI / 2.0), (Vector3(v) + offset) * cell_size)
		var part := "Souterrain" if split and _buried(v, corners, union, columns) else "Surface"
		var key := Vector2i(floori(v.x / float(chunk)), floori(v.z / float(chunk)))
		_report["tiles"] += 1
		var by_role: Dictionary = _report["by_role"]
		by_role[role_id] = int(by_role.get(role_id, 0)) + 1
		for s in mesh.get_surface_count():
			if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arrays := _arrays_of(mesh, s)
			_group(_chunk(chunks, key), role_id, part, mesh.surface_get_material(s), arrays)["pieces"].append([arrays, xf])
			_report["triangles_in"] += _tri_count(arrays)


## Une tuile ENFOUIE : chacune de ses cases vides a au moins `_deep` cases pleines au-dessus d'elle.
func _buried(v: Vector3i, corners: Array, union: Dictionary, columns: Dictionary) -> bool:
	var empty := 0
	for c: Vector3i in corners:
		var e := v + c
		if union.has(e):
			continue
		empty += 1
		if _cover(columns, e.x, e.y, e.z) < _deep:
			return false
	return empty > 0


## L'eau : la nappe que MB a cuite (`water/*.glb`), montrée par le nœud du greffon, découpée par triangle.
func _harvest_water(w: Dictionary, base: String, root: Node3D, cell_size: float) -> void:
	for e in w.get("water", []):
		if not e["visible"]:
			continue
		if not e["mesh"] is String:
			_add_warning("la couche d'eau « %s » n'a pas de nappe cuite par MB : rien à montrer" % e["name"])
			continue
		var wn := Node3D.new()
		wn.set_script(WorldFile.WaterNode)
		wn.scale = Vector3.ONE * cell_size
		wn.look = str(e["look"])
		wn.sources = e["sources"]
		wn.auto_rebuild = false
		wn.mesh_path = _resolve(base, str(e["mesh"]))
		root.add_child(wn)
		var mi: MeshInstance3D = wn._sheet
		if mi == null or mi.mesh == null:
			_add_warning("la nappe « %s » ne se lit pas" % e["mesh"])
			continue
		var mesh := mi.mesh
		var xf := mi.global_transform
		for s in mesh.get_surface_count():
			var mat: Material = mi.material_override if mi.material_override else mi.get_active_material(s)
			var arrays := _arrays_of(mesh, s)
			var verts: PackedVector3Array = xf * (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array)
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else _sequence(verts.size())
			var per_chunk := {}
			for t in range(0, idx.size(), 3):
				var c := (verts[idx[t]] + verts[idx[t + 1]] + verts[idx[t + 2]]) / 3.0
				var key := Vector2i(floori(c.x / chunk), floori(c.z / chunk))
				if not per_chunk.has(key):
					per_chunk[key] = []
				per_chunk[key].append_array([idx[t], idx[t + 1], idx[t + 2]])
			for key: Vector2i in per_chunk:
				var sub := arrays.duplicate()
				sub[Mesh.ARRAY_INDEX] = PackedInt32Array(per_chunk[key])
				_group(_pending_of(key), _default_role, "Eau", mat, sub)["pieces"].append([sub, xf])
				_report["water_triangles"] += per_chunk[key].size() / 3


## ⚠ On ne relit PAS les MultiMesh du greffon : sans fenêtre (le rendu factice de --headless), elles ne gardent pas
## leurs instances — mesuré : 551 arbres rendus à l'origine. On refait les poses par la fonction même du greffon
## (`instances`), plant par plant, et le morceau les garde en DONNÉES (`world/feuillage_morceau.gd`).
func _harvest_foliage(w: Dictionary, base: String, root: Node3D, cell_size: float) -> void:
	var fo: Dictionary = w.get("foliage", {})
	if (fo.get("models", []) as Array).is_empty():
		return
	var fn := Node3D.new()
	fn.set_script(WorldFile.FoliageNode)
	fn.scale = Vector3.ONE * cell_size
	var ms: Array = []
	for m in fo["models"]:
		var d: Dictionary = (m as Dictionary).duplicate()
		if d["mesh"] is String:
			d["mesh"] = _resolve(base, str(d["mesh"]))
		ms.append(d)
	fn.models = ms
	var flat := PackedFloat32Array()
	for p in fo["plants"]:
		flat.append_array(PackedFloat32Array(p))
	fn.plants = flat
	root.add_child(fn)
	var by_model := {}
	for pl in fn.plant_list():
		if not by_model.has(pl["model"]):
			by_model[pl["model"]] = []
		by_model[pl["model"]].append(pl)
	var g: Transform3D = fn.global_transform
	for m in fn.models:
		var mine: Array = by_model.get(int(m["id"]), [])
		if mine.is_empty() or not m.get("mesh") is String:
			continue
		var d: Dictionary = fn.load_model(str(m["mesh"]))
		if d.has("error"):
			_add_warning("feuillage %s — %s" % [m["mesh"], d["error"]])
			continue
		_report["plants"] += mine.size()
		# LE TRONC de ce modèle (en unités du modèle) : il devient un cylindre de collision par plant.
		var trunk := _trunk_of(d["parts"])
		for pl in mine:
			var tf: Transform3D = g * WorldFile.Foliage.transform(m, pl)
			var sc := tf.basis.x.length()
			var ground: Vector3 = g * (pl["p"] as Vector3)
			var r: float = clampf(trunk.x * sc, 0.12, 0.9)
			var h: float = clampf(trunk.y * sc, 1.0, 4.0)
			var key := Vector2i(floori(ground.x / chunk), floori(ground.z / chunk))
			if not _trunks.has(key):
				_trunks[key] = []
			_trunks[key].append([ground + Vector3(0, h * 0.5, 0), r, h])
			_report["trunks"] = int(_report.get("trunks", 0)) + 1
		for part in d["parts"]:
			var inst: Array = fn.instances(m, mine, part[1])
			for i in mine.size():
				var t: Transform3D = g * (inst[0][i] as Transform3D)
				var key := Vector2i(floori(t.origin.x / chunk), floori(t.origin.z / chunk))
				var fol: Dictionary = _role_of_chunk(_pending_of(key), _default_role)["Feuillage"]
				var mesh: Mesh = part[3]
				if not fol.has(mesh):
					fol[mesh] = {"transforms": [], "custom": [], "model": int(m["id"])}
				fol[mesh]["transforms"].append(t)
				fol[mesh]["custom"].append(inst[1][i])


## Le tronc d'un modèle de plant : [rayon, hauteur] en unités du modèle — le rayon, le 75e centile de l'écart à l'axe des
## sommets du quart BAS du modèle (le tronc, pas la couronne) ; la hauteur, 40 % de celle du modèle.
static func _trunk_of(parts: Array) -> Vector2:
	var pts := PackedVector3Array()
	for part in parts:
		var mesh: Mesh = part[0]
		var pose: Transform3D = part[1]
		for s in mesh.get_surface_count():
			pts.append_array(pose * (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array))
	if pts.is_empty():
		return Vector2(0.3, 2.0)
	var lo := INF
	var hi := -INF
	for v in pts:
		lo = minf(lo, v.y)
		hi = maxf(hi, v.y)
	var cut := lo + (hi - lo) * 0.25
	var axis := Vector2.ZERO
	var n := 0
	for v in pts:
		if v.y <= cut:
			axis += Vector2(v.x, v.z)
			n += 1
	if n == 0:
		return Vector2(0.3, (hi - lo) * 0.4)
	axis /= n
	var ds: Array = []
	for v in pts:
		if v.y <= cut:
			ds.append(Vector2(v.x, v.z).distance_to(axis))
	ds.sort()
	return Vector2(float(ds[int(ds.size() * 0.75)]), (hi - lo) * 0.4)


# --- Fusion -----------------------------------------------------------------------------------------------------

## Un morceau en cours : rôle -> {"Surface", "Souterrain", "Eau": groupes ; "Feuillage": plants}.
static func _chunk(chunks: Dictionary, key: Vector2i) -> Dictionary:
	if not chunks.has(key):
		chunks[key] = {}
	return chunks[key]


func _pending_of(key: Vector2i) -> Dictionary:
	return _chunk(_pending, key)


static func _role_of_chunk(c: Dictionary, role: String) -> Dictionary:
	if not c.has(role):
		c[role] = {"Surface": {}, "Souterrain": {}, "Eau": {}, "Feuillage": {}}
	return c[role]


## Le groupe où vont les triangles d'un matériau ET d'un format de sommets (une surface fusionnée n'a qu'un format).
func _group(c: Dictionary, role: String, part: String, mat: Material, arrays: Array) -> Dictionary:
	if not _mat_seen.has(mat):
		_mat_seen[mat] = _mat_key(mat)  # la clé se calcule UNE fois par matériau, pas par tuile
		_report["materials_in"] += 1
		_warn_if_per_tile(mat)
	var mk: String = _mat_seen[mat]
	if not _mat_by_key.has(mk):
		_mat_by_key[mk] = mat
	var sig := mk + "|" + str([Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV,
		Mesh.ARRAY_TEX_UV2].map(func(a: int) -> bool: return arrays[a] != null))
	var groups: Dictionary = _role_of_chunk(c, role)[part]
	if not groups.has(sig):
		groups[sig] = {"mat": _mat_by_key[mk], "pieces": []}
	return groups[sig]


## Fusionne les morceaux d'un groupe ([arrays, pose] chacun) en UNE surface.
## ⚠ Tout se fait dans des variables LOCALES : un tableau compact (Packed*Array) rangé dans un Dictionary et
## allongé là est RECOPIÉ à chaque ajout (copie sur écriture) — mesuré : 31 s au lieu de quelques-unes.
static func _merge(pieces: Array, centre := false) -> Array:
	var first: Array = pieces[0][0]
	var centres := PackedFloat32Array()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var tans := PackedFloat32Array()
	var cols := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx_out := PackedInt32Array()
	for piece: Array in pieces:
		var arrays: Array = piece[0]
		var xf: Transform3D = piece[1]
		var rot := Transform3D(xf.basis.orthonormalized(), Vector3.ZERO)
		var src: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var base := verts.size()
		verts.append_array(xf * src)
		if centre:
			# Le centre de la tuile (sa pose), sur chacun de ses sommets.
			var at_c := centres.size()
			centres.resize(at_c + src.size() * 4)
			for i in src.size():
				centres[at_c + i * 4] = xf.origin.x
				centres[at_c + i * 4 + 1] = xf.origin.y
				centres[at_c + i * 4 + 2] = xf.origin.z
		if first[Mesh.ARRAY_NORMAL] != null:
			norms.append_array(rot * (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array))
		if first[Mesh.ARRAY_TANGENT] != null:
			var tan: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
			var start := tans.size()
			tans.resize(start + tan.size())
			for i in range(0, tan.size(), 4):
				var t := rot.basis * Vector3(tan[i], tan[i + 1], tan[i + 2])
				tans[start + i] = t.x
				tans[start + i + 1] = t.y
				tans[start + i + 2] = t.z
				tans[start + i + 3] = tan[i + 3]
		if first[Mesh.ARRAY_COLOR] != null:
			cols.append_array(arrays[Mesh.ARRAY_COLOR])
		if first[Mesh.ARRAY_TEX_UV] != null:
			uv.append_array(arrays[Mesh.ARRAY_TEX_UV])
		if first[Mesh.ARRAY_TEX_UV2] != null:
			uv2.append_array(arrays[Mesh.ARRAY_TEX_UV2])
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else _sequence(src.size())
		var at := idx_out.size()
		idx_out.resize(at + idx.size())
		# Un quart de tour garde l'orientation des faces ; un miroir (déterminant < 0) l'inverse.
		var flip := xf.basis.determinant() < 0.0
		for i in range(0, idx.size(), 3):
			idx_out[at + i] = idx[i] + base
			idx_out[at + i + 1] = (idx[i + 2] if flip else idx[i + 1]) + base
			idx_out[at + i + 2] = (idx[i + 1] if flip else idx[i + 2]) + base
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	if first[Mesh.ARRAY_NORMAL] != null:
		out[Mesh.ARRAY_NORMAL] = norms
	if first[Mesh.ARRAY_TANGENT] != null:
		out[Mesh.ARRAY_TANGENT] = tans
	if first[Mesh.ARRAY_COLOR] != null:
		out[Mesh.ARRAY_COLOR] = cols
	if first[Mesh.ARRAY_TEX_UV] != null:
		out[Mesh.ARRAY_TEX_UV] = uv
	if first[Mesh.ARRAY_TEX_UV2] != null:
		out[Mesh.ARRAY_TEX_UV2] = uv2
	if centre:
		out[Mesh.ARRAY_CUSTOM0] = centres
	out[Mesh.ARRAY_INDEX] = idx_out
	return out


## Les sommets IDENTIQUES (position, normale, UV, couleur…) n'en font plus qu'un — en C++ (`SurfaceTool.index`).
## Mesuré sur le témoin : chaque triangle avait ses trois sommets à lui (sommets = indices).
static func _weld(arrays: Array) -> Array:
	var st := SurfaceTool.new()
	st.create_from_arrays(arrays)
	st.index()
	return st.commit_to_arrays()


func _arrays_of(mesh: Mesh, s: int) -> Array:
	var k := "%d:%d" % [mesh.get_instance_id(), s]
	if not _arrays_cache.has(k):
		_arrays_cache[k] = mesh.surface_get_arrays(s)
	return _arrays_cache[k]


## Un shader qui lirait ENCORE l'origine de la tuile dans sa matrice après `_patch_material` (une forme que la copie
## cuite ne sait pas réécrire) : fusionnées, les tuiles n'ont plus que l'origine du morceau — la cuisson le DIT.
func _warn_if_per_tile(mat: Material) -> void:
	var m := mat
	while m != null:
		if m is ShaderMaterial and (m as ShaderMaterial).shader != null \
				and ((m as ShaderMaterial).shader.code.contains("MODEL_MATRIX)[3]")
				or (m as ShaderMaterial).shader.code.contains("MODEL_MATRIX) * vec4(0.0, 0.0, 0.0, 1.0)")):
			_add_warning("matériau animé ou transition : la phase / le centre PAR TUILE est perdu à la fusion (%s)"
				% (mat.resource_name if mat.resource_name != "" else mat.get_class()))
			return
		m = m.next_pass


## Le matériau des TRANSITIONS, comme `MarchingBlocksTransitions.refresh()` le bâtit (la table des paires, la texture
## 3D des cases du monde entier, les représentants) — son shader lisant le centre de la tuile dans CUSTOM0. null : aucune
## paire active.
func _transitions_material(w: Dictionary, layers: Array, base: String) -> ShaderMaterial:
	var tr: Dictionary = w.get("transitions", {})
	var table: Dictionary = Trans.table(tr.get("pairs", []), layers.size())
	if table.is_empty():
		return null
	var mat: ShaderMaterial = Trans.new_material()
	_patch_material(mat)
	var union := {}
	for li in layers.size():
		if not layers[li]["visible"]:
			continue
		for c: Array in layers[li]["cells"]:
			var k := Vector3i(int(c[0]), int(c[1]), int(c[2]))
			if not union.has(k):
				union[k] = li
	var chosen := {}
	for c in tr.get("choices", []):
		chosen[Vector3i(int(c[0]), int(c[1]), int(c[2]))] = int(c[3])
	var cells: Dictionary = Trans.cell_texture(union, chosen)
	Trans.set_table(mat, table)
	var reps: Array = []
	for r in tr.get("representatives", []):
		var d: Dictionary = (r as Dictionary).duplicate()
		d["image"] = Anim._image(_resolve(base, str(r["image"]))) if r.get("image") is String else null
		reps.append(d)
	Trans.set_representatives(mat, reps)
	# ⚠ LES TEXTURES PARTENT EN DONNÉES (`world/transitions_cuites.gd`) : sans fenêtre, une texture faite à la volée
	# s'enregistre VIDE. Le matériau garde ses réglages ; le ChunkStreamer lui rend ses textures au chargement.
	var data: Resource = TransitionsData.new()
	data.cells = cells["bytes"]
	data.origin = cells["origin"]
	data.size = cells["size"]
	var images: Array[Image] = []
	for k in Trans.LAYERS_MAX:
		var rd: Dictionary = reps[k] if k < reps.size() else {}
		var img: Image = null
		if rd.get("image") is Image:
			img = (rd["image"] as Image).duplicate()
			if img.is_compressed():
				img.decompress()
			img.clear_mipmaps()
			img.convert(Image.FORMAT_RGBA8)
			img.resize(256, 256, Image.INTERPOLATE_BILINEAR)
		else:
			img = Image.create_empty(256, 256, false, Image.FORMAT_RGBA8)
			img.fill(Color.WHITE)
		img.generate_mipmaps()
		images.append(img)
	data.images = images
	var colors := PackedColorArray()
	for k in Trans.LAYERS_MAX:
		var c: Array = (reps[k] as Dictionary).get("color", [1.0, 1.0, 1.0, 1.0]) if k < reps.size() else [1.0, 1.0, 1.0, 1.0]
		colors.append(Color(c[0], c[1], c[2], c[3]))
	data.colors = colors
	# La table des paires, comme `Trans.set_table` la bâtit (une texture faite à la volée : elle aussi part en données).
	var timg := Image.create_empty(2 * Trans.LAYERS_MAX, Trans.LAYERS_MAX, false, Image.FORMAT_RGBAF)
	for key in table:
		var cd: PackedStringArray = String(key).split("|")
		var rg: Dictionary = table[key]
		timg.set_pixel(2 * int(cd[1]), int(cd[0]), Color(1.0, rg["softness"], rg["reach"], rg["irregularity"]))
		timg.set_pixel(2 * int(cd[1]) + 1, int(cd[0]), Color(rg["fills_hollows"], rg["grain"], 0.0, 0.0))
	data.table = timg
	_transitions_data = data
	mat.set_shader_parameter("cases", null)
	mat.set_shader_parameter("representants", null)
	mat.set_shader_parameter("table", null)
	_report["transitions"] = {"pairs": table.size(), "cells_texture": str(cells["size"])}
	return mat


## La copie cuite d'un matériau (et de ses passes suivantes) dont le shader lit l'origine de la tuile dans sa matrice :
## elle la lit dans CUSTOM0, que `_merge` pose sur chaque sommet. Les deux formes du greffon : le centre des transitions,
## la phase de l'animation.
func _patch_material(m: Material) -> void:
	while m != null:
		if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
			var sh: Shader = (m as ShaderMaterial).shader
			if not _patched.has(sh):
				var code := sh.code
				var cuit := code.replace("(mb_world_to_format * MODEL_MATRIX)[3].xyz",
					"(mb_world_to_format * vec4(CUSTOM0.xyz, 1.0)).xyz").replace(
					"((mb_world_to_format * MODEL_MATRIX) * vec4(0.0, 0.0, 0.0, 1.0)).xyz",
					"(mb_world_to_format * vec4(CUSTOM0.xyz, 1.0)).xyz")
				if cuit == code:
					_patched[sh] = sh
				else:
					var s2 := Shader.new()
					s2.code = cuit
					_patched[sh] = s2
					_patched[s2] = s2
					_need_centre = true
			(m as ShaderMaterial).shader = _patched[sh]
		m = m.next_pass


func _add_warning(why: String) -> void:
	if not _report.has("warnings"):
		_report["warnings"] = []
	if not why in _report["warnings"]:
		_report["warnings"].append(why)
		push_warning("Cuisson : " + why)


## Deux matériaux aux mêmes réglages et aux mêmes images n'en font qu'un (leur nom ne compte pas).
static func _mat_key(m: Material) -> String:
	if m == null:
		return "null"
	var parts: Array = [m.get_class()]
	for p in m.get_property_list():
		if not (p["usage"] & PROPERTY_USAGE_STORAGE) or str(p["name"]).begins_with("resource_"):
			continue
		var v: Variant = m.get(p["name"])
		if v is Material:
			parts.append("%s=%s" % [p["name"], _mat_key(v)])
		elif v is Object:
			parts.append("%s=#%d" % [p["name"], (v as Object).get_instance_id()])
		else:
			parts.append("%s=%s" % [p["name"], str(v)])
	return str(parts).md5_text()


# --- Écriture ---------------------------------------------------------------------------------------------------

## Écrit un morceau : une scène par rôle, la collision et le sous-sol. `columns` : celles de la fenêtre ({} si le
## morceau n'a que de l'eau ou des plants).
func _write_chunk(key: Vector2i, c: Dictionary, columns: Dictionary) -> void:
	# L'eau et le feuillage du morceau le rejoignent ici.
	if _pending.has(key):
		var p: Dictionary = _pending[key]
		for role: String in p:
			var dst := _role_of_chunk(c, role)
			for part in ["Eau", "Feuillage"]:
				dst[part].merge(p[role][part])
		_pending.erase(key)
	var entry: Dictionary = _written.get(key, {"key": [key.x, key.y], "files": {}, "aabb": {}, "triangles": {},
		"plants": 0, "has_underground": false, "has_water": false})
	var shapes: Array = []
	for role: String in c:
		var g: Dictionary = c[role]
		var root := Node3D.new()
		root.name = "%s_%d_%d" % [role, key.x, key.y]
		var tris := 0
		var aabb := AABB()
		var first := true
		for part in ["Surface", "Souterrain", "Eau"]:
			if (g[part] as Dictionary).is_empty():
				continue
			var im := ImporterMesh.new()
			for sig in g[part]:
				var grp: Dictionary = g[part][sig]
				var centre: bool = _need_centre and part != "Eau"
				# Le centre des tuiles va avec elles ; `SurfaceTool.index` ne le garderait pas : pas de soudure alors.
				var arrays := _merge(grp["pieces"], true) if centre else _weld(_merge(grp["pieces"]))
				var flags := Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES if compress else 0
				if centre:
					flags |= Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
				im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, _shared(grp["mat"]), "", flags)
				tris += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			if (lod or collision_max_error > 0.0) and part != "Eau":
				im.generate_lods(25.0, 60.0, [])
			if part != "Eau" and collision:
				shapes.append(_collision_of(im))
			var mi := MeshInstance3D.new()
			mi.name = part
			mi.mesh = im.get_mesh()
			if part == "Eau":
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				entry["has_water"] = true
			if part == "Souterrain":
				mi.visible = false  # le ChunkStreamer le montre sous terre
				entry["has_underground"] = true
			root.add_child(mi)
			mi.owner = root
			aabb = mi.mesh.get_aabb() if first else aabb.merge(mi.mesh.get_aabb())
			first = false
		if not (g["Feuillage"] as Dictionary).is_empty():
			var fol := Node3D.new()
			fol.name = "Feuillage"
			fol.set_script(FoliageChunk)
			fol.view_distance = foliage_range
			var parts: Array = []
			var by_model := {}
			for mesh: Mesh in g["Feuillage"]:
				var d: Dictionary = g["Feuillage"][mesh]
				var buf := PackedFloat32Array()
				for i in d["transforms"].size():
					var t: Transform3D = d["transforms"][i]
					var cc: Color = d["custom"][i]
					buf.append_array([t.basis.x.x, t.basis.y.x, t.basis.z.x, t.origin.x,
						t.basis.x.y, t.basis.y.y, t.basis.z.y, t.origin.y,
						t.basis.x.z, t.basis.y.z, t.basis.z.z, t.origin.z, cc.r, cc.g, cc.b, cc.a])
					var box := AABB(t.origin, Vector3.ZERO)
					aabb = box if first else aabb.merge(box)
					first = false
				parts.append({"mesh": _shared(mesh), "buffer": buf})
				by_model[d["model"]] = d["transforms"].size()  # un plant a plusieurs parties : compté une fois
			fol.parts = parts
			root.add_child(fol)
			fol.owner = root
			for m in by_model:
				entry["plants"] += int(by_model[m])
		if root.get_child_count() == 0:
			root.free()
			continue
		var file := "%s/m_%d_%d.scn" % [role, key.x, key.y]
		_save_scene(root, file)
		entry["files"][role] = file
		entry["triangles"][role] = tris
		entry["aabb"][role] = [aabb.position.x, aabb.position.y, aabb.position.z, aabb.size.x, aabb.size.y, aabb.size.z]
	# LA COLLISION ET LE SOUS-SOL, À PART : le jeu ne les charge qu'autour du joueur.
	var runs := _underground_runs(key, columns)
	var trunks: Array = _trunks.get(key, [])
	_trunks.erase(key)
	if not shapes.is_empty() or not runs.is_empty() or not trunks.is_empty():
		var body := StaticBody3D.new()
		body.name = "Collision_%d_%d" % [key.x, key.y]
		body.collision_layer = 1
		body.collision_mask = 0
		# LES TRIANGLES EN DONNÉES (`world/collision_morceau.gd`) : le jeu en fait des formes sur le fil principal, à
		# petites doses — une forme concave lue dans un fil coûtait jusqu'à 45 ms à l'entrée du morceau.
		if not shapes.is_empty():
			var all := PackedVector3Array()
			for f: PackedVector3Array in shapes:
				all.append_array(f)
			var formes := Node.new()
			formes.name = "Formes"
			formes.set_script(CollisionChunk)
			var pieces: Array[PackedVector3Array] = []
			var step: int = CollisionChunk.PIECE * 3
			for i in range(0, all.size(), step):
				pieces.append(all.slice(i, mini(i + step, all.size())))
			formes.pieces = pieces
			body.add_child(formes)
			formes.owner = body
		# Les troncs : un cylindre par arbre (les formes de même taille partagées), sur la couche physique 5 (16) — le
		# joueur les heurte (son masque la prend), la caméra ne bute pas dessus (elle ne lit que la couche 1).
		var trunk_body: StaticBody3D = null
		if not trunks.is_empty():
			trunk_body = StaticBody3D.new()
			trunk_body.name = "Troncs"
			trunk_body.collision_layer = 16
			trunk_body.collision_mask = 0
			body.add_child(trunk_body)
			trunk_body.owner = body
		for t: Array in trunks:
			var sk := "%.2f|%.1f" % [t[1], t[2]]
			if not _trunk_shapes.has(sk):
				var cyl := CylinderShape3D.new()
				cyl.radius = snappedf(t[1], 0.01)
				cyl.height = snappedf(t[2], 0.1)
				_trunk_shapes[sk] = cyl
			var tc := CollisionShape3D.new()
			tc.shape = _trunk_shapes[sk]
			tc.position = t[0]
			trunk_body.add_child(tc)
			tc.owner = body
		if not runs.is_empty():
			var under := Node.new()
			under.name = "SousSol"
			under.set_script(UndergroundChunk)
			under.runs = runs
			body.add_child(under)
			under.owner = body
		var col_file := "%s/c_%d_%d.scn" % [COLLISION_TRACK, key.x, key.y]
		_save_scene(body, col_file)
		entry["files"][COLLISION_TRACK] = col_file
		entry["aabb"][COLLISION_TRACK] = [key.x * chunk, -1e6, key.y * chunk, chunk, 2e6, chunk]
		_report["underground_runs"] = int(_report.get("underground_runs", 0)) + runs.size() / 4
	if not entry["files"].is_empty():
		_written[key] = entry


## Les tronçons d'air ENFOUI des colonnes d'un morceau : entre deux cases pleines, l'air dont la colonne porte au
## moins `_deep` cases pleines au-dessus.
func _underground_runs(key: Vector2i, columns: Dictionary) -> PackedInt32Array:
	var runs := PackedInt32Array()
	for x in range(key.x * chunk, (key.x + 1) * chunk):
		for z in range(key.y * chunk, (key.y + 1) * chunk):
			var ys: PackedInt32Array = columns.get(Vector2i(x, z), PackedInt32Array())
			for i in ys.size() - 1:
				if ys[i + 1] - ys[i] > 1 and ys.size() - (i + 1) >= _deep:
					runs.append_array([x, z, ys[i] + 1, ys[i + 1] - 1])
	return runs


func _save_scene(root: Node, file: String) -> void:
	var packed := PackedScene.new()
	packed.pack(root)
	if ResourceSaver.save(packed, _out.path_join(file), ResourceSaver.FLAG_COMPRESS) != OK:
		push_error("Cuisson : impossible d'écrire %s" % file)
	root.free()


## La forme de collision d'une partie : ses triangles, pris au LOD le plus simple dont l'erreur reste sous
## `collision_max_error` (les LOD vont du plus fin au plus simple ; leur « taille » est leur erreur, en mètres).
## LA COLLISION D'UN MORCEAU, SOUDÉE PUIS SIMPLIFIÉE (9 octobre 2026). Le maillage de rendu ne se soude pas (chaque
## sommet porte le centre de SA tuile, CUSTOM0) : simplifié tel quel, il ne fondait jamais deux tuiles voisines — une
## dalle plate de 16 × 16 cases gardait jusqu'à 15 000 triangles de collision (27 M pour le Val), et Godot bâtit la
## structure d'une forme concave quand elle ENTRE dans l'espace physique, sur le fil principal : jusqu'à 10 ms par
## morceau, 35 ms sous charge — les à-coups de la traversée. Ici, les POSITIONS seules, arrondies au 1/10 de mm et
## soudées (les tuiles voisines partagent leurs sommets), puis le LOD le plus simple dont l'erreur reste sous
## `collision_max_error` (5 cm) : la sonde de collision le vérifie, rayon par rayon.
func _collision_of(im: ImporterMesh) -> PackedVector3Array:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_in := 0
	for s in im.get_surface_count():
		var arrays := im.get_surface_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for i in idx.size():
			st.add_vertex(verts[idx[i]].snapped(Vector3.ONE * 0.0001))
		n_in += idx.size() / 3
	var faces := PackedVector3Array()
	if n_in > 0:
		st.index()
		st.generate_normals()
		var welded := ImporterMesh.new()
		welded.add_surface(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
		welded.generate_lods(25.0, 60.0, [])
		var wa := welded.get_surface_arrays(0)
		var verts: PackedVector3Array = wa[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = wa[Mesh.ARRAY_INDEX]
		for l in welded.get_surface_lod_count(0):
			if welded.get_surface_lod_size(0, l) > collision_max_error:
				break
			idx = welded.get_surface_lod_indices(0, l)
		faces.resize(idx.size())
		for i in idx.size():
			faces[i] = verts[idx[i]]
	_report["collision_triangles"] = _report.get("collision_triangles", 0) + faces.size() / 3
	_report["collision_triangles_before_weld"] = _report.get("collision_triangles_before_weld", 0) + n_in
	return faces


## Écrit UNE fois dans `partage/` une ressource que plusieurs morceaux utilisent (et ce qu'elle porte : textures,
## shader, passe suivante), pour que les morceaux y renvoient. Une ressource qui a déjà son fichier reste où elle est.
func _shared(res: Resource) -> Resource:
	if res == null or _saved.has(res):
		return res
	_saved[res] = true
	if res is Material or res is Mesh:
		for p in res.get_property_list():
			if p["usage"] & PROPERTY_USAGE_STORAGE and not str(p["name"]).begins_with("resource_"):
				var v: Variant = res.get(p["name"])
				if v is Resource:
					_shared(v)
	if res is Mesh:
		for s in (res as Mesh).get_surface_count():
			_shared((res as Mesh).surface_get_material(s))
	var path := res.resource_path
	if path != "" and not path.contains("::"):
		return res
	var file := _out.path_join("partage/%s_%d.res" % [res.get_class().to_lower(), _saved.size()])
	if ResourceSaver.save(res, file, ResourceSaver.FLAG_COMPRESS) == OK:
		res.take_over_path(file)
	return res


static func _clear_dir(d: String) -> void:
	DirAccess.make_dir_recursive_absolute(d)
	for f in DirAccess.get_files_at(d):
		DirAccess.remove_absolute(d.path_join(f))


static func _tri_count(arrays: Array) -> int:
	return (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 if arrays[Mesh.ARRAY_INDEX] != null \
		else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3


static func _sequence(n: int) -> PackedInt32Array:
	var a := PackedInt32Array()
	a.resize(n)
	for i in n:
		a[i] = i
	return a

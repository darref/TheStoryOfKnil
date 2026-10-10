extends Node
## LES ÉPREUVES DE LA CUISSON ET DU CHARGEMENT EN MORCEAUX — headless, sur le monde d'essai
## (`fabriquer_monde_essai.tscn` puis `--import` d'abord) :
##   Godot --headless --path D:/TheStoryOfKnil res://tests/test_cuisson.tscn
## Sort avec 0 si tout est vert.

const Cuisson := preload("res://tools/cuisson/cuisson.gd")
const WorldFile := preload("res://addons/marchingblocks_paint/mb_world_file.gd")
const WORLD := "res://mondes/essai.mbworld/world.json"
const OUT := "res://cuit/essai"
## Le rôle de chaque couche du monde d'essai (couches.json).
const ROLES := {"GrosObstacles": "gros", "Obstacles": "obstacles", "Sol": "sol"}
## Des points d'essai (pieds du joueur) : dans une galerie, sous l'arche, sur la place.
const IN_GALLERY := Vector3(16.5, -4.25, 40.5)
const UNDER_ARCH := Vector3(-8.5, 0.75, -2.5)
const ON_PLAZA := Vector3(0.5, 0.75, 0.5)

var _fails := 0
var _checks := 0
var _last_rep := {}


func check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		printerr("ÉCHEC : " + what)


func _ready() -> void:
	await get_tree().process_frame
	var c := Cuisson.new()
	c.window = 1  # une fenêtre par morceau : beaucoup de bords de fenêtres, tous éprouvés
	var rep := c.cuire(self, WORLD, OUT)
	_last_rep = rep
	print("RAPPORT : ", JSON.stringify(rep))
	check(not rep.has("error"), "la cuisson aboutit")
	if rep.has("error"):
		return _end()
	check(int(rep["windows"]) > 4, "plusieurs fenêtres (%d)" % rep["windows"])
	await get_tree().process_frame
	_check_baked(rep)
	_check_against_plugin()
	await _check_streamer()
	_end()


func _end() -> void:
	print("ÉPREUVES CUISSON : %d vérifications, %d échecs" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _manifest() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(OUT.path_join("monde.json")))


func _check_baked(rep: Dictionary) -> void:
	var manifest := _manifest()
	check(manifest["format"] == Cuisson.FORMAT and int(manifest["version"]) == Cuisson.VERSION, "monde.json écrit (v2)")
	check(manifest["source_md5"] == FileAccess.get_md5(WORLD), "l'empreinte de la source")
	for t in ["sol", "obstacles", "gros", "batiments", "collision"]:
		check(manifest["tracks"].has(t), "la piste %s existe" % t)
	check(float(manifest["tracks"]["gros"]["distance"]) > float(manifest["tracks"]["sol"]["distance"]),
		"les gros obstacles se voient de plus loin que le sol")
	check(int(rep["materials_out"]) <= int(rep["materials_in"]), "les matériaux identiques fusionnés")
	check(int(rep["water_triangles"]) > 0, "le lac a sa nappe")
	var other_warnings: Array = (rep.get("warnings", []) as Array).filter(func(w: String) -> bool:
		return not w.contains("manquent au jeu de tuiles"))
	check(other_warnings.is_empty(), "aucun autre avertissement (%s)" % str(other_warnings))
	var plants := 0
	var underground := 0
	var water := 0
	var lods := 0
	var refs_plugin := 0
	var with_plants := 0
	var by_track := {}
	var plant_sum := Vector2.ZERO  # Σ (x, z) des poses d'UNE partie (le tronc : ses parties sont l'une sur l'autre)
	for e: Dictionary in manifest["chunks"]:
		plants += int(e["plants"])
		underground += 1 if e["has_underground"] else 0
		water += 1 if e["has_water"] else 0
		for t: String in e["files"]:
			by_track[t] = int(by_track.get(t, 0)) + 1
			var path := OUT.path_join(e["files"][t])
			for d in ResourceLoader.get_dependencies(path):
				if d.contains("addons/"):
					refs_plugin += 1
			if t == "collision":
				continue
			var n: Node = (load(path) as PackedScene).instantiate()
			check(not n.has_node("Surface") or e["files"].has("collision"), "%s a sa collision" % path)
			var s := n.get_node_or_null("Surface") as MeshInstance3D
			if s and s.mesh.get_surface_count() > 0 \
					and not (RenderingServer.mesh_get_surface(s.mesh.get_rid(), 0).get("lods", []) as Array).is_empty():
				lods += 1
			var under := n.get_node_or_null("Souterrain") as MeshInstance3D
			if under:
				check(t == "sol" and not under.visible, "%s : le souterrain est au sol, caché par défaut" % path)
			var fol := n.get_node_or_null("Feuillage")
			if fol:
				with_plants += 1
				var buf: PackedFloat32Array = fol.parts[0]["buffer"]
				for i in range(0, buf.size(), 16):
					plant_sum += Vector2(buf[i + 3], buf[i + 11])
			n.free()
	print("PISTES : ", by_track)
	for t in ["sol", "obstacles", "gros", "collision"]:
		check(int(by_track.get(t, 0)) > 0, "des morceaux pour la piste %s" % t)
	check(int(by_track.get("gros", 0)) < int(by_track.get("sol", 0)), "le volcan ne couvre que quelques morceaux")
	check(plants == int(rep["plants"]), "chaque arbre dans un morceau, une fois (%d / %d)" % [plants, rep["plants"]])
	var want_sum := Vector2.ZERO
	var flat: Array = JSON.parse_string(FileAccess.get_file_as_string(WORLD))["foliage"]["plants"]
	for k in range(0, flat.size(), 7):
		want_sum += Vector2(flat[k + 1], flat[k + 3])
	check(with_plants > 1, "les arbres répartis sur plusieurs morceaux (%d)" % with_plants)
	check(plant_sum.distance_to(want_sum) < 0.01 * want_sum.length() + 1.0,
		"chaque arbre à sa place (Σ x, z : %s / %s)" % [str(plant_sum), str(want_sum)])
	check(underground > 0, "les galeries donnent des tuiles souterraines (%d morceaux)" % underground)
	_check_transitions(rep, manifest)
	check(water > 0, "un morceau porte l'eau")
	check(lods > 0, "les surfaces ont des LOD")
	check(refs_plugin == 0, "aucun morceau ne dépend du greffon (%d renvois)" % refs_plugin)


## LA FIDÉLITÉ : le monde ENTIER bâti par le greffon (WorldFile.build : ses GridMap), couche par couche, contre les
## morceaux cuits PAR FENÊTRES, rôle par rôle — l'empreinte des triangles (Σ aire × centre, Σ aire).
func _check_against_plugin() -> void:
	var root := Node3D.new()
	add_child(root)
	var built := WorldFile.build(WORLD, root)
	var mesh_print := {}
	var want := {}
	# Les cubes rouges du greffon (des tuiles manquantes : contacts diagonaux du monde d'essai) = les trous comptés
	# par la cuisson, ni plus ni moins.
	var red := 0
	for node in built["nodes"]:
		red += (node.get_node("Errors") as GridMap).get_used_cells().size()
	check(red == int(_last_rep.get("tiles_missing", 0)), "les trous comptés = les cubes rouges du greffon (%d / %d)"
		% [_last_rep.get("tiles_missing", 0), red])
	for node in built["nodes"]:
		var role: String = ROLES[str(node.name)]
		var tiles := node.get_node("Tiles") as GridMap
		var lib := tiles.mesh_library
		var acc := Vector4.ZERO
		for v: Vector3i in tiles.get_used_cells():
			var mesh := lib.get_item_mesh(tiles.get_cell_item(v))
			if not mesh_print.has(mesh):
				mesh_print[mesh] = _print_of_mesh(mesh)
			var p: Vector4 = mesh_print[mesh]
			var xf := tiles.global_transform * Transform3D(tiles.get_cell_item_basis(v), tiles.map_to_local(v))
			var c := xf.basis * Vector3(p.x, p.y, p.z) + xf.origin * p.w
			acc += Vector4(c.x, c.y, c.z, p.w)
		want[role] = acc
	root.free()
	var got := {}
	for e: Dictionary in _manifest()["chunks"]:
		for t: String in e["files"]:
			if t == "collision":
				continue
			var n: Node = (load(OUT.path_join(e["files"][t])) as PackedScene).instantiate()
			for part in ["Surface", "Souterrain"]:
				var mi := n.get_node_or_null(part) as MeshInstance3D
				if mi:
					got[t] = got.get(t, Vector4.ZERO) + _print_of_mesh(mi.mesh)
			n.free()
	for role: String in want:
		var a: Vector4 = want[role]
		var b: Vector4 = got.get(role, Vector4.ZERO)
		var err := (a - b).abs()
		check(err.w < 1e-3 * a.w and Vector3(err.x, err.y, err.z).length() < 1e-4 * a.w * 128.0,
			"%s : même géométrie que le greffon (aire %.1f / %.1f, centre %s / %s)" % [role, b.w, a.w,
			str(Vector3(b.x, b.y, b.z) / maxf(b.w, 1e-9)), str(Vector3(a.x, a.y, a.z) / a.w)])


static func _print_of_mesh(mesh: Mesh) -> Vector4:
	var out := Vector4.ZERO
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(v.size()))
		for i in range(0, idx.size(), 3):
			var p0 := v[idx[i]]
			var p1 := v[idx[i + 1]]
			var p2 := v[idx[i + 2]]
			var area := (p1 - p0).cross(p2 - p0).length() * 0.5
			var c := (p0 + p1 + p2) / 3.0 * area
			out += Vector4(c.x, c.y, c.z, area)
	return out


func _check_streamer() -> void:
	var target := Node3D.new()
	target.position = ON_PLAZA
	add_child(target)
	var s := ChunkStreamer.new()
	s.baked_dir = OUT
	s.target = target
	s.distances = {"sol": 30.0, "obstacles": 30.0, "collision": 10.0}
	s.unload_margin = 10.0
	add_child(s)
	var total_sol: int = s._tracks["sol"].size()
	var first := s.loaded_count("sol")
	check(first > 0 and first < total_sol, "au départ, seulement les morceaux de sol proches (%d / %d)" % [first, total_sol])
	check(s.loaded_count("collision") > 0 and s.loaded_count("collision") < first,
		"la collision, seulement tout près (%d / %d montrés)" % [s.loaded_count("collision"), first])
	check(s.loaded_count("gros") > 0, "le volcan, lointain, est déjà là (sa piste voit à 400)")
	check(s.loaded_count("obstacles") > 0, "les massifs de la place sont là")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var q := PhysicsRayQueryParameters3D.create(Vector3(0.5, 30, 0.5), Vector3(0.5, -30, 0.5), 1)
	var hit := get_viewport().world_3d.direct_space_state.intersect_ray(q)
	check(not hit.is_empty() and absf(hit["position"].y - 0.75) < 0.3,
		"la place se marche (sol à y = %s)" % str(hit.get("position", Vector3.INF).y))
	# SOUS TERRE : la place non, l'arche non (une case de couvert), la galerie oui.
	Interior.set_underground(false)
	check(not s.is_underground_at(ON_PLAZA), "sur la place : à l'air")
	check(not s.is_underground_at(UNDER_ARCH), "sous l'arche : à l'air (une seule case au-dessus)")
	target.position = IN_GALLERY
	await _wait(0.6)
	check(s.is_underground_at(IN_GALLERY), "dans la galerie : sous terre")
	check(Interior.is_underground() and GameState.get_value("place.interior_type") == "souterrain",
		"sous terre : l'intérieur « souterrain » est dit")
	var ck := float(s._chunk)
	var key := Vector2i(floori(IN_GALLERY.x / ck), floori(IN_GALLERY.z / ck))
	var node: Node = s._tracks["sol"][key]["node"]
	check(node != null and node.get_node("Souterrain").visible, "sous terre : les tuiles souterraines se montrent")
	var q2 := PhysicsRayQueryParameters3D.create(IN_GALLERY + Vector3.UP * 0.5, IN_GALLERY + Vector3.DOWN * 3, 1)
	var hit2 := get_viewport().world_3d.direct_space_state.intersect_ray(q2)
	check(not hit2.is_empty() and absf(hit2["position"].y - IN_GALLERY.y) < 0.4,
		"le sol de la galerie se marche (y = %s)" % str(hit2.get("position", Vector3.INF).y))
	target.position = ON_PLAZA + Vector3(3, 0, 3)
	await _wait(0.6)
	check(not Interior.is_underground(), "remonté : à l'air")
	check(node == null or not node.get_node("Souterrain").visible, "à l'air : les tuiles souterraines se cachent")
	# Un saut à l'autre bout, puis une marche lente : le chargement suit.
	target.position = Vector3(55, 0, 55)
	for i in 120:
		await get_tree().process_frame
	var here := Vector2i(floori(55.0 / ck), floori(55.0 / ck))
	check(s.state_of(here) == "on" and s.state_of(here, "collision") == "on", "le morceau d'arrivée est chargé, collision comprise")
	check(s.state_of(Vector2i(-1, -1)) == "off" and s.state_of(Vector2i(-1, -1), "collision") == "off", "le morceau du départ est déchargé")
	target.position = Vector3(55, 0, 20)
	for i in 120:
		await get_tree().process_frame
	var walked := Vector2i(floori(55.0 / ck), floori(20.0 / ck))
	check(s.state_of(walked) == "on" and s.state_of(walked, "collision") == "on", "en marchant, le sol et la collision suivent")
	s.queue_free()
	target.queue_free()


## Attendre en TEMPS, pas en images : sans fenêtre, 30 images peuvent durer moins que le maintien (0,25 s) de l'état
## « sous terre » — vu : « remonté : à l'air » échouait.
func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


## LES TRANSITIONS : le matériau du greffon en passe suivante des tuiles, son shader cuit lisant le centre de la tuile
## dans CUSTOM0 ; et chaque sommet porte le centre de SA tuile (un sommet v + 1 entier, à moins d'une tuile du sommet).
func _check_transitions(rep: Dictionary, manifest: Dictionary) -> void:
	check(int(rep.get("transitions", {}).get("pairs", 0)) == 6, "trois paires actives, dans les deux sens (%s)" % str(rep.get("transitions")))
	var e: Dictionary = manifest["chunks"].filter(func(c: Dictionary) -> bool: return c["files"].has("sol"))[0]
	var n: Node = (load(OUT.path_join(e["files"]["sol"])) as PackedScene).instantiate()
	var mi := n.get_node("Surface") as MeshInstance3D
	var mat := mi.mesh.surface_get_material(0)
	var tr: Material = mat.next_pass if mat else null
	check(tr is ShaderMaterial, "les tuiles portent le passage des transitions")
	if tr is ShaderMaterial:
		var code: String = (tr as ShaderMaterial).shader.code
		check(code.contains("CUSTOM0") and not code.contains("MODEL_MATRIX)[3]"), "le shader cuit lit le centre dans CUSTOM0")
		# Le monde chargé (le ChunkStreamer) rend au matériau partagé ses textures, PLEINES.
		var s := ChunkStreamer.new()
		s.baked_dir = OUT
		s.load_manifest()
		var tex: Variant = (tr as ShaderMaterial).get_shader_parameter("cases")
		var want_size: Vector3i = s._transitions_data.size if s._transitions_data else Vector3i.ZERO
		check(tex is Texture3D and (tex as Texture3D).get_width() == want_size.x and want_size.x > 1
			and (tex as Texture3D).get_depth() == want_size.z, "la texture 3D des cases est rebâtie (%s)" % str(want_size))
		var arr: Variant = (tr as ShaderMaterial).get_shader_parameter("representants")
		check(arr is Texture2DArray and (arr as Texture2DArray).get_layers() == 15, "les représentants sont rebâtis")
		check(s._transitions_mat == tr, "le matériau rebâti est celui des morceaux (le même, partagé)")
		var tab: Variant = (tr as ShaderMaterial).get_shader_parameter("table")
		var timg: Image = s._transitions_data.table if s._transitions_data else null
		check(tab is ImageTexture and timg != null and timg.get_width() == 30 and timg.get_pixel(2 * 1, 0).r == 1.0,
			"la table des paires est rebâtie (la paire 0 couvre 1 active)")
		var col: Variant = (tr as ShaderMaterial).get_shader_parameter("rep_couleur")
		check(col is PackedColorArray and (col as PackedColorArray).size() == 15
			and (col as PackedColorArray)[2].is_equal_approx(Color(0.3, 0.55, 0.2, 1.0)),
			"les couleurs des représentants sont reposées (%s)" % str(col).substr(0, 60))
		s.free()
	var a := mi.mesh.surface_get_arrays(0)
	var c: PackedFloat32Array = a[Mesh.ARRAY_CUSTOM0] if a[Mesh.ARRAY_CUSTOM0] != null else PackedFloat32Array()
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	check(c.size() == v.size() * 4, "un centre par sommet (%d / %d)" % [c.size() / 4, v.size()])
	var bad := 0
	for i in mini(v.size(), 4000):
		var ce := Vector3(c[i * 4], c[i * 4 + 1], c[i * 4 + 2])
		var d := (v[i] - ce).abs()
		if d.x > 0.76 or d.y > 0.76 or d.z > 0.76 or (ce - Vector3.ONE).distance_to((ce - Vector3.ONE).round()) > 1e-4:
			bad += 1
	check(bad == 0, "chaque sommet porte le centre de sa tuile (%d écarts)" % bad)
	n.free()

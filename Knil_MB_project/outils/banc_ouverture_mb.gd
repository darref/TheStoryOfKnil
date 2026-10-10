extends SceneTree
## LE BANC D'OUVERTURE DANS MB — l'appli MarchingBlocks (son écran, `app/editor.tscn`) ouvre un projet comme au
## lancement, et on mesure : le temps, la mémoire, et si elle tient. Lancé DANS le projet MB, avec fenêtre :
##   godot --path D:/MarchingBlocks --script D:/TheStoryOfKnil/Knil_MB_project/outils/banc_ouverture_mb.gd -- --projet=<.mbproj>
##         [--grilles-sans-physique]
## ⚠ L'appli rouvre au lancement le projet de ses réglages (`user://reglages.cfg`, « monde ») : le banc le fait pointer
## sur le projet à mesurer, puis REMET le fichier de réglages tel qu'il était (copie gardée à côté).

const REGLAGES := "user://reglages.cfg"
var _app: Node
var _t0 := 0


func _initialize() -> void:
	_lancer.call_deferred()


func _lancer() -> void:
	var projet := ""
	var tenir := 8
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--projet="):
			projet = a.trim_prefix("--projet=")
		elif a.begins_with("--tenir="):
			tenir = int(a.trim_prefix("--tenir="))  # combien de secondes après l'ouverture
		elif a.begins_with("--octant="):
			var o := int(a.trim_prefix("--octant="))  # essai : la taille des octants des GridMap de l'appli
			node_added.connect(func(n: Node) -> void:
				if n is GridMap:
					(n as GridMap).cell_octant_size = o)
		elif a == "--sans-physique":
			PhysicsServer3D.set_active(false)  # diagnostic : le pas physique ne tourne plus
		elif a == "--grilles-sans-physique":
			# Le diagnostic du plantage : chaque GridMap de l'appli, dès qu'elle entre, hors de toute couche physique.
			node_added.connect(func(n: Node) -> void:
				if n is GridMap:
					(n as GridMap).collision_layer = 0
					(n as GridMap).collision_mask = 0)
	var garde := ProjectSettings.globalize_path(REGLAGES) + ".avant_banc"
	DirAccess.copy_absolute(ProjectSettings.globalize_path(REGLAGES), garde)
	var cfg := ConfigFile.new()
	cfg.load(REGLAGES)
	cfg.set_value("projet", "monde", projet)
	cfg.set_value("projet", "dernier", projet)
	cfg.save(REGLAGES)
	print("BANC : ouverture de %s (%d Mo)" % [projet, FileAccess.get_file_as_bytes(projet).size() / 1048576 if FileAccess.file_exists(projet) else -1])
	_t0 = Time.get_ticks_msec()
	_app = (load("res://app/editor.tscn") as PackedScene).instantiate()
	root.add_child(_app)
	var dernier := -1
	for i in 2400:
		await create_timer(0.5).timeout
		var ouvert: String = str(_app.get("_projet"))
		var mem := OS.get_static_memory_usage() / 1048576
		if ouvert == projet and dernier < 0:
			dernier = Time.get_ticks_msec() - _t0
			print("BANC : projet ouvert après %.1f s · mémoire %d Mo" % [dernier / 1000.0, mem])
		if dernier >= 0 and i % 20 == 0 and tenir > 8:
			print("BANC :   %d s · mémoire %d Mo · %d img/s · traitement %.0f ms · physique %.0f ms · %d appels · %.1f M prim · %d objets" % [
				(Time.get_ticks_msec() - _t0 - dernier) / 1000, mem, Engine.get_frames_per_second(),
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1e6,
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
		if dernier >= 0 and Time.get_ticks_msec() - _t0 > dernier + tenir * 1000:
			print("BANC : tient %d s après l'ouverture · mémoire %d Mo (pic %d Mo) · %d img/s" % [tenir, mem,
				OS.get_static_memory_peak_usage() / 1048576, Engine.get_frames_per_second()])
			print("BANC : rendu · %d appels · %.1f M prim · %d objets · mémoire vidéo %d Mo · traitement %.0f ms" % [
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1e6,
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576,
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])
			break
	for a in OS.get_cmdline_user_args():
		if dernier >= 0 and a.begins_with("--vues="):
			# Le diagnostic du rendu : des reculs de caméra (et une borne des ombres), chacun mesuré après 6 s.
			# --vues=60;monde;monde@300;monde@0   (recul en cases, ou « monde » : tout cadré ; @ : ombres jusqu'à)
			var vue: Node = _app.get("_vue")
			if "--lod" in OS.get_cmdline_user_args():
				# L'essai des LOD : chaque pièce de chaque grille Rendu refaite avec ses niveaux (ImporterMesh).
				var t := Time.get_ticks_msec()
				var faits := {}
				var tris := [0, 0]
				for g in root.find_children("Rendu", "GridMap", true, false):
					var lib: MeshLibrary = (g as GridMap).mesh_library
					if lib == null:
						continue
					if not faits.has(lib):
						var neuve: MeshLibrary = lib.duplicate()
						for id in neuve.get_item_list():
							var m := neuve.get_item_mesh(id)
							if m == null:
								continue
							var im := ImporterMesh.new()
							for si in m.get_surface_count():
								im.add_surface(Mesh.PRIMITIVE_TRIANGLES, m.surface_get_arrays(si), [], {}, m.surface_get_material(si))
							im.generate_lods(25.0, 60.0, [])
							var lm := im.get_mesh()
							for si in lm.get_surface_count():
								tris[0] += (m.surface_get_arrays(si)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 if m.surface_get_arrays(si)[Mesh.ARRAY_INDEX] != null else (m.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
								tris[1] += lm.surface_get_lod_count(si)
							neuve.set_item_mesh(id, lm)
						faits[lib] = neuve
					(g as GridMap).mesh_library = faits[lib]
				print("BANC : LOD faits en %d ms · %d triangles de pièces · %d niveaux" % [Time.get_ticks_msec() - t, tris[0], tris[1]])
				await create_timer(15.0).timeout
			if "--sans-feuillage" in OS.get_cmdline_user_args():
				for n in root.find_children("*", "MultiMeshInstance3D", true, false):
					(n as Node3D).visible = false
			for v in a.trim_prefix("--vues=").split(";"):
				var parts := v.split("@")
				if parts[0] == "monde":
					vue.call("cadrer_toute_la_matiere")
				else:
					vue.set("_distance", float(parts[0]))
					vue.call("_caler")
				var soleil: DirectionalLight3D = vue.get("_soleil")
				if "--loin" in OS.get_cmdline_user_args():
					(vue.get("_camera") as Camera3D).far = maxf(250.0, float(vue.get("_distance")) * 2.5)
				if parts.size() > 1:
					soleil.shadow_enabled = float(parts[1]) > 0.0
					soleil.directional_shadow_max_distance = maxf(float(parts[1]), 1.0)
				else:
					soleil.shadow_enabled = true
				await create_timer(6.0).timeout
				print("BANC : vue %-10s recul %4.0f · %3d img/s · %5d appels · %6.1f M prim · ombres %s · loin %.0f" % [v,
					float(vue.get("_distance")), Engine.get_frames_per_second(),
					Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
					Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1e6,
					"non" if not soleil.shadow_enabled else "%.0f" % soleil.directional_shadow_max_distance,
					(vue.get("_camera") as Camera3D).far])
	if dernier >= 0 and "--chronos" in OS.get_cmdline_user_args():
		# Le diagnostic de la lenteur : chaque suivi du `_process` de l'écran, chronométré à part.
		var suivis := {
			"_dire_les_trous": func() -> void: _app.call("_dire_les_trous"),
			"_dire_les_ecarts": func() -> void: _app.call("_dire_les_ecarts"),
			"_transitions.suivre": func() -> void: _app.get("_transitions").call("suivre"),
			"_animation.suivre": func() -> void: _app.get("_animation").call("suivre", 0.016),
			"_suivre_le_geste": func() -> void: _app.call("_suivre_le_geste"),
			"_dire_l_etat_pbr": func() -> void: _app.call("_dire_l_etat_pbr"),
			"vue._process": func() -> void: _app.get("_vue").call("_process", 0.016),
		}
		for nom: String in suivis:
			var t := Time.get_ticks_usec()
			for k in 5:
				(suivis[nom] as Callable).call()
			print("BANC : chrono %-22s %.1f ms" % [nom, (Time.get_ticks_usec() - t) / 5000.0])
	if dernier < 0:
		print("BANC : PAS OUVERT en 120 s · mémoire %d Mo" % (OS.get_static_memory_usage() / 1048576))
	# Les réglages de l'utilisateur, remis tels quels.
	_app.queue_free()
	await process_frame
	DirAccess.copy_absolute(garde, ProjectSettings.globalize_path(REGLAGES))
	DirAccess.remove_absolute(garde)
	print("BANC : réglages remis")
	quit()

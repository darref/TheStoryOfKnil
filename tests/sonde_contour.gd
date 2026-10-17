extends Node
## LE CONTOUR NOIR (la charte reprise de Spirit3D) — sur la scène principale : Knil et chaque Interactable portent
## leurs coques (enfants INTERNES, sans ombre, liées au squelette pour Knil) ; rien d'autre n'est contouré.
## Avec fenêtre, en plus : des captures (user://captures/contour_*.png).
##   Godot --headless --path D:/TheStoryOfKnil res://tests/sonde_contour.tscn
## Sort avec 0 si tout est vert.
const OUT := "user://captures"

var _fails := 0
var _checks := 0


func check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		printerr("ÉCHEC : " + what)


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	for e in main.find_children("*", "Ennemi", true, false):  # les ennemis posés sur la carte : pas ici
		e.free()
	add_child(main)
	GameClock.from_save({"minutes": 10 * 60})
	await _frames(30)
	var player: Player = main.get_node("Player")
	# Knil : un mesh skinné, donc la coque porte le mesh d'origine et suit le squelette.
	var knil_hulls := _hulls(player.get_node("Modele"))
	check(knil_hulls.size() > 0, "Knil porte un contour (%d coques)" % knil_hulls.size())
	for h in knil_hulls:
		var body := h.get_parent() as MeshInstance3D
		check(h.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "la coque de Knil ne projette pas d'ombre")
		check(OutlineHull.is_hull_material(h.material_override), "la coque porte le shader du contour")
		check(h.mesh == body.mesh or h.mesh.get_surface_count() == body.mesh.get_surface_count(), "la coque porte toutes les surfaces")
		if OutlineHull.is_skinned_mesh(body.mesh):
			check(h.get_node_or_null(h.skeleton) is Skeleton3D, "la coque de Knil suit son squelette")
			check(h.skin == body.skin, "et sa peau")
	check(player.get_node("Modele").get_children().all(func(c): return not c.name.begins_with(OutlineHull.HULL_NODE_NAME)),
		"les coques sont INTERNES (invisibles pour get_children : rien ne s'enregistre)")
	# Chaque Interactable.
	var n := 0
	for it in get_tree().get_nodes_in_group("interactables"):
		n += 1
		check(_hulls(it).size() > 0, "%s porte un contour" % it.name)
	check(n >= 4, "les interactables de la scène (%d)" % n)
	# Rien d'autre : le monde cuit, l'auberge ne sont pas soulignés.
	check(_hulls(main.get_node("Monde")).is_empty(), "le monde n'est pas contouré")
	check(_hulls(main.get_node("Auberge/Batisse")).is_empty(), "l'auberge n'est pas contourée")
	# La boîte du shader : un mesh à arêtes vives se recuit, un capsule lisse non.
	check(OutlineHull.smooth_normal_mesh(BoxMesh.new()) != null, "un cube se recuit (normales lissées en CUSTOM0)")
	if DisplayServer.get_name() != "headless":
		await _captures(main, player)
	print("sonde_contour : %d / %d" % [_checks - _fails, _checks])
	get_tree().quit(1 if _fails > 0 else 0)


func _captures(main: Node, player: Player) -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var marchande: Node3D = main.get_node("Bourg/Marchande")
	player.teleport(marchande.global_position + Vector3(2.0, 0.5, 2.0))
	await _frames(90)
	get_viewport().get_texture().get_image().save_png(OUT + "/contour_dessus.png")
	var rig := main.get_node("CameraRig")
	for i in 4:  # zoomer : Knil de près
		rig.set("zoom", float(rig.get("zoom")) / 1.6)
	await _frames(60)
	get_viewport().get_texture().get_image().save_png(OUT + "/contour_pres.png")
	print("captures : ", ProjectSettings.globalize_path(OUT))


func _hulls(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	_collect(root, out)
	return out


func _collect(node: Node, out: Array[MeshInstance3D]) -> void:
	for c in node.get_children(true):
		if c is MeshInstance3D and bool(c.get_meta(OutlineHull.META_HULL, false)):
			out.append(c)
		else:
			_collect(c, out)


func _frames(k: int) -> void:
	for i in k:
		await get_tree().process_frame

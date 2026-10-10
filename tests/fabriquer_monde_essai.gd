extends Node
## FABRIQUER LE MONDE D'ESSAI — un `.mbworld` au format EXACT de MarchingBlocks (world.json v1), en attendant le vrai
## monde peint dans le logiciel. Ses COUCHES sont celles de Knil (tools/cuisson/couches.json), dans l'ordre
## conseillé (la première l'emporte où elles se touchent) :
##   GrosObstacles  un VOLCAN à cratère (au nord-est)
##   Obstacles      un anneau de MASSIFS autour de la place du village, percé de quatre chemins
##   Sol            le relief (collines, plateau plat au centre — dessus à y = 1 —, cuvette du lac), une ARCHE sur le
##                  plateau, et des GALERIES sous presque toute la carte (un quadrillage, deux cases de haut, enfoui)
## plus un LAC (sa nappe cuite comme MB la cuit : un .glb dans water/) et des ARBRES (un modèle fait ici, en .glb).
##   Godot --headless --path D:/Knil res://tests/fabriquer_monde_essai.tscn [-- --taille=128 --nom=essai]
## Puis `--import` (les .glb du monde), puis la cuisson.

const WorldFile := preload("res://addons/marchingblocks_paint/mb_world_file.gd")
const TILESET := "res://assets/tilesets/temoin.mbset"
const LAKE := Vector2i(-30, 30)
const VOLCANO := Vector2i(30, -30)
const VOLCANO_RADIUS := 14
const RING := Vector2(13.0, 14.6)  # l'anneau des massifs autour de la place
const GROUND_BOTTOM := -8          # le sol est plein jusque-là
const GALLERY := Vector2i(-4, -3)  # les galeries : ces deux rangées de cases, vides
const GALLERY_STEP := 16
## L'arche (dans le Sol) : deux piliers et un linteau d'une case — dessous, de l'air NON enfoui.
const ARCH := Rect2i(-10, -3, 5, 2)

var OUT := "res://mondes/essai.mbworld"


func _ready() -> void:
	var n := 128
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--nom="):
			OUT = "res://mondes/%s.mbworld" % a.trim_prefix("--nom=")
		if a.begins_with("--taille="):
			n = int(a.trim_prefix("--taille="))
	for d in ["sol.mbset", "foliage", "water"]:
		DirAccess.make_dir_recursive_absolute(OUT.path_join(d))
	for f in ["tileset.json", "tiles.glb", "README.txt"]:
		DirAccess.copy_absolute(TILESET.path_join(f), OUT.path_join("sol.mbset").path_join(f))
	_write_tree(OUT.path_join("foliage/arbre.glb"))

	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.045
	var ground := PackedInt32Array()
	var obstacles := PackedInt32Array()
	var volcano := PackedInt32Array()
	var heights := {}
	var half := n >> 1
	var reach := half - 8  # les galeries s'arrêtent à 8 cases du bord
	for x in range(-half, n - half):
		for z in range(-half, n - half):
			var h := _height(noise, x, z)
			heights[Vector2i(x, z)] = h
			var gallery := absi(x) < reach and absi(z) < reach \
				and (posmod(x, GALLERY_STEP) < 2 or posmod(z, GALLERY_STEP) < 2)
			for y in range(GROUND_BOTTOM, h - 1):
				if gallery and y >= GALLERY.x and y <= GALLERY.y:
					continue
				ground.append_array([x, y, z])
			var p := Vector2(x, z)
			var r := p.length()
			# L'anneau des massifs, trois cases au-dessus du sol, sauf les quatre chemins.
			if r >= RING.x and r <= RING.y and absi(x) > 2 and absi(z) > 2:
				for y in range(h - 1, h + 2):
					obstacles.append_array([x, y, z])
			# Le volcan : un cône posé sur le sol, son cratère creusé.
			var dv := p.distance_to(Vector2(VOLCANO))
			if dv <= VOLCANO_RADIUS:
				var top := int(round(15.0 * (1.0 - dv / VOLCANO_RADIUS)))
				if dv < 4.0:
					top = 9
				for y in range(h - 1, h - 1 + top):
					volcano.append_array([x, y, z])
	# L'arche, sur le plateau (dessus à y = 1) : piliers sur y 1..2, linteau en y = 3.
	for x in range(ARCH.position.x, ARCH.end.x):
		for z in range(ARCH.position.y, ARCH.end.y):
			ground.append_array([x, 3, z])
			if x == ARCH.position.x or x == ARCH.end.x - 1:
				ground.append_array([x, 1, z, x, 2, z])

	var plants := PackedFloat32Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for x in range(-half + 2, n - half - 2, 5):
		for z in range(-half + 2, n - half - 2, 5):
			var p := Vector2i(x + rng.randi_range(-1, 1), z + rng.randi_range(-1, 1))
			if Vector2(p).length() < RING.y + 2 or Vector2(p - LAKE).length() < 13 \
					or Vector2(p - VOLCANO).length() < VOLCANO_RADIUS + 2:
				continue
			plants.append_array([1, p.x + 0.5, heights.get(p, 1) - 1, p.y + 0.5, rng.randf() * TAU, 0.8 + rng.randf() * 0.5, 1])
	var world := {
		"format": "marchingblocks-world", "version": 1, "name": "essai", "generator": "Knil (essai)",
		"layers": [
			{"name": "GrosObstacles", "visible": true, "tileset": "sol.mbset/tileset.json", "cells": Array(volcano)},
			{"name": "Obstacles", "visible": true, "tileset": "sol.mbset/tileset.json", "cells": Array(obstacles)},
			{"name": "Sol", "visible": true, "tileset": "sol.mbset/tileset.json", "cells": Array(ground)},
		],
		"water": [{"name": "Lac", "visible": true, "look": "clear", "mesh": null, "sources": [LAKE.x, 0, LAKE.y]}],
		"foliage": {"models": [{"id": 1, "name": "Arbre", "mesh": "foliage/arbre.glb"}], "plants": Array(plants)},
		# LES TRANSITIONS (le format de l'atelier Transitions) : les trois paires actives, les réglages par défaut, un
		# représentant de couleur unie par couche.
		"transitions": {"pairs": [{"a": 0, "b": 1, "active": true, "a_covers_b": {}, "b_covers_a": {}},
			{"a": 0, "b": 2, "active": true, "a_covers_b": {}, "b_covers_a": {}},
			{"a": 1, "b": 2, "active": true, "a_covers_b": {}, "b_covers_a": {}}],
			"representatives": [{"image": null, "color": [0.55, 0.2, 0.12, 1.0], "scale": 1.0, "roughness": 0.9},
				{"image": null, "color": [0.5, 0.5, 0.52, 1.0], "scale": 1.0, "roughness": 0.9},
				{"image": null, "color": [0.3, 0.55, 0.2, 1.0], "scale": 1.0, "roughness": 0.9}],
			"choices": []},
	}
	_save(world)
	# LA NAPPE, cuite comme MB la cuit : le greffon la déduit (sources + cases), on l'écrit en .glb.
	var host := Node3D.new()
	add_child(host)
	var built := WorldFile.build(OUT.path_join("world.json"), host)
	for e in built.get("extras", []):
		if e.get_script() == WorldFile.WaterNode:
			e.rebuild_water_now()
			_write_mesh(e.sheet_mesh(), OUT.path_join("water/lac.glb"))
	host.free()
	world["water"][0]["mesh"] = "water/lac.glb"
	_save(world)
	print("MONDE D'ESSAI : %d × %d colonnes · Sol %d cases · Obstacles %d · GrosObstacles %d · %d arbres → %s" % [
		n, n, ground.size() / 3, obstacles.size() / 3, volcano.size() / 3, plants.size() / 7, OUT])
	get_tree().quit()


func _save(world: Dictionary) -> void:
	var f := FileAccess.open(OUT.path_join("world.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(world))
	f.close()


## La hauteur d'une colonne (en cases) : collines, plateau, cuvette du lac et son bord.
func _height(noise: FastNoiseLite, x: int, z: int) -> int:
	var p := Vector2(x, z)
	if p.length() <= 12:
		return 2
	var dl := p.distance_to(Vector2(LAKE))
	if dl <= 8:
		return 1
	if dl <= 11:
		return 4
	return 1 + int(round((noise.get_noise_2d(x, z) + 1.0) * 2.0))


func _write_mesh(mesh: Mesh, path: String) -> void:
	var root := Node3D.new()
	root.name = "Nappe"
	var mi := MeshInstance3D.new()
	mi.name = "Lac"
	mi.mesh = mesh
	root.add_child(mi)
	mi.owner = root
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	doc.append_from_scene(root, state)
	doc.write_to_filesystem(state, ProjectSettings.globalize_path(path))
	root.free()


## Un arbre simple (un tronc, un houppier), écrit en .glb : le modèle de plant de l'essai.
func _write_tree(path: String) -> void:
	var root := Node3D.new()
	root.name = "Arbre"
	var trunk := MeshInstance3D.new()
	trunk.name = "Tronc"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.18
	cyl.height = 1.6
	cyl.radial_segments = 8
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.4, 0.27, 0.15)
	cyl.material = bark
	trunk.mesh = cyl
	trunk.position.y = 0.8
	var crown := MeshInstance3D.new()
	crown.name = "Houppier"
	var sph := SphereMesh.new()
	sph.radius = 0.9
	sph.height = 1.6
	sph.radial_segments = 10
	sph.rings = 6
	var leaves := StandardMaterial3D.new()
	leaves.albedo_color = Color(0.22, 0.5, 0.2)
	sph.material = leaves
	crown.mesh = sph
	crown.position.y = 2.1
	root.add_child(trunk)
	root.add_child(crown)
	trunk.owner = root
	crown.owner = root
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	doc.append_from_scene(root, state)
	doc.write_to_filesystem(state, ProjectSettings.globalize_path(path))
	root.free()

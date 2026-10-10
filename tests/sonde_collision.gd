extends Node
## LA COLLISION CUITE CONTRE LE RENDU — headless : autour de quelques points d'un monde cuit, la collision chargée
## (simplifiée, couche 1) est comparée, rayon par rayon, à une collision COMPLÈTE bâtie sur les maillages affichés
## (couche 16) — depuis le ciel, et depuis le niveau des galeries. Un écart de plus de `TOL` est un trou (ou un
## mur) que le joueur sentirait et ne verrait pas.
##   Godot --headless --path D:/Resolve res://tests/sonde_collision.tscn -- --monde=res://cuit/val_de_resolve
##         [--points=x,z;x,z…] [--pas=1.3] [--galerie=-3.6]
## Sort avec 0 si aucun écart.

const TOL := 0.15
const FULL_LAYER := 1 << 15

var _fails := 0


func _ready() -> void:
	var dir := "res://cuit/val_de_resolve"
	var points: Array = [Vector2(0.5, 0.5), Vector2(24.5, 40.5), Vector2(-150, -20), Vector2(150, 140)]
	var step := 1.3
	var gallery_y := -3.6
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"monde": dir = kv[1]
			"pas": step = float(kv[1])
			"galerie": gallery_y = float(kv[1])
			"points":
				points = []
				for t in kv[1].split(";"):
					var c := t.split(",")
					points.append(Vector2(float(c[0]), float(c[1])))
	var target := Node3D.new()
	add_child(target)
	var s := ChunkStreamer.new()
	s.baked_dir = dir
	s.target = target
	s.distances = {"collision": 1.0}  # le morceau du point seulement
	var total := 0
	for p: Vector2 in points:
		target.position = Vector3(p.x, 0, p.y)
		if s.get_parent() == null:
			add_child(s)
		else:
			s.load_around_now(target.position)
		await get_tree().physics_frame
		var ck := float(s._chunk)
		var key := Vector2i(floori(p.x / ck), floori(p.y / ck))
		# La collision COMPLÈTE : chaque maillage montrable du morceau, en forme concave pleine.
		var full := StaticBody3D.new()
		full.collision_layer = FULL_LAYER
		full.collision_mask = 0
		add_child(full)
		for t: String in s._tracks:
			if t == "collision" or not s._tracks[t].has(key) or s._tracks[t][key]["node"] == null:
				continue
			for part in ["Surface", "Souterrain"]:
				var mi := (s._tracks[t][key]["node"] as Node).get_node_or_null(part) as MeshInstance3D
				if mi:
					var cs := CollisionShape3D.new()
					cs.shape = mi.mesh.create_trimesh_shape()
					full.add_child(cs)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var space := get_viewport().world_3d.direct_space_state
		var n := 0
		var bad := 0
		var worst := 0.0
		# L'intérieur du morceau : à ses bords, les tuiles sont à ses voisins (la forme complète n'a que les siennes).
		# ⚠ Jamais sur une coordonnée ENTIÈRE : c'est l'arête d'une marche, où un rayon tombe d'un côté ou de l'autre
		# pour un rien (vu : 0,75 contre 1,00 en x = 12,00) — ce n'est pas un trou. 1,63 + 1,3 k n'est jamais entier.
		var x := key.x * ck + 1.63
		while x < key.x * ck + ck - 1.5:
			var z := key.y * ck + 1.63
			while z < key.y * ck + ck - 1.5:
				for from_y in [80.0, gallery_y]:
					var a := Vector3(x, from_y, z)
					var b := a + Vector3.DOWN * 100.0
					var hb := space.intersect_ray(PhysicsRayQueryParameters3D.create(a, b, 1))
					var hf := space.intersect_ray(PhysicsRayQueryParameters3D.create(a, b, FULL_LAYER))
					if hf.is_empty() and hb.is_empty():
						continue
					n += 1
					var yb: float = hb["position"].y if not hb.is_empty() else -INF
					var yf: float = hf["position"].y if not hf.is_empty() else -INF
					var d := absf(yb - yf)
					worst = maxf(worst, d if is_finite(d) else 999.0)
					if not d <= TOL:
						bad += 1
						if bad <= 3:
							printerr("  écart en (%.2f, %.2f) depuis y=%.1f : cuite %.2f, complète %.2f" % [x, z, from_y, yb, yf])
				z += step
			x += step
		print("morceau %s autour de %s : %d rayons, %d écarts > %.2f m (pire %.2f m)" % [key, p, n, bad, TOL, worst])
		total += bad
		full.queue_free()
		await get_tree().physics_frame
	_fails = total
	print("COLLISION : %d écarts" % total)
	get_tree().quit(1 if total > 0 else 0)

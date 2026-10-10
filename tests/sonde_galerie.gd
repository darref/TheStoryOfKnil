extends Node
## LES GALERIES SE PARCOURENT-ELLES ? — headless : autour d'un escalier de galerie d'un monde cuit, la COUPE de la
## galerie (sol, plafond, largeur libre) mesurée à la collision chargée, puis un corps à la capsule du JOUEUR qui
## descend l'escalier, suit le couloir, et remonte (en sautant les marches).
##   Godot --headless --path D:/Resolve res://tests/sonde_galerie.tscn -- --monde=res://cuit/val_de_resolve
##         [--escalier=8,0]   (le coin de l'escalier : x, z — le couloir court le long de x, de z à z + 3)
## Sort avec 0 si le joueur descend, longe le couloir et remonte.

const PLAYER := preload("res://player/player.tscn")

var _space: PhysicsDirectSpaceState3D


func _ready() -> void:
	var dir := "res://cuit/val_de_resolve"
	var stair := Vector2i(8, 0)
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"monde": dir = kv[1]
			"escalier":
				var c := kv[1].split(",")
				stair = Vector2i(int(c[0]), int(c[1]))
	var target := Node3D.new()
	add_child(target)
	target.position = Vector3(stair.x + 10, 0, stair.y + 1)
	var s := ChunkStreamer.new()
	s.baked_dir = dir
	s.target = target
	s.distances = {"collision": 40.0}
	add_child(s)
	for i in 4:
		await get_tree().physics_frame
	_space = get_viewport().world_3d.direct_space_state

	# 1. LA COUPE : en travers du couloir (z), à quelques x du couloir ; sol, plafond, hauteur libre.
	var zc := stair.y + 2.0
	for x in [stair.x - 6.5, stair.x + 1.5, stair.x + 7.5, stair.x + 9.5, stair.x + 10.5, stair.x + 11.5, stair.x + 16.5]:
		var line := "x=%6.1f |" % x
		var z := zc - 2.75
		while z <= zc + 2.76:
			var fl := _ray(Vector3(x, -3.0, z), Vector3.DOWN, 6.0)
			var ce := _ray(Vector3(x, -3.0, z), Vector3.UP, 6.0)
			line += " %5.2f/%5.2f" % [fl, ce]
			z += 0.5
		print(line)
	# La largeur libre, à hauteur de hanche et de tête, au milieu du couloir.
	for y in [-3.6, -2.6, -1.6]:
		var x := stair.x + 16.5
		var zl := _ray(Vector3(x, y, zc), Vector3.BACK, 5.0)
		var zr := _ray(Vector3(x, y, zc), Vector3.FORWARD, 5.0)
		print("largeur libre à y=%.1f : %.2f m (de z=%.2f à %.2f)" % [y, zl - zr, zr, zl])
	# Le profil de l'escalier, le long de x, au milieu.
	var prof := "escalier (sol / plafond le long de x) :"
	var x2 := stair.x - 2.0
	while x2 <= stair.x + 14.0:
		prof += "\n  x=%5.2f  sol %6.2f  plafond %6.2f" % [x2, _ray(Vector3(x2, 3.0, zc), Vector3.DOWN, 8.0),
			_ray(Vector3(x2, -3.5, zc), Vector3.UP, 6.0)]
		x2 += 0.5
	print(prof)

	# 2. LE JOUEUR : descendre, longer, remonter.
	var p := PLAYER.instantiate() as CharacterBody3D
	p.set_physics_process(false)
	add_child(p)
	p.collision_layer = 2
	p.collision_mask = 1 | 16
	p.global_position = Vector3(stair.x - 1.0, 2.0, zc)
	var ok := true
	ok = await _walk(p, Vector3.RIGHT, stair.x + 30.0, 12.0, "descendre et longer") and ok
	print("  arrivé en %s" % p.global_position)
	ok = await _walk(p, Vector3.LEFT, stair.x - 1.0, 15.0, "remonter (en sautant)") and ok
	print("  arrivé en %s" % p.global_position)
	print("GALERIE : %s" % ("PARCOURUE" if ok else "BLOQUÉE"))
	get_tree().quit(0 if ok else 1)


func _ray(from: Vector3, dir: Vector3, length: float) -> float:
	var h := _space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + dir * length, 1))
	if h.is_empty():
		return NAN
	var q: Vector3 = h["position"]
	return q.y if absf(dir.y) > 0.5 else q.z


## Un corps à la capsule du joueur, poussé vers `dir` (marche, gravité, saut quand il bute) jusqu'à `goal_x`.
func _walk(p: CharacterBody3D, dir: Vector3, goal_x: float, seconds: float, what: String) -> bool:
	var g := 9.8
	var dt := 1.0 / 60.0
	var t := 0.0
	var stuck := 0.0
	var last := p.global_position
	while t < seconds:
		p.velocity.x = dir.x * 3.5
		p.velocity.z = 0.0
		if p.is_on_floor():
			# Bute contre une marche : il saute (1,4 m, comme le joueur).
			if stuck > 0.1:
				p.velocity.y = sqrt(2.0 * g * 1.4)
				stuck = 0.0
		else:
			p.velocity.y -= g * dt
		p.move_and_slide()
		await get_tree().physics_frame
		t += dt
		if p.global_position.distance_to(last) < 0.01:
			stuck += dt
		else:
			stuck = maxf(stuck - dt, 0.0)
		last = p.global_position
		if (p.global_position.x - goal_x) * dir.x >= 0.0:
			print("%s : OK (%.1f s)" % [what, t])
			return true
	printerr("%s : BLOQUÉ en %s" % [what, p.global_position])
	return false

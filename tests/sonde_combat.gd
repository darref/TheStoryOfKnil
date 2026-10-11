extends Node
## LE COMBAT — headless, sans le monde cuit : un sol, Knil, une cible (un Frappable) devant lui. Le coup de genou
## (F, clic gauche, RT) touche la cible UNE fois, la pousse, fait avancer Knil d'un pas ; un appui pendant le
## rétablissement enchaîne ; trop loin, rien. En boule (R, LT tenus) : Knil ne bouge ni ne saute ni ne frappe, le
## bouclier pare (la vie ne baisse pas) — mais pas avant d'être en boule ; sans boule, le coup coûte, puis Knil est
## invulnérable un moment. Sans les animations : la doublure (le modèle s'écrase, se cabre) puis revient au repos.
##   Godot --headless --path D:/TheStoryOfKnil res://tests/sonde_combat.tscn
## Sort avec 0 si tout est vert.

var _fails := 0
var _checks := 0
var _struck: Array = []


func check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		printerr("ÉCHEC : " + what)


func _ready() -> void:
	GameState.set_value("player.health", 6)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60, 1, 60)
	floor_shape.shape = box
	floor_shape.position.y = -0.5
	floor_body.add_child(floor_shape)
	add_child(floor_body)
	var cam := Camera3D.new()  # le déplacement suit la caméra : vue de dessus, « avant » = −z
	cam.position = Vector3(0, 20, 0)
	cam.rotation.x = -PI / 2
	add_child(cam)
	var player: Player = load("res://player/player.tscn").instantiate()
	add_child(player)
	player.teleport(Vector3(0, 0.1, 0))
	player.rotation.y = 0.0  # il regarde vers +z
	var target := Frappable.new()
	var ts := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.4
	ts.shape = sphere
	target.add_child(ts)
	target.position = Vector3(0, 0.6, 1.0)
	add_child(target)
	target.struck.connect(func(d: int, k: Vector3, s: Node) -> void: _struck.append([d, k, s]))
	var events: Array = []
	EventBus.player_attacked.connect(func(kind: String) -> void: events.append("attaque " + kind))
	EventBus.player_hit.connect(func(_t: Node, kind: String) -> void: events.append("touché " + kind))
	EventBus.player_guard_changed.connect(func(on: bool) -> void: events.append("boule %s" % on))
	await _frames(30)
	check(player.is_on_floor(), "Knil est au sol")
	var model: Node3D = player.get_node("Modele")
	var rest_scale := model.scale

	# --- Le coup de genou ---------------------------------------------------------------------------------
	var z0 := player.global_position.z
	await _tap("attack")
	check(player.action == Player.Action.KNEE, "F : le coup de genou commence")
	var leaned := false
	for i in 20:
		await get_tree().physics_frame
		leaned = leaned or model.rotation.x < -0.1
	check(_struck.size() == 1, "le genou touche la cible une fois (%d)" % _struck.size())
	if _struck.size() > 0:
		check(_struck[0][0] == player.knee_damage, "les dégâts : %d demi-cœurs" % _struck[0][0])
		check(_struck[0][1].z > 3.0, "la cible est poussée devant (%.1f m/s)" % _struck[0][1].z)
		check(_struck[0][2] == player, "la source du coup : Knil")
	check(player.global_position.z - z0 > 0.15, "Knil s'élance d'un pas (%.2f m)" % (player.global_position.z - z0))
	check(leaned, "sans animation, la doublure : il se cabre")
	check(events.has("attaque genou") and events.has("touché genou"), "l'EventBus dit le coup et la touche")
	# l'enchaînement : un appui pendant le rétablissement relance un coup
	await _frames(4)
	await _tap("attack")
	await _frames(30)
	check(_struck.size() == 2, "un appui pendant le rétablissement enchaîne un second coup (%d)" % _struck.size())
	await _frames(40)
	check(player.action == Player.Action.NONE, "le coup fini, Knil est libre")
	check(absf(model.rotation.x) < 0.01, "la doublure revient au repos")
	# trop loin : rien
	target.position.z = player.global_position.z + 3.0
	await _frames(2)
	await _tap("attack")
	await _frames(40)
	check(_struck.size() == 2, "cible à 3 m : le genou ne la touche pas")
	target.position.z = player.global_position.z + 1.0

	# --- En boule -----------------------------------------------------------------------------------------
	var hp0 := int(GameState.get_value("player.health"))
	Input.action_press("guard")
	await _frames(2)
	check(player.action == Player.Action.GUARD and not player.is_guarding(), "R : il se met en boule (pas encore paré)")
	check(player.take_hit(1) == 1, "frappé AVANT d'être en boule : le coup passe")
	await _frames(20)
	check(player.is_guarding(), "en boule : le bouclier pare")
	check(model.scale.y < rest_scale.y * 0.7, "sans animation, la doublure : il s'écrase (%.2f)" % (model.scale.y / rest_scale.y))
	var hp1 := int(GameState.get_value("player.health"))
	check(player.take_hit(2, Vector3(5, 0, 0)) == 0 and int(GameState.get_value("player.health")) == hp1,
		"en boule, le coup est paré : la vie ne baisse pas")
	var p0 := player.global_position
	Input.action_press("move_left")
	await _tap("jump")
	await _tap("attack")
	await _frames(30)
	Input.action_release("move_left")
	check(Vector2(player.global_position.x - p0.x, player.global_position.z - p0.z).length() < 0.6,
		"en boule, il ne marche pas (seule la poussée du coup paré) : %.2f m" % p0.distance_to(player.global_position))
	check(player.global_position.y < p0.y + 0.1, "en boule, il ne saute pas")
	check(player.action == Player.Action.GUARD, "en boule, il ne frappe pas")
	Input.action_release("guard")
	await _frames(20)
	check(player.action == Player.Action.NONE and events.has("boule false"), "R relâché : il sort de la boule")
	check(absf(model.scale.y - rest_scale.y) < 0.01, "la doublure revient au repos")
	await _frames(40)  # l'invulnérabilité du premier coup passée

	# --- Frappé sans bouclier -------------------------------------------------------------------------------
	var hp2 := int(GameState.get_value("player.health"))
	check(hp2 == hp0 - 1, "seul le coup d'avant la boule a compté (%d → %d)" % [hp0, hp2])
	check(player.take_hit(2) == 2 and int(GameState.get_value("player.health")) == hp2 - 2, "sans boule, le coup coûte")
	check(player.take_hit(2) == 0, "juste après, Knil est invulnérable un moment")

	print("ÉPREUVES COMBAT : %d vérifications, %d échecs" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(action)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

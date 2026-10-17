extends Node
## L'ENNEMI (le dealer) — headless, sans le monde cuit : un sol, Knil, un dealer à 8 m. Derrière un mur, il ne voit
## pas Knil ; le mur ôté, il le voit, court vers lui, s'arrête à portée et frappe (Knil perd 2 demi-cœurs) ; en
## boule, le coup est paré ; un genou pendant son armée la COUPE (il chancelle, Knil n'a rien) ; frappé à mort, il
## tombe, ne heurte plus rien et disparaît. Un autre, semé (Knil loin), rentre chez lui. Posé au-dessus de rien
## (collision pas chargée), il ne tombe pas ; loin de Knil, il dort.
##   Godot --headless --path D:/TheStoryOfKnil res://tests/sonde_ennemi.tscn
## Sort avec 0 si tout est vert.

const DEALER := preload("res://ennemis/dealer.tscn")

var _fails := 0
var _checks := 0


func check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		printerr("ÉCHEC : " + what)
	else:
		print("ok : " + what)


func _ready() -> void:
	GameState.set_value("player.health", 6)
	add_child(_box(Vector3(80, 1, 80), Vector3(0, -0.5, 0)))
	var wall := _box(Vector3(6, 3, 0.5), Vector3(0, 1.5, 4))
	add_child(wall)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 20, 0)
	cam.rotation.x = -PI / 2
	add_child(cam)
	var player: Player = load("res://player/player.tscn").instantiate()
	add_child(player)
	player.teleport(Vector3(0, 0.1, 0))
	player.rotation.y = 0.0  # il regarde vers +z, vers le dealer
	var dealer: Ennemi = DEALER.instantiate()
	dealer.corpse_time = 0.5
	dealer.position = Vector3(0, 0.1, 8)
	add_child(dealer)
	var events: Array = []
	EventBus.enemy_alerted.connect(func(_e: Node) -> void: events.append("vu"))
	EventBus.enemy_attacked.connect(func(_e: Node) -> void: events.append("coup"))
	EventBus.enemy_damaged.connect(func(_e: Node, n: int) -> void: events.append("frappé %d" % n))
	EventBus.enemy_died.connect(func(_e: Node) -> void: events.append("mort"))
	var damaged: Array = []
	EventBus.player_damaged.connect(func(n: int, blocked: bool) -> void: damaged.append([n, blocked]))
	var anim: AnimationPlayer = dealer._anim
	check(anim != null and anim.has_animation("ennemi/course") and anim.has_animation("ennemi/coup") \
		and anim.has_animation("ennemi/mort") and anim.has_animation("ennemi/garde"), "ses animations sont là")

	# --- Le mur cache Knil ---------------------------------------------------------------------------------
	await _frames(90)
	check(dealer.is_on_floor(), "le dealer est au sol")
	check(dealer.state == Ennemi.State.IDLE, "derrière le mur, il ne voit pas Knil (%s)" % Ennemi.State.keys()[dealer.state])
	check(anim.current_animation == "ennemi/garde", "il attend en garde (%s)" % anim.current_animation)
	wall.queue_free()
	await _frames(40)
	check(dealer.state == Ennemi.State.CHASE and events.has("vu"), "le mur ôté, il voit Knil et le prend en chasse")

	# --- Il approche et frappe -------------------------------------------------------------------------------
	var ran := false
	for i in 240:
		await get_tree().physics_frame
		ran = ran or anim.current_animation == "ennemi/course"
		if dealer.state == Ennemi.State.ATTACK:
			break
	var d := _flat_distance(dealer, player)
	check(dealer.state == Ennemi.State.ATTACK, "il arrive à portée et frappe")
	check(ran, "il court (l'animation « course »)")
	check(d <= dealer.attack_range + 0.1, "il s'arrête à portée (%.2f m)" % d)
	await _frames(3)
	check(anim.current_animation == "ennemi/coup", "l'animation du coup se joue (%s)" % anim.current_animation)
	await _frames(40)
	check(int(GameState.get_value("player.health")) == 4, "Knil perd %d demi-cœurs (vie %d)" % [dealer.attack_damage,
		int(GameState.get_value("player.health"))])

	# --- En boule, Knil pare --------------------------------------------------------------------------------
	Input.action_press("guard")
	damaged.clear()
	for i in 240:
		await get_tree().physics_frame
		if not damaged.is_empty():
			break
	Input.action_release("guard")
	check(not damaged.is_empty() and damaged[0][1], "le coup suivant tombe sur le bouclier (paré)")
	check(int(GameState.get_value("player.health")) == 4, "en boule, la vie ne baisse pas")
	await _frames(5)

	# --- Frapper le premier coupe son armée -----------------------------------------------------------------
	damaged.clear()
	for i in 240:
		await get_tree().physics_frame
		if dealer.state == Ennemi.State.ATTACK and dealer._state_time < 0.05:
			break
	player.rotation.y = atan2(dealer.global_position.x - player.global_position.x, dealer.global_position.z - player.global_position.z)
	await _tap("attack")
	var hurt := false
	for i in 30:
		await get_tree().physics_frame
		hurt = hurt or dealer.state == Ennemi.State.HURT
	check(hurt, "un genou pendant son armée : il chancelle")
	check(dealer.health == dealer.max_health - player.knee_damage, "il perd %d demi-cœurs (vie %d)" % [player.knee_damage, dealer.health])
	check(damaged.is_empty() or damaged.all(func(x: Array) -> bool: return x[0] == 0), "son coup est coupé : Knil n'a rien")

	# --- À mort -----------------------------------------------------------------------------------------------
	for i in 8:
		if dealer.state == Ennemi.State.DEAD:
			break
		player.rotation.y = atan2(dealer.global_position.x - player.global_position.x, dealer.global_position.z - player.global_position.z)
		await _tap("kick")
		await _frames(50)
	check(dealer.state == Ennemi.State.DEAD and events.has("mort"), "frappé à mort, il tombe")
	check(dealer.collision_layer == 0, "mort, il ne heurte plus personne")
	await _frames(20)
	check(anim.current_animation == "ennemi/mort" or anim.assigned_animation == "ennemi/mort", "l'animation de la mort")
	await _frames(250)
	check(not is_instance_valid(dealer), "puis il disparaît")

	# --- Semé, il rentre chez lui -------------------------------------------------------------------------
	var d2: Ennemi = DEALER.instantiate()
	d2.position = Vector3(-15, 0.1, 0)
	add_child(d2)
	player.teleport(Vector3(-15, 0.1, 6))
	await _frames(40)
	check(d2.state == Ennemi.State.CHASE, "un autre le voit")
	await _frames(30)
	var moved := d2.global_position.distance_to(d2.home)
	player.teleport(Vector3(5, 0.1, 6))  # à ~20 m : au-delà de sa poursuite, en deçà du sommeil
	await _frames(40)
	check(d2.state == Ennemi.State.RETURN, "Knil loin : il abandonne (%s)" % Ennemi.State.keys()[d2.state])
	for i in 600:
		await get_tree().physics_frame
		if d2.state == Ennemi.State.IDLE:
			break
	check(moved > 0.5 and d2.state == Ennemi.State.IDLE and d2.global_position.distance_to(d2.home) < 0.6,
		"il rentre chez lui (parti à %.1f m, revenu à %.2f m)" % [moved, d2.global_position.distance_to(d2.home)])

	# --- Semé de très loin, il est ramené chez lui ------------------------------------------------------------
	player.teleport(Vector3(-15, 0.1, 6))
	await _frames(70)
	var away := d2.global_position.distance_to(d2.home)
	player.teleport(Vector3(38, 0.1, -38))
	await _frames(5)
	check(away > 0.5 and d2._asleep and d2.state == Ennemi.State.IDLE and d2.global_position.distance_to(d2.home) < 0.01,
		"semé de très loin : endormi, ramené chez lui (parti à %.1f m)" % away)

	# --- Pas de collision sous lui : il attend ---------------------------------------------------------------
	var d3: Ennemi = DEALER.instantiate()
	d3.position = Vector3(48, 5, 30)  # hors du sol (±40)
	add_child(d3)
	await _frames(60)
	check(absf(d3.global_position.y - 5.0) < 0.05, "au-dessus de rien, il ne tombe pas (y %.2f)" % d3.global_position.y)

	# --- Loin, il dort ----------------------------------------------------------------------------------------
	player.teleport(Vector3(38, 0.1, -38))
	await _frames(10)
	check(d3._asleep and d2._asleep, "loin de Knil, ils dorment")

	print("sonde_ennemi : %d vérifications, %d échecs" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _box(size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = at
	return body


func _flat_distance(a: Node3D, b: Node3D) -> float:
	return Vector2(a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z).length()


func _tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(action)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

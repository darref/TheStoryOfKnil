extends Node
## LA TRICHE ET LES LIMITES — headless, sur la scène principale (le monde cuit doit porter ses limites) :
## un joueur jeté hors de la zone jouable y revient ; les murs invisibles sont là ; F1 fait voler (Espace monte),
## F2 traverse — mais pas les limites ; F3 change la vitesse.
##   Godot --headless --path D:/Knil res://tests/sonde_triche_limites.tscn
## Sort avec 0 si tout est vert.
const Triche := preload("res://core/triche.gd")

var _fails := 0
var _checks := 0


func check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		printerr("ÉCHEC : " + what)


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	var player: Player = main.get_node("Player")
	var monde: ChunkStreamer = main.get_node("Monde")
	await _frames(30)
	var b := monde.play_bounds
	check(b.size.x > 100.0, "le monde cuit porte ses limites (%s)" % str(b))
	check(player.world_bounds == b, "le joueur les connaît")
	check(monde.get_node_or_null("Limites") != null and monde.get_node("Limites").get_child_count() == 4, "quatre murs invisibles")
	# Jeté dehors (un bug, un saut sur le cadre) : ramené en dedans.
	player.teleport(Vector3(b.end.x + 30.0, 20.0, 0.0))
	await _frames(3)
	check(player.global_position.x <= b.end.x + 0.01, "hors des limites : ramené en dedans (x = %.1f, max %.1f)" % [player.global_position.x, b.end.x])
	# La triche : active (data/triche.json).
	Triche.lire()
	check(Triche.actif, "la triche est active")
	player.teleport(Vector3(0.5, 1.0, 14.0))
	await _frames(30)
	await _key(KEY_F1)
	await _frames(2)
	check(Triche.vol, "F1 : le vol")
	var y0 := player.global_position.y
	Input.action_press("jump")
	await _frames(60)
	Input.action_release("jump")
	check(player.global_position.y > y0 + 3.0, "en vol, Espace monte (+%.1f m)" % (player.global_position.y - y0))
	await _key(KEY_F2)
	await _frames(2)
	check(Triche.fantome and player.collision_mask == 0, "F2 : le fantôme traverse tout")
	# Même en fantôme, les limites tiennent.
	player.teleport(Vector3(b.position.x - 50.0, 30.0, b.position.y - 50.0))
	await _frames(3)
	check(player.global_position.x >= b.position.x - 0.01 and player.global_position.z >= b.position.y - 0.01,
		"en fantôme aussi, les limites tiennent")
	await _frames(30)  # la téléportation lointaine charge d'un coup : une touche pressée pendant ce temps se perd
	await _key(KEY_F3)
	await _frames(2)
	check(Triche.vitesse == 3.0, "F3 : vitesse ×3")
	await _key(KEY_F3)
	await _key(KEY_F3)
	await _key(KEY_F2)
	await _key(KEY_F1)
	await _frames(2)
	check(not Triche.vol and not Triche.fantome and Triche.vitesse == 1.0, "tout se rééteint")
	print("ÉPREUVES TRICHE ET LIMITES : %d vérifications, %d échecs" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


## Une touche, comme au clavier : l'appui, puis le relâchement une image plus tard.
func _key(k: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = k
		e.pressed = pressed
		Input.parse_input_event(e)
		await get_tree().physics_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

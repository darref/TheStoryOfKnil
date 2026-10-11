extends Node
## LA CAMÉRA — headless, sans le monde cuit : un sol, Knil, la caméra de jeu. Un MUR entre la vue oblique et Knil :
## la caméra passe VERTICALE (droit au-dessus) et Knil avance encore vers le haut de l'écran ; le mur ôté, elle revient
## à l'oblique. Et le bras-ressort : un plafond au-dessus de Knil, la caméra reste dessous.
##   Godot --headless --path D:/TheStoryOfKnil res://tests/sonde_camera.tscn
## Sort avec 0 si tout est vert.

var _fails := 0
var _checks := 0


func check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		printerr("ÉCHEC : " + what)


func _box(size: Vector3, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = pos
	add_child(body)
	return body


func _ready() -> void:
	_box(Vector3(80, 1, 80), Vector3(0, -0.5, 0))
	var player: Player = load("res://player/player.tscn").instantiate()
	add_child(player)
	player.teleport(Vector3(0, 0.1, 0))
	var rig := CameraRig.new()
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.current = true
	rig.add_child(cam)
	rig.target = player
	add_child(rig)
	await _frames(40)
	check(not rig.overhead and _tilt(cam) < 70.0, "vue libre : l'oblique (%.0f°)" % _tilt(cam))
	# Un mur de 10 m entre la caméra (au sud, +z) et Knil.
	var wall := _box(Vector3(20, 10, 1), Vector3(0, 5, 3))
	await _frames(40)
	check(rig.overhead, "un mur cache Knil : la caméra passe verticale")
	check(_tilt(cam) > 85.0, "elle regarde droit en bas (%.0f°)" % _tilt(cam))
	check(absf(cam.global_position.x - player.global_position.x) < 0.5 and absf(cam.global_position.z - player.global_position.z) < 0.5,
		"droit au-dessus de Knil")
	# En vertical, « avant » reste le haut de l'écran (−z) : le stick ne tourne pas.
	var z0 := player.global_position.z
	Input.action_press("move_forward")
	await _frames(20)
	Input.action_release("move_forward")
	check(player.global_position.z < z0 - 0.5, "en vertical, avancer va vers le haut de l'écran (%.2f m)" % (z0 - player.global_position.z))
	player.teleport(Vector3(0, 0.1, 0))
	wall.queue_free()
	await _frames(10)
	check(rig.overhead, "le mur ôté : elle attend un peu avant de revenir (pas de clignotement)")
	await _frames(60)
	check(not rig.overhead and _tilt(cam) < 70.0, "puis revient à l'oblique (%.0f°)" % _tilt(cam))
	# Le bras-ressort : un plafond à 3 m au-dessus de Knil — la caméra ne passe pas à travers.
	_box(Vector3(80, 1, 80), Vector3(0, 3.5, 0))
	await _frames(60)
	check(cam.global_position.y < 3.0, "sous un plafond, la caméra reste dessous (y = %.2f)" % cam.global_position.y)
	print("ÉPREUVES CAMÉRA : %d vérifications, %d échecs" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


## L'inclinaison de la caméra sous l'horizon, en degrés (90 : droit en bas).
func _tilt(cam: Camera3D) -> float:
	return rad_to_deg(asin(clampf(cam.global_basis.z.y, -1.0, 1.0)))  # la caméra regarde vers −z local


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

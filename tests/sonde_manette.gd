extends Node
## LA MANETTE — headless : la scène principale menée par de faux événements de manette (ceux qu'une vraie enverrait) :
## le stick gauche déplace, A saute, X fait parler (et on ne bouge pas pendant le dialogue), B ferme, le stick droit
## zoome, Back bascule la vue haute ; et les textes à l'écran passent à la manette.
##   Godot --headless --path D:/TheStoryOfKnil res://tests/sonde_manette.tscn
## Sort avec 0 si tout est vert.
const Inputs := preload("res://core/inputs.gd")

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
	var rig: CameraRig = main.get_node("CameraRig")
	await _frames(60)
	# Le stick gauche, vers l'avant (vers le haut de l'écran : −z en vue de dessus).
	var z0 := player.global_position.z
	_axis(JOY_AXIS_LEFT_Y, -1.0)
	await _frames(60)
	_axis(JOY_AXIS_LEFT_Y, 0.0)
	await _frames(20)
	check(z0 - player.global_position.z > 1.5, "le stick gauche fait avancer (%.2f m)" % (z0 - player.global_position.z))
	check(Inputs.pad, "le dernier appareil est la manette")
	# A : le saut.
	var y0 := player.global_position.y
	var top := y0
	_button(JOY_BUTTON_A)
	for i in 60:
		await get_tree().physics_frame
		top = maxf(top, player.global_position.y)
	check(top - y0 > 1.2, "A fait sauter (+%.2f m)" % (top - y0))
	await _frames(60)
	# X : la marchande parle ; le stick ne fait pas bouger pendant le dialogue ; B ferme.
	player.teleport(main.get_node("Bourg/Marchande").global_position + Vector3(1.0, 0.3, 0))
	await _frames(30)
	check(player.focus != null, "la marchande est à portée")
	var hud := main.get_node("HUD")
	check(str(hud._prompt.text).begins_with("X —"), "l'invite dit X (%s)" % hud._prompt.text)
	_button(JOY_BUTTON_X)
	await _frames(5)
	check(player.focus != null and player.focus.is_talking(), "X fait parler")
	check(hud._box.visible and str(hud._line.text) != "", "la boîte de dialogue montre la réplique")
	var x0 := player.global_position.x
	_axis(JOY_AXIS_LEFT_X, 1.0)
	await _frames(30)
	_axis(JOY_AXIS_LEFT_X, 0.0)
	check(absf(player.global_position.x - x0) < 0.1, "pendant le dialogue, on ne bouge pas")
	_button(JOY_BUTTON_B)
	await _frames(5)
	check(not player.focus.is_talking() and not hud._box.visible, "B ferme le dialogue")
	# Le stick droit : le zoom ; Back : la vue haute.
	var z := rig.zoom
	_axis(JOY_AXIS_RIGHT_Y, 1.0)
	await _frames(40)
	_axis(JOY_AXIS_RIGHT_Y, 0.0)
	check(rig.zoom > z * 1.5, "le stick droit ↓ éloigne la caméra (zoom %.2f → %.2f)" % [z, rig.zoom])
	_button(JOY_BUTTON_BACK)
	await _frames(2)
	check(rig.high, "Back : la vue haute")
	_button(JOY_BUTTON_BACK)
	await _frames(2)
	check(not rig.high, "Back encore : retour")
	# Le clavier reprend la main : les textes aussi.
	var k := InputEventKey.new()
	k.physical_keycode = KEY_W
	k.pressed = true
	Input.parse_input_event(k)
	k = k.duplicate()
	k.pressed = false
	Input.parse_input_event(k)
	await _frames(2)
	check(not Inputs.pad, "une touche : retour au clavier")
	print("ÉPREUVES MANETTE : %d vérifications, %d échecs" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _axis(axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)


func _button(b: JoyButton) -> void:
	for pressed in [true, false]:
		var e := InputEventJoypadButton.new()
		e.device = 0
		e.button_index = b
		e.pressed = pressed
		Input.parse_input_event(e)
		await get_tree().physics_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

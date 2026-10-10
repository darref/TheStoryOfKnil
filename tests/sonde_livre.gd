extends Node
## LE LIVRE (le menu copié de Spirit3D) — headless, mené par de faux événements clavier et manette : le jeu démarre
## agrandi et tourne ; Échap ouvre le livre et met le jeu en PAUSE ; la sélection suit la croix ; A ouvre une page, B la
## referme ; Start rend le jeu ; en dialogue, Échap ferme d'abord le dialogue ; F1–F8 n'ouvrent rien en jeu ; le
## SubViewport du jeu rend à la résolution de la fenêtre.
##   Godot --headless --path D:/TheStoryOfKnil res://tests/sonde_livre.tscn
## Sort avec 0 si tout est vert.

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
	process_mode = Node.PROCESS_MODE_ALWAYS
	var livre: Book = load("res://scenes/livre.tscn").instantiate()
	add_child(livre)
	await _frames(30)
	var jeu: Cell = livre.find_game_cell()
	check(jeu != null and jeu.is_game_cell(), "le livre a une cellule de jeu")
	check(jeu.enlarged and not livre.is_open(), "le jeu démarre agrandi")
	check(not get_tree().paused, "le jeu tourne")
	var numbered := livre.numbered_cells()
	check(numbered.size() == 5, "cinq pages numérotées, les vides sautées (%d)" % numbered.size())
	# La zone du livre (16:9, bandes noires si la fenêtre a un autre ratio), en pixels d'écran.
	var win := livre.size
	var svp_size := Vector2(jeu.subviewport.size)
	check(svp_size.distance_to(win) < 3.0, "le jeu rend à la résolution de l'écran (%s pour %s)" % [svp_size, win])
	var hud: CanvasLayer = jeu.hud
	check(hud != null and hud.visible, "le HUD se voit en jeu")

	# F1 en jeu : la triche, pas le livre.
	_key(KEY_F1)
	await _frames(5)
	check(jeu.enlarged, "F1 en jeu n'ouvre pas de page du livre")

	# Échap : le livre, le jeu en pause, la sélection sur « Jouer ».
	_key(KEY_ESCAPE)
	await _frames(20)
	check(not jeu.enlarged and livre.is_open(), "Échap ouvre le livre")
	check(get_tree().paused, "livre ouvert : le jeu est en pause")
	check(not hud.visible, "livre ouvert : le HUD est caché")
	check(livre.selected_cell == jeu, "la sélection est sur « Jouer »")

	# La croix : à droite, « Commandes » ; A l'ouvre ; B la referme.
	await _button(JOY_BUTTON_DPAD_RIGHT)
	await _frames(5)
	check(livre.selected_cell != null and livre.selected_cell.name == "Commandes", "croix → : Commandes (%s)" % livre.selected_cell)
	await _button(JOY_BUTTON_DPAD_DOWN)
	await _frames(5)
	check(livre.selected_cell != null and livre.selected_cell.name == "Quitter", "croix ↓ sous Commandes (vide) : la seule page d'en bas, Quitter (%s)" % livre.selected_cell)
	await _button(JOY_BUTTON_DPAD_RIGHT)
	await _frames(5)
	check(livre.selected_cell.name == "Quitter", "croix → au bord, une seule planche : rien ne bouge")
	await _button(JOY_BUTTON_DPAD_UP)
	await _button(JOY_BUTTON_DPAD_LEFT)
	await _frames(5)
	var options: Cell = livre.selected_cell
	check(options != null and options.name == "Options", "croix ↑ ← : Options (%s)" % options)
	await _button(JOY_BUTTON_A)
	await _frames(20)
	check(options.enlarged and not livre.is_open(), "A ouvre la page Options")
	check(get_tree().paused, "une page ouverte : le jeu reste en pause")
	check(not jeu.visible, "une page ouverte : les autres cellules sont cachées")
	var focus := get_viewport().gui_get_focus_owner()
	check(focus != null and options.is_ancestor_of(focus), "le premier réglage a le focus (%s)" % focus)
	await _button(JOY_BUTTON_B)
	await _frames(20)
	check(not options.enlarged and livre.is_open(), "B referme la page")
	check(livre.selected_cell == options, "la sélection revient sur Options")

	# F2 livre ouvert : la page n° 2 (Commandes) ; Échap la referme.
	_key(KEY_F2)
	await _frames(20)
	var commandes: Cell = livre.numbered_cells()[1]
	check(commandes.enlarged, "F2, livre ouvert : la page n° 2")
	_key(KEY_ESCAPE)
	await _frames(20)
	check(livre.is_open(), "Échap referme la page")

	# Start : retour au jeu, la pause levée.
	await _button(JOY_BUTTON_START)
	await _frames(20)
	check(jeu.enlarged and not get_tree().paused, "Start rend le jeu, la pause levée")
	check(hud.visible, "le HUD revient")
	check(Vector2(jeu.subviewport.size).distance_to(win) < 3.0, "toujours à la résolution de la fenêtre")

	# En dialogue : Échap ferme le dialogue, PAS le jeu ; l'appui suivant ouvre le livre.
	EventBus.dialogue_shown.emit("Quelqu'un", "Une réplique.")
	await _frames(2)
	_key(KEY_ESCAPE)
	await _frames(10)
	check(jeu.enlarged, "en dialogue, Échap n'ouvre pas le livre")
	EventBus.dialogue_closed.emit()
	await _frames(2)
	_key(KEY_ESCAPE)
	await _frames(20)
	check(livre.is_open() and get_tree().paused, "dialogue fermé : Échap ouvre le livre")
	_key(KEY_ESCAPE)
	await _frames(20)
	check(jeu.enlarged and not get_tree().paused, "Échap, livre ouvert : retour au jeu")

	print("ÉPREUVES LIVRE : %d vérifications, %d échecs" % [_checks, _fails])
	get_tree().paused = false
	get_tree().quit(1 if _fails > 0 else 0)


func _key(k: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = pressed
		Input.parse_input_event(e)


func _button(b: JoyButton) -> void:
	for pressed in [true, false]:
		var e := InputEventJoypadButton.new()
		e.device = 0
		e.button_index = b
		e.pressed = pressed
		Input.parse_input_event(e)
		await get_tree().process_frame


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

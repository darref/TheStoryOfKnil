extends Node
## LES ZOOMS À L'IMAGE — avec fenêtre, sur le monde de la scène principale : la vue normale, la molette (cinq crans vers
## le bas), Ctrl + molette (la vue haute), puis le retour (Ctrl + molette vers le haut). Ce que le streamer charge à
## chaque fois. Images dans user://captures/zoom_*.png.
##   Godot --path D:/Knil --windowed res://tests/capture_zoom.tscn
const OUT := "user://captures"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	GameClock.from_save({"minutes": 15.0 * 60})
	var monde: ChunkStreamer = main.get_node("Monde")
	var rig: CameraRig = main.get_node("CameraRig")
	await _settle(180)
	await _shot("1_normal", monde, rig)
	for i in 5:
		_wheel(false, true)
	await _settle(240)
	await _shot("2_molette", monde, rig)
	_wheel(true, true)
	await _settle(600)
	await _shot("3_vue_haute", monde, rig)
	_wheel(true, false)
	await _settle(240)
	await _shot("4_retour", monde, rig)
	get_tree().quit()


## Un cran de molette, vers le bas (`down`) ou le haut, avec ou sans Ctrl — par la file des entrées, comme la vraie.
func _wheel(ctrl: bool, down: bool) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP
		e.pressed = pressed
		e.ctrl_pressed = ctrl
		e.position = get_viewport().get_visible_rect().size / 2
		Input.parse_input_event(e)


func _settle(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name_: String, monde: ChunkStreamer, rig: CameraRig) -> void:
	get_viewport().get_texture().get_image().save_png(OUT + "/zoom_%s.png" % name_)
	print("%s : zoom %.2f · haute %s · caméra à %.0f m du joueur · rayon vu %.0f m · morceaux sol %d, gros %d, collision %d · %d appels · %.0f img/s"
		% [name_, rig.zoom, rig.high, rig.global_position.distance_to(rig.target.global_position), rig.view_radius(),
		monde.loaded_count("sol"), monde.loaded_count("gros"), monde.loaded_count("collision"),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Engine.get_frames_per_second()])

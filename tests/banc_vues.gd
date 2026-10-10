extends Node3D
## BANC DES VUES — avec fenêtre, sur un monde cuit : au même endroit, ce que coûte chaque vue — de dessus, troisième
## personne EN SURFACE face à l'horizon (le pire : la vue porte loin), troisième personne dans une GALERIE — et la
## pire image PENDANT chaque bascule (entrée, sortie).
##   Godot --path D:/TheStoryOfKnil --windowed res://tests/banc_vues.tscn [-- --monde=res://cuit/grand]

const SURFACE := Vector3(40.5, 3.0, 8.5)
const GALLERY := Vector3(16.5, -4.25, 40.5)

var _s: ChunkStreamer
var _rig: CameraRig
var _target: Node3D


func _ready() -> void:
	var dir := "res://cuit/grand"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--monde="):
			dir = a.trim_prefix("--monde=")
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.4, 0)
	sun.shadow_enabled = true
	add_child(sun)
	_target = Node3D.new()
	_target.position = SURFACE
	add_child(_target)
	_s = ChunkStreamer.new()
	_s.baked_dir = dir
	_s.target = _target
	add_child(_s)
	_rig = load("res://player/camera_rig.gd").new()
	_rig.target = _target
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = 55
	_rig.add_child(cam)
	add_child(_rig)
	cam.current = true
	await _settle(120)
	await _measure("de dessus, en surface")
	_rig.set_mode(CameraRig.Mode.THIRD_PERSON)
	print("bascule vers la 3e personne (surface) : pire image %.1f ms" % await _worst(90))
	await _measure("3e personne, en surface, face à l'horizon")
	_rig.set_mode(CameraRig.Mode.TOPDOWN)
	await _settle(90)
	_target.position = GALLERY
	await _settle(150)
	_rig.set_mode(CameraRig.Mode.THIRD_PERSON)
	print("entrée en galerie : pire image %.1f ms" % await _worst(90))
	await _measure("3e personne, dans une galerie (souterrain=%s)" % Interior.is_underground())
	# Une sortie RÉALISTE : remonter juste au-dessus (pas de saut : le chargement ne bouge pas).
	_target.position = GALLERY + Vector3(0, 5.0, 0)
	_rig.set_mode(CameraRig.Mode.TOPDOWN)
	print("sortie de galerie : pire image %.1f ms" % await _worst(150))
	get_tree().quit()


func _settle(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _worst(n: int) -> float:
	var worst := 0.0
	var last := Time.get_ticks_usec()
	for i in n:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
	return worst


func _measure(what: String) -> void:
	await _settle(30)
	var t := Time.get_ticks_usec()
	for i in 120:
		await get_tree().process_frame
	var fps := 120.0 / ((Time.get_ticks_usec() - t) / 1e6)
	print("%s : %.0f img/s · %d appels de dessin · %.2f M triangles · %d objets · morceaux sol %d, gros %d" % [what, fps,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1e6,
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		_s.loaded_count("sol"), _s.loaded_count("gros")])

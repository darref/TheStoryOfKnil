extends Node
## UN MONDE CUIT À L'IMAGE — avec fenêtre : la scène principale sur le monde demandé, la caméra de jeu en quelques
## lieux. Images dans user://captures/<monde>_<lieu>.png.
##   Godot --path D:/TheStoryOfKnil --windowed res://tests/capture_monde.tscn -- --monde=res://cuit/monde_knil
##         [--lieux=x,y,z;x,y,z…] [--heure=10]
const OUT := "user://captures"

func _ready() -> void:
	var dir := "res://cuit/monde_knil"
	var spots: Array = [Vector3(0.5, 3, 12), Vector3(-30, 6, 0), Vector3(-160, 8, -20), Vector3(150, 8, 130)]
	var hour := 10.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--monde="):
			dir = a.trim_prefix("--monde=")
		elif a.begins_with("--heure="):
			hour = float(a.trim_prefix("--heure="))
		elif a.begins_with("--lieux="):
			spots = []
			for t in a.trim_prefix("--lieux=").split(";"):
				var c := t.split(",")
				spots.append(Vector3(float(c[0]), float(c[1]), float(c[2])))
	DirAccess.make_dir_recursive_absolute(OUT)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.get_node("Monde").baked_dir = dir
	add_child(main)
	GameClock.from_save({"minutes": hour * 60.0})
	var player: Player = main.get_node("Player")
	for i in spots.size():
		player.teleport(spots[i])
		for k in 240:
			await get_tree().process_frame
		var name_ := "%s_%d" % [dir.get_file(), i]
		get_viewport().get_texture().get_image().save_png(OUT + "/%s.png" % name_)
		print("%s : %s · y=%.2f · %s · %d appels" % [name_, str(spots[i]), player.global_position.y,
			GameState.get_value("place.interior_type"), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	get_tree().quit()

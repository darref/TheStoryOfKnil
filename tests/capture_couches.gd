extends Node
## LES COUCHES À L'IMAGE — avec fenêtre : la place et son anneau de massifs (Obstacles), le volcan (GrosObstacles)
## vu de loin, et une galerie (Sol, souterrain) à la torche. Images dans user://captures.
##   Godot --path D:/Knil --windowed res://tests/capture_couches.tscn
const OUT := "user://captures"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	GameClock.from_save({"minutes": 10.0 * 60})
	var player: Player = main.get_node("Player")
	for shot in [["place", Vector3(-12, 3, 4)], ["volcan", Vector3(12, 3, -14)], ["galerie", Vector3(16.5, -4.0, 36.5)]]:
		player.teleport(shot[1])
		for i in 300:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(OUT + "/couches_%s.png" % shot[0])
		print("%s : %s · %d appels de dessin" % [shot[0], GameState.get_value("place.interior_type"),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	get_tree().quit()

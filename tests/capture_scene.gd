extends Node
## CAPTURES — avec fenêtre : la vue de dessus, puis la troisième personne dans l'auberge.
const OUT := "user://captures"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	GameClock.from_save({"minutes": 10 * 60})
	for i in 150:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OUT + "/vue_dessus.png")
	_stats("vue de dessus")
	var player0: Player = main.get_node("Player")
	player0.teleport(Vector3(-22, 4, 22))  # au bord du lac, sous les arbres
	for i in 150:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OUT + "/lac.png")
	_stats("lac")
	var player: Player = main.get_node("Player")
	player.teleport(main.get_node("Auberge").global_position + Vector3(-1, 0.5, -1))
	DecisionEngine.open_encounter(main.get_node("Auberge/Aubergiste").describe())
	for i in 150:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OUT + "/interieur.png")
	DecisionEngine.close_encounter()
	player.teleport(Vector3(24, 1.5, -30))  # l'entrée du tunnel
	for i in 150:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OUT + "/tunnel.png")
	_stats("tunnel")
	get_tree().quit()


func _stats(what: String) -> void:
	print("%s : %d appels de dessin, %d triangles, %d img/s" % [what,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Engine.get_frames_per_second()])

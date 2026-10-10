extends Node
## LA NUIT — avec fenêtre : à 23 h dehors (la lune, l'ambiante de nuit, la torche), dans l'auberge, puis à midi
## (la torche éteinte d'elle-même). Les images dans user://captures ; l'état de la torche dans la sortie.
##   Godot --path D:/Resolve --windowed res://tests/capture_nuit.tscn
const OUT := "user://captures"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	var player: Player = main.get_node("Player")
	var torch: OmniLight3D = player.get_node("Torche")
	for shot in [["nuit_dehors", 23 * 60, Vector3(-4, 3, -10)], ["nuit_auberge", 23 * 60 + 5, Vector3(5, 1.5, 5)],
			["midi_dehors", 12 * 60, Vector3(-4, 3, -10)]]:
		GameClock.from_save({"minutes": float(shot[1])})
		player.teleport(shot[2])
		for i in 400:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(OUT + "/%s.png" % shot[0])
		print("%s : %s · torche %s (%.2f)" % [shot[0], GameClock.phase(), "allumée" if torch.visible else "éteinte", torch.light_energy])
	get_tree().quit()

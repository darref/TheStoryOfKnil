extends Node
## SONDE DE LA SCÈNE PRINCIPALE — headless : les morceaux cuits chargés, le joueur dessus, la région, la caméra.
##   Godot --headless --path D:/TheStoryOfKnil res://tests/sonde_scene.tscn

func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for i in 180:
		await get_tree().physics_frame
	var monde: ChunkStreamer = main.get_node("Monde")
	var player: Player = main.get_node("Player")
	var rig: CameraRig = main.get_node("CameraRig")
	print("morceaux chargés : sol %d · obstacles %d · gros %d · collision %d" % [monde.loaded_count("sol"),
		monde.loaded_count("obstacles"), monde.loaded_count("gros"), monde.loaded_count("collision")])
	print("joueur : y=%.2f au sol=%s · région=%s · caméra=%s" % [player.global_position.y, player.is_on_floor(),
		GameState.get_value("place.region_id"), CameraRig.Mode.keys()[rig.mode]])
	player.teleport(main.get_node("Auberge").global_position + Vector3(0, 0.5, 0))
	for i in 60:
		await get_tree().physics_frame
	print("dans l'auberge : intérieur=%s · caméra=%s · focus=%s" % [GameState.get_value("place.interior_type"),
		CameraRig.Mode.keys()[rig.mode], player.focus.entity_id if player.focus else "-"])
	var aubergiste: Interactable = main.get_node("Auberge/Aubergiste")
	aubergiste.interact()
	print("dialogue : parle=%s · HUD=%s" % [aubergiste.is_talking(), main.get_node("HUD")._line.text])
	aubergiste.close()
	# LE SAUT : sur la place, un appui d'Espace — la hauteur atteinte, puis le retour au sol.
	player.teleport(Vector3(0.5, 1.0, 14.0))
	for i in 30:
		await get_tree().physics_frame
	var y0 := player.global_position.y
	Input.action_press("jump")
	await get_tree().physics_frame
	Input.action_release("jump")
	var top := y0
	for i in 90:
		await get_tree().physics_frame
		top = maxf(top, player.global_position.y)
	print("saut : sol %.2f · sommet %.2f (+%.2f m) · revenu au sol=%s y=%.2f" % [y0, top, top - y0, player.is_on_floor(),
		player.global_position.y])
	player.teleport(Vector3(64.5, -3.0, 40.5))  # dans une galerie du Val (un couloir tous les 64 m), sous la dalle
	for i in 90:
		await get_tree().physics_frame
	print("dans la galerie : y=%.2f au sol=%s · intérieur=%s · caméra=%s · torche=%s" % [player.global_position.y,
		player.is_on_floor(), GameState.get_value("place.interior_type"), CameraRig.Mode.keys()[rig.mode],
		player.get_node("Torche").visible])
	get_tree().quit()

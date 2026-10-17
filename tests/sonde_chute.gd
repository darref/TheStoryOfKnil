extends Node
## LES CHUTES À TRAVERS LE SOL — headless : le vrai jeu (main.tscn), Knil court tout droit dans huit directions, vite
## (vitesse de triche `--vitesse`, 3 par défaut : 21 m/s), à travers les morceaux qui se chargent en fond. On relève
## chaque passage SOUS LE SOL (Knil plus de `--marge` m sous la dernière hauteur où il touchait le sol, sans
## sauter) : c'est un trou de collision, ou un morceau dont la collision est arrivée trop tard.
##   Godot --headless --path D:/TheStoryOfKnil res://tests/sonde_chute.tscn [-- --vitesse=8 --duree=6]
## Sort avec 0 si aucune chute.
const Triche := preload("res://core/triche.gd")


func _ready() -> void:
	var speed := 3.0
	var each := 6.0
	var margin := 2.0
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"vitesse": speed = float(kv[1])
			"duree": each = float(kv[1])
			"marge": margin = float(kv[1])
	var main: Node = load("res://scenes/main.tscn").instantiate()
	for e in main.find_children("*", "Ennemi", true, false):  # les ennemis posés sur la carte : pas ici
		e.free()
	add_child(main)
	var player: Player = main.get_node("Player")
	await _frames(90)
	var start := player.global_position
	Triche.vitesse = speed
	var falls := 0
	for i in 8:
		var ang := TAU * i / 8.0
		var d := Vector2(cos(ang), sin(ang))
		player.teleport(start)
		await _frames(30)
		var floor_y := player.global_position.y
		var worst := 0.0
		Input.action_press("run")
		for pair in [["move_right", d.x], ["move_left", -d.x], ["move_back", d.y], ["move_forward", -d.y]]:
			if pair[1] > 0.01:
				Input.action_press(pair[0], pair[1])
		var frames := int(each * Engine.physics_ticks_per_second)
		var fell_here := false
		for f in frames:
			await get_tree().physics_frame
			if player.is_on_floor():
				floor_y = player.global_position.y
			var drop := floor_y - player.global_position.y
			worst = maxf(worst, drop)
			if drop > margin and not fell_here:
				fell_here = true
				falls += 1
				printerr("CHUTE : direction %d, en (%.1f, %.1f, %.1f), %.1f m sous le dernier sol" % [i, player.global_position.x, player.global_position.y, player.global_position.z, drop])
		for a in ["run", "move_right", "move_left", "move_back", "move_forward"]:
			Input.action_release(a)
		print("direction %d : fini en (%.0f, %.0f), plus bas %.2f m sous le dernier sol" % [i, player.global_position.x, player.global_position.z, worst])
	Triche.vitesse = 1.0
	print("CHUTES : %d sur 8 courses à ×%.0f" % [falls, speed])
	get_tree().quit(1 if falls > 0 else 0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

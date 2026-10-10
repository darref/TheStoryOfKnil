extends Node3D
## LA RÉFÉRENCE À L'IMAGE — avec fenêtre : un .mbworld bâti par le GREFFON lui-même (ses GridMap, son nœud de
## transitions), vu par la caméra de jeu en un lieu. Pour comparer à la même vue du monde CUIT (`capture_monde`).
##   Godot --path D:/TheStoryOfKnil --windowed res://tests/capture_reference.tscn -- --monde=res://mondes/essai.mbworld/world.json
##         --lieu=x,y,z [--nom=ref]
const WorldFile := preload("res://addons/marchingblocks_paint/mb_world_file.gd")

func _ready() -> void:
	var world := "res://mondes/essai.mbworld/world.json"
	var at := Vector3(30, 9.2, -18)
	var nom := "reference"
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"monde": world = kv[1]
			"nom": nom = kv[1]
			"lieu":
				var c := kv[1].split(",")
				at = Vector3(float(c[0]), float(c[1]), float(c[2]))
	var env := WorldEnvironment.new()
	env.environment = (load("res://scenes/main.tscn") as PackedScene).instantiate().get_node("Environment").environment
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.4, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var root := Node3D.new()
	add_child(root)
	WorldFile.build(world, root)
	var cam := Camera3D.new()
	cam.fov = 55
	add_child(cam)
	cam.current = true
	cam.look_at_from_position(at + Vector3(0, 14, 9), at)
	for i in 240:
		await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute("user://captures")
	get_viewport().get_texture().get_image().save_png("user://captures/%s.png" % nom)
	print("référence écrite : %s" % nom)
	get_tree().quit()

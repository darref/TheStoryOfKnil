extends Node
## LANCER LA CUISSON — en ligne de commande, sans fenêtre :
##   Godot --headless --path D:/Resolve res://tools/cuisson/cuire.tscn -- --monde=res://mondes/x.mbworld/world.json
##        [--sortie=res://cuit/x] [--morceau=16] [--sans-lod] [--compression] [--sans-collision] [--erreur-collision=0.05]
## Le .mbworld vient du logiciel MarchingBlocks (World, « Export the world… ») ; le copier sous `mondes/`.

const Cuisson := preload("res://tools/cuisson/cuisson.gd")


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "oui"
	if not args.has("monde"):
		printerr("Il faut --monde=res://…/world.json")
		get_tree().quit(2)
		return
	var monde: String = args["monde"]
	var nom := monde.get_base_dir().get_file().get_basename()
	var c := Cuisson.new()
	c.chunk = int(args.get("morceau", 16))
	c.lod = not args.has("sans-lod")
	c.compress = args.has("compression")
	c.collision = not args.has("sans-collision")
	if args.has("erreur-collision"):
		c.collision_max_error = float(args["erreur-collision"])
	var rep := c.cuire(self, monde, args.get("sortie", "res://cuit/" + nom))
	if rep.has("error"):
		printerr("CUISSON REFUSÉE : ", rep["error"])
		get_tree().quit(1)
		return
	print("CUISSON : ", JSON.stringify(rep))
	get_tree().quit(0)

extends Node
## BANC — le temps que met le greffon (GDScript) à poser un monde de N × N colonnes, au chargement.
##   Godot --headless --path D:/TheStoryOfKnil res://tests/banc_taille.tscn

const MBWorld := preload("res://addons/marchingblocks_paint/mb_world.gd")

func _ready() -> void:
	for n in [64, 128, 256]:
		var w: Node3D = MBWorld.new()
		w.tileset = "res://assets/tilesets/temoin.mbset/tileset.json"
		add_child(w)
		var cells: Array = []
		var noise := FastNoiseLite.new()
		noise.frequency = 0.03
		for x in n:
			for z in n:
				for y in 1 + int((noise.get_noise_2d(x, z) + 1.0) * 3.0):
					cells.append(Vector3i(x, y, z))
		var t := Time.get_ticks_msec()
		w.apply_cells(cells, [])
		print("%d × %d : %d cases, %d tuiles, %d ms" % [n, n, cells.size(), w.last_report()["tiles"], Time.get_ticks_msec() - t])
		w.queue_free()
		await get_tree().process_frame
	get_tree().quit()

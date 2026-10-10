extends Node3D
## BANC DE RENDU — avec fenêtre : un monde de N × N colonnes posé par le greffon (GridMap), vu de la caméra de
## jeu (vue de dessus) puis de très haut. Appels de dessin, objets, triangles, images par seconde.
##   Godot --path D:/Knil res://tests/banc_rendu.tscn

const MBWorld := preload("res://addons/marchingblocks_paint/mb_world.gd")
const N := 256

func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.4, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var w: Node3D = MBWorld.new()
	w.tileset = "res://assets/tilesets/temoin.mbset/tileset.json"
	add_child(w)
	var cells: Array = []
	var noise := FastNoiseLite.new()
	noise.frequency = 0.03
	for x in N:
		for z in N:
			for y in 1 + int((noise.get_noise_2d(x, z) + 1.0) * 3.0):
				cells.append(Vector3i(x, y, z))
	w.apply_cells(cells, [])
	w.get_node("Cells").visible = false
	var t0 := Time.get_ticks_msec()
	if "--cuit" in OS.get_cmdline_user_args():
		var baked := _bake(w.get_node("Tiles"), 32)
		w.get_node("Tiles").visible = false
		add_child(baked)
		print("cuisson : %d maillages en %d ms" % [baked.get_child_count(), Time.get_ticks_msec() - t0])
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 55
	for view in [["vue de dessus (jeu)", Vector3(128, 18, 137), Vector3(128, 4, 128)],
			["vue très haute (tout le monde)", Vector3(128, 260, 300), Vector3(128, 0, 128)]]:
		cam.look_at_from_position(view[1], view[2])
		for i in 90:
			await get_tree().process_frame
		var t := Time.get_ticks_usec()
		for i in 60:
			await get_tree().process_frame
		var fps := 60.0 / ((Time.get_ticks_usec() - t) / 1e6)
		print("%s : %d appels de dessin, %d objets, %d triangles, %.0f img/s" % [view[0],
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), fps])
	get_tree().quit()


## La CUISSON : les tuiles d'un morceau de size × size colonnes fusionnées en UN maillage, une surface par matériau.
func _bake(tiles: GridMap, size: int) -> Node3D:
	var root := Node3D.new()
	var lib := tiles.mesh_library
	var chunks := {}
	for c in tiles.get_used_cells():
		var k := Vector2i(floori(c.x / float(size)), floori(c.z / float(size)))
		if not chunks.has(k):
			chunks[k] = {}
		var xf := tiles.global_transform * Transform3D(tiles.get_cell_item_basis(c), tiles.map_to_local(c))
		var mesh := lib.get_item_mesh(tiles.get_cell_item(c))
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s)
			if not chunks[k].has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				chunks[k][mat] = st
			chunks[k][mat].append_from(mesh, s, xf)
	for k in chunks:
		var am := ArrayMesh.new()
		for mat in chunks[k]:
			chunks[k][mat].commit(am)
			am.surface_set_material(am.get_surface_count() - 1, mat)
		var mi := MeshInstance3D.new()
		mi.mesh = am
		root.add_child(mi)
	return root

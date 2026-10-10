@tool
extends RefCounted
## LOADS A MARCHINGBLOCKS TILESET — a `<name>.mbset/` folder: `tileset.json` + `tiles.glb`.
##
## Returns {"manifest": Dictionary, "library": MeshLibrary} — one library item per tile, named after the
## tile — or {"error": reason}. Every failure says WHICH one: a missing file, an unreadable manifest, a
## newer format, a tile the manifest lists but the .glb does not carry.
##
## ANIMATED TEXTURES: a material of `tiles.glb` whose glTF extras carry `mb_animation` is replaced by the animated
## material (`mb_animation.gd`); its frames are read in the `.mbset` folder. Such a library OWNS its meshes (`own`):
## the animated material of one layer carries that layer's place in the world.

const Rule := preload("res://addons/marchingblocks_paint/mb_rule.gd")
const Anim := preload("res://addons/marchingblocks_paint/mb_animation.gd")


static func load_tileset(manifest_path: String) -> Dictionary:
	if not FileAccess.file_exists(manifest_path):
		return {"error": "file not found: %s" % manifest_path}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(manifest_path)) != OK or not json.data is Dictionary:
		return {"error": "tileset.json is not valid JSON (line %d)" % json.get_error_line()}
	var manifest: Dictionary = json.data
	if manifest.get("format", "") != Rule.FORMAT:
		return {"error": "not a MarchingBlocks tileset"}
	var why := Rule.check(manifest)
	if why != "":
		return {"error": why}

	var glb := manifest_path.get_base_dir().path_join(str(manifest.get("tiles_file", "tiles.glb")))
	var meshes := _meshes_of(glb)
	if meshes.has("error"):
		return meshes
	var library := MeshLibrary.new()
	var missing: Array = []
	var next_id := 0
	# Every tile: the base tile of each key, then its variants (step 8).
	var all_tiles: Array = []
	for key in manifest.get("tiles", {}):
		all_tiles.append(str(manifest["tiles"][key]))
	for key in manifest.get("variants", {}):
		for t in manifest["variants"][key]:
			all_tiles.append(str(t))
	for tile: String in all_tiles:
		if not meshes.has(tile):
			missing.append(tile)
			continue
		library.create_item(next_id)
		library.set_item_name(next_id, tile)
		library.set_item_mesh(next_id, meshes[tile])
		next_id += 1
	if not missing.is_empty():
		return {"error": "%d tile(s) listed in tileset.json are not in %s: %s"
			% [missing.size(), glb.get_file(), str(missing.slice(0, 5))]}
	var animated := animate(library, glb)
	return {"manifest": manifest, "library": library, "animated": animated}


## Replaces every animated material of the library by its animated material. Returns how many materials are animated.
## The animation is read in the glTF JSON of the .glb (the most certain), else in the "extras" meta of the material.
static func animate(library: MeshLibrary, glb: String) -> int:
	var by_name := Anim.of_glb(glb)
	var base := glb.get_base_dir()
	var found := {}
	for id in library.get_item_list():
		var mesh := library.get_item_mesh(id)
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s)
			if m is BaseMaterial3D and not found.has(m):
				var a: Dictionary = by_name.get(m.resource_name, {})
				if a.is_empty():
					a = Anim.of_material(m)
				if not a.is_empty():
					found[m] = a
	if found.is_empty():
		return 0
	var copies := own(library)
	var animated := {}
	for still in found:
		animated[copies.get(still, still)] = Anim.material(copies.get(still, still), found[still], base)
	for id in library.get_item_list():
		var mesh := library.get_item_mesh(id)
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s)
			if animated.has(m):
				mesh.surface_set_material(s, animated[m])
	return animated.size()


## Every mesh of the library becomes the library's OWN copy, its materials too (one copy per material, shared by
## its surfaces as before): a material changed for one layer — its place in the world, the transitions pass laid over
## it — must not change another layer, or another world, that loaded the same file. Returns {original: copy}.
static func own(library: MeshLibrary) -> Dictionary:
	var copies := {}
	for id in library.get_item_list():
		var mesh := library.get_item_mesh(id)
		if mesh == null or mesh.has_meta("mb_own"):
			continue
		var copy := mesh.duplicate() as Mesh
		for s in copy.get_surface_count():
			var m := copy.surface_get_material(s)
			if m == null:
				continue
			if not copies.has(m):
				copies[m] = m.duplicate()
			copy.surface_set_material(s, copies[m])
		copy.set_meta("mb_own", true)
		library.set_item_mesh(id, copy)
	return copies


## {node name: Mesh} for every mesh node of the .glb. An imported resource is used when the project has
## one (res://), otherwise the file is read at run time.
static func _meshes_of(glb: String) -> Dictionary:
	var scene: Node = null
	if glb.begins_with("res://") and ResourceLoader.exists(glb):
		var packed := load(glb) as PackedScene
		if packed != null:
			scene = packed.instantiate()
	if scene == null:
		if not FileAccess.file_exists(glb):
			return {"error": "file not found: %s" % glb}
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		var err := doc.append_from_file(glb, state)
		if err != OK:
			return {"error": "%s could not be read (error %d)" % [glb.get_file(), err]}
		scene = doc.generate_scene(state)
		if scene == null:
			return {"error": "%s holds no scene" % glb.get_file()}
	var out := {}
	_collect(scene, out)
	scene.free()
	return out


## A node is recognised by what it CARRIES, not by its class: the editor import yields
## ImporterMeshInstance3D, which does not inherit MeshInstance3D.
static func _collect(node: Node, out: Dictionary) -> void:
	var m = node.get("mesh")
	if m is ImporterMesh:
		m = (m as ImporterMesh).get_mesh()
	if m is Mesh:
		out[str(node.name)] = m
	for child in node.get_children():
		_collect(child, out)

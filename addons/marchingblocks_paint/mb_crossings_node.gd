@tool
extends Node3D
## THE CROSSINGS OF A WORLD — its stairs and slopes, each drawn from its model's mesh AND given a COLLISION (the mesh's
## triangles, a StaticBody3D per crossing): a character walks up them. The import puts this node next to the layers,
## scaled by their cell size: its own space is FORMAT space (one unit, one cell). Rebuilt from `models` and `placements`
## when it enters the tree, and when either changes.

const Crossings := preload("res://addons/marchingblocks_paint/mb_crossings.gd")
const Tileset := preload("res://addons/marchingblocks_paint/mb_tileset.gd")

## The models: [{id, name, kind, width, height, depth, mesh (a .glb path, or null)}].
@export var models: Array = []:
	set(value):
		models = value
		_dirty()
## The crossings, 5 integers each: model id, x, y, z of the foot cell, quarter turn.
@export var placements: PackedInt32Array = PackedInt32Array():
	set(value):
		placements = value
		_dirty()
## The physics layer of their collision (the layers' tiles get theirs from the game).
@export_flags_3d_physics var collision_layer := 1
## TRIPLANAR textures, as the layers' tiles (`MarchingBlocksWorld.triplanar`): a crossing takes a layer's ground material,
## blended in WORLD space at the file's repeat — seamless with the ground it stands on.
@export var triplanar := true:
	set(value):
		triplanar = value
		_dirty()

static var _meshes := {}


func _ready() -> void:
	rebuild()


func _dirty() -> void:
	if is_inside_tree():
		rebuild.call_deferred()


func rebuild() -> void:
	for c in get_children(true):
		if c.has_meta("mb_crossing"):
			remove_child(c)
			c.queue_free()
	var by_id := {}
	for m in models:
		by_id[int(m["id"])] = m
	for k in range(0, placements.size() - 4, 5):
		var m = by_id.get(placements[k])
		if m == null:
			continue
		var mesh := _own_mesh(mesh_of(m), by_id, int(m["id"]))
		if mesh == null:
			continue
		var t := Crossings.transform_of(m, Vector3i(placements[k + 1], placements[k + 2], placements[k + 3]),
			placements[k + 4])
		var body := StaticBody3D.new()
		body.set_meta("mb_crossing", true)
		body.collision_layer = collision_layer
		body.transform = t
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		body.add_child(mi)
		var shape := CollisionShape3D.new()
		shape.shape = mesh.create_trimesh_shape()
		body.add_child(shape)
		add_child(body, false, Node.INTERNAL_MODE_BACK)


var _owned := {}


## This node's own copy of a model's mesh, its materials set to triplanar at this node's scale (one cell = one unit of
## its space): another world loading the same file keeps its own.
func _own_mesh(mesh: Mesh, _by_id: Dictionary, id: int) -> Mesh:
	if mesh == null:
		return null
	if _owned.has(id) and (_owned[id] as Mesh).get_meta("mb_source") == mesh:
		return _owned[id]
	var copy := mesh.duplicate() as Mesh
	copy.set_meta("mb_source", mesh)
	var cell := (global_transform if is_inside_tree() else transform).basis.get_scale().x
	for s in copy.get_surface_count():
		var mat := copy.surface_get_material(s)
		if not mat is BaseMaterial3D:
			continue
		var own := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
		var repeat := Tileset.repeat_of(copy, s)
		var on := triplanar and repeat > 0.0
		own.uv1_triplanar = on
		own.uv1_world_triplanar = on
		own.uv1_triplanar_sharpness = 4.0
		own.uv1_scale = Vector3.ONE / (repeat * cell) if on else Vector3.ONE
		copy.surface_set_material(s, own)
	_owned[id] = copy
	return copy


## A model's mesh, read once per path (an imported resource when the project has one, else the .glb at run time).
static func mesh_of(m: Dictionary) -> Mesh:
	var path = m.get("mesh")
	if not path is String:
		return null
	if _meshes.has(path):
		return _meshes[path]
	var scene: Node = null
	if (path as String).begins_with("res://") and ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		if packed != null:
			scene = packed.instantiate()
	if scene == null and FileAccess.file_exists(path):
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(path, state) == OK:
			scene = doc.generate_scene(state)
	var found: Mesh = null
	if scene != null:
		for n in [scene] + scene.find_children("*", "", true, false):
			var mm = n.get("mesh")
			if mm is ImporterMesh:
				mm = (mm as ImporterMesh).get_mesh()
			if mm is Mesh:
				found = mm
				break
		scene.free()
	if found == null:
		push_warning("MarchingBlocks crossings: no mesh in %s" % path)
	_meshes[path] = found
	return found

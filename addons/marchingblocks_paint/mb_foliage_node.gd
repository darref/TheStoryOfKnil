@tool
extends Node3D
## THE FOLIAGE OF A WORLD — its plants, drawn as MultiMeshes (one per part of a model: thousands of trees cost a few
## draw calls), swaying in the WIND. The import puts it next to the layers, scaled by their cell size: its own space
## is FORMAT space (one unit, one cell), the space of the plants.
##
## THE WIND is the MarchingBlocks tool's own shader (`mb_shaders.gd`, WIND): every material of a model is taken into
## it (colour, image, vertex colour, alpha scissor or blend, roughness, metal, normal) and keeps its look. Each plant
## gives it (ground, height above the ground, phase, amplitude) — `mb_foliage.gd`, `wind_of` —, the ground and the
## height turned into Godot's world (the shader moves vertices in world space). ⚠ Exact for a world moved and scaled;
## turned, the wind turns with it.
## ⚠ The model's own animation (a skeleton) is not played — nor in the tool.

const Foliage := preload("res://addons/marchingblocks_paint/mb_foliage.gd")
const Shaders := preload("res://addons/marchingblocks_paint/mb_shaders.gd")

## The models: [{id, name, mesh (a .glb path, or null), ground_offset, scale, scale_random, footprint, height, wind}].
@export var models: Array = []:
	set(value):
		models = value
		_dirty()
## The plants, 7 numbers each: model id, x, y, z (on the ground, FORMAT space), yaw, scale, mode (0 air, 1 planted).
@export var plants: PackedFloat32Array = PackedFloat32Array():
	set(value):
		plants = value
		_dirty()

static var _loaded := {}
static var _wind_shaders := {}
var _built := false


func _ready() -> void:
	set_notify_transform(true)
	rebuild()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and _built:
		rebuild()


func _dirty() -> void:
	if is_inside_tree():
		rebuild.call_deferred()


## The models by id.
func models_by_id() -> Dictionary:
	var d := {}
	for m in models:
		d[int(m["id"])] = m
	return d


## The plants as dictionaries ({model, p, yaw, scale, mode}).
func plant_list() -> Array:
	var out: Array = []
	for k in range(0, plants.size() - 6, 7):
		out.append(Foliage.plant_of(Array(plants.slice(k, k + 7))))
	return out


## How many plants of a model are drawn.
func drawn(id: int) -> int:
	for c in get_children(true):
		if c is MultiMeshInstance3D and c.get_meta("model", -1) == id:
			return (c as MultiMeshInstance3D).multimesh.instance_count
	return 0


func rebuild() -> void:
	for c in get_children(true):
		if c is MultiMeshInstance3D:
			c.queue_free()
			remove_child(c)
	_built = true
	var by_model := {}
	for pl in plant_list():
		if not by_model.has(pl["model"]):
			by_model[pl["model"]] = []
		(by_model[pl["model"]] as Array).append(pl)
	for m in models:
		var mine: Array = by_model.get(int(m["id"]), [])
		if mine.is_empty() or not m.get("mesh") is String:
			continue
		var d := load_model(str(m["mesh"]))
		if d.has("error"):
			push_warning("MarchingBlocks foliage: %s — %s" % [m["mesh"], d["error"]])
			continue
		for part in d["parts"]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = part[3]
			mm.instance_count = mine.size()
			var inst := instances(m, mine, part[1])
			for i in mine.size():
				mm.set_instance_transform(i, inst[0][i])
				mm.set_instance_custom_data(i, inst[1][i])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.set_meta("model", int(m["id"]))
			add_child(mmi, false, Node.INTERNAL_MODE_BACK)


## WHAT EACH PLANT GIVES THE MULTIMESH of a part: [poses, wind data]. The pose: the plant's (`Foliage.transform`), then
## the part's in the model. The wind: (ground, height above the ground, phase, amplitude) — the shader moves vertices in
## WORLD space, so the ground and the height are turned into Godot's world (this node's pose and scale).
func instances(m: Dictionary, plants_: Array, part_pose: Transform3D) -> Array:
	var g := global_transform if is_inside_tree() else transform
	var up := (g.basis * Vector3.UP).length()
	var poses: Array = []
	var wind: Array = []
	for pl in plants_:
		poses.append(Foliage.transform(m, pl) * part_pose)
		var w := Foliage.wind_of(m, pl)
		wind.append(Color((g * (pl["p"] as Vector3)).y, w.g * up, w.b, w.a))
	return [poses, wind]


## A model's parts: {"parts": [[mesh, pose in the model, materials, wind mesh]…]} or {"error"}. Cached by path.
static func load_model(path: String) -> Dictionary:
	if _loaded.has(path):
		return _loaded[path]
	var scene: Node = null
	if path.begins_with("res://") and ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		if packed != null:
			scene = packed.instantiate()
	if scene == null:
		if not FileAccess.file_exists(path):
			return {"error": "file not found"}
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(path, state) != OK:
			return {"error": "not a readable glTF file"}
		scene = doc.generate_scene(state)
		if scene == null:
			return {"error": "the file has no scene"}
	var d := {"parts": []}
	for n in _descendants(scene):
		var mesh = n.get("mesh") if n is Node3D else null
		if mesh is ImporterMesh:
			mesh = (mesh as ImporterMesh).get_mesh()
		if not mesh is Mesh or (mesh as Mesh).get_surface_count() == 0:
			continue
		var pose := Transform3D.IDENTITY
		var c: Node = n
		while c != null and c != scene:
			if c is Node3D:
				pose = (c as Node3D).transform * pose
			c = c.get_parent()
		var mats: Array = []
		var wind := ArrayMesh.new()
		for s in (mesh as Mesh).get_surface_count():
			var mat: Material = null
			if n is MeshInstance3D:
				mat = (n as MeshInstance3D).get_surface_override_material(s)
			if mat == null:
				mat = (mesh as Mesh).surface_get_material(s)
			mats.append(mat)
			wind.add_surface_from_arrays((mesh as Mesh).surface_get_primitive_type(s), (mesh as Mesh).surface_get_arrays(s))
			wind.surface_set_material(s, wind_material(mat))
		d["parts"].append([mesh, pose, mats, wind])
	scene.free()
	if d["parts"].is_empty():
		d = {"error": "the file has no mesh"}
	_loaded[path] = d
	return d


static func _descendants(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_descendants(c))
	return out


## The wind shader for a cull mode ("back", "disabled", "front") and a transparency ("opaque", "decoupe" — alpha
## scissor —, "melange" — blend): the tool's own, its two marks filled as the tool fills them.
static func wind_shader(cull: String, alpha: String) -> Shader:
	var key := cull + "|" + alpha
	if not _wind_shaders.has(key):
		var s := Shader.new()
		s.code = Shaders.WIND.replace("@CULL@", "cull_" + cull).replace("@ALPHA@", {
			"opaque": "",
			"decoupe": "ALPHA = c.a; ALPHA_SCISSOR_THRESHOLD = seuil_alpha;",
			"melange": "ALPHA = c.a;"}[alpha])
		_wind_shaders[key] = s
	return _wind_shaders[key]


## A surface's material, taken into the wind shader. A material that is not a standard one keeps its look, no wind.
static func wind_material(m: Material) -> Material:
	if m != null and not m is BaseMaterial3D:
		return m
	var s := m as BaseMaterial3D
	var cull := "back"
	var alpha := "opaque"
	if s != null:
		cull = {BaseMaterial3D.CULL_DISABLED: "disabled", BaseMaterial3D.CULL_FRONT: "front"}.get(s.cull_mode, "back")
		if s.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
			alpha = "decoupe"
		elif s.transparency in [BaseMaterial3D.TRANSPARENCY_ALPHA, BaseMaterial3D.TRANSPARENCY_ALPHA_HASH,
				BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS]:
			alpha = "melange"
	var v := ShaderMaterial.new()
	v.shader = wind_shader(cull, alpha)
	v.set_shader_parameter("sens_vent", Foliage.WIND_DIRECTION)
	if s == null:
		v.set_shader_parameter("albedo", Color(0.8, 0.8, 0.8))
		return v
	v.set_shader_parameter("albedo", s.albedo_color)
	v.set_shader_parameter("a_texture", s.albedo_texture != null)
	v.set_shader_parameter("tex_albedo", s.albedo_texture)
	v.set_shader_parameter("couleur_sommet", s.vertex_color_use_as_albedo)
	v.set_shader_parameter("rugosite", s.roughness)
	v.set_shader_parameter("a_rugosite", s.roughness_texture != null)
	v.set_shader_parameter("tex_rugosite", s.roughness_texture)
	v.set_shader_parameter("canal_rugosite", _channel(s.roughness_texture_channel))
	v.set_shader_parameter("metal", s.metallic)
	v.set_shader_parameter("a_metal", s.metallic_texture != null)
	v.set_shader_parameter("tex_metal", s.metallic_texture)
	v.set_shader_parameter("canal_metal", _channel(s.metallic_texture_channel))
	v.set_shader_parameter("a_normale", s.normal_enabled and s.normal_texture != null)
	v.set_shader_parameter("tex_normale", s.normal_texture)
	v.set_shader_parameter("force_normale", s.normal_scale)
	v.set_shader_parameter("seuil_alpha", s.alpha_scissor_threshold)
	return v


static func _channel(c: int) -> Vector4:
	return [Vector4(1, 0, 0, 0), Vector4(0, 1, 0, 0), Vector4(0, 0, 1, 0), Vector4(0, 0, 0, 1),
		Vector4(0.299, 0.587, 0.114, 0)][clampi(c, 0, 4)]

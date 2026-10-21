@tool
extends Node
## THE TRANSITIONS OF A WORLD — where two layers meet, the surface of one takes the look of the other, softly. A
## sibling of the MarchingBlocksWorld layers it blends (the import puts it there). The geometry never changes: a pass
## is laid OVER the tiles' materials (`next_pass`), the MarchingBlocks tool's own shader (`mb_transitions.gd`).
##
## It follows the layers: paint a cell, hide a layer, and the blend follows. Layer i of the world (the order of the
## siblings) is rank i of the rule; the first 255 layers blend.
## ⚠ The layers of one world are expected to share their pose and cell size (as the import makes them).

const Trans := preload("res://addons/marchingblocks_paint/mb_transitions.gd")
const Anim := preload("res://addons/marchingblocks_paint/mb_animation.gd")
const World := preload("res://addons/marchingblocks_paint/mb_world.gd")

## The pairs of layers, by index: [{a, b, active, a_covers_b: settings, b_covers_a: settings}] — settings
## {softness, reach, irregularity, grain, fills_hollows}.
@export var pairs: Array = []:
	set(value):
		pairs = value
		_signature = ""
## One per layer: {image: a PNG path (or null: plain colour), color: [r, g, b, a], scale, roughness}.
@export var representatives: Array = []:
	set(value):
		representatives = value
		_representatives_set = false
		_signature = ""
## The layer chosen to cover at a vertex, flat: x y z L per vertex.
@export var choices: PackedInt32Array = PackedInt32Array():
	set(value):
		choices = value
		_signature = ""
@export var enabled := true:
	set(value):
		enabled = value
		_signature = ""

var _material: ShaderMaterial
var _signature := ""
var _representatives_set := false
var _hooked: Array = []


func _ready() -> void:
	refresh()


## In the editor it follows every change; in a game, call `refresh()` after changing cells (painting a whole world
## each frame to watch it would cost more than the blend).
func _process(_delta: float) -> void:
	if (Engine.is_editor_hint() or _signature == "") and _current_signature() != _signature:
		refresh()


func _exit_tree() -> void:
	_unhook()


## The layers this node blends: its MarchingBlocksWorld siblings, in order.
func layers() -> Array:
	var parent := get_parent()
	if parent == null:
		return []
	return parent.get_children().filter(func(n: Node) -> bool: return n.get_script() == World)


## The pass laid over the tiles (null until the first refresh).
func material() -> ShaderMaterial:
	return _material


## The table of the active directions ({"C|D": settings}).
func table() -> Dictionary:
	return Trans.table(pairs, layers().size())


func _current_signature() -> String:
	var parts := PackedStringArray([str(enabled), str(get_parent().get_instance_id() if get_parent() else 0)])
	for l in layers():
		parts.append("%d|%d|%s|%s" % [l._cells_fingerprint(), l.get_instance_id(), l.visible,
			str((l._loaded as Dictionary).get("library", null))])
		parts.append(str(l.format_space()))
	return "#".join(parts)


## Rebuilds the cells texture, the table, and lays the pass over every layer's tiles.
func refresh() -> void:
	_signature = _current_signature()
	var ls := layers()
	var t := Trans.table(pairs, ls.size())
	if not enabled or t.is_empty() or ls.is_empty():
		_unhook()
		return
	if _material == null:
		_material = Trans.new_material()
	var union := {}
	for i in ls.size():
		if not (ls[i] as Node3D).visible:
			continue
		for c in ls[i].cells():
			union[c] = i
	var chosen := {}
	for k in range(0, choices.size() - 3, 4):
		chosen[Vector3i(choices[k], choices[k + 1], choices[k + 2])] = choices[k + 3]
	Trans.set_cells(_material, Trans.cell_texture(union, chosen))
	Trans.set_table(_material, t)
	if not _representatives_set:
		var reps: Array = []
		for r in representatives:
			var d: Dictionary = (r as Dictionary).duplicate()
			d["image"] = Anim._image(str(r["image"])) if r.get("image") is String else null
			reps.append(d)
		Trans.set_representatives(_material, reps, ls.size())
		_representatives_set = true
	_material.set_shader_parameter("mb_world_to_format", Projection(ls[0].format_space()))
	_unhook()
	for l in ls:
		for m in l.tile_materials():
			var mat := m as Material
			if mat.next_pass == null:
				mat.next_pass = _material
				_hooked.append(mat)


func _unhook() -> void:
	for m in _hooked:
		if is_instance_valid(m) and (m as Material).next_pass == _material:
			(m as Material).next_pass = null
	_hooked = []

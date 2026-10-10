@tool
extends RefCounted
## THE PLANT TOOL'S WORLD — what the foliage rule (`mb_foliage.gd`, proven by `foliage_conformance.json`) asks of a
## world painted with this plugin, and the three gestures of the Plant tool: one plant, a dab of the brush, erase.
##
## The rule reads the world through three questions (`check`, `brush`): is a cell FULL (every visible layer of the
## world), is there WATER at a point (the cells the world's MarchingBlocksWater nodes deduce), and where is the GROUND
## under a point. The ground is the one you SEE: a vertical ray against the triangles of the tiles the layers placed
## (what the rule says: « each engine looks for the ground by a vertical ray against ITS placed tile meshes »); where it
## meets none — a layer without tiles — the ground of the cells (`ground_of_cells`).
##
## Everything is in the CELL space of the layer being edited (cell c covers [c, c + 1]) — the FORMAT space of the plants.
## ⚠ The MarchingBlocksFoliage node must stand where the world's import put it (next to the layers, scaled by their cell
## size): its own space is format space. Moved apart from the layers, its plants are drawn apart too.
##
## Nothing here touches the scene: each gesture returns the plants as they should be, and the editor (`mb_editor.gd`)
## sets them in ONE undo step.

const Foliage := preload("res://addons/marchingblocks_paint/mb_foliage.gd")
const FoliageNode := preload("res://addons/marchingblocks_paint/mb_foliage_node.gd")
const WaterNode := preload("res://addons/marchingblocks_paint/mb_water_node.gd")
const Tools := preload("res://addons/marchingblocks_paint/mb_tools.gd")

const REACH := 2000.0
## The refusals, said on screen.
const REASONS := {"in_matter": "inside the matter", "too_steep": "the ground is too steep", "in_water": "in the water",
	"at_edge": "its footprint is not carried by the ground (an edge)",
	"under_matter": "the matter above leaves no room to grow", "too_close": "too close to another plant",
	"already_there": "a plant is already there", "no_ground": "no ground under it"}

## The triangles of a tile mesh, by mesh.
static var _faces := {}


## The MarchingBlocksFoliage node of a layer's world (a sibling of the layers), or null.
static func foliage_of(layer: Node) -> Node:
	if layer == null or layer.get_parent() == null:
		return null
	for n in layer.get_parent().get_children():
		if n.get_script() == FoliageNode:
			return n
	return null


## The models of a foliage node by id, every setting filled in (a hand-made model may lack some).
static func models_of(foliage: Node) -> Dictionary:
	var out := {}
	for m in foliage.models:
		var d: Dictionary = Foliage.MODEL_DEFAULTS.duplicate()
		d.merge(m, true)
		out[int(d["id"])] = d
	return out


## The matter of the world (every visible layer), enough to aim: {"full"}.
static func matter(layer: Node) -> Dictionary:
	var full := {}
	for l in layer.layers():
		if l.visible:
			full.merge(l.cells())
	return {"full": func(c: Vector3i) -> bool: return full.has(c)}


## WHAT THE RULE ASKS OF THIS WORLD, built once per gesture: {"full", "ground", "water"} (the rule's `world`), and
## "tiles" (how many tiles the ground is looked for on).
static func ask(layer: Node) -> Dictionary:
	var full := {}
	var columns := {}
	var tiles := 0
	var cs: float = layer.cell_size
	for l in layer.layers():
		if not l.visible:
			continue
		full.merge(l.cells())
		var grid := l.get_node_or_null("Tiles") as GridMap
		if grid == null or grid.mesh_library == null:
			continue
		# Tile local → its layer (the grid's offset, the tile's turn) → the edited layer (siblings) → cells (÷ cell size).
		var to_cells: Transform3D = Transform3D.IDENTITY.scaled(Vector3.ONE / cs) * layer.transform.affine_inverse() * l.transform
		for v in grid.get_used_cells():
			var mesh := grid.mesh_library.get_item_mesh(grid.get_cell_item(v))
			if mesh == null:
				continue
			var pose: Transform3D = to_cells * grid.transform * Transform3D(grid.get_cell_item_basis(v), grid.map_to_local(v))
			var box: AABB = pose * mesh.get_aabb()
			var tile := [pose, mesh]
			for x in range(floori(box.position.x), floori(box.end.x) + 1):
				for z in range(floori(box.position.z), floori(box.end.z) + 1):
					var k := Vector2i(x, z)
					if not columns.has(k):
						columns[k] = []
					(columns[k] as Array).append(tile)
			tiles += 1
	var water := {}
	if layer.get_parent() != null:
		for n in layer.get_parent().get_children():
			if n.get_script() == WaterNode and n.visible:
				water.merge(n.water_cells())
	var is_full := func(c: Vector3i) -> bool: return full.has(c)
	return {
		"full": is_full,
		"water": func(q: Vector3) -> bool: return water.has(Foliage.water_cell(q)),
		"ground": func(x: float, z: float, y_top: float) -> Variant: return ground(columns, is_full, x, z, y_top),
		"tiles": tiles,
		"cells": full,
	}


## THE GROUND under (x, z), below y_top: the highest triangle of a placed tile that a vertical ray meets, {y, normal}
## (the normal turned up); none met: the ground of the cells; nothing: null.
static func ground(columns: Dictionary, is_full: Callable, x: float, z: float, y_top: float) -> Variant:
	var best: Variant = null
	var from := Vector3(x, y_top, z)
	for tile in columns.get(Vector2i(floori(x), floori(z)), []):
		var pose: Transform3D = tile[0]
		var back := pose.affine_inverse()
		var o := back * from
		var d := back.basis * Vector3.DOWN
		var faces := _faces_of(tile[1])
		for i in range(0, faces.size(), 3):
			var hit = Geometry3D.ray_intersects_triangle(o, d, faces[i], faces[i + 1], faces[i + 2])
			if hit == null:
				continue
			var p := pose * (hit as Vector3)
			if p.y > y_top or p.y < Foliage.GROUND_SEARCH_FLOOR or (best != null and p.y <= float(best["y"])):
				continue
			var n := (pose.basis.inverse().transposed() * (faces[i + 1] - faces[i]).cross(faces[i + 2] - faces[i])).normalized()
			best = {"y": p.y, "normal": n if n.y >= 0.0 else -n}
	if best != null:
		return best
	return Foliage.ground_of_cells(is_full, x, z, y_top)


static func _faces_of(mesh: Mesh) -> PackedVector3Array:
	if not _faces.has(mesh):
		_faces[mesh] = mesh.get_faces()
	return _faces[mesh]


## WHERE A RAY (in cells) MEETS THE WORLD for a mode: in the air, the plane of the floor; planted, the matter (the face
## the ray enters by, the exact point on it). null: nowhere.
static func aimed_point(asked: Dictionary, origin: Vector3, direction: Vector3, mode: String, floor_y: int) -> Variant:
	if direction.length_squared() < 1e-12:
		return null
	if mode == "air":
		if absf(direction.y) < 1e-9:
			return null
		var t := (float(floor_y) - origin.y) / direction.y
		return null if t <= 0.0 else origin + direction * t
	var r := Tools.ray(asked["full"], origin, direction, REACH)
	if not r["hit"]:
		return null
	var n: Vector3i = r["normal"]
	var c: Vector3i = r["cell"]
	var axis := 0 if n.x != 0 else (1 if n.y != 0 else 2)
	var plane := float(c[axis] + (1 if n[axis] > 0 else 0))
	var dn := direction.normalized()
	if absf(dn[axis]) < 1e-12:
		return null
	var p := origin + dn * ((plane - origin[axis]) / dn[axis])
	p[axis] = plane
	return p


## A refusal said in words.
static func reason(code: String) -> String:
	return REASONS.get(code, "refused")


## ONE PLANT where the ray points: {"plants": the new flat list (or null: nothing changed), "status", "reason"}.
## `settings`: {model, mode, spacing, max_slope, random_yaw}; `draw`: a RandomNumberGenerator (yaw, then scale).
static func plant_at(layer: Node, foliage: Node, origin: Vector3, direction: Vector3, settings: Dictionary,
		draw: RandomNumberGenerator, asked: Dictionary = {}) -> Dictionary:
	var models := models_of(foliage)
	var id := int(settings["model"])
	if not models.has(id):
		return {"plants": null, "status": "Plant — choose a model (the foliage of this world has none).", "reason": "no_model"}
	var m: Dictionary = models[id]
	var mode: String = settings["mode"]
	if asked.is_empty():
		asked = ask(layer)
	var aim = aimed_point(asked, origin, direction, mode, layer.floor_y)
	if aim == null:
		return {"plants": null, "status": "Plant — point at the world.", "reason": "no_ground"}
	var p: Vector3 = aim
	var normal := Vector3.UP
	if mode != "air":
		var g = (asked["ground"] as Callable).call(p.x, p.z, p.y + 1.0)
		if g == null:
			return {"plants": null, "status": "Plant — not planted: no ground under it.", "reason": "no_ground"}
		p.y = float(g["y"])
		normal = g["normal"]
	var a := clampf(float(m["scale_random"]), 0.0, 0.9)
	var yaw := draw.randf() * TAU if settings["random_yaw"] else 0.0
	var scale := 1.0 + (draw.randf() * 2.0 - 1.0) * a
	var pl := Foliage.plant(id, p, yaw, scale, mode)
	var there: Array = foliage.plant_list()
	var ix := Foliage.index(there, models)
	var why := Foliage.check(m, pl, normal, mode, asked, ix, models, float(settings["spacing"]),
		float(settings["max_slope"]))
	if why != "":
		return {"plants": null, "status": "Plant — not planted: %s." % reason(why), "reason": why}
	var out: PackedFloat32Array = foliage.plants.duplicate()
	out.append_array(_row(pl))
	return {"plants": out, "status": "Plant — planted (%d plant(s))." % (out.size() / 7), "reason": ""}


## A DAB OF THE BRUSH around the point the ray meets: `tries` candidates drawn in the disc (angle, distance, yaw,
## scale — the tool's order), each put on the ground and checked; accepted ones respect each other.
static func sow_at(layer: Node, foliage: Node, origin: Vector3, direction: Vector3, settings: Dictionary,
		draw: RandomNumberGenerator, asked: Dictionary = {}) -> Dictionary:
	var models := models_of(foliage)
	var id := int(settings["model"])
	if not models.has(id):
		return {"plants": null, "status": "Plant — choose a model (the foliage of this world has none).", "planted": 0}
	var m: Dictionary = models[id]
	var mode: String = settings["mode"]
	if asked.is_empty():
		asked = ask(layer)
	var aim = aimed_point(asked, origin, direction, mode, layer.floor_y)
	if aim == null:
		return {"plants": null, "status": "Plant — point at the world.", "planted": 0}
	var centre: Vector3 = aim
	var a := clampf(float(m["scale_random"]), 0.0, 0.9)
	var radius := float(settings["radius"])
	var candidates: Array = []
	for i in int(settings["tries"]):
		var angle := draw.randf() * TAU
		var d := sqrt(draw.randf()) * radius
		var yaw := draw.randf() * TAU if settings["random_yaw"] else 0.0
		var scale := 1.0 + (draw.randf() * 2.0 - 1.0) * a
		candidates.append([centre.x + cos(angle) * d, centre.z + sin(angle) * d, yaw, scale])
	# The ground is looked for below the dab (planted), or the plane itself (in the air).
	var y_top := centre.y if mode == "air" else centre.y + 1.5
	var ix := Foliage.index(foliage.plant_list(), models)
	var r := Foliage.brush(m, y_top, candidates, mode, asked, ix, models, float(settings["spacing"]),
		float(settings["max_slope"]))
	var refused: Array = []
	for why in r["refused"]:
		refused.append("%d %s" % [int(r["refused"][why]), why.replace("_", " ")])
	var said := "" if refused.is_empty() else ", refused: " + ", ".join(refused)
	if (r["plants"] as Array).is_empty():
		return {"plants": null, "status": "Plant — nothing planted in this dab%s." % said, "planted": 0}
	var out: PackedFloat32Array = foliage.plants.duplicate()
	for pl in r["plants"]:
		out.append_array(_row(pl))
	return {"plants": out, "status": "Plant — %d planted%s." % [(r["plants"] as Array).size(), said],
		"planted": (r["plants"] as Array).size()}


## ERASE around the point the ray meets: the plants within the radius in the plane, within radius + 2 in height and
## radius + 0.5 in space (the tool's rule).
static func erase_at(layer: Node, foliage: Node, origin: Vector3, direction: Vector3, settings: Dictionary,
		asked: Dictionary = {}) -> Dictionary:
	if asked.is_empty():
		asked = ask(layer)
	var aim = aimed_point(asked, origin, direction, settings["mode"], layer.floor_y)
	if aim == null:
		return {"plants": null, "status": "Plant — point at the world.", "removed": 0}
	var centre: Vector3 = aim
	var radius := float(settings["radius"])
	var out := PackedFloat32Array()
	var removed := 0
	for pl in foliage.plant_list():
		var q: Vector3 = pl["p"]
		if Vector2(q.x - centre.x, q.z - centre.z).length() <= radius and absf(q.y - centre.y) <= radius + 2.0 \
				and q.distance_to(centre) <= radius + 0.5:
			removed += 1
			continue
		out.append_array(_row(pl))
	if removed == 0:
		return {"plants": null, "status": "Plant — no plant within the brush to erase.", "removed": 0}
	return {"plants": out, "status": "Plant — %d removed, %d left." % [removed, out.size() / 7], "removed": removed}


## A plant as its seven numbers.
static func _row(pl: Dictionary) -> PackedFloat32Array:
	var p: Vector3 = pl["p"]
	return PackedFloat32Array([pl["model"], p.x, p.y, p.z, pl["yaw"], pl["scale"], 0 if pl["mode"] == "air" else 1])

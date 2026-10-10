@tool
extends Node3D
## A MARCHINGBLOCKS WORLD LAYER — you paint CELLS, the tiles follow.
##
##   Cells   the GridMap you paint, with Godot's own GridMap editor: one palette item, "cell".
##   Tiles   what the rule places, half a cell further — never edit it, it is rebuilt from Cells.
##   Errors  red cubes where the tileset lacks the tile the rule asks for. Nothing is ever filled in:
##           a hole must be seen where it happens.
##
## One node is one LAYER, with its own tileset. Sibling MarchingBlocksWorld nodes under the same parent are
## the layers of ONE world (rock, ice…), and their order among the children is their PRIORITY (the first is
## the highest). The rule reads every visible layer together — no wall where two layers meet — and a vertex
## is placed by the highest layer among its 8 cells, with that layer's tiles. A cell belongs to one layer:
## painting it in one layer removes it from the others. Hide a layer and the world closes without it.

const Rule := preload("res://addons/marchingblocks_paint/mb_rule.gd")
const Tileset := preload("res://addons/marchingblocks_paint/mb_tileset.gd")

## The tileset: the `tileset.json` inside a `.mbset` folder made by MarchingBlocks.
@export_file("*.json") var tileset := "":
	set(value):
		tileset = value
		_loaded = {}
		rebuild()

@export var cell_size := 1.0:
	set(value):
		cell_size = maxf(0.01, value)
		_place_grids()
		rebuild()

## Rebuild while painting in the editor. Turn off for huge maps and call rebuild() yourself.
@export var live_update := true

## The floor the Grid aim paints on, in cells (Page Up / Page Down with the MarchingBlocks toolbar).
@export var floor_y := 0

## VARIANTS (the tileset rule, step 8) — only for a tileset whose keys have variants.
## The weights of the random draw, per key: key -> [base weight, variant 1, variant 2, …] (integers; a missing
## entry is 1, a negative one 0). Same world, same tiles: the draw is a hash of the vertex, never random.
@export var variant_weights: Dictionary = {}:
	set(value):
		variant_weights = value
		rebuild()

## The variant CHOSEN at a vertex: Vector3i -> 0 (the base tile), 1, 2… The Variant tool sets it.
@export var variant_choices: Dictionary = {}:
	set(value):
		variant_choices = value
		rebuild()

var _loaded := {}
var _fingerprint := -1
var _last := {"tiles": 0, "missing": 0, "error": ""}


func _ready() -> void:
	_build_children()
	rebuild()
	set_notify_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_update_format_space()


## Godot's world → FORMAT space (cell c covers [c, c + 1], the tile of vertex v centred on v + piece_offset): the
## inverse of this node's pose, divided by the cell size. The animated tiles read their phase in it.
func format_space() -> Transform3D:
	var t := global_transform if is_inside_tree() else transform
	return t.affine_inverse().scaled(Vector3.ONE / cell_size)


## The materials of the tiles this layer places, its OWN copies (`Tileset.own`): what the transitions pass is laid
## over. [] without a tileset.
func tile_materials() -> Array:
	if _loaded.is_empty() or _loaded.has("error"):
		return []
	var library: MeshLibrary = _loaded["library"]
	Tileset.own(library)
	var out: Array = []
	for id in library.get_item_list():
		var mesh := library.get_item_mesh(id)
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s)
			if m != null and not out.has(m):
				out.append(m)
	return out


## Every animated material of this layer learns where the layer stands.
func _update_format_space() -> void:
	if _loaded.is_empty() or _loaded.has("error") or int(_loaded.get("animated", 0)) == 0:
		return
	var f := Projection(format_space())
	var library: MeshLibrary = _loaded["library"]
	for id in library.get_item_list():
		var mesh := library.get_item_mesh(id)
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s)
			if m is ShaderMaterial and m.has_meta("mb_animation"):
				(m as ShaderMaterial).set_shader_parameter("mb_world_to_format", f)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and live_update and _world_fingerprint() != _fingerprint:
		rebuild()


## The layers of this node's world, in priority order: the MarchingBlocksWorld siblings (this node
## included) under the same parent; just this node when it has no parent.
func layers() -> Array:
	var parent := get_parent()
	if parent == null:
		return [self]
	var out: Array = []
	for n in parent.get_children():
		if n.get_script() == get_script():
			out.append(n)
	return out


## What the last rebuild did: {"tiles", "missing", "error"}.
func last_report() -> Dictionary:
	return _last


func rebuild() -> Dictionary:
	if not is_inside_tree() and get_node_or_null("Cells") == null:
		return _last
	_build_children()
	var tiles_grid := get_node("Tiles") as GridMap
	var errors := get_node("Errors") as GridMap
	tiles_grid.clear()
	errors.clear()
	_fingerprint = _world_fingerprint()
	if tileset == "":
		_last = {"tiles": 0, "missing": 0, "error": "no tileset chosen"}
		return _last
	if _loaded.is_empty():
		_loaded = Tileset.load_tileset(tileset)
	if _loaded.has("error"):
		_last = {"tiles": 0, "missing": 0, "error": _loaded["error"]}
		push_warning("MarchingBlocks: " + _loaded["error"])
		return _last
	var library: MeshLibrary = _loaded["library"]
	tiles_grid.mesh_library = library
	_update_format_space()
	var ids := {}
	for id in library.get_item_list():
		ids[library.get_item_name(id)] = id
	# Step 7: the rule reads EVERY layer of the world; this node keeps the vertices it owns.
	var all_layers := layers()
	var mine := all_layers.find(self)
	var described: Array = []
	for l in all_layers:
		var own: bool = l == self
		described.append({"cells": l.cells(), "visible": l.visible,
			"tiles": _loaded["manifest"].get("tiles", {}) if own else {},
			"variants": _loaded["manifest"].get("variants", {}) if own else {},
			"weights": variant_weights if own else {}, "choices": variant_choices if own else {}})
	var orientation := []
	for q in 4:
		orientation.append(tiles_grid.get_orthogonal_index_from_basis(Basis(Vector3.UP, q * PI / 2.0)))
	var placed := 0
	var missing := 0
	for p in Rule.placements_layered(described, _loaded["manifest"])[mine]:
		var v := Vector3i(p[0], p[1], p[2])
		if p[3] == null or not ids.has(p[3]):
			errors.set_cell_item(v, 0)
			missing += 1
			continue
		tiles_grid.set_cell_item(v, ids[p[3]], orientation[int(p[4]) % 4])
		placed += 1
	_last = {"tiles": placed, "missing": missing, "error": ""}
	return _last


## The number of variants of the tile placed at vertex v (0: none, or nothing placed), and which one it is:
## {"key", "variants", "current"} — {} when nothing of this layer is placed there.
func variant_at(v: Vector3i) -> Dictionary:
	if _loaded.is_empty() or _loaded.has("error"):
		return {}
	var tiles_grid := get_node_or_null("Tiles") as GridMap
	if tiles_grid == null or tiles_grid.get_cell_item(v) == GridMap.INVALID_CELL_ITEM:
		return {}
	var placed := tiles_grid.mesh_library.get_item_name(tiles_grid.get_cell_item(v))
	var manifest: Dictionary = _loaded["manifest"]
	for key in manifest.get("tiles", {}):
		var list: Array = manifest.get("variants", {}).get(key, [])
		if str(manifest["tiles"][key]) == placed:
			return {"key": key, "variants": list.size(), "current": 0}
		var i := list.find(placed)
		if i >= 0:
			return {"key": key, "variants": list.size(), "current": i + 1}
	return {}


## The painted cells, {Vector3i: true} — read from the Cells grid, the only truth.
func cells() -> Dictionary:
	var d := {}
	var grid := get_node_or_null("Cells") as GridMap
	if grid != null:
		for c in grid.get_used_cells():
			d[c] = true
	return d


## Applies what a tool returned: clears, then sets, then rebuilds the world once. Arrays or Dictionaries of
## Vector3i. The editor calls it from its undo actions — undoing is apply_cells(clear, set).
## A cell belongs to ONE layer: the cells it sets are removed from the other layers of the world. Returns
## what was taken, {layer node: [cells]}, so that the same undo step can give it back.
func apply_cells(set_cells: Variant, clear_cells: Variant) -> Dictionary:
	_build_children()
	var grid := get_node("Cells") as GridMap
	for c in clear_cells:
		grid.set_cell_item(c, GridMap.INVALID_CELL_ITEM)
	for c in set_cells:
		grid.set_cell_item(c, 0)
	var taken := taken_from_others(set_cells)
	for l in taken:
		var g := l.get_node("Cells") as GridMap
		for c in taken[l]:
			g.set_cell_item(c, GridMap.INVALID_CELL_ITEM)
	for l in layers():
		l.rebuild()
	return taken


## The cells among `set_cells` that OTHER layers of the world hold: {layer node: [cells]}.
func taken_from_others(set_cells: Variant) -> Dictionary:
	var taken := {}
	for l in layers():
		if l == self or l.get_node_or_null("Cells") == null:
			continue
		var g := l.get_node("Cells") as GridMap
		for c in set_cells:
			if g.get_cell_item(c) != GridMap.INVALID_CELL_ITEM:
				if not taken.has(l):
					taken[l] = []
				taken[l].append(c)
	return taken


## A world-space point or direction in CELL space (cell c covers [c, c+1]).
func world_to_cells(p: Vector3) -> Vector3:
	return (global_transform.affine_inverse() * p) / cell_size


func world_direction_to_cells(d: Vector3) -> Vector3:
	return (global_transform.affine_inverse().basis * d) / cell_size


## The cell of the floor plane under a world ray, or null.
func cell_under_ray(origin: Vector3, direction: Vector3) -> Variant:
	var o := world_to_cells(origin)
	var d := world_direction_to_cells(direction)
	if absf(d.y) < 1e-6:
		return null
	var t := (floor_y - o.y) / d.y
	if t <= 0.0:
		return null
	var hit := o + d * t
	# Cell c covers [c, c+1]: the FLOOR of the hit, never a rounding.
	return Vector3i(floori(hit.x), floor_y, floori(hit.z))


func _build_children() -> void:
	for n in ["Cells", "Tiles", "Errors"]:
		if get_node_or_null(n) == null:
			var g := GridMap.new()
			g.name = n
			add_child(g)
			if Engine.is_editor_hint() and is_inside_tree() and get_tree().edited_scene_root != null:
				g.owner = get_tree().edited_scene_root
	var cells := get_node("Cells") as GridMap
	if cells.mesh_library == null:
		cells.mesh_library = _palette("cell", Color(0.45, 0.62, 0.95, 0.22))
	var errors := get_node("Errors") as GridMap
	if errors.mesh_library == null:
		errors.mesh_library = _palette("missing", Color(0.9, 0.2, 0.15, 0.7))
	_place_grids()


## The piece of vertex v sits at (v + piece_offset) * cell_size. A GridMap centres item v at
## (v + 0.5) * cell_size, so the Tiles and Errors grids are shifted by (piece_offset - 0.5) cells.
func _place_grids() -> void:
	var offset := Vector3.ONE
	if not _loaded.is_empty() and _loaded.has("manifest"):
		var o: Array = _loaded["manifest"].get("piece_offset", [1, 1, 1])
		offset = Vector3(float(o[0]), float(o[1]), float(o[2]))
	for n in ["Cells", "Tiles", "Errors"]:
		var g := get_node_or_null(n) as GridMap
		if g != null:
			g.cell_size = Vector3.ONE * cell_size
			g.position = Vector3.ZERO if n == "Cells" else (offset - Vector3.ONE * 0.5) * cell_size


static func _palette(item_name: String, colour: Color) -> MeshLibrary:
	var lib := MeshLibrary.new()
	var box := BoxMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = colour
	box.material = m
	lib.create_item(0)
	lib.set_item_name(0, item_name)
	lib.set_item_mesh(0, box)
	return lib


## Every layer's cells and visibility, and their order: any of them changes what this layer places.
func _world_fingerprint() -> int:
	var h := 0
	for l in layers():
		h = (h * 131 + l._cells_fingerprint() * 2 + (1 if l.visible else 0)) & 0x7FFFFFFF
	return h


func _cells_fingerprint() -> int:
	var cells := get_node_or_null("Cells") as GridMap
	if cells == null:
		return -1
	var h := 0
	for c in cells.get_used_cells():
		h = (h * 31 + c.x * 73856093 + c.y * 19349663 + c.z * 83492791) & 0x7FFFFFFF
	return h * 31 + cells.get_used_cells().size()

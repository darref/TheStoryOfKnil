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

## Rebuild while painting in the editor. Turn off for huge maps and call rebuild_world() yourself.
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

## TRIPLANAR TEXTURES — on by default (20 October 2026). The file's UVs are a box projection chosen FACE BY FACE (the
## face's dominant axis): exact on flat ground, but on a sculpted, curved tile (a bump, a rounded rock) the axis changes
## from one face to the next and the texture breaks into patches — seen from above, square "pixels" (WaterDrop, seen and
## measured). On, every box-projected material of the layer blends the three projections in WORLD space, at the same
## repeat as the file's (cells per repeat, read back from its UVs, × this layer's cell size and scale): seamless from tile
## to tile and from layer to layer, whatever the quarter turn. Off: the file's UVs, as before.
@export var triplanar := true:
	set(value):
		triplanar = value
		_update_triplanar()

var _loaded := {}
var _fingerprint := -1
var _built_frame := -1
var _last := {"tiles": 0, "missing": 0, "error": ""}


func _ready() -> void:
	_build_children()
	# The first layer to be ready builds the WHOLE world in one pass; its siblings, built in the same frame, skip.
	if _built_frame != Engine.get_process_frames():
		rebuild_world()
	set_notify_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_update_format_space()
		_update_triplanar()


## The triplanar settings of every box-projected material of this layer (`triplanar`). The materials are this layer's
## OWN copies (`Tileset.own`): another layer, another world loading the same file keeps its own.
func _update_triplanar() -> void:
	if _loaded.is_empty() or _loaded.has("error"):
		return
	var library: MeshLibrary = _loaded["library"]
	Tileset.own(library)
	var t := global_transform if is_inside_tree() else transform
	var cell := cell_size * t.basis.get_scale().x
	var done := {}
	for id in library.get_item_list():
		var mesh := library.get_item_mesh(id)
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s)
			if not m is BaseMaterial3D or done.has(m):
				continue
			done[m] = true
			if not m.has_meta("mb_repeat"):
				m.set_meta("mb_repeat", Tileset.repeat_of(mesh, s))
			var repeat := float(m.get_meta("mb_repeat"))
			var on := triplanar and repeat > 0.0
			(m as BaseMaterial3D).uv1_triplanar = on
			(m as BaseMaterial3D).uv1_world_triplanar = on
			(m as BaseMaterial3D).uv1_triplanar_sharpness = 4.0
			(m as BaseMaterial3D).uv1_scale = Vector3.ONE / (repeat * cell) if on else Vector3.ONE


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
		rebuild_world()


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


## Rebuilds THIS layer's tiles. To rebuild every layer of the world (after a change to the cells, at load), call
## `rebuild_world()`: the rule reads all the layers anyway, and one pass serves them all.
func rebuild() -> Dictionary:
	return _rebuild_layers([self]).get(self, _last)


## Rebuilds EVERY layer of this world in ONE pass of the rule: {layer node: its report}. The rule always reads all the
## layers and returns one list per layer; rebuilding them one by one ran the same pass once per layer and threw away
## all lists but one (17 passes of ~2.9 s for a 17-layer world of 331 467 cells, measured in WaterDrop, 20 October
## 2026). The lists are the same: each layer gets exactly what its own pass gave it.
func rebuild_world() -> Dictionary:
	return _rebuild_layers(layers())


func _rebuild_layers(targets: Array) -> Dictionary:
	var reports := {}
	var all_layers := layers()
	var fingerprint := _world_fingerprint()
	var frame := Engine.get_process_frames()
	# The layers sharing a rule (the same corners, table, classes and context) are placed in one pass. A world's
	# tilesets share one by contract (`Rule.placements_layered`); a stray one gets its own pass.
	var groups := {}
	for l in targets:
		if not l.is_inside_tree() and l.get_node_or_null("Cells") == null:
			reports[l] = l._last
			continue
		var r: Dictionary = l._prepare(fingerprint)
		l._built_frame = frame
		if not r.is_empty():
			l._last = r
			reports[l] = r
			continue
		var m: Dictionary = l._loaded["manifest"]
		var key: int = [m.get("corners"), m.get("table"), m.get("classes"), m.get("context")].hash()
		if not groups.has(key):
			groups[key] = []
		groups[key].append(l)
	var cells := {}
	for key in groups:
		var group: Array = groups[key]
		var file := ""
		var packed: Array = []
		if tile_cache_dir != "":
			file = tile_cache_dir.path_join("%08x.bin" % _cache_key(all_layers, group, fingerprint))
			packed = _read_tile_cache(file, all_layers.size())
		if packed.is_empty():
			if cells.is_empty():
				for l in all_layers:
					cells[l] = l.cells()
			var described: Array = []
			for l in all_layers:
				var own: bool = group.has(l)
				var m: Dictionary = l._loaded["manifest"] if own else {}
				described.append({"cells": cells[l], "visible": l.visible,
					"tiles": m.get("tiles", {}), "variants": m.get("variants", {}),
					"weights": l.variant_weights if own else {}, "choices": l.variant_choices if own else {}})
			for out in Rule.placements_layered(described, group[0]._loaded["manifest"]):
				packed.append(_pack(out))
			if file != "":
				_write_tile_cache(file, packed)
		for l in group:
			reports[l] = l._place(packed[all_layers.find(l)])
	return reports


## THE TILE CACHE — opt-in, for a GAME: set this to a folder (e.g. "user://marchingblocks_tiles") and the rule's
## result is kept there, keyed by everything that changes it (every layer's cells, visibility and order, each tileset
## and its file date, the variant weights and choices). A world met again lays its tiles from the cache instead of
## running the rule (2.5 s for a world of 331 467 cells, measured in WaterDrop, 20 October 2026). Empty: no cache —
## the editor's default, where the cells change all the time.
static var tile_cache_dir := ""
## Bumped whenever the rule or the cache's layout changes: every older cache is ignored.
const TILE_CACHE_VERSION := 1


func _cache_key(all_layers: Array, group: Array, fingerprint: int) -> int:
	var parts: Array = [TILE_CACHE_VERSION, fingerprint]
	for l in all_layers:
		var own: bool = group.has(l)
		parts.append([l.visible, (l.get_node("Cells") as GridMap).get_used_cells().size(), l.tileset if own else "",
			FileAccess.get_modified_time(l.tileset) if own and l.tileset != "" else 0,
			l.variant_weights if own else {}, l.variant_choices if own else {}])
	return parts.hash()


static func _read_tile_cache(file: String, layer_count: int) -> Array:
	if not FileAccess.file_exists(file):
		return []
	var f := FileAccess.open(file, FileAccess.READ)
	if f == null:
		return []
	var d = f.get_var()
	if not d is Array or (d as Array).size() != 2 or d[0] != TILE_CACHE_VERSION or not d[1] is Array \
			or (d[1] as Array).size() != layer_count:
		return []
	return d[1]


static func _write_tile_cache(file: String, packed: Array) -> void:
	DirAccess.make_dir_recursive_absolute(file.get_base_dir())
	var f := FileAccess.open(file, FileAccess.WRITE)
	if f != null:
		f.store_var([TILE_CACHE_VERSION, packed])


## A layer's placements, packed: [PackedInt32Array of x, y, z, tile index (-1: none), quarter turns ; PackedStringArray
## of the tile names] — what the cache keeps, and what `_place` lays.
static func _pack(placements: Array) -> Array:
	var ints := PackedInt32Array()
	ints.resize(placements.size() * 5)
	var names := PackedStringArray()
	var index := {}
	var k := 0
	for p in placements:
		var n := -1
		if p[3] != null:
			if not index.has(p[3]):
				index[p[3]] = names.size()
				names.append(str(p[3]))
			n = index[p[3]]
		ints[k] = p[0]
		ints[k + 1] = p[1]
		ints[k + 2] = p[2]
		ints[k + 3] = n
		ints[k + 4] = int(p[4])
		k += 5
	return [ints, names]


## Empties the Tiles and Errors grids and loads the tileset: {} when the layer can be placed, else its report.
func _prepare(fingerprint: int) -> Dictionary:
	_build_children()
	(get_node("Tiles") as GridMap).clear()
	(get_node("Errors") as GridMap).clear()
	_fingerprint = fingerprint
	if tileset == "":
		return {"tiles": 0, "missing": 0, "error": "no tileset chosen"}
	# An EMPTY layer places nothing: its tileset waits for its first cell (11 of the 17 layers of a generated island
	# are empty, ~0.1 s of loading each — measured in WaterDrop, 20 October 2026).
	if (get_node("Cells") as GridMap).get_used_cells().is_empty() and _loaded.is_empty():
		return {"tiles": 0, "missing": 0, "error": ""}
	if _loaded.is_empty():
		_loaded = Tileset.load_tileset(tileset)
	if _loaded.has("error"):
		push_warning("MarchingBlocks: " + _loaded["error"])
		return {"tiles": 0, "missing": 0, "error": _loaded["error"]}
	(get_node("Tiles") as GridMap).mesh_library = _loaded["library"]
	_update_format_space()
	_update_triplanar()
	return {}


## Lays this layer's placements (packed by `_pack`) into Tiles, or Errors.
func _place(packed: Array) -> Dictionary:
	var tiles_grid := get_node("Tiles") as GridMap
	var errors := get_node("Errors") as GridMap
	var library: MeshLibrary = _loaded["library"]
	var ids := {}
	for id in library.get_item_list():
		ids[library.get_item_name(id)] = id
	var orientation := []
	for q in 4:
		orientation.append(tiles_grid.get_orthogonal_index_from_basis(Basis(Vector3.UP, q * PI / 2.0)))
	var ints: PackedInt32Array = packed[0]
	var names: PackedStringArray = packed[1]
	var item := PackedInt32Array()   # tile index → library item (-1: the tileset lacks it)
	for name in names:
		item.append(int(ids.get(name, -1)))
	var placed := 0
	var missing := 0
	for k in range(0, ints.size(), 5):
		var v := Vector3i(ints[k], ints[k + 1], ints[k + 2])
		var n := ints[k + 3]
		if n < 0 or item[n] < 0:
			errors.set_cell_item(v, 0)
			missing += 1
			continue
		tiles_grid.set_cell_item(v, item[n], orientation[ints[k + 4] % 4])
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
	rebuild_world()
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

@tool
extends Node3D
## A WATER LAYER OF A WORLD — the water sheet MarchingBlocks baked (`water/<name>.glb`, in FORMAT space: the import
## scales this node by the layers' cell size), drawn with a material: YOURS if you set one, otherwise the example look
## the world suggests. The six looks shipped with the plugin are EXAMPLES, not an obligation — any water shader gets
## the data: COLOR_0 r, g the flow along x and z ([-1, 1] mapped to [0, 1]); b the kind (0 still, 0.5 river, 0.75
## foam, 1 waterfall); a the depth / 8 (still water and rivers) or the amount of foam (waterfalls, foam); NORMAL the
## shape (a waterfall is a curved, closed sheet); TEXCOORD_0.
##
## THE WATER FOLLOWS THE CELLS. The water is deduced from the sources of every water layer and the cells of every tile
## layer of the world, hidden ones too (`mb_water.gd`, the rule of the tool), and its sheet is rebuilt from it
## (`mb_water_mesh.gd`, the tool's mesher) — the same sheet MarchingBlocks bakes:
##   - NEVER DURING A STROKE: while you paint, the sheet stays as it was and says it is STALE;
##   - once the cells have been still for REBUILD_DELAY (and no mouse button is held), the water is recomputed on a
##     WORKER THREAD from a copy of the cells, reusing what did not change (the bodies whose footprint holds no changed
##     cell, the sheets of a layer whose bodies were all reused, the waterfalls and springs that did not move), and the
##     new sheet is swapped in on the main thread;
##   - "Rebuild water" (in the inspector) always rebuilds;
##   - if a rebuild after a stroke took longer than `auto_limit` (a huge sea, in GDScript), the automatic rebuild PAUSES
##     itself: the sheet stays stale until you press "Rebuild water" (a fast rebuild resumes it).
## All water layers of a world are computed together (the sea is the first source in the void among all of them): the
## first water layer among its siblings leads.

const Water := preload("res://addons/marchingblocks_paint/mb_water.gd")
const WaterMesh := preload("res://addons/marchingblocks_paint/mb_water_mesh.gd")
const Shaders := preload("res://addons/marchingblocks_paint/mb_shaders.gd")
const World := preload("res://addons/marchingblocks_paint/mb_world.gd")

## Cells still for this long (ms) after a stroke before the water is recomputed.
const REBUILD_DELAY := 500

## The baked sheet: a .glb path (res://…), or "" (nothing to draw).
@export_file("*.glb") var mesh_path := "":
	set(value):
		mesh_path = value
		_dirty()
## The look the world suggests: stylized, clear, reflective, lava, swamp or acid (an unknown one: stylized).
@export var look := "stylized":
	set(value):
		look = value
		_dirty()
## Your own water material. Empty: the example look above.
@export var material: Material:
	set(value):
		material = value
		_dirty()
## Where the water was placed: [x, y, z] per source, FORMAT space.
@export var sources: Array = []
## Where the ground of the tiles is drawn, for the heights of the water (world.json `water_floor`): 0.25 inset, 0
## centred, -0.25 outset (the first water layer's value).
@export_enum("Inset:0", "Centred:1", "Outset:2") var floor_kind := 0
const FLOORS := [0.25, 0.0, -0.25]


## The floor r of `floor_kind`.
func water_floor() -> float:
	return FLOORS[clampi(floor_kind, 0, 2)]
## The tile cells the baked sheet was made for (a fingerprint, set at import); 0: unknown.
@export var baked_for := 0
## In the editor, rebuild the sheet by itself after each stroke (all water layers of the world: any one asks for all).
@export var auto_rebuild := true:
	set(value):
		auto_rebuild = value
		update_configuration_warnings()
## A rebuild after a stroke slower than this (seconds) pauses the automatic rebuild (the first water layer's value).
@export var auto_limit := 1.0
## Rebuild the water now (all water layers of this world), even when the automatic rebuild paused itself.
@export_tool_button("Rebuild water", "Reload") var rebuild_water_button := rebuild_water

var _sheet: MeshInstance3D
## The sheet rebuilt here (null: the baked one is shown), and the cells (fingerprint) the shown sheet was made for.
var _rebuilt: ArrayMesh
var _shown_for := 0
var _shown_known := false
## THE LEADER'S STATE (the first water layer of the world):
##   _base — the last computation {cells, world, memories, arrays, fingerprint}: what the next one reuses;
##   _job — the computation running on a worker thread (or {}), _task its id;
##   _seen — the hash of the cells last seen, _changed_at — when they last changed (ms), _pending — to recompute;
##   paused — the automatic rebuild paused itself; last_seconds / last_reused — the last rebuild, measured.
var _base := {}
var _job := {}
var _task := -1
var _seen := -1
var _changed_at := 0
var _pending := false
var paused := false
var last_seconds := 0.0
var last_reused := ""
static var _looks := {}


func _ready() -> void:
	rebuild()


func _exit_tree() -> void:
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_job = {}


func _dirty() -> void:
	if is_inside_tree():
		rebuild.call_deferred()


## The example material of a look (one shader per look, shared).
static func look_material(name: String) -> ShaderMaterial:
	var key: String = name if name in Shaders.WATER_LOOKS else "stylized"
	if not _looks.has(key):
		var s := Shader.new()
		s.code = Shaders.WATER[key]
		_looks[key] = s
	var m := ShaderMaterial.new()
	m.shader = _looks[key]
	return m


## Shows the sheet: the rebuilt one if there is one, else the baked one.
func rebuild() -> void:
	if _sheet == null or not is_instance_valid(_sheet):
		_sheet = MeshInstance3D.new()
		_sheet.name = "Sheet"
		add_child(_sheet, false, Node.INTERNAL_MODE_BACK)
	if _rebuilt != null:
		_sheet.mesh = _rebuilt
	else:
		_sheet.mesh = _mesh_of(mesh_path) if mesh_path != "" else null
	_sheet.material_override = material if material != null else look_material(look)


## The mesh shown now (the rebuilt sheet, or the baked one), or null.
func sheet_mesh() -> Mesh:
	return _sheet.mesh if _sheet != null and is_instance_valid(_sheet) else null


## The first mesh of the .glb (the sheet is one node, one mesh).
static func _mesh_of(path: String) -> Mesh:
	var scene: Node = null
	if path.begins_with("res://") and ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		if packed != null:
			scene = packed.instantiate()
	if scene == null and FileAccess.file_exists(path):
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(path, state) == OK:
			scene = doc.generate_scene(state)
	if scene == null:
		push_warning("MarchingBlocks water: cannot read %s" % path)
		return null
	var found: Mesh = null
	var stack: Array = [scene]
	while not stack.is_empty() and found == null:
		var n: Node = stack.pop_front()
		var m = n.get("mesh")
		if m is ImporterMesh:
			m = (m as ImporterMesh).get_mesh()
		if m is Mesh:
			found = m
		stack.append_array(n.get_children())
	scene.free()
	return found


## The tile layers of this water's world: the MarchingBlocksWorld siblings.
func layers() -> Array:
	var parent := get_parent()
	if parent == null:
		return []
	return parent.get_children().filter(func(n: Node) -> bool: return n.get_script() == World)


## Every water layer of this world, in order (the sea is the FIRST source in the void among all of them).
func water_layers() -> Array:
	var parent := get_parent()
	if parent == null:
		return [self]
	return parent.get_children().filter(func(n: Node) -> bool: return n.get_script() == get_script())


## The water layer that computes for the whole world: the first one.
func leader() -> Node:
	return water_layers()[0]


## The cells of every tile layer, hidden ones too.
func world_cells() -> Dictionary:
	var all := {}
	for l in layers():
		all.merge(l.cells())
	return all


## Every source of the world's water layers, in order, and which of them are each layer's: [sources, [counts]].
func _all_sources() -> Array:
	var all: Array = []
	var counts: Array = []
	for w in water_layers():
		for s in w.sources:
			all.append(Vector3i(int(s[0]), int(s[1]), int(s[2])))
		counts.append((w.sources as Array).size())
	return [all, counts]


## The water cells of THIS layer now, deduced from the cells: {cell: true}.
func water_cells() -> Dictionary:
	var src := _all_sources()
	var r := Water.world(world_cells(), src[0])
	var out := {}
	var k := 0
	for w in water_layers():
		var n: int = (w.sources as Array).size()
		if w == self:
			for i in range(k, k + n):
				out.merge(r["bodies"][i]["water"])
		k += n
	return out


## A fingerprint of a set of cells, whatever their order (never 0, which means "unknown"): a sum of one hash per
## cell, so that it follows a stroke from the cells it changed alone (`_compute`).
static func fingerprint(cells: Dictionary) -> int:
	var s := 0
	for c: Vector3i in cells:
		s += _cell_hash(c)
	return _fingerprint_of(s, cells.size())


static func _cell_hash(c: Vector3i) -> int:
	var h := (c.x * 73856093) ^ (c.y * 19349663) ^ (c.z * 83492791)
	return (h * 0x9E3779B1) & 0xFFFFFFFFFFFF


static func _fingerprint_of(sum: int, count: int) -> int:
	var h := ((sum * 31 + count) ^ (sum >> 29)) & 0x7FFFFFFF
	return h if h != 0 else 1


## Is the sheet shown stale — were the tile cells changed since it was made (baked, or rebuilt here)?
func stale() -> bool:
	var made_for := _shown_for if _shown_known else baked_for
	return made_for != 0 and fingerprint(world_cells()) != made_for


## What the inspector says: "" when the sheet is up to date.
func _get_configuration_warnings() -> PackedStringArray:
	var l := leader() if is_inside_tree() else self
	if l.paused:
		return PackedStringArray(["The last water rebuild took %.1f s: the automatic rebuild is paused. Press "
			% l.last_seconds + "\"Rebuild water\" to update the sheet."])
	if l._pending or l._task != -1:
		return PackedStringArray(["The cells changed: the water sheet is stale until it is rebuilt."])
	return PackedStringArray()


# ── THE REBUILD ─────────────────────────────────────────────────────────────────────────────────────

## A cheap hash of the cells of the tile layers, to see that they changed: the fingerprint each layer took of the
## world's cells at its last rebuild (`live_update`, or `apply_cells`) — read, not recomputed, every frame.
func _cells_hash() -> int:
	var h := 7
	for l in layers():
		h = (h * 131 + int(l._fingerprint)) & 0x7FFFFFFF
	return h


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint() or leader() != self:
		return
	tick(Time.get_ticks_msec(), Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))


## One step of the leader's rebuild, at `now` (ms); `stroke`: a mouse button is held (a stroke may be going on).
## Called every frame in the editor; a script or a test may call it itself.
func tick(now: int, stroke := false) -> void:
	_collect()
	var h := _cells_hash()
	if h != _seen:
		var first := _seen == -1
		_seen = h
		_changed_at = now
		# At the first look, the sheet is up to date if the cells are those it was made for.
		_pending = not first or stale()
		for w in water_layers():
			w.update_configuration_warnings()
	if not _pending or _task != -1 or stroke or now - _changed_at < REBUILD_DELAY:
		return
	if paused or not water_layers().any(func(w: Node) -> bool: return w.auto_rebuild):
		return
	_start(true)


## "Rebuild water": recompute now, on a worker thread (the sheet is swapped in when it is done).
func rebuild_water() -> void:
	var l := leader()
	if l._task != -1:
		l._pending = true
		return
	l._start(true)


## Recompute now, on THIS thread, and swap the sheets in. Returns the seconds it took.
func rebuild_water_now() -> float:
	var l := leader()
	if l._task != -1:
		WorkerThreadPool.wait_for_task_completion(l._task)
		l._task = -1
		l._finish()
	l._start(false)
	return l.last_seconds


## Takes a COPY of the cells (each tile layer's used cells: a native copy, cheap on the main thread) and the sources,
## and computes on a worker thread (`threaded`) or here.
func _start(threaded: bool) -> void:
	var src := _all_sources()
	var used: Array = []
	for l in layers():
		var grid := l.get_node_or_null("Cells") as GridMap
		used.append(grid.get_used_cells() if grid != null else [])
	_job = {"layers": used, "sources": src[0], "counts": src[1], "base": _base, "hash": _cells_hash(),
		"floor": leader().water_floor()}
	_pending = false
	if threaded:
		_task = WorkerThreadPool.add_task(_compute.bind(_job), false, "MarchingBlocks water")
	else:
		_compute(_job)
		_finish()


## When the worker is done: its result becomes the base, and the sheets are swapped in.
func _collect() -> void:
	if _task == -1 or not WorkerThreadPool.is_task_completed(_task):
		return
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	_finish()


## THE CELLS of a job, and what changed since its base: {cells: {cell: number of tile layers holding it}, used (each
## tile layer's array of used cells), changed ({cell: true}, or null without a base), box, sum (of the cell hashes, for
## the fingerprint)}. ⚠ THE BASE IS CONSUMED: its `cells` are updated in place, changed cell by changed cell.
## What a stroke costs is what it CHANGED, not the size of the world:
##   - a tile layer whose used cells are the same array as last time is skipped (a native comparison);
##   - otherwise only the MIDDLE of its two arrays is compared — what lies before the first difference and after the
##     last one is the same, in the same place, in both (a GridMap lists its cells in insertion order: a stroke adds at
##     the end, removes here and there);
##   - the box and the fingerprint follow the changed cells (the box is swept again only when a cell on its edge goes).
static func _cells_of(job: Dictionary) -> Dictionary:
	var used: Array = job["layers"]
	var base: Dictionary = job["base"]
	if base.is_empty() or (base["used"] as Array).size() != used.size():
		var cells := {}
		var sum := 0
		for arr in used:
			for c: Vector3i in arr:
				var n: int = cells.get(c, 0)
				if n == 0:
					sum += _cell_hash(c)
				cells[c] = n + 1
		return {"cells": cells, "used": used, "changed": null, "box": Water.box(cells), "sum": sum}
	var cells: Dictionary = base["cells"]
	var sum: int = base["sum"]
	var changed := {}
	var gone := false
	var bx: Dictionary = base["box"]
	var lo: Vector3i = bx["lo"] + Vector3i.ONE if not bx.is_empty() else Vector3i.ZERO
	var hi: Vector3i = bx["hi"] - Vector3i.ONE if not bx.is_empty() else Vector3i.ZERO
	for i in used.size():
		var old: Array = base["used"][i]
		var now: Array = used[i]
		if now == old:
			continue
		var m := mini(old.size(), now.size())
		var p := 0
		while p < m and old[p] == now[p]:
			p += 1
		var s := 0
		while s < m - p and old[old.size() - 1 - s] == now[now.size() - 1 - s]:
			s += 1
		var old_mid := {}
		for k in range(p, old.size() - s):
			old_mid[old[k]] = true
		var now_mid := {}
		for k in range(p, now.size() - s):
			now_mid[now[k]] = true
		for c: Vector3i in now_mid:
			if old_mid.has(c):
				continue
			var n: int = cells.get(c, 0)
			if n == 0:
				sum += _cell_hash(c)
				changed[c] = true
				if bx.is_empty():
					gone = true   # no box yet: swept below
				else:
					lo = Vector3i(mini(lo.x, c.x), mini(lo.y, c.y), mini(lo.z, c.z))
					hi = Vector3i(maxi(hi.x, c.x), maxi(hi.y, c.y), maxi(hi.z, c.z))
			cells[c] = n + 1
		for c: Vector3i in old_mid:
			if now_mid.has(c):
				continue
			var n: int = cells[c]
			if n == 1:
				cells.erase(c)
				sum -= _cell_hash(c)
				changed[c] = true
				if c.x == lo.x or c.y == lo.y or c.z == lo.z or c.x == hi.x or c.y == hi.y or c.z == hi.z:
					gone = true
			else:
				cells[c] = n - 1
	var b2: Dictionary = Water.box(cells) if gone or cells.is_empty() else \
		{"lo": lo - Vector3i.ONE, "hi": hi + Vector3i.ONE}
	return {"cells": cells, "used": used, "changed": changed, "box": b2, "sum": sum}


## THE COMPUTATION, on a copy (a worker thread may run it): the rule with the reuse, then the sheet of every layer —
## kept as it was when all its bodies were reused.
static func _compute(job: Dictionary) -> void:
	var t := Time.get_ticks_usec()
	var base: Dictionary = job["base"]
	var got := _cells_of(job)
	var cells: Dictionary = got["cells"]
	var changed: Variant = got["changed"]
	if changed == null:
		base = {}
	var t_diff := Time.get_ticks_usec()
	var w := Water.world(cells, job["sources"], Water.VOLUME_MAX, base.get("world", {}), changed, got["box"])
	var t_rule := Time.get_ticks_usec()
	var memories: Array = base.get("memories", [])
	var before: Array = base.get("arrays", [])
	var arrays: Array = []
	var new_memories: Array = []
	var kept := 0
	var k := 0
	for i in (job["counts"] as Array).size():
		var n: int = job["counts"][i]
		var bodies: Array = (w["bodies"] as Array).slice(k, k + n)
		# Another floor: nothing is reused (the heights changed).
		var reused := not base.is_empty() and float(base.get("floor", 0.25)) == float(job.get("floor", 0.25)) \
				and i < before.size() and range(n).all(func(j: int) -> bool:
			return is_same(bodies[j], base["world"]["bodies"][k + j]))
		var m: Dictionary = memories[i] if i < memories.size() and not base.is_empty() else {}
		if reused:
			arrays.append(before[i])
			kept += 1
		else:
			arrays.append(WaterMesh.arrays(bodies, cells, w["box"], m, float(job.get("floor", 0.25))))
		new_memories.append(m)
		k += n
	var t_sheets := Time.get_ticks_usec()
	var bodies_kept := 0
	if not base.is_empty():
		for j in (w["bodies"] as Array).size():
			if j < (base["world"]["bodies"] as Array).size() and is_same(w["bodies"][j], base["world"]["bodies"][j]):
				bodies_kept += 1
	job["out"] = {"floor": float(job.get("floor", 0.25)), "cells": cells, "used": got["used"], "box": got["box"], "sum": got["sum"],
		"world": w, "memories": new_memories, "arrays": arrays, "fingerprint": _fingerprint_of(got["sum"], cells.size())}
	job["seconds"] = (Time.get_ticks_usec() - t) / 1e6
	job["detail"] = "cells %d ms, rule %d ms, sheets %d ms" % [(t_diff - t) / 1000, (t_rule - t_diff) / 1000,
		(t_sheets - t_rule) / 1000]
	job["incremental"] = not base.is_empty()
	job["reused"] = "%d of %d sources, %d of %d layers" % [bodies_kept, (w["bodies"] as Array).size(), kept,
		(job["counts"] as Array).size()]


## Swaps the computed sheets in (main thread), and decides whether the automatic rebuild pauses.
func _finish() -> void:
	var job := _job
	_job = {}
	if not job.has("out"):
		return
	_base = job["out"]
	last_seconds = job["seconds"]
	last_reused = job["reused"]
	if job["incremental"]:
		var was := paused
		paused = last_seconds > auto_limit
		if paused and not was:
			push_warning(("MarchingBlocks water: rebuilding the water took %.1f s — the automatic rebuild is paused "
				+ "(press \"Rebuild water\").") % last_seconds)
	var layers_ := water_layers()
	for i in mini(layers_.size(), (_base["arrays"] as Array).size()):
		var w: Node = layers_[i]
		w._rebuilt = WaterMesh.to_mesh(_base["arrays"][i])
		if w._rebuilt == null:
			w._rebuilt = ArrayMesh.new()   # nothing to draw — not the baked sheet either
		w._shown_for = _base["fingerprint"]
		w._shown_known = true
		w.rebuild()
	# The cells moved while it was computing: once more.
	if _cells_hash() != job["hash"]:
		_pending = true
	for w in layers_:
		w.update_configuration_warnings()

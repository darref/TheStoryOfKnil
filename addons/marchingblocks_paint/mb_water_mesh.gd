@tool
extends RefCounted
## THE WATER MESH — the water sheet of one water layer, REBUILT from its bodies (`mb_water.gd`, `world`) and the full
## cells of every tile layer. What MarchingBlocks bakes into `water/<name>.glb`, computed here again when you paint.
##
## The rule is written in `water_mesh_conformance.json` (`rules_text`, "THE WATER MESH"; the MarchingBlocks tool's
## `eau_maillage.gd` is its reference, line by line); this file implements it, and that file's cases prove it — a
## BAG of triangles, compared without order, rotations allowed, reflections refused. It uses nothing from the tool.
##
## THE CONTRACT every vertex carries (what the six looks, or your own shader, read):
##   COLOR_0 r, g — the flow along x and z, [-1, 1] mapped to [0, 1] ((0.5, 0.5): still water);
##   COLOR_0 b    — the kind: 0 still (sea, lake), 0.5 river, 0.75 foam, 1 waterfall;
##   COLOR_0 a    — the depth / 8 (still water, rivers; 1 without a floor), or the amount of foam (waterfall, foam);
##   NORMAL       — the shape (a waterfall is a curved sheet, closed into the rock);
##   UV           — (x, z) on the flats; (across, y) on a waterfall, so that it scrolls down.
##
## Floats are computed in DOUBLE and stored in 32-bit vectors (Vector3, Color), like the reference: the cases are
## matched on the ARRAYS (`arrays`), before Godot's ArrayMesh quantizes colours to 8 bits and normals to octahedra.
## The triangles are listed CLOCKWISE seen from the front (Godot's order; the .glb and the cases list them the other
## way round).

const Water := preload("res://addons/marchingblocks_paint/mb_water.gd")

## A still sheet is at its top row + SURFACE; a river band at its cell + RIVER; a sheet reaches OVERLAP under the
## full cell next to it (the thinned rock hides the edge).
const SURFACE := 0.7
const RIVER := -0.15
const OVERLAP := 0.45
## THE WATERFALL: a curved sheet leaving the lip flat, out by SHEET * sqrt(drop / ARC), then flaring FLARE per cell
## of drop (at most FLARE_MAX). A free end (no waterfall next to it on its plane) is rounded (ROUNDING) and goes
## INTO_ROCK behind the cliff's plane; it reaches OVERHANG past its cell there.
const SHEET := 0.35
const ARC := 0.7
const FLARE := 0.04
const FLARE_MAX := 0.2
const INTO_ROCK := 0.4
const ROUNDING := 0.35
const OVERHANG := 0.1
## THE FOAM: a ring CHURN wide where the waterfall meets the water, a spray SPRAY high; the foam rises from 0 to 1
## over FOAM_RISE above that water.
const CHURN := 0.85
const SPRAY := 0.9
const FOAM_RISE := 1.3
## The sea reaches this far beyond the world's box: "as far as the eye can see".
const HORIZON := 2000.0
## THE SPRING of a river: a dome of foam SPRING wide, SPRING_DOME high.
const SPRING := 0.7
const SPRING_DOME := 0.08

const STILL := 0.0
const FLOWING := 0.5
const FOAM := 0.75
const FALL := 1.0

const DOWN := Vector3i(0, -1, 0)
const UP := Vector3i(0, 1, 0)


## THE MESH of one water layer: an ArrayMesh of one surface, or null when there is nothing to draw.
static func mesh(bodies: Array, cells: Dictionary, box: Variant = null, memory: Variant = null) -> ArrayMesh:
	return to_mesh(arrays(bodies, cells, box, memory))


## The ArrayMesh of computed arrays, or null when they are empty.
static func to_mesh(a: Dictionary) -> ArrayMesh:
	if (a["v"] as PackedVector3Array).is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = a["v"]
	arr[Mesh.ARRAY_NORMAL] = a["n"]
	arr[Mesh.ARRAY_COLOR] = a["c"]
	arr[Mesh.ARRAY_TEX_UV] = a["uv"]
	arr[Mesh.ARRAY_INDEX] = a["i"]
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## THE ARRAYS of the mesh: {v, n, c, uv, i} (indices clockwise, Godot's order). What the cases describe.
## `bodies`: the `Water.world` results of ONE water layer, in order (a refused one draws nothing). `cells`: the full
## cells of every tile layer. `box`: the world's box if the caller has it (`Water.box`, the full cells grown by one).
## `memory`: a Dictionary kept by the caller from one call to the next (or null) — the sheets of a body that is the
## SAME object as last time (`Water.world` reuses a body whose footprint did not change) are reused, and so are the
## waterfalls whose fields did not change and the springs: the same output, a fraction of the cost.
static func arrays(bodies: Array, cells: Dictionary, box: Variant = null, memory: Variant = null) -> Dictionary:
	var a := _arrays()
	var b: Dictionary = box if box != null else Water.box(cells)
	var flats: Array = []
	var seen := {}
	var springs: Array = []
	# The STILL waters (sea, lakes, the lakes of the rivers): a waterfall falling into one lays its foam on ITS sheet.
	var still: Array = []
	for r in bodies:
		if r == null or r["error"] != "":
			continue
		if r["kind"] == "sea" or r["kind"] == "lake":
			still.append(r["water"])
		elif r["kind"] == "river":
			for lake in r["lakes"]:
				still.append(lake["cells"])
	seen["still"] = still
	var keep: Dictionary = memory if memory != null else {}
	var used := {}
	for j in bodies.size():
		var r: Variant = bodies[j]
		if r == null or r["error"] != "":
			continue
		if keep.has(j) and is_same(keep[j][0], r):
			flats.append_array(keep[j][1])
		else:
			var sheets := _sheets_of_body(r, cells, b)
			keep[j] = [r, sheets]
			flats.append_array(sheets)
		used[j] = true
		if r["kind"] == "river":
			_river(a, r["course"], cells, flats, seen, springs)
	for j in keep.keys():
		if j is int and not used.has(j):
			keep.erase(j)
	var foam: Array = []
	if memory != null:
		var falls := {}
		_lay_waterfalls(a, seen, foam, flats, keep.get("falls", {}), falls)
		keep["falls"] = falls
	else:
		_lay_waterfalls(a, seen, foam, flats)
	var springs_before: Dictionary = keep.get("springs", {})
	var springs_now := {}
	for c: Vector3i in springs:
		var gs: Variant = springs_before.get(c)
		if gs == null:
			gs = (_spring(c) as Array).map(_compiled_grid)
		springs_now[c] = gs
		foam.append_array(gs)
	if memory != null:
		keep["springs"] = springs_now
	_lay_flats(a, flats)
	for g: Dictionary in foam:
		_lay(a, g)
	return a


## The sheet rectangles of a body: the sea (and its horizon), a lake, the lakes of a river.
static func _sheets_of_body(r: Dictionary, cells: Dictionary, b: Dictionary) -> Array:
	var flats: Array = []
	match r["kind"]:
		"sea":
			var level: int = r["level"]
			var h := NAN
			if not b.is_empty() and level > (b["hi"] as Vector3i).y:
				h = level + SURFACE   # the world is drowned: the sheet is at the level, not at the box's top row
			flats.append_array(sheet_rectangles(r["water"], cells, level, h))
			flats.append_array(_horizon(b, float(level) + SURFACE))
		"lake":
			flats.append_array(sheet_rectangles(r["water"], cells, r["level"]))
		"river":
			for lake in r["lakes"]:
				flats.append_array(sheet_rectangles(lake["cells"], cells, lake["level"]))
	return flats


## THE FLATS WITHOUT T-JUNCTIONS: every horizontal rectangle {x0, x1, z0, z1, h, color}; a corner of ANOTHER rectangle
## at the same height lying on one of its sides is inserted there, and the rectangle is then drawn as a fan around its
## centre (a convex polygon: no flat triangle). Without one, two triangles. UV = (x, z). Coordinates are multiples of
## 0.05: compared in TWENTIETHS, exactly. (A T-junction left a thread of background pixels along a shared side.)
static func _lay_flats(a: Dictionary, flats: Array) -> void:
	var on_z := {}   # (h, z) → [x of the points on that line]
	var on_x := {}   # (h, x) → [z]
	for r: Dictionary in flats:
		if r.has("pts"):
			# POINTS of something else (the top of a waterfall, on the end of its band): inserted, nothing to draw.
			for q: Vector3 in r["pts"]:
				_note(on_z, Vector2i(_k(q.y), _k(q.z)), _k(q.x))
				_note(on_x, Vector2i(_k(q.y), _k(q.x)), _k(q.z))
			continue
		var hk := _k(r["h"])
		for x in [r["x0"], r["x1"]]:
			for z in [r["z0"], r["z1"]]:
				_note(on_z, Vector2i(hk, _k(z)), _k(x))
				_note(on_x, Vector2i(hk, _k(x)), _k(z))
	for key in on_z:
		(on_z[key] as Array).sort()
	for key in on_x:
		(on_x[key] as Array).sort()
	for r: Dictionary in flats:
		if r.has("pts"):
			continue
		var hk := _k(r["h"])
		var x0 := _k(r["x0"])
		var x1 := _k(r["x1"])
		var z0 := _k(r["z0"])
		var z1 := _k(r["z1"])
		# The outline, in a fixed direction: (x0,z0) → (x1,z0) → (x1,z1) → (x0,z1).
		var outline: Array[Vector2i] = [Vector2i(x0, z0)]
		for x in _between(on_z.get(Vector2i(hk, z0), []), x0, x1):
			outline.append(Vector2i(x, z0))
		outline.append(Vector2i(x1, z0))
		for z in _between(on_x.get(Vector2i(hk, x1), []), z0, z1):
			outline.append(Vector2i(x1, z))
		outline.append(Vector2i(x1, z1))
		var back: Array = _between(on_z.get(Vector2i(hk, z1), []), x0, x1)
		back.reverse()
		for x in back:
			outline.append(Vector2i(x, z1))
		outline.append(Vector2i(x0, z1))
		var up: Array = _between(on_x.get(Vector2i(hk, x0), []), z0, z1)
		up.reverse()
		for z in up:
			outline.append(Vector2i(x0, z))
		var h: float = r["h"]
		var c: Color = r["color"]
		if outline.size() == 4:
			_flat(a, r["x0"], r["x1"], r["z0"], r["z1"], h, c)
			continue
		var base: int = (a["v"] as PackedVector3Array).size()
		var centre := Vector3((float(r["x0"]) + float(r["x1"])) * 0.5, h, (float(r["z0"]) + float(r["z1"])) * 0.5)
		a["v"].append(centre)
		a["n"].append(Vector3.UP)
		a["c"].append(c)
		a["uv"].append(Vector2(centre.x, centre.z))
		for t in outline:
			var p := Vector3(t.x / 20.0, h, t.y / 20.0)
			a["v"].append(p)
			a["n"].append(Vector3.UP)
			a["c"].append(c)
			a["uv"].append(Vector2(p.x, p.z))
		var n := outline.size()
		for k in n:
			# (centre, k, k+1) turns DOWN, away from the normal: Godot's clockwise order.
			a["i"].append_array([base, base + 1 + k, base + 1 + (k + 1) % n])


static func _k(v: float) -> int:
	return roundi(v * 20.0)


static func _note(d: Dictionary, key: Vector2i, v: int) -> void:
	if not d.has(key):
		d[key] = [v]
	elif not (d[key] as Array).has(v):
		(d[key] as Array).append(v)


## The sorted values of `l` strictly between lo and hi.
static func _between(l: Array, lo: int, hi: int) -> Array:
	var out: Array = []
	var i := l.bsearch(lo, false)
	while i < l.size() and int(l[i]) < hi:
		out.append(l[i])
		i += 1
	return out


static func _arrays() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(),
		"uv": PackedVector2Array(), "i": PackedInt32Array()}


## color(flow, kind, a) = (flow.x * 0.5 + 0.5, flow.y * 0.5 + 0.5, kind, clamp(a, 0, 1)).
static func _color(flow: Vector2, kind: float, a: float) -> Color:
	return Color(flow.x * 0.5 + 0.5, flow.y * 0.5 + 0.5, kind, clampf(a, 0.0, 1.0))


## A quad, corners in outline order, normal `n`; its two triangles listed so that their stored cross product points
## AWAY from the normal (Godot's clockwise front faces).
static func _quad(a: Dictionary, p: Array, n: Vector3, c: Color, uv: Array) -> void:
	var base: int = (a["v"] as PackedVector3Array).size()
	for k in 4:
		a["v"].append(p[k])
		a["n"].append(n)
		a["c"].append(c)
		a["uv"].append(uv[k])
	var x: Vector3 = (p[1] - p[0]).cross(p[2] - p[0])
	if x.dot(n) > 0.0:
		a["i"].append_array([base, base + 2, base + 1, base, base + 3, base + 2])
	else:
		a["i"].append_array([base, base + 1, base + 2, base, base + 2, base + 3])


## A horizontal rectangle [x0, x1] × [z0, z1] at height h, UV = (x, z).
static func _flat(a: Dictionary, x0: float, x1: float, z0: float, z1: float, h: float, c: Color) -> void:
	_quad(a, [Vector3(x0, h, z0), Vector3(x1, h, z0), Vector3(x1, h, z1), Vector3(x0, h, z1)], Vector3.UP, c,
		[Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])


## The cell `c` at height `h`, reaching OVERLAP under each full neighbour of its row: a rectangle for `_lay_flats`.
static func _cell_flat(c: Vector3i, h: float, cells: Dictionary, color: Color) -> Dictionary:
	var xm := OVERLAP if cells.has(c + Vector3i(-1, 0, 0)) else 0.0
	var xp := OVERLAP if cells.has(c + Vector3i(1, 0, 0)) else 0.0
	var zm := OVERLAP if cells.has(c + Vector3i(0, 0, -1)) else 0.0
	var zp := OVERLAP if cells.has(c + Vector3i(0, 0, 1)) else 0.0
	return {"x0": c.x - xm, "x1": c.x + 1 + xp, "z0": c.z - zm, "z1": c.z + 1 + zp, "h": h, "color": color}


## THE DRAWN SURFACE of a still water at `level`: its surface (`Water.surface`: nothing above), PLUS its cells of the
## level under a full cell (water under a floating storey or a ceiling: there is air between the sheet and the rock).
static func drawn_surface(water: Dictionary, cells: Dictionary, level: int) -> Array[Vector3i]:
	var s := Water.surface(water, cells)
	for c: Vector3i in water:
		if c.y == level and cells.has(c + Vector3i.UP):
			s.append(c)
	return s


## THE RECTANGLES OF A SHEET: each cell of the drawn surface is the rectangle [x - overlap, x + 1 + overlap] × [z …]
## at its row + SURFACE (or `h_forced`), coloured by its depth; then
##   1. in a ROW (same y, same z), contiguous cells of the same colour and the same z overlaps merge;
##   2. two strips of NEIGHBOURING rows in z, of the same extent in x (overlaps included), of the same colour, with
##      no overlap on their shared side, merge.
## Each merge only joins two rectangles sharing a WHOLE side. Fixed order (y, z, x): no hash table decides anything.
static func sheet_rectangles(water: Dictionary, cells: Dictionary, level: int, h_forced := NAN) -> Array:
	var depths := {}
	for c: Vector3i in drawn_surface(water, cells, level):
		depths[c] = Water.depth(water, cells, c)
	var sorted: Array = _sorted(depths.keys())
	# 1. The rows.
	var strips: Array = []
	var cur := {}
	for c: Vector3i in sorted:
		var p: int = depths[c]
		var color := _color(Vector2.ZERO, STILL, 1.0 if p < 0 else p / 8.0)
		var xm := OVERLAP if cells.has(c + Vector3i(-1, 0, 0)) else 0.0
		var xp := OVERLAP if cells.has(c + Vector3i(1, 0, 0)) else 0.0
		var zm := OVERLAP if cells.has(c + Vector3i(0, 0, -1)) else 0.0
		var zp := OVERLAP if cells.has(c + Vector3i(0, 0, 1)) else 0.0
		if not cur.is_empty() and cur["y"] == c.y and cur["z"] == c.z and cur["end"] == c.x \
				and cur["xp"] == 0.0 and xm == 0.0 and cur["zm"] == zm and cur["zp"] == zp \
				and cur["color"] == color:
			cur["end"] = c.x + 1
			cur["xp"] = xp
			continue
		if not cur.is_empty():
			strips.append(cur)
		cur = {"y": c.y, "z": c.z, "start": c.x, "end": c.x + 1, "xm": xm, "xp": xp, "zm": zm, "zp": zp,
			"color": color}
	if not cur.is_empty():
		strips.append(cur)
	# 2. Neighbouring strips in z, of the same extent: each strip looks for the open rectangle it extends.
	var rects: Array = []
	var open := {}   # (y, z, x0, x1, color) → a rectangle that may still grow
	for s: Dictionary in strips:
		var x0: float = s["start"] - s["xm"]
		var x1: float = s["end"] + s["xp"]
		var key := [s["y"], s["z"], x0, x1, s["color"]]
		var r: Variant = open.get(key, null)
		if r != null:
			open.erase(key)
			r["z1"] = s["z"] + 1 + s["zp"]
		else:
			r = {"x0": x0, "x1": x1, "z0": s["z"] - s["zm"], "z1": s["z"] + 1 + s["zp"],
				"h": h_forced if not is_nan(h_forced) else s["y"] + SURFACE, "color": s["color"]}
			rects.append(r)
		if s["zp"] == 0.0:
			open[[s["y"], s["z"] + 1, x0, x1, s["color"]]] = r
	return rects


## Cells in (y, z, x) order — by an integer key and the native sort.
static func _sorted(list: Array) -> Array:
	if list.is_empty():
		return list
	var lo := Vector3i(2147483647, 2147483647, 2147483647)
	var hi := -lo
	for c: Vector3i in list:
		lo = Vector3i(mini(lo.x, c.x), mini(lo.y, c.y), mini(lo.z, c.z))
		hi = Vector3i(maxi(hi.x, c.x), maxi(hi.y, c.y), maxi(hi.z, c.z))
	var nx := hi.x - lo.x + 1
	var nz := hi.z - lo.z + 1
	var keys := PackedInt64Array()
	keys.resize(list.size())
	for i in list.size():
		var c: Vector3i = list[i]
		keys[i] = (int(c.y - lo.y) * nz + (c.z - lo.z)) * nx + (c.x - lo.x)
	keys.sort()
	var out: Array = []
	out.resize(keys.size())
	for i in keys.size():
		var k: int = keys[i]
		out[i] = Vector3i(lo.x + k % nx, lo.y + k / (nx * nz), lo.z + (k / nx) % nz)
	return out


## The sea beyond the world's box: four large rectangles around it, without a floor. Without a world, one.
static func _horizon(b: Dictionary, h: float) -> Array:
	var c := _color(Vector2.ZERO, STILL, 1.0)
	var r := func(x0: float, x1: float, z0: float, z1: float) -> Dictionary:
		return {"x0": x0, "x1": x1, "z0": z0, "z1": z1, "h": h, "color": c}
	if b.is_empty():
		return [r.call(-HORIZON, HORIZON, -HORIZON, HORIZON)]
	var lo: Vector3i = b["lo"]
	var hi: Vector3i = b["hi"]
	var x0 := float(lo.x)
	var x1 := float(hi.x + 1)
	var z0 := float(lo.z)
	var z1 := float(hi.z + 1)
	return [r.call(-HORIZON, HORIZON, -HORIZON, z0), r.call(-HORIZON, HORIZON, z1, HORIZON), r.call(-HORIZON, x0, z0, z1),
		r.call(x1, HORIZON, z0, z1)]


static func _horizontal(d: Vector3i) -> bool:
	return d.y == 0 and absi(d.x) + absi(d.z) == 1


## A river: a BAND on each course cell that RESTS ON MATTER (one cell, one band: the rivers of a layer share `seen`),
## and a waterfall per run of "fall" entries. The bands go to `flats`, the waterfalls to `seen` (laid afterwards by
## `_lay_waterfalls`, all rivers together); the spring, if any, to `springs`.
static func _river(a: Dictionary, course: Array, cells: Dictionary, flats: Array, seen: Dictionary,
		springs: Array = []) -> void:
	var n := course.size()
	# THE SPRING: the first cell of a river that flows on matter. A river leaving an overflowing lake has none.
	if n > 0 and course[0]["kind"] == "flow" and cells.has((course[0]["cell"] as Vector3i) + DOWN) \
			and not springs.has(course[0]["cell"]):
		springs.append(course[0]["cell"])
	for i in n:
		var e: Dictionary = course[i]
		var c: Vector3i = e["cell"]
		if e["kind"] == "lake" or not cells.has(c + DOWN) or seen.has(c):
			continue
		var d := flow_of(course, i)
		seen[c] = true
		flats.append(_cell_flat(c, c.y + RIVER, cells, _color(Vector2(d.x, d.z), FLOWING, 0.05)))
	var i := 0
	while i < n:
		var e: Dictionary = course[i]
		var c: Vector3i = e["cell"]
		if e["kind"] == "fall":
			# The run of falls, and the cell it falls from (the last "flow", just above).
			var j := i
			while j < n and course[j]["kind"] == "fall":
				j += 1
			var lip: Vector3i = course[i - 1]["cell"] if i > 0 else c + UP
			var d := Vector3i.ZERO
			if i >= 2 and _horizontal(lip - course[i - 2]["cell"]):
				d = lip - course[i - 2]["cell"]
			else:
				for f: Vector3i in Water.HORIZONTAL:
					if cells.has(c - f):
						d = f
						break
			_waterfall(lip, course[j - 1]["cell"], d, cells, seen)
			i = j
		else:
			i += 1


## The FLOW at entry `i` of a course (horizontal, or zero): towards the next cell if it is beside it, else from the
## previous one.
static func flow_of(course: Array, i: int) -> Vector3i:
	var c: Vector3i = course[i]["cell"]
	if i + 1 < course.size() and _horizontal(course[i + 1]["cell"] - c):
		return course[i + 1]["cell"] - c
	if i > 0 and _horizontal(c - course[i - 1]["cell"]):
		return c - course[i - 1]["cell"]
	return Vector3i.ZERO


## The waterfall of a river from the lip `lip` (the cell the water falls from) down to its last fall cell `bottom`,
## on the plane of the cliff it leaves (the side -`d`). Kept in `seen` under the key of its plane and its place along
## it: two rivers falling at the same place make ONE, from the highest lip to the lowest foot.
## `ground`: the height of the water it falls into — the band of `bottom` if it rests on matter, else the sheet below
## (bottom.y - 0.3 = the row below + SURFACE); the foot of the sheet is 0.15 lower, under the water.
static func _waterfall(lip: Vector3i, bottom: Vector3i, d: Vector3i, cells: Dictionary, seen: Dictionary) -> void:
	var top := lip.y + RIVER
	var foot := bottom.y - 0.3
	var ground := bottom.y + RIVER if cells.has(bottom + DOWN) else foot
	# FALLING INTO A HOLLOW IT FILLS: the foam is on the sheet of the still water that drowns `bottom`, not at its floor.
	for water: Dictionary in seen.get("still", []):
		if water.has(bottom):
			var h := bottom
			while water.has(h + UP):
				h += UP
			ground = h.y + SURFACE
			foot = minf(foot, ground - 0.15)
			break
	# The plane: x = const (axis 0) or z = const (axis 2); `along` the cell along the plane.
	var axis := 0 if d.x != 0 else 2
	var sense: int = d.x if d.x != 0 else d.z
	var along: int = lip.z if axis == 0 else lip.x
	var plane := 0.0
	if sense == 0:
		axis = 2
		sense = 1
		along = lip.x
		plane = lip.z + 0.5
	else:
		var edge: int = lip.x if axis == 0 else lip.z
		plane = float(edge) if sense > 0 else float(edge + 1)
	var key := "%d|%d|%d" % [axis, roundi(plane * 20.0), along]
	var l: Dictionary = seen.get(key, {})
	if l.is_empty():
		seen[key] = {"axis": axis, "sense": sense, "plane": plane, "along": along, "top": top, "foot": foot,
			"ground": ground, "d": d}
	else:
		l["top"] = maxf(l["top"], top)
		l["foot"] = minf(l["foot"], foot)
		l["ground"] = minf(l["ground"], ground)


## The successive drops of a sheet: its curve (fine at the top, where it bends), then every 0.5, then its foot.
## (32-bit floats, like the reference.)
static func _drops(total: float) -> PackedFloat32Array:
	var c := PackedFloat32Array()
	for h in [0.0, 0.02, 0.06, 0.12, 0.2, 0.3, 0.42, 0.55, ARC]:
		if h < total - 0.01:
			c.append(h)
	var h := ARC + 0.5
	while h < total - 0.2:
		c.append(h)
		h += 0.5
	c.append(total)
	return c


## How far out of the plane the sheet is after `drop` cells of drop (in the middle, far from the ends).
static func _out(drop: float) -> float:
	return SHEET * sqrt(clampf(drop / ARC, 0.0, 1.0)) + minf(FLARE * maxf(drop - ARC, 0.0), FLARE_MAX)


## The profile across: 1 in the middle, 0 at the end of a free end (where the sheet went into the rock).
static func _profile(u: float, u0: float, u1: float, free0: bool, free1: bool) -> float:
	var r := 1.0
	if free0 and u < u0 + ROUNDING:
		var t := clampf((u - u0) / ROUNDING, 0.0, 1.0)
		r = minf(r, sqrt(1.0 - (1.0 - t) * (1.0 - t)))
	if free1 and u > u1 - ROUNDING:
		var t := clampf((u1 - u) / ROUNDING, 0.0, 1.0)
		r = minf(r, sqrt(1.0 - (1.0 - t) * (1.0 - t)))
	return r


## How far in front of the plane a point of the sheet is: `r` its profile, `drop` its drop.
static func _front(r: float, drop: float) -> float:
	return lerpf(-INTO_ROCK * clampf(drop / 0.15, 0.0, 1.0), _out(drop), r)


## The point (u, drop) of a waterfall `l`, in the world.
static func _point(l: Dictionary, u: float, drop: float) -> Vector3:
	var r := 0.0 if l["straight"] else _profile(u, l["u0"], l["u1"], l["free0"], l["free1"])
	var p: float = float(l["plane"]) + (0.0 if l["straight"] else _front(r, drop)) * int(l["sense"])
	var y: float = float(l["top"]) - drop
	return Vector3(p, y, u) if int(l["axis"]) == 0 else Vector3(u, y, p)


## The normal of a waterfall at (u, drop), by differences — FORWARDS: (down) × (along the plane) points to -x for
## axis 0, to +z for axis 2, hence `_sign`.
static func _normal(l: Dictionary, u: float, drop: float) -> Vector3:
	var e := 0.01
	var tu := _point(l, u + e, drop) - _point(l, u - e, drop)
	var th := _point(l, u, drop + e) - _point(l, u, maxf(drop - e, 0.0))
	var n := th.cross(tu) * _sign(l)
	if n.length() < 1e-9:
		return Vector3(l["sense"], 0, 0) if int(l["axis"]) == 0 else Vector3(0, 0, l["sense"])
	return n.normalized()


static func _sign(l: Dictionary) -> int:
	return -int(l["sense"]) if int(l["axis"]) == 0 else int(l["sense"])


## The waterfalls kept in `seen`: each laid at once (opaque), its foam kept in `foam` (transparent, laid last). A
## FREE end (no waterfall next to it on its plane) is rounded and goes into the rock; an end with one stays straight
## and ends on the cell's border, where the neighbour takes over (same rows, same points).
## `before` / `after`: {the fields of a waterfall: its grids} — the same fields give the same grids.
static func _lay_waterfalls(a: Dictionary, seen: Dictionary, foam: Array, flats: Array = [],
		before: Dictionary = {}, after: Variant = null) -> void:
	for key in seen:
		if not key is String or key == "still":
			continue
		var l: Dictionary = seen[key]
		var u_cell: int = l["along"]
		l["straight"] = l["d"] == Vector3i.ZERO
		var plane_key := "%d|%d|" % [l["axis"], roundi(float(l["plane"]) * 20.0)]
		l["free0"] = not l["straight"] and not seen.has(plane_key + str(u_cell - 1))
		l["free1"] = not l["straight"] and not seen.has(plane_key + str(u_cell + 1))
		var signature := [l["axis"], l["sense"], l["plane"], u_cell, l["top"], l["foot"], l["ground"], l["d"],
			l["free0"], l["free1"]]
		var done: Variant = before.get(signature)
		if done == null:
			done = _waterfall_grids(l)
		if after != null:
			after[signature] = done
		_lay(a, done[0])
		# ITS TOP IS ON THE END OF THE BAND that reaches it: its points are inserted into the flats (no T-junction).
		flats.append({"pts": done[1]})
		foam.append(done[2])
		foam.append(done[3])


## A waterfall `l` (free ends and straight decided): [its compiled sheet, the top row of its sheet, its compiled foam
## ring, its compiled spray].
static func _waterfall_grids(l: Dictionary) -> Array:
	var u_cell: int = l["along"]
	l["u0"] = float(u_cell) - (OVERHANG if l["free0"] else 0.0)
	l["u1"] = float(u_cell) + 1.0 + (OVERHANG if l["free1"] else 0.0)
	var us := _across(l)
	var top: float = l["top"]
	var ground: float = l["ground"]
	var total: float = top - float(l["foot"])
	var dd: Vector3i = l["d"]
	var flow := Vector2(dd.x, dd.z)
	var g := {"p": [], "n": [], "c": [], "uv": []}
	for drop in _drops(total):
		var rp: Array = []
		var rn: Array = []
		var rc: Array = []
		var ruv: Array = []
		for u in us:
			var p := _point(l, u, drop)
			var e := clampf(1.0 - (p.y - ground) / FOAM_RISE, 0.0, 1.0)
			rp.append(p)
			rn.append(_normal(l, u, drop))
			rc.append(_color(flow, FALL, e * e))
			ruv.append(Vector2(u, p.y))
		g["p"].append(rp)
		g["n"].append(rn)
		g["c"].append(rc)
		g["uv"].append(ruv)
	# THE FOAM: at the foot, where the sheet meets the water (`ground`). Each point of the foot moves out along the
	# sheet's normal there — forwards in the middle, sideways on the rounded ends: the ring goes round.
	var drop_ground := clampf(top - ground, 0.0, total)
	var feet: Array = []
	var dirs: Array = []
	for u in us:
		var p := _point(l, u, drop_ground)
		var n := _normal(l, u, drop_ground)
		var h := Vector3(n.x, 0.0, n.z)
		if h.length() < 0.2:
			h = Vector3(l["sense"], 0, 0) if int(l["axis"]) == 0 else Vector3(0, 0, l["sense"])
		feet.append(Vector3(p.x, ground, p.z))
		dirs.append(h.normalized())
	var ring := _crown(feet, dirs, us, flow, ground, [0.0, 0.25, 0.55, CHURN], [0.0, 0.0, 0.0, 0.0],
		[1.0, 0.85, 0.45, 0.0], true)
	# The spray rises IN FRONT of the sheet only: on the rounded ends it fades (its foam × the profile cubed).
	var weights: Array = []
	for u in us:
		weights.append(1.0 if l["straight"] else pow(_profile(u, l["u0"], l["u1"], l["free0"], l["free1"]), 3.0))
	var spray := _crown(feet, dirs, us, flow, ground, [0.06, 0.16, 0.22, 0.2], [0.0, 0.3, 0.6, SPRAY],
		[0.95, 0.7, 0.35, 0.0], false, weights)
	return [_compiled_grid(g), g["p"][0], _compiled_grid(ring), _compiled_grid(spray)]


## The points across a waterfall: the rounded ends finely, the cell borders, the middle (multiples of 0.05).
static func _across(l: Dictionary) -> Array:
	var u0: float = l["u0"]
	var u1: float = l["u1"]
	var us: Array = []
	for f in [0.0, 0.05, 0.1, 0.2, 0.3, ROUNDING]:
		if l["free0"]:
			us.append(u0 + f)
		if l["free1"]:
			us.append(u1 - f)
	var a: int = l["along"]
	for u in [float(a), a + 0.5, a + 1.0]:
		us.append(u)
	us.sort()
	var kept: Array = []
	for u: float in us:
		if u < u0 - 0.001 or u > u1 + 0.001:
			continue
		if kept.is_empty() or u - float(kept[-1]) > 0.005:
			kept.append(u)
	return kept


## A crown of foam around the foot: row k at `offsets[k]` from the foot, `rises[k]` above the water, of foam
## `foams[k]` (× `weights[i]` if given). `flat`: the ring laid on the water (normal up, 0.02 above); else the spray,
## standing.
static func _crown(feet: Array, dirs: Array, us: Array, flow: Vector2, ground: float, offsets: Array, rises: Array,
		foams: Array, flat: bool, weights: Array = []) -> Dictionary:
	var g := {"p": [], "n": [], "c": [], "uv": []}
	for k in offsets.size():
		var rp: Array = []
		var rn: Array = []
		var rc: Array = []
		var ruv: Array = []
		for i in us.size():
			var p: Vector3 = feet[i] + dirs[i] * float(offsets[k]) + Vector3(0, float(rises[k]) + (0.02 if flat else 0.0), 0)
			rp.append(p)
			rn.append(Vector3.UP if flat else dirs[i])
			rc.append(_color(flow, FOAM, float(foams[k]) * (float(weights[i]) if not weights.is_empty() else 1.0)))
			ruv.append(Vector2(us[i], ground - float(offsets[k]) * 1.5 if flat else p.y))
		g["p"].append(rp)
		g["n"].append(rn)
		g["c"].append(rc)
		g["uv"].append(ruv)
	return g


## THE SPRING of a river, on the band of cell `c`: the water WELLS UP — a disc of foam, domed in the middle, that
## spreads and fades, and a small veil of spray. Kind "foam"; UV (angle × 0.6, height - 1.5 radius).
static func _spring(c: Vector3i) -> Array:
	var centre := Vector3(c.x + 0.5, c.y + RIVER, c.z + 0.5)
	var turns := 16
	var disc := {"p": [], "n": [], "c": [], "uv": []}
	var radii := [0.0, 0.2, 0.42, SPRING]
	var lifts := [SPRING_DOME, SPRING_DOME * 0.7, SPRING_DOME * 0.3, 0.02]
	var foams := [1.0, 0.95, 0.6, 0.0]
	for k in radii.size():
		var rp: Array = []
		var rn: Array = []
		var rc: Array = []
		var ruv: Array = []
		for i in turns + 1:
			var ang := TAU * float(i % turns) / turns
			var d := Vector3(cos(ang), 0, sin(ang))
			rp.append(centre + d * float(radii[k]) + Vector3(0, float(lifts[k]), 0))
			rn.append(Vector3.UP)
			rc.append(_color(Vector2.ZERO, FOAM, foams[k]))
			ruv.append(Vector2(ang * 0.6, centre.y - float(radii[k]) * 1.5))
		disc["p"].append(rp)
		disc["n"].append(rn)
		disc["c"].append(rc)
		disc["uv"].append(ruv)
	var veil := {"p": [], "n": [], "c": [], "uv": []}
	for k in 3:
		var r: float = [0.12, 0.2, 0.24][k]
		var h: float = [0.02, 0.18, 0.34][k]
		var rp: Array = []
		var rn: Array = []
		var rc: Array = []
		var ruv: Array = []
		for i in turns + 1:
			var ang := TAU * float(i % turns) / turns
			var d := Vector3(cos(ang), 0, sin(ang))
			rp.append(centre + d * r + Vector3(0, h, 0))
			rn.append(d)
			rc.append(_color(Vector2.ZERO, FOAM, [0.8, 0.45, 0.0][k]))
			ruv.append(Vector2(ang * 0.6, centre.y + h))
		veil["p"].append(rp)
		veil["n"].append(rn)
		veil["c"].append(rc)
		veil["uv"].append(ruv)
	return [disc, veil]


## A COMPILED GRID: {v, n, c, uv, i}, indices from 0. Each quad (i, j) gives (k0, k1, k2) and (k0, k2, k3); a
## triangle without area (|cross| < 1e-7) is dropped; each is turned by the normal of its FIRST corner. The vertices no
## triangle uses are removed (the centre of a disc): the .glb export drops them too.
static func _compiled_grid(g: Dictionary) -> Dictionary:
	var v := PackedVector3Array()
	var ns := PackedVector3Array()
	var cs := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var p: Array = g["p"]
	var nr := p.size()
	if nr < 2:
		return {"v": v, "n": ns, "c": cs, "uv": uvs, "i": idx}
	var nc: int = (p[0] as Array).size()
	for i in nr:
		for j in nc:
			v.append(p[i][j])
			ns.append(g["n"][i][j])
			cs.append(g["c"][i][j])
			uvs.append(g["uv"][i][j])
	for i in nr - 1:
		for j in nc - 1:
			var k := [i * nc + j, i * nc + j + 1, (i + 1) * nc + j + 1, (i + 1) * nc + j]
			for t in [[k[0], k[1], k[2]], [k[0], k[2], k[3]]]:
				var x: Vector3 = (v[t[1]] - v[t[0]]).cross(v[t[2]] - v[t[0]])
				if x.length() < 1e-7:
					continue
				if x.dot(ns[t[0]]) > 0.0:
					idx.append_array([t[0], t[2], t[1]])
				else:
					idx.append_array([t[0], t[1], t[2]])
	var n := v.size()
	var renum := PackedInt32Array()
	renum.resize(n)
	renum.fill(-1)
	for i in idx:
		renum[i] = 0
	var kept := 0
	for i in n:
		if renum[i] == 0:
			renum[i] = kept
			kept += 1
	if kept < n:
		var v2 := PackedVector3Array()
		var n2 := PackedVector3Array()
		var c2 := PackedColorArray()
		var uv2 := PackedVector2Array()
		for i in n:
			if renum[i] >= 0:
				v2.append(v[i])
				n2.append(ns[i])
				c2.append(cs[i])
				uv2.append(uvs[i])
		for t in idx.size():
			idx[t] = renum[idx[t]]
		v = v2
		ns = n2
		cs = c2
		uvs = uv2
	return {"v": v, "n": ns, "c": cs, "uv": uvs, "i": idx}


## Lays a compiled grid into the arrays `a`, its indices shifted by the vertices already there.
static func _lay(a: Dictionary, g: Dictionary) -> void:
	var base: int = (a["v"] as PackedVector3Array).size()
	a["v"].append_array(g["v"])
	a["n"].append_array(g["n"])
	a["c"].append_array(g["c"])
	a["uv"].append_array(g["uv"])
	var idx: PackedInt32Array = (g["i"] as PackedInt32Array).duplicate()
	if base != 0:
		for t in idx.size():
			idx[t] += base
	a["i"].append_array(idx)

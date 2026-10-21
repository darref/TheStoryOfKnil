@tool
extends RefCounted
## WATER — lakes, rivers and one sea, DEDUCED from sources and the cells of every tile layer (hidden ones too).
## Water never changes cells.
##
## The rule is written in `water_conformance.json` (`rules_text`; the MarchingBlocks tool's `fluides.gd` is its
## reference, line by line); this file implements it, and that file's cases prove it — it uses nothing from the tool.
## Everything is INTEGER and tied by INSERTION ORDER: neighbours in a fixed order (+x, -x, +z, -z, down, up), a heap
## tied by an insertion counter — never by a hash table.
##
## What a world SHOWS is the water sheet the tool baked (`water/<name>.glb`, its COLOR_0 the contract: flow, kind,
## depth); this rule tells which cells hold water once the cells are painted again, and `mb_water_mesh.gd` rebuilds
## the sheet from it.
##
## THE REUSE (the tool's own, ported): `world` may take its previous result and the cells changed since. A body whose
## FOOTPRINT (the box of every cell it looked at, grown by one) holds no changed cell, under a compatible world box, is
## reused AS IS — the same Dictionary, recognised by `is_same`. It gives the SAME output as a full computation (proved
## on random strokes by the plugin's bench), for a fraction of the cost.

## A lake (or a river's lake) of more cells is refused (too_large). Not the sea: it is never refused for its size.
const VOLUME_MAX := 64 * 64 * 64
const STEPS_MAX := 4096
## A lake overflows when, from its threshold, a fall is at most this many cells away, flat.
const OVERFLOW_REACH := 4
const HORIZONTAL := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const NEIGHBOURS := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	Vector3i(0, -1, 0), Vector3i(0, 1, 0)]
const DOWN := Vector3i(0, -1, 0)
const UP := Vector3i(0, 1, 0)
## The looks a water layer may suggest (an unknown one is accepted).
const LOOKS := ["stylized", "clear", "reflective", "lava", "swamp", "acid"]


# ── READING ──────────────────────────────────────────────────────────────────────────────────────────

## READS the `water` key of a decoded world.json: {"water": [{name, visible, look, mesh, sources: [[x, y, z]…]}]}
## or {"error": reason}. Absent: no water.
static func read(world: Variant) -> Dictionary:
	if not world is Dictionary:
		return {"error": "not a MarchingBlocks world"}
	var list = (world as Dictionary).get("water", [])
	if not list is Array:
		return {"error": "water is not an array"}
	var out: Array = []
	for e in list:
		if not e is Dictionary or not e.get("name") is String or not e.get("visible") is bool \
				or not e.get("look") is String:
			return {"error": "a water layer has no name, visibility or look"}
		var m = e.get("mesh")
		if m != null and not m is String:
			return {"error": "water '%s': mesh is neither a path nor null" % e["name"]}
		var flat = e.get("sources")
		if not flat is Array or (flat as Array).size() % 3 != 0:
			return {"error": "water '%s': sources is not a list of x y z triples" % e["name"]}
		var sources: Array = []
		for i in range(0, flat.size(), 3):
			for n in [flat[i], flat[i + 1], flat[i + 2]]:
				if not (n is float or n is int) or int(n) != n:
					return {"error": "water '%s': a source coordinate is not an integer" % e["name"]}
			sources.append([int(flat[i]), int(flat[i + 1]), int(flat[i + 2])])
		out.append({"name": e["name"], "visible": e["visible"], "look": e["look"], "mesh": m, "sources": sources})
	# THE FLOOR the water sits on (`water_floor`): 0.25, 0 or -0.25; absent (worlds exported before it): 0.25.
	var f = (world as Dictionary).get("water_floor", 0.25)
	if not (f is float or f is int) or not float(f) in [0.25, 0.0, -0.25]:
		return {"error": "water_floor is not 0.25, 0 or -0.25"}
	return {"water": out, "water_floor": float(f)}


# ── THE BOX AND THE SEA ──────────────────────────────────────────────────────────────────────────────

## The box of the full cells, grown by one: {lo, hi}; {} for an empty world.
static func box(cells: Dictionary) -> Dictionary:
	if cells.is_empty():
		return {}
	var lo := Vector3i(2147483647, 2147483647, 2147483647)
	var hi := Vector3i(-2147483647, -2147483647, -2147483647)
	for c: Vector3i in cells:
		lo = Vector3i(mini(lo.x, c.x), mini(lo.y, c.y), mini(lo.z, c.z))
		hi = Vector3i(maxi(hi.x, c.x), maxi(hi.y, c.y), maxi(hi.z, c.z))
	return {"lo": lo - Vector3i.ONE, "hi": hi + Vector3i.ONE}


## A source in the VOID: nothing full below it, in its column.
static func in_the_void(cells: Dictionary, source: Vector3i, b: Dictionary = {}) -> bool:
	if b.is_empty():
		b = box(cells)
	if b.is_empty():
		return true
	var lo: Vector3i = b["lo"]
	var c := source
	while c.y > lo.y:
		c += DOWN
		if cells.has(c):
			return false
	return true


## THE SEA at `level`: every empty cell of the box, at most at that level, joined by faces to the horizon (the box's
## sides and bottom). By column runs: the bottom run of every column is sea; another run is if it overlaps, by a
## face, a sea run of a neighbouring column. Returns {"water": {cell: true}, "error": ""}.
static func sea(cells: Dictionary, level: int, b: Dictionary = {}) -> Dictionary:
	var water := {}
	if b.is_empty():
		b = box(cells)
	if b.is_empty():
		return {"water": water, "error": ""}
	var lo: Vector3i = b["lo"]
	var hi: Vector3i = b["hi"]
	if level < lo.y:
		return {"water": water, "error": ""}
	var top := mini(level, hi.y)
	var fulls := {}
	for c: Vector3i in cells:
		if c.y <= top:
			var k := Vector2i(c.x, c.z)
			if fulls.has(k):
				(fulls[k] as Array).append(c.y)
			else:
				fulls[k] = [c.y]
	var tx := PackedInt32Array()
	var tz := PackedInt32Array()
	var t0 := PackedInt32Array()
	var t1 := PackedInt32Array()
	var start := {}
	for x in range(lo.x, hi.x + 1):
		for z in range(lo.z, hi.z + 1):
			var k := Vector2i(x, z)
			var first := t0.size()
			var y := lo.y
			if fulls.has(k):
				var ys: Array = fulls[k]
				ys.sort()
				for f: int in ys:
					if f > y:
						tx.append(x)
						tz.append(z)
						t0.append(y)
						t1.append(f - 1)
					y = f + 1
			if y <= top:
				tx.append(x)
				tz.append(z)
				t0.append(y)
				t1.append(top)
			start[k] = Vector2i(first, t0.size() - first)
	var inside := PackedByteArray()
	inside.resize(t0.size())
	var queue := PackedInt32Array()
	for i in t0.size():
		if t0[i] == lo.y:
			inside[i] = 1
			queue.append(i)
	var n := 0
	while n < queue.size():
		var i: int = queue[n]
		n += 1
		for f: Vector3i in HORIZONTAL:
			var v: Variant = start.get(Vector2i(tx[i] + f.x, tz[i] + f.z))
			if v == null:
				continue
			for j in range((v as Vector2i).x, (v as Vector2i).x + (v as Vector2i).y):
				if inside[j] == 0 and t0[j] <= t1[i] and t1[j] >= t0[i]:
					inside[j] = 1
					queue.append(j)
	for i in queue:
		for y in range(t0[i], t1[i] + 1):
			water[Vector3i(tx[i], y, tz[i])] = true
	return {"water": water, "error": ""}


# ── The heap: (priority, insertion order) in one 64-bit key ─────────────────────────────────────────

const BIAS := 1 << 20


static func _key(priority: int, order: int) -> int:
	return ((priority + BIAS) << 32) | order


static func _push(heap: PackedInt64Array, key: int) -> void:
	heap.append(key)
	var i := heap.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if heap[i] >= heap[p]:
			break
		var t: int = heap[i]
		heap[i] = heap[p]
		heap[p] = t
		i = p


static func _pop(heap: PackedInt64Array) -> int:
	var top: int = heap[0]
	var n := heap.size() - 1
	heap[0] = heap[n]
	heap.resize(n)
	var i := 0
	while true:
		var l := 2 * i + 1
		if l >= n:
			break
		var m := l
		if l + 1 < n and heap[l + 1] < heap[l]:
			m = l + 1
		if heap[m] >= heap[i]:
			break
		var t: int = heap[i]
		heap[i] = heap[m]
		heap[m] = t
		i = m
	return top


# ── Hollows and flat runs ────────────────────────────────────────────────────────────────────────────

## A HOLLOW, by priority flood from c; the water already there (`fixed`, and the lakes laid, `lakes`) is a way out.
## {"level", "cells", "threshold" (or null), "way_out": "leaves" | "joins" | "closed", "error"}. A closed cavity
## rises to `ceiling`.
static func _hollow(cells: Dictionary, b: Dictionary, fixed: Dictionary, lakes: Dictionary, c: Vector3i,
		ceiling: int, max_cells: int) -> Dictionary:
	var lo: Vector3i = b["lo"]
	var hi: Vector3i = b["hi"]
	var heap := PackedInt64Array()
	var entries: Array[Vector3i] = [c]
	var seen := {c: true}
	var pred := {}
	var prio := {c: c.y}
	_push(heap, _key(c.y, 0))
	var out_cells: Array[Vector3i] = []
	while not heap.is_empty():
		var k := _pop(heap)
		var p: int = (k >> 32) - BIAS
		var u: Vector3i = entries[k & 0xFFFFFFFF]
		var is_water: bool = fixed.has(u) or lakes.has(u)
		if is_water or u.x == lo.x or u.y == lo.y or u.z == lo.z or u.x == hi.x or u.z == hi.z:
			var lake := {}
			for s in out_cells:
				if prio[s] < p:
					lake[s] = true
			var path: Array[Vector3i] = []
			var w: Variant = u
			while w != null:
				path.push_front(w)
				w = pred.get(w)
			var threshold: Variant = null
			for s in path:
				if prio[s] >= p:
					threshold = s
					break
			return {"level": p - 1, "cells": lake, "threshold": threshold, "way_out": "joins" if is_water else "leaves",
				"error": "", "seen": seen}
		out_cells.append(u)
		if out_cells.size() > max_cells:
			return {"error": "too_large"}
		for f: Vector3i in NEIGHBOURS:
			var v: Vector3i = u + f
			if seen.has(v) or cells.has(v) or v.x < lo.x or v.y < lo.y or v.z < lo.z or v.x > hi.x or v.y > hi.y \
					or v.z > hi.z:
				continue
			seen[v] = true
			pred[v] = u
			var q := maxi(p, v.y)
			prio[v] = q
			_push(heap, _key(q, entries.size()))
			entries.append(v)
	var closed := {}
	var level := c.y
	for s in out_cells:
		if prio[s] <= ceiling:
			closed[s] = true
			level = maxi(level, s.y)
	return {"level": level, "cells": closed, "threshold": null, "way_out": "closed", "error": "", "seen": seen}


## THE FLAT RUN: from c, on its floor, the shortest path (breadth first, neighbours in order) to a cell the water
## falls from, joins other water, or leaves the world. `ignore`: the lake just left, flown over without falling in.
## {"path", "end": "" (falls next) | "leaves" | "joins", "seen"}, or {"hollow": true, "seen"}, or {"error"}; `seen`:
## the cells visited (for the footprint).
static func _flat(cells: Dictionary, b: Dictionary, fixed: Dictionary, lakes: Dictionary, c: Vector3i,
		ignore: Dictionary, max_cells: int) -> Dictionary:
	var lo: Vector3i = b["lo"]
	var hi: Vector3i = b["hi"]
	var pred := {c: null}
	var queue: Array[Vector3i] = [c]
	var i := 0
	while i < queue.size():
		var u: Vector3i = queue[i]
		i += 1
		var d: Vector3i = u + DOWN
		var end := "?"
		if not ignore.has(d) and (fixed.has(d) or lakes.has(d)):
			end = "joins"
		elif not cells.has(d) and not ignore.has(d) and d.y >= lo.y:
			end = ""
		elif u.x == lo.x or u.y == lo.y or u.z == lo.z or u.x == hi.x or u.z == hi.z:
			end = "leaves"
		if end == "?":
			for f: Vector3i in HORIZONTAL:
				var v: Vector3i = u + f
				if cells.has(v) or v.x < lo.x or v.z < lo.z or v.x > hi.x or v.z > hi.z or pred.has(v):
					continue
				if fixed.has(v) or lakes.has(v):
					end = "joins"
					break
				pred[v] = u
				queue.append(v)
		if end != "?":
			var path: Array[Vector3i] = []
			var w: Variant = u
			while w != null:
				path.push_front(w)
				w = pred[w]
			return {"path": path, "end": end, "seen": pred}
		if queue.size() > max_cells:
			return {"error": "too_large"}
	return {"hollow": true, "seen": pred}


# ── A SOURCE, AND THE WORLD ──────────────────────────────────────────────────────────────────────────

## ONE SOURCE. `fixed`: the water already there (the sea), which the source may join. Returns:
##   kind   — "sea", "lake", "river", or "" when refused;  error — "" or in_matter, in_water, too_large, too_long;
##   level  — sea and lake: the level (the highest row of water cells);
##   water  — {cell: true}: the sea's cells, or the cells of the lake(s);
##   lakes  — [{level, cells}];  course — [{cell, kind: flow | fall | lake, lake: index or -1}] in order;
##   end    — river: leaves, joins or closed; lake: closed in a closed cavity;
##   footprint — [lo, hi]: the box of every cell it looked at, grown by one (the sea: the whole box up to level + 1);
##   box    — the world box it was computed under.
static func source(cells: Dictionary, s: Vector3i, fixed: Dictionary = {}, max_cells := VOLUME_MAX,
		b: Dictionary = {}) -> Dictionary:
	if b.is_empty():
		b = box(cells)
	var r := {"kind": "", "error": "", "level": 0, "water": {}, "lakes": [], "course": [], "end": ""}
	if cells.has(s):
		r["error"] = "in_matter"
		return r
	if fixed.has(s):
		r["error"] = "in_water"
		return r
	if in_the_void(cells, s, b):
		var o := sea(cells, s.y, b)
		r["kind"] = "sea"
		r["level"] = s.y
		r["water"] = o["water"]
		# The sea depends on the whole box below its level, and on the row above (its surface).
		if not b.is_empty():
			r["footprint"] = [b["lo"], Vector3i((b["hi"] as Vector3i).x, s.y + 1, (b["hi"] as Vector3i).z)]
		r["box"] = b
		return r
	var lakes_d := {}
	var foot := {"lo": s, "hi": s}
	var c := s
	while not cells.has(c + DOWN) and c.y > (b["lo"] as Vector3i).y:
		c += DOWN
		if fixed.has(c):
			r["error"] = "in_water"
			return r
	var course: Array = []
	var lakes: Array = []
	var ignore := {}
	var first := true
	var steps := 0
	while true:
		steps += 1
		if steps > STEPS_MAX or course.size() > STEPS_MAX:
			return _refuse(r, "too_long")
		var flat := _flat(cells, b, fixed, lakes_d, c, ignore, max_cells)
		if flat.has("error"):
			return _refuse(r, flat["error"])
		_grow(foot, flat.get("seen", {}))
		if flat.has("hollow"):
			var h := _hollow(cells, b, fixed, lakes_d, c, s.y, max_cells)
			_grow(foot, h.get("seen", {}))
			if h["error"] != "":
				return _refuse(r, h["error"])
			lakes.append({"level": h["level"], "cells": h["cells"]})
			for k in h["cells"]:
				lakes_d[k] = true
			if first and not (h["way_out"] == "leaves"
					and _fall_near(cells, b, fixed, lakes_d, h["threshold"], h["cells"], max_cells, foot)):
				r["kind"] = "lake"
				r["level"] = h["level"]
				r["end"] = "closed" if h["way_out"] == "closed" else ""
				break
			first = false
			r["kind"] = "river"
			course.append({"cell": c, "kind": "lake", "lake": lakes.size() - 1})
			if h["way_out"] == "closed":
				r["end"] = "closed"
				break
			if fixed.has(h["threshold"]) or lakes_d.has(h["threshold"]):
				r["end"] = "joins"
				break
			c = h["threshold"]
			ignore = h["cells"]
			continue
		first = false
		r["kind"] = "river"
		for k: Vector3i in flat["path"]:
			if course.is_empty() or course[-1]["cell"] != k:
				course.append({"cell": k, "kind": "flow"})
		if flat["end"] != "":
			r["end"] = flat["end"]
			break
		ignore = {}
		var u: Vector3i = flat["path"][-1]
		var end := ""
		while true:
			var v: Vector3i = u + DOWN
			if fixed.has(v) or lakes_d.has(v):
				end = "joins"
				break
			if cells.has(v):
				break
			course.append({"cell": v, "kind": "fall"})
			_grow(foot, {v: true})
			u = v
			# The BOTTOM only: a fall along a side of the box goes down to the bottom (or to the sea).
			if v.y == (b["lo"] as Vector3i).y:
				end = "leaves"
				break
		if end != "":
			r["end"] = end
			break
		c = u
	r["course"] = course
	r["lakes"] = lakes
	r["water"] = lakes_d
	_grow(foot, {c: true})
	r["footprint"] = [(foot["lo"] as Vector3i) - Vector3i.ONE, (foot["hi"] as Vector3i) + Vector3i.ONE]
	r["box"] = b
	return r


## Grows the footprint `f` ({lo, hi}) to hold the cells of `list`.
static func _grow(f: Dictionary, list: Dictionary) -> void:
	var lo: Vector3i = f["lo"]
	var hi: Vector3i = f["hi"]
	for k: Vector3i in list:
		lo = Vector3i(mini(lo.x, k.x), mini(lo.y, k.y), mini(lo.z, k.z))
		hi = Vector3i(maxi(hi.x, k.x), maxi(hi.y, k.y), maxi(hi.z, k.z))
	f["lo"] = lo
	f["hi"] = hi


## From a lake's threshold, does the water find, flat, a fall (or other water, or the edge) at most OVERFLOW_REACH
## cells away? The river's own flat run, bounded.
static func _fall_near(cells: Dictionary, b: Dictionary, fixed: Dictionary, lakes: Dictionary, threshold: Variant,
		lake: Dictionary, max_cells: int, foot: Dictionary = {"lo": Vector3i.ZERO, "hi": Vector3i.ZERO}) -> bool:
	if threshold == null:
		return false
	var flat := _flat(cells, b, fixed, lakes, threshold, lake, mini(max_cells, (2 * OVERFLOW_REACH + 1) ** 2))
	_grow(foot, flat.get("seen", {}))
	return flat.has("path") and (flat["path"] as Array).size() - 1 <= OVERFLOW_REACH


static func _refuse(r: Dictionary, error: String) -> Dictionary:
	r["kind"] = ""
	r["error"] = error
	r["water"] = {}
	r["lakes"] = []
	r["course"] = []
	r["end"] = ""
	return r


## THE WORLD'S WATER: the sea first (the FIRST source in the void, in source order; any other in the void is refused,
## one_sea_only), then every other source against the sea only — their order does not matter.
## {"bodies": [one `source` result per source, in order], "sea": {cell: true}, "sources", "box"}.
## THE REUSE: `before` is a previous result, `changed` the full cells added or removed since ({cell: true}; null:
## everything is computed). A body is reused (the same Dictionary) when no changed cell is in its footprint and the
## box did not move where it looked (`_box_compatible`); a body that is not the sea also needs the sea reused.
## `b`: the box of `cells`, if the caller has it (else it is computed: a sweep of every cell).
static func world(cells: Dictionary, sources: Array, max_cells := VOLUME_MAX, before: Dictionary = {},
		changed: Variant = null, b: Variant = null) -> Dictionary:
	var bodies: Array = []
	bodies.resize(sources.size())
	var bx: Dictionary = b if b != null else box(cells)
	var old := {}
	if changed != null and before.has("bodies") and before.has("sources"):
		for i in (before["sources"] as Array).size():
			old[before["sources"][i]] = before["bodies"][i]
	var reuse := func(s: Vector3i) -> Variant:
		var r: Variant = old.get(s, null)
		if r == null or r["error"] != "" or not r.has("footprint") or not _box_compatible(r, bx):
			return null
		var lo: Vector3i = r["footprint"][0]
		var hi: Vector3i = r["footprint"][1]
		for c: Vector3i in changed:
			if c.x >= lo.x and c.y >= lo.y and c.z >= lo.z and c.x <= hi.x and c.y <= hi.y and c.z <= hi.z:
				return null
		return r
	var sea_reused := true
	var seas := 0
	for i in sources.size():
		var s: Vector3i = sources[i]
		if not cells.has(s) and in_the_void(cells, s, bx):
			if seas > 0:
				bodies[i] = _refuse({"kind": "", "error": "", "level": 0, "water": {}, "lakes": [], "course": [],
					"end": ""}, "one_sea_only")
				continue
			seas += 1
			var r: Variant = reuse.call(s)
			if r == null or r["kind"] != "sea":
				sea_reused = false
				r = source(cells, s, {}, max_cells, bx)
			bodies[i] = r
	var seas_before := 0
	for r in before.get("bodies", []):
		if r != null and r["kind"] == "sea":
			seas_before += 1
	sea_reused = sea_reused and not old.is_empty() and seas == seas_before and before.has("sea")
	var sea_d := {}
	if sea_reused:
		sea_d = before["sea"]
	else:
		# ONE sea: its water IS the sea water — shared, never copied (a sea of millions of cells). Nobody changes it.
		var holding: Array = bodies.filter(func(r): return r != null and not (r["water"] as Dictionary).is_empty())
		if holding.size() == 1:
			sea_d = holding[0]["water"]
		else:
			for r in holding:
				for k in r["water"]:
					sea_d[k] = true
	for i in sources.size():
		if bodies[i] == null:
			var r: Variant = reuse.call(sources[i]) if sea_reused else null
			if r == null or r["kind"] == "sea":
				r = source(cells, sources[i], sea_d, max_cells, bx)
			bodies[i] = r
	return {"bodies": bodies, "sea": sea_d, "sources": sources.duplicate(), "box": bx}


## Did the world's box move WHERE the body looked? Each face (sides, bottom, top) that moved must stay out of the
## footprint, at its old place as at its new one: painting above the highest point raises the box's top, and must not
## recompute a lake that never rose that high.
static func _box_compatible(r: Dictionary, b: Dictionary) -> bool:
	var rb: Dictionary = r.get("box", {})
	if rb.is_empty() or b.is_empty():
		return rb.is_empty() and b.is_empty()
	var flo: Vector3i = r["footprint"][0]
	var fhi: Vector3i = r["footprint"][1]
	var alo: Vector3i = rb["lo"]
	var ahi: Vector3i = rb["hi"]
	var nlo: Vector3i = b["lo"]
	var nhi: Vector3i = b["hi"]
	for k in 3:
		if alo[k] != nlo[k] and flo[k] <= maxi(alo[k], nlo[k]):
			return false
		if ahi[k] != nhi[k] and fhi[k] >= mini(ahi[k], nhi[k]):
			return false
	return true


## The full cells added or removed between two states of the world.
static func changed_between(before: Dictionary, after: Dictionary) -> Dictionary:
	var d := {}
	for c in after:
		if not before.has(c):
			d[c] = true
	for c in before:
		if not after.has(c):
			d[c] = true
	return d


## THE WIDTH OF A RIVER: `width` sources side by side ACROSS the first horizontal step of the river placed at s,
## centred on s (one more on the + side when even), s first; only the neighbours that ARE rivers stay. A source that
## is not a river does not widen.
static func river_width(cells: Dictionary, s: Vector3i, width: int, fixed: Dictionary = {}) -> Array:
	var b := box(cells)
	var r := source(cells, s, fixed, VOLUME_MAX, b)
	if width <= 1 or r["kind"] != "river":
		return [s]
	var across := Vector3i(1, 0, 0)
	var course: Array = r["course"]
	for i in range(1, course.size()):
		var a: Vector3i = course[i - 1]["cell"]
		var next: Vector3i = course[i]["cell"]
		if a.x != next.x or a.z != next.z:
			across = Vector3i(0, 0, 1) if next.x != a.x else Vector3i(1, 0, 0)
			break
	var out: Array = [s]
	var low := -((width - 1) / 2)
	for k in range(low, low + width):
		if k == 0:
			continue
		var c: Vector3i = s + across * k
		if cells.has(c):
			continue
		var rc := source(cells, c, fixed, VOLUME_MAX, b)
		if rc["error"] == "" and rc["kind"] == "river":
			out.append(c)
	return out


## THE SURFACE of a water: its cells whose cell above is neither water nor full.
static func surface(water: Dictionary, cells: Dictionary) -> Array[Vector3i]:
	var s: Array[Vector3i] = []
	for c: Vector3i in water:
		var h: Vector3i = c + UP
		if not water.has(h) and not cells.has(h):
			s.append(c)
	return s


## THE DEPTH below a water cell, in water cells down to the floor (the cell included); -1 without a floor.
static func depth(water: Dictionary, cells: Dictionary, c: Vector3i) -> int:
	var n := 0
	var u := c
	while water.has(u):
		n += 1
		u += DOWN
	return n if cells.has(u) else -1

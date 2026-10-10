@tool
extends RefCounted
## FOLIAGE — the plants of a world: models (a .glb each, copied into the .mbworld folder) and plants (a point ON THE
## GROUND, a yaw, a scale, a mode). They sway in the WIND, a shader on the same data in every engine.
##
## The rules (reading, placing, the brush, the wind) are written in `foliage_conformance.json` (`rules_text`); this
## file implements them from that text, and that file's cases prove it — it uses nothing from the MarchingBlocks tool.
##
## A MODEL: {id, name, mesh, ground_offset, scale, scale_random, footprint, height, wind}.
## A PLANT: {model, p (Vector3, on the ground, FORMAT space), yaw, scale, mode "air" | "ground"}.
## Placing modes: "air" (in the void, on the grid plane), "free" (planted, free neighbourhood), "overflow" (planted,
## may overflow an edge and its neighbours).

const MODES := ["air", "free", "overflow"]
const MAX_SLOPE := 40.0
const GROUND_TOLERANCE := 0.35
const EDGE_SAMPLES := 8
const DUPLICATE := 0.05
const WATER_OFFSET := 0.2
const GROUND_SEARCH_FLOOR := -64
const WIND_DIRECTION := Vector2(1.0, 0.35)
const BUCKET := 4.0
const MODEL_DEFAULTS := {"ground_offset": 0.0, "scale": 1.0, "scale_random": 0.2, "footprint": 0.5, "height": 1.0,
	"wind": 0.5}


# ── READING ──────────────────────────────────────────────────────────────────────────────────────────

static func _integer(x: Variant) -> bool:
	return (x is float or x is int) and int(x) == x


static func _number(x: Variant) -> bool:
	return x is float or x is int


## READS the `foliage` key of a decoded world.json: {"foliage": {models: [...], plants: [[model, x, y, z, yaw, scale,
## mode 0 | 1]…]}} or {"error": reason}. Absent: no plant. A malformed entry refuses the whole file; so does a plant
## of an unknown model (it would not be drawn, and be lost without a word).
static func read(world: Variant) -> Dictionary:
	if not world is Dictionary:
		return {"error": "not a MarchingBlocks world"}
	var d: Variant = (world as Dictionary).get("foliage")
	if d == null:
		return {"foliage": {"models": [], "plants": []}}
	if not d is Dictionary:
		return {"error": "foliage is not an object"}
	var list: Variant = d.get("models", [])
	if not list is Array:
		return {"error": "foliage: models is not an array"}
	var models: Array = []
	var ids := {}
	for i in (list as Array).size():
		var m: Variant = list[i]
		if not m is Dictionary:
			return {"error": "foliage: a model is not an object"}
		if not _integer(m.get("id")):
			return {"error": "foliage: a model has no integer id"}
		if m.has("name") and not m["name"] is String:
			return {"error": "foliage: a model's name is not a string"}
		if not (m.get("mesh") == null or m.get("mesh") is String):
			return {"error": "foliage: a model's mesh is neither a path nor null"}
		var out := {"id": int(m["id"]), "name": str(m.get("name", "Model %d" % (i + 1))), "mesh": m.get("mesh")}
		for k in MODEL_DEFAULTS:
			var v: Variant = m.get(k, MODEL_DEFAULTS[k])
			if not _number(v):
				return {"error": "foliage: model %d: %s is not a number" % [i, k]}
			out[k] = float(v)
		if ids.has(out["id"]):
			return {"error": "foliage: the model id %d appears twice" % out["id"]}
		ids[out["id"]] = true
		models.append(out)
	var flat: Variant = d.get("plants", [])
	if not flat is Array or (flat as Array).size() % 7 != 0:
		return {"error": "foliage: plants are not groups of seven numbers"}
	var plants: Array = []
	for k in range(0, (flat as Array).size(), 7):
		for j in 7:
			if not _number(flat[k + j]):
				return {"error": "foliage: plant %d is not made of numbers" % (k / 7)}
		if not ids.has(int(flat[k])):
			return {"error": "foliage: plant %d uses model %d, which does not exist" % [k / 7, int(flat[k])]}
		plants.append([int(flat[k]), float(flat[k + 1]), float(flat[k + 2]), float(flat[k + 3]), float(flat[k + 4]),
			float(flat[k + 5]), 0 if int(flat[k + 6]) == 0 else 1])
	return {"foliage": {"models": models, "plants": plants}}


## A plant from its seven numbers.
static func plant_of(row: Array) -> Dictionary:
	return {"model": int(row[0]), "p": Vector3(row[1], row[2], row[3]), "yaw": float(row[4]),
		"scale": float(row[5]), "mode": "air" if int(row[6]) == 0 else "ground"}


static func plant(model: int, p: Vector3, yaw: float, scale: float, mode: String) -> Dictionary:
	return {"model": model, "p": p, "yaw": yaw, "scale": scale, "mode": "air" if mode == "air" else "ground"}


# ── PLACING ──────────────────────────────────────────────────────────────────────────────────────────

## The total scale of a plant (its own draw × its model's).
static func scale_of(m: Dictionary, pl: Dictionary) -> float:
	return float(m["scale"]) * float(pl["scale"])


## Its height above the ground: max(0, (height + ground_offset) s).
static func height_above_ground(m: Dictionary, pl: Dictionary) -> float:
	return maxf(0.0, (float(m["height"]) + float(m["ground_offset"])) * scale_of(m, pl))


## WHERE THE MODEL SITS: T = translate(p + (0, ground_offset s, 0)) rotateY(yaw) scale(s).
static func transform(m: Dictionary, pl: Dictionary) -> Transform3D:
	var s := scale_of(m, pl)
	var b := Basis(Vector3.UP, float(pl["yaw"])).scaled(Vector3.ONE * s)
	return Transform3D(b, (pl["p"] as Vector3) + Vector3(0.0, float(m["ground_offset"]) * s, 0.0))


static func _radius(m: Dictionary, pl: Dictionary) -> float:
	return float(m["footprint"]) * scale_of(m, pl)


## The plants in buckets, so that a candidate is not compared with thousands: {buckets, radius_max}.
static func index(plants: Array, models: Dictionary) -> Dictionary:
	var ix := {"buckets": {}, "radius_max": 0.0}
	for pl in plants:
		add_to_index(ix, pl, models)
	return ix


static func add_to_index(ix: Dictionary, pl: Dictionary, models: Dictionary) -> void:
	var k := _bucket(pl["p"])
	if not ix["buckets"].has(k):
		ix["buckets"][k] = []
	(ix["buckets"][k] as Array).append(pl)
	if models.has(pl["model"]):
		ix["radius_max"] = maxf(ix["radius_max"], _radius(models[pl["model"]], pl))


static func _bucket(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / BUCKET), floori(p.z / BUCKET))


## The plants within `reach` of p in the plane (and within reach + 2 in height).
static func near(ix: Dictionary, p: Vector3, reach: float) -> Array:
	var out: Array = []
	var lo := _bucket(p - Vector3(reach, 0, reach))
	var hi := _bucket(p + Vector3(reach, 0, reach))
	for x in range(lo.x, hi.x + 1):
		for z in range(lo.y, hi.y + 1):
			for pl in ix["buckets"].get(Vector2i(x, z), []):
				var q: Vector3 = pl["p"]
				if Vector2(q.x - p.x, q.z - p.z).length() <= reach and absf(q.y - p.y) <= reach + 2.0:
					out.append(pl)
	return out


## CAN `pl` BE PLANTED in this mode? "" if so, else why: in_matter, too_steep, in_water, at_edge, under_matter,
## too_close, already_there. `world`: {"ground": Callable(x, z, y_top) -> null or {y, normal}, "full":
## Callable(Vector3i) -> bool, "water": Callable(Vector3) -> bool (optional)}; `normal`: the ground's (UP in the air).
static func check(m: Dictionary, pl: Dictionary, normal: Vector3, mode: String, world: Dictionary, ix: Dictionary,
		models: Dictionary, spacing := 0.0, max_slope := MAX_SLOPE) -> String:
	var p: Vector3 = pl["p"]
	var full: Callable = world["full"]
	var r := _radius(m, pl)
	var reach := maxf(spacing, DUPLICATE)
	if mode == "free":
		reach = maxf(reach, r + float(ix.get("radius_max", 0.0)))
	for other in near(ix, p, reach):
		var q: Vector3 = other["p"]
		var d := Vector2(q.x - p.x, q.z - p.z).length()
		if d < DUPLICATE:
			return "already_there"
		if d < spacing:
			return "too_close"
		if mode == "free" and models.has(other["model"]) and d < r + _radius(models[other["model"]], other):
			return "too_close"
	if mode == "air":
		if full.call(Vector3i(floori(p.x), floori(p.y), floori(p.z))):
			return "in_matter"
		return ""
	if normal.normalized().y < cos(deg_to_rad(max_slope)) - 1e-6:
		return "too_steep"
	var water: Callable = world.get("water", Callable())
	if water.is_valid() and water.call(p + Vector3(0, 0.1, 0)):
		return "in_water"
	if mode != "free":
		return ""
	var ground: Callable = world["ground"]
	var edge: Array = [Vector2.ZERO]
	for k in EDGE_SAMPLES:
		var a := TAU * float(k) / float(EDGE_SAMPLES)
		edge.append(Vector2(cos(a), sin(a)) * r)
	for b: Vector2 in edge:
		if b == Vector2.ZERO:
			continue
		var g = ground.call(p.x + b.x, p.z + b.y, p.y + 1.0)
		if g == null or absf(float(g["y"]) - p.y) > GROUND_TOLERANCE:
			return "at_edge"
	var h := height_above_ground(m, pl)
	var y0 := floori(p.y + 0.3)
	var y1 := floori(p.y + maxf(h, 0.3))
	for b: Vector2 in edge:
		var q := Vector2(p.x, p.z) + b * 0.5
		for y in range(y0, y1 + 1):
			if full.call(Vector3i(floori(q.x), y, floori(q.y))):
				return "under_matter"
	return ""


## THE BRUSH, its candidates given ([[x, z, yaw, scale]…], in order): each is put on the ground found below `y_top`
## (planted modes; none: no_ground) or on the plane y_top (air), then checked; an accepted plant joins the index AT
## ONCE. Returns {"plants": [...], "refused": {reason: count}}.
static func brush(m: Dictionary, y_top: float, candidates: Array, mode: String, world: Dictionary, ix: Dictionary,
		models: Dictionary, spacing := 0.0, max_slope := MAX_SLOPE) -> Dictionary:
	var out := {"plants": [], "refused": {}}
	for c in candidates:
		brush_one(m, float(c[0]), float(c[1]), y_top, float(c[2]), float(c[3]), mode, world, ix, models, spacing,
			max_slope, out)
	return out


static func brush_one(m: Dictionary, x: float, z: float, y_top: float, yaw: float, scale: float, mode: String,
		world: Dictionary, ix: Dictionary, models: Dictionary, spacing: float, max_slope: float,
		out: Dictionary) -> void:
	var refused: Dictionary = out["refused"]
	var p := Vector3(x, y_top, z)
	var n := Vector3.UP
	if mode != "air":
		var g = (world["ground"] as Callable).call(x, z, y_top)
		if g == null:
			refused["no_ground"] = int(refused.get("no_ground", 0)) + 1
			return
		p.y = float(g["y"])
		n = g["normal"]
	var pl := plant(int(m["id"]), p, yaw, scale, mode)
	var why := check(m, pl, n, mode, world, ix, models, spacing, max_slope)
	if why != "":
		refused[why] = int(refused.get(why, 0)) + 1
		return
	(out["plants"] as Array).append(pl)
	add_to_index(ix, pl, models)


## The cell whose water a point q is in: (floor(q.x), floor(q.y + WATER_OFFSET), floor(q.z)).
static func water_cell(q: Vector3) -> Vector3i:
	return Vector3i(floori(q.x), floori(q.y + WATER_OFFSET), floori(q.z))


## THE GROUND OF CELLS (no tiles): in column (floor x, floor z), from floor(y_top) - 1 down, the first FULL cell whose
## cell above is empty: {y: its y + 1, normal: UP}; none: null.
static func ground_of_cells(full: Callable, x: float, z: float, y_top: float, y_floor := GROUND_SEARCH_FLOOR) -> Variant:
	var cx := floori(x)
	var cz := floori(z)
	for y in range(floori(y_top) - 1, y_floor - 1, -1):
		if full.call(Vector3i(cx, y, cz)) and not full.call(Vector3i(cx, y + 1, cz)):
			return {"y": float(y + 1), "normal": Vector3.UP}
	return null


# ── THE WIND ─────────────────────────────────────────────────────────────────────────────────────────

## What each plant gives the wind shader: (ground, height above the ground, phase, amplitude).
static func wind_of(m: Dictionary, pl: Dictionary) -> Color:
	var p: Vector3 = pl["p"]
	return Color(p.y, height_above_ground(m, pl), fposmod(p.x * 0.37 + p.z * 0.71, TAU), float(m["wind"]))


## THE SWAY of a vertex (world space, its normal too) at time t — the wind shader's vertex(), line by line.
static func sway(vertex: Vector3, normal: Vector3, wind: Color, t: float, direction := WIND_DIRECTION) -> Vector3:
	var height := wind.g
	if height <= 0.0:
		return vertex
	var h := clampf((vertex.y - wind.r) / height, 0.0, 1.0)
	var phase := wind.b
	var amplitude := wind.a * height * 0.05
	var b := 0.35 + 0.6 * sin(t * 1.1 + phase) + 0.3 * sin(t * 2.3 + phase * 1.7)
	var s := direction.normalized() * b * amplitude * h * h
	var v := vertex + Vector3(s.x, 0.0, s.y)
	return v + normal * sin(t * 7.0 + v.dot(Vector3(2.1, 1.7, 2.9))) * 0.015 * wind.a * h

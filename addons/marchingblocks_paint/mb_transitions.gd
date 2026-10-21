@tool
extends RefCounted
## TRANSITIONS BETWEEN LAYERS — how two tile layers blend where they meet. The GEOMETRY never changes (the tiles are
## the ones the tileset rule places); only the LOOK of the surface does: the other layer's representative image is
## drawn over the surface, with an alpha the rule computes at every point.
##
## The rule is written in `transitions_conformance.json` (`rules_text`); this file implements it from that text, and
## that file's cases prove it — it uses nothing from the MarchingBlocks tool. The SHADER is the tool's own (a generated
## copy, `mb_shaders.gd`), laid OVER the tiles' materials (`next_pass`); `mb_world_to_format` turns Godot's world into
## FORMAT space (the cells), set by the MarchingBlocksTransitions node.
##
## ⚠ The shader draws one noise PER DIRECTION (each direction's grain); the cases give one n for both. Known, not
## settled in the tool either (engines/PARITE.md §4): the image follows the shader.

const Shaders := preload("res://addons/marchingblocks_paint/mb_shaders.gd")

## Layers 0 to 254 blend: a rank and a choice each fit in a byte of their own (two bytes per cell).
const LAYERS_MAX := 255
const MARGIN := 6
const DEFAULTS := {"softness": 0.45, "reach": 0.2, "irregularity": 0.35, "grain": 1.5, "fills_hollows": 0.5}
const BOUNDS := {"softness": [0.05, 1.0], "reach": [-0.5, 0.5], "irregularity": [0.0, 1.0], "grain": [0.25, 6.0],
	"fills_hollows": [0.0, 1.0]}


# ── READING ──────────────────────────────────────────────────────────────────────────────────────────

## One direction's settings, complete and clamped: a missing setting takes its default.
static func settings(r: Variant) -> Dictionary:
	var d: Dictionary = r if r is Dictionary else {}
	var out := {}
	for k in DEFAULTS:
		out[k] = clampf(float(d.get(k, DEFAULTS[k])), BOUNDS[k][0], BOUNDS[k][1])
	return out


static func _integer(x: Variant) -> bool:
	return (x is float or x is int) and int(x) == x


static func _number(x: Variant) -> bool:
	return x is float or x is int


## READS the `transitions` key of a decoded world.json: {"transitions": {pairs, representatives, choices: [[x, y, z,
## L]…] sorted by vertex}} — settings completed and clamped — or {"error": reason}. Absent: nothing blends.
static func read(world: Variant) -> Dictionary:
	if not world is Dictionary:
		return {"error": "not a MarchingBlocks world"}
	var layer_count: int = (world.get("layers") as Array).size() if world.get("layers") is Array else 0
	var t: Variant = (world as Dictionary).get("transitions")
	if t == null:
		return {"transitions": {"pairs": [], "representatives": [], "choices": []}}
	if not t is Dictionary:
		return {"error": "transitions is not an object"}
	var pairs_in: Variant = t.get("pairs", [])
	if not pairs_in is Array:
		return {"error": "transitions: pairs is not an array"}
	var pairs: Array = []
	var seen := {}
	for p in pairs_in:
		if not p is Dictionary or not _integer(p.get("a")) or not _integer(p.get("b")) or not p.get("active") is bool:
			return {"error": "transitions: a pair has no layers a, b or no active"}
		var a := int(p["a"])
		var b := int(p["b"])
		if a < 0 or b >= layer_count or a >= b:
			return {"error": "transitions: the pair %d, %d is not two layers a < b" % [a, b]}
		if seen.has(Vector2i(a, b)):
			return {"error": "transitions: the pair %d, %d appears twice" % [a, b]}
		seen[Vector2i(a, b)] = true
		var dirs := {}
		for k in ["a_covers_b", "b_covers_a"]:
			var r: Variant = p.get(k)
			if not r is Dictionary:
				return {"error": "transitions: the pair %d, %d has no %s" % [a, b, k]}
			for name in r:
				if not _number(r[name]):
					return {"error": "transitions: the setting %s of the pair %d, %d is not a number" % [name, a, b]}
			dirs[k] = settings(r)
		pairs.append({"a": a, "b": b, "active": p["active"], "a_covers_b": dirs["a_covers_b"],
			"b_covers_a": dirs["b_covers_a"]})
	var reps_in: Variant = t.get("representatives")
	if not reps_in is Array or (reps_in as Array).size() != layer_count:
		return {"error": "transitions: representatives is not one per layer"}
	var reps: Array = []
	for r in reps_in:
		if not r is Dictionary or not (r.get("image") == null or r.get("image") is String):
			return {"error": "transitions: a representative's image is neither a path nor null"}
		var c: Variant = r.get("color")
		if not c is Array or (c as Array).size() != 4 or (c as Array).any(func(x): return not _number(x)):
			return {"error": "transitions: a representative's color is not four numbers"}
		if not _number(r.get("scale")) or not _number(r.get("roughness")):
			return {"error": "transitions: a representative's scale or roughness is not a number"}
		reps.append({"image": r["image"], "color": (c as Array).map(func(x): return float(x)),
			"scale": maxf(float(r["scale"]), 0.01), "roughness": clampf(float(r["roughness"]), 0.0, 1.0)})
	var flat: Variant = t.get("choices", [])
	if not flat is Array or (flat as Array).size() % 4 != 0:
		return {"error": "transitions: choices is not a list of x y z L"}
	var chosen := {}
	for i in range(0, flat.size(), 4):
		for x in [flat[i], flat[i + 1], flat[i + 2], flat[i + 3]]:
			if not _integer(x):
				return {"error": "transitions: a choice is not made of integers"}
		var v := Vector3i(int(flat[i]), int(flat[i + 1]), int(flat[i + 2]))
		if chosen.has(v):
			return {"error": "transitions: the vertex %s is chosen twice" % v}
		if int(flat[i + 3]) < 0 or int(flat[i + 3]) >= layer_count:
			return {"error": "transitions: a choice names layer %d, which does not exist" % int(flat[i + 3])}
		chosen[v] = int(flat[i + 3])
	var vertices: Array = chosen.keys()
	vertices.sort()
	var choices: Array = []
	for v: Vector3i in vertices:
		choices.append([v.x, v.y, v.z, chosen[v]])
	return {"transitions": {"pairs": pairs, "representatives": reps, "choices": choices}}


## THE TABLE: {"C|D": settings when C covers D} for both directions of every ACTIVE pair whose two layers blend
## (both below LAYERS_MAX, both among the `layer_count` layers).
static func table(pairs: Array, layer_count: int) -> Dictionary:
	var out := {}
	for p in pairs:
		if not bool(p.get("active", false)):
			continue
		var a := int(p["a"])
		var b := int(p["b"])
		if a < 0 or b < 0 or a >= layer_count or b >= layer_count or a >= LAYERS_MAX or b >= LAYERS_MAX:
			continue
		out["%d|%d" % [a, b]] = settings(p.get("a_covers_b", {}))
		out["%d|%d" % [b, a]] = settings(p.get("b_covers_a", {}))
	return out


# ── THE RULE ─────────────────────────────────────────────────────────────────────────────────────────

## The trilinear weight of corner k = dx + 2 dy + 4 dz at the point f of the cell.
static func weight(k: int, f: Vector3) -> float:
	var o := Vector3(k & 1, (k >> 1) & 1, (k >> 2) & 1)
	return (f.x if o.x > 0 else 1.0 - f.x) * (f.y if o.y > 0 else 1.0 - f.y) * (f.z if o.z > 0 else 1.0 - f.z)


## THE BLEND at a point: `ranks` the eight corners' layers (-1 empty), `f` the point in the tile's cell, `choices` the
## layer chosen at each corner's vertex (-1 none), `table` {"C|D": settings}, `h` {rank: luminance of its
## representative at the point}, `n` the noise. {} when nothing is drawn, else {owner, other, s, vote, alpha}.
static func blend(ranks: Array, f: Vector3, choices: Array, table_: Dictionary, h: Dictionary = {},
		n := 0.5) -> Dictionary:
	var owner := 999
	for r in ranks:
		if int(r) >= 0 and int(r) < owner:
			owner = int(r)
	if owner == 999:
		return {}
	var w_owner := 0.0
	var parts := {}
	for k in 8:
		var r := int(ranks[k])
		if r < 0:
			continue
		if r == owner:
			w_owner += weight(k, f)
		else:
			parts[r] = float(parts.get(r, 0.0)) + weight(k, f)
	var other := -1
	var best := 0.0
	# Ties: the corners in order, the first part strictly larger wins (the shader's order).
	for k in 8:
		var r := int(ranks[k])
		if r >= 0 and r != owner and float(parts[r]) > best:
			best = parts[r]
			other = r
	if other < 0:
		return {}
	var key_oo := "%d|%d" % [other, owner]
	var key_ow := "%d|%d" % [owner, other]
	if not table_.has(key_oo) or not table_.has(key_ow):
		return {}
	var s: float = best / (best + w_owner)
	var priority := mini(owner, other)
	var vote := 0.0
	for k in 8:
		var c := int(choices[k]) if k < choices.size() else -1
		var covering: int = c if c == owner or c == other else priority
		if covering == other:
			vote += weight(k, f)
	var a_other := visible(table_[key_oo], s, float(h.get(owner, 0.5)), n)
	var a_owner := 1.0 - visible(table_[key_ow], 1.0 - s, float(h.get(other, 0.5)), n)
	return {"owner": owner, "other": other, "s": s, "vote": vote, "alpha": vote * a_other + (1.0 - vote) * a_owner}


## How much of the covering layer shows, its part of the cells being `s_c` and `h` the luminance of the covered one.
## The shift is ZERO at both ends.
static func visible(rg: Dictionary, s_c: float, h: float, n: float) -> float:
	var shift: float = (float(rg["reach"]) + float(rg["fills_hollows"]) * (0.5 - h)
		+ float(rg["irregularity"]) * (n - 0.5)) * 4.0 * s_c * (1.0 - s_c)
	return smoothstep(0.5 - float(rg["softness"]) * 0.5, 0.5 + float(rg["softness"]) * 0.5, s_c + shift)


# ── THE CELL TEXTURE (the recommended packing: what the shader reads) ───────────────────────────────

## {origin, size, bytes}: TWO bytes per cell (RG8) over the box of `cells` ({cell: rank}) grown by MARGIN — R = rank
## + 1 (0: empty, or a rank >= LAYERS_MAX), G = the rank chosen at that vertex + 1 (`choices` {vertex: rank}; outside
## the box: dropped). Texel (x, y, z) is the cell origin + (x, y, z); its bytes are 2 i (R) and 2 i + 1 (G).
static func cell_texture(cells: Dictionary, choices: Dictionary) -> Dictionary:
	if cells.is_empty():
		return {"origin": Vector3i.ZERO, "size": Vector3i.ONE, "bytes": PackedByteArray([0, 0])}
	var lo := Vector3i(1 << 30, 1 << 30, 1 << 30)
	var hi := -lo
	for c: Vector3i in cells:
		lo = lo.min(c)
		hi = hi.max(c)
	var origin := lo - Vector3i.ONE * MARGIN
	var size := hi - lo + Vector3i.ONE * (2 * MARGIN + 1)
	var bytes := PackedByteArray()
	bytes.resize(2 * size.x * size.y * size.z)
	for c: Vector3i in cells:
		bytes[2 * _index(origin, size, c)] = _byte(int(cells[c]))
	for v: Vector3i in choices:
		var i := _index(origin, size, v)
		if i >= 0:
			bytes[2 * i + 1] = _byte(int(choices[v]))
	return {"origin": origin, "size": size, "bytes": bytes}


static func _byte(rank: int) -> int:
	return rank + 1 if rank >= 0 and rank < LAYERS_MAX else 0


static func _index(origin: Vector3i, size: Vector3i, c: Vector3i) -> int:
	var t: Vector3i = c - origin
	if t.x < 0 or t.y < 0 or t.z < 0 or t.x >= size.x or t.y >= size.y or t.z >= size.z:
		return -1
	return (t.z * size.y + t.y) * size.x + t.x


# ── THE LOOK (the shader's data) ─────────────────────────────────────────────────────────────────────

## The material laid over the tiles: the tool's shader. Drawn after the artist's materials.
static func new_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = Shaders.TRANSITIONS
	var m := ShaderMaterial.new()
	m.resource_name = "mb_transitions"
	m.shader = sh
	m.render_priority = 1
	return m


## The cells (one RG8 3D texture) into the material.
static func set_cells(m: ShaderMaterial, d: Dictionary) -> void:
	var size: Vector3i = d["size"]
	var per := 2 * size.x * size.y
	var slices: Array[Image] = []
	for z in size.z:
		slices.append(Image.create_from_data(size.x, size.y, false, Image.FORMAT_RG8,
			(d["bytes"] as PackedByteArray).slice(z * per, (z + 1) * per)))
	var tex := ImageTexture3D.new()
	tex.create(Image.FORMAT_RG8, size.x, size.y, size.z, false, slices)
	m.set_shader_parameter("cases", tex)
	m.set_shader_parameter("origine", d["origin"])
	m.set_shader_parameter("taille", size)


## The table into the material (2 N × N texels, floats, N = the largest rank in the table + 1, at most LAYERS_MAX):
## at (2 D, C) active, softness, reach, irregularity; at (2 D + 1, C) fills_hollows, grain — when C covers D. The
## shader blends no rank outside it.
static func set_table(m: ShaderMaterial, t: Dictionary) -> void:
	var n := 1
	for key in t:
		for r in String(key).split("|"):
			n = maxi(n, int(r) + 1)
	n = mini(n, LAYERS_MAX)
	var img := Image.create_empty(2 * n, n, false, Image.FORMAT_RGBAF)
	for key in t:
		var cd: PackedStringArray = String(key).split("|")
		var c := int(cd[0])
		var d := int(cd[1])
		if c >= n or d >= n:
			continue
		var rg: Dictionary = t[key]
		img.set_pixel(2 * d, c, Color(1.0, rg["softness"], rg["reach"], rg["irregularity"]))
		img.set_pixel(2 * d + 1, c, Color(rg["fills_hollows"], rg["grain"], 0.0, 0.0))
	m.set_shader_parameter("table", ImageTexture.create_from_image(img))


## The representatives into the material, by layer rank: [{image: Image or null, color, scale, roughness}] — one
## slice per layer (at least `count`, at most LAYERS_MAX; a 256² slice with its mipmaps is ~350 KB). The colour
## multiplies the image AS IS (no sRGB conversion).
static func set_representatives(m: ShaderMaterial, reps: Array, count := 0) -> void:
	var images: Array[Image] = []
	var n := clampi(maxi(reps.size(), count), 1, LAYERS_MAX)
	var params := Image.create_empty(n, 2, false, Image.FORMAT_RGBAF)
	for k in n:
		var d: Dictionary = reps[k] if k < reps.size() else {}
		var img: Image = null
		if d.get("image") is Image:
			img = (d["image"] as Image).duplicate()
			if img.is_compressed():
				img.decompress()
			img.clear_mipmaps()
			img.convert(Image.FORMAT_RGBA8)
			img.resize(256, 256, Image.INTERPOLATE_BILINEAR)
		else:
			img = Image.create_empty(256, 256, false, Image.FORMAT_RGBA8)
			img.fill(Color.WHITE)
		img.generate_mipmaps()
		images.append(img)
		var c: Array = d.get("color", [1.0, 1.0, 1.0, 1.0])
		params.set_pixel(k, 0, Color(c[0], c[1], c[2], c[3]))
		params.set_pixel(k, 1, Color(float(d.get("scale", 1.0)), float(d.get("roughness", 0.8)), 0.0, 0.0))
	var arr := Texture2DArray.new()
	arr.create_from_images(images)
	m.set_shader_parameter("representants", arr)
	m.set_shader_parameter("rep_params", ImageTexture.create_from_image(params))

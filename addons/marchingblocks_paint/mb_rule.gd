@tool
extends RefCounted
## THE PLACEMENT RULE of the MarchingBlocks tileset format — implemented from the format itself.
##
## This file reads nothing but a tileset manifest (`tileset.json`): its `table`, `corners`, `classes`
## and `context`. It deliberately does not use any MarchingBlocks internals: it is the rule as
## any engine would implement it, and `conformance.json` (shipped next to it) proves it matches the
## reference implementation, case by case.
##
## The rule, in short (the manifest's `rules_text` says it in full):
##   1. a full cell c touches the 8 vertices c - corners[t];
##   2. at vertex v, bit t is set when cell v + corners[t] is full;
##   3. table[bits] gives [class, quarter_turns]; class -1 places nothing;
##   4. an outdoor-capable class is OUTDOOR when no empty cell among the 8 has a full cell above it,
##      from v.y + 2 up to the highest full cell of the layer; outdoor tries "<id>_outdoor" first;
##   5. each key has exactly one tile, tiles[key];
##   6. a missing key is returned as null — show an error marker, never fill in;
##   7. layers: steps 1-4 read the UNION of every visible layer of a world (a cell in two layers belongs
##      to the first); a vertex is placed by the first layer, in priority order, owning one of its 8 cells,
##      with that layer's tiles;
##   8. variants (optional): a key may have variants (the manifest's `variants`); the layer that places v
##      picks one — its CHOICE at v if it has one, otherwise a weighted draw by a hash of v, never random.

const FORMAT := "marchingblocks-tileset"
const SUPPORTED_VERSION := 1


## Checks a manifest before use. Returns "" when usable, otherwise the reason.
## A manifest from a NEWER format is refused: its rule may mean something else, and placing anyway
## would be a silent lie.
static func check(manifest: Dictionary) -> String:
	if int(manifest.get("version", 0)) > SUPPORTED_VERSION:
		return "made by a newer MarchingBlocks (format %d, this plugin reads %d): update the plugin" \
			% [int(manifest.get("version", 0)), SUPPORTED_VERSION]
	for field in ["corners", "table", "classes", "context"]:
		if not manifest.has(field):
			return "not a MarchingBlocks tileset: '%s' is missing" % field
	if (manifest["table"] as Array).size() != 256:
		return "the table must have 256 entries"
	for key in manifest.get("tiles", {}):
		if not manifest["tiles"][key] is String:
			return "tile '%s' must be one tile name (one tile per key)" % key
	var variants = manifest.get("variants", {})
	if not variants is Dictionary:
		return "variants must be an object: key -> list of tile names"
	for key in variants:
		if not variants[key] is Array or (variants[key] as Array).any(func(t): return not t is String):
			return "the variants of '%s' must be a list of tile names" % key
	return ""


## Every placement for a layer alone: [x, y, z, tile name or null, quarter_turns], sorted by vertex.
## `cells`: {Vector3i: true}. `rule`: the manifest. `tiles`: {key: tile name} (the manifest's `tiles`).
## Step 8: `variants` {key: [tile names]} (the manifest's), `weights` {key: [int]}, `choices` {Vector3i: int}.
static func placements(cells: Dictionary, rule: Dictionary, tiles: Dictionary, variants := {}, weights := {},
		choices := {}) -> Array:
	return placements_layered([{"cells": cells, "tiles": tiles, "visible": true, "variants": variants,
		"weights": weights, "choices": choices}], rule)[0]


## Every placement of a world of LAYERS (step 7), one list per layer, in the same order. `layers`, in
## priority order (the first is the highest): [{"cells": {Vector3i: true}, "tiles": {key: name},
## "visible": bool, and optionally "variants", "weights", "choices" (step 8)}]. Every layer must use a
## tileset made with the same rule (`rule`).
static func placements_layered(layers: Array, rule: Dictionary) -> Array:
	var union := {}   # cell -> index of the layer that owns it
	for i in layers.size():
		if layers[i].get("visible", true):
			for c in layers[i]["cells"]:
				if not union.has(c):
					union[c] = i
	var outs: Array = []
	for i in layers.size():
		outs.append([])
	var corners: Array = []
	for c in rule["corners"]:
		corners.append(Vector3i(int(c[0]), int(c[1]), int(c[2])))
	var table: Array = rule["table"]
	var classes: Array = rule["classes"]
	var band: int = int(rule["context"].get("band", 2))
	var suffix: String = str(rule["context"].get("outdoor_suffix", "_outdoor"))

	# The highest full cell of each column: « nothing full above the band » is one comparison with it, instead of a
	# climb up the column for every empty corner of every vertex (`_outdoor`) — the same answer; the pass went from 2.98
	# to 2.50 s on a world of 331 467 cells (measured in WaterDrop, 20 October 2026).
	var columns := {}
	for c in union:
		var k := Vector2i((c as Vector3i).x, (c as Vector3i).z)
		if (c as Vector3i).y > int(columns.get(k, -2147483648)):
			columns[k] = (c as Vector3i).y
	var vertices := {}
	for c in union:
		for t in 8:
			vertices[(c as Vector3i) - corners[t]] = true

	for key in vertices:
		var v: Vector3i = key
		var bits := 0
		var owner := -1
		for t in 8:
			if union.has(v + corners[t]):
				bits |= 1 << t
				var l: int = union[v + corners[t]]
				if owner < 0 or l < owner:
					owner = l
		var tiles: Dictionary = layers[owner]["tiles"]
		var entry: Array = table[bits]
		var cls: int = int(entry[0])
		if cls < 0:
			continue
		var id: String = classes[cls]["id"]
		var chosen := ""
		if bool(classes[cls]["outdoor_possible"]) and _outdoor(union, columns, v, corners, band):
			if str(tiles.get(id + suffix, "")) != "":
				chosen = id + suffix
		if chosen == "" and str(tiles.get(id, "")) != "":
			chosen = id
		var tile = null
		if chosen != "":
			tile = variant_tile(v, chosen, str(tiles[chosen]), layers[owner].get("variants", {}),
				layers[owner].get("weights", {}), layers[owner].get("choices", {}))
		outs[owner].append([v.x, v.y, v.z, tile, int(entry[1])])
	for out in outs:
		(out as Array).sort_custom(func(a: Array, b: Array) -> bool:
			if a[0] != b[0]:
				return a[0] < b[0]
			if a[1] != b[1]:
				return a[1] < b[1]
			return a[2] < b[2])
	return outs


## Step 8: the tile placed at v for `key`, whose base tile is `base`. `variants`: {key: [tile names]};
## `weights`: {key: [base weight, variant 1, …]} (a missing entry is 1, a negative one 0); `choices`:
## {Vector3i: int} (0 is the base). Same world, same tiles: the draw is a hash of v, never random.
static func variant_tile(v: Vector3i, key: String, base: String, variants: Dictionary, weights: Dictionary,
		choices: Dictionary) -> String:
	var list: Array = variants.get(key, [])
	var n := list.size()
	if n == 0:
		return base
	if choices.has(v):
		var c := int(choices[v])
		if c >= 0 and c <= n:
			return base if c == 0 else str(list[c - 1])
	var w: Array = weights.get(key, [])
	var ws: Array[int] = []
	var total := 0
	for k in n + 1:
		var x := maxi(0, int(w[k]) if k < w.size() else 1)
		ws.append(x)
		total += x
	if total <= 0:
		return base
	var r := vertex_hash(v) % total
	for k in n + 1:
		r -= ws[k]
		if r < 0:
			return base if k == 0 else str(list[k - 1])
	return base


## The vertex hash of step 8, on 64-bit integers (GDScript's int).
static func vertex_hash(v: Vector3i) -> int:
	var h: int = ((v.x * 73856093) ^ (v.y * 19349663) ^ (v.z * 83492791)) & 0x7FFFFFFF
	h = ((h ^ (h >> 16)) * 0x45D9F3B) & 0x7FFFFFFF
	h = ((h ^ (h >> 16)) * 0x45D9F3B) & 0x7FFFFFFF
	return h ^ (h >> 16)


## Outdoor: every EMPTY cell among the 8 around v has nothing full above the vertex's two-cell band. `columns`: the
## highest full cell of each column, {Vector2i(x, z): y}.
static func _outdoor(cells: Dictionary, columns: Dictionary, v: Vector3i, corners: Array, band: int) -> bool:
	for t in 8:
		var e: Vector3i = v + corners[t]
		if cells.has(e):
			continue
		if int(columns.get(Vector2i(e.x, e.z), -2147483648)) >= v.y + band:
			return false
	return true

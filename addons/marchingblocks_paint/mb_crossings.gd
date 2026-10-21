@tool
extends RefCounted
## CROSSINGS — stairs and slopes set OVER the painted world (MarchingBlocks's Crossings workshop, 20 October 2026). The
## `crossings` key of world.json, read and checked here; where each one sits (`transform_of`). The rule is written in
## the world's README.txt (`regle_franchisseurs` of the tool): a crossing's mesh is in MODEL space, in cells — x across
## its width, y up, climbing toward -z, its foot at z = 0 — and a placement names its FOOT cell and a quarter turn.

const KINDS := ["stairs", "slope"]
## The climbing direction of each quarter turn.
const DIRECTIONS := [Vector3i(0, 0, -1), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0)]


## {"crossings": {"models": [...], "placements": [[model, x, y, z, quarter], ...]}} or {"error"}; absent: no crossing.
static func read(world: Variant) -> Dictionary:
	var c = world.get("crossings", null) if world is Dictionary else null
	if c == null:
		return {"crossings": {"models": [], "placements": []}}
	if not c is Dictionary or not c.get("models") is Array or not c.get("placements", []) is Array:
		return {"error": "crossings: not {models, placements}"}
	var models: Array = []
	var ids := {}
	for m in c["models"]:
		if not m is Dictionary or not m.has("id") or not str(m.get("kind", "")) in KINDS:
			return {"error": "crossings: a model is malformed"}
		for k in ["width", "height", "depth"]:
			if not (m.get(k, 1) is float or m.get(k, 1) is int) or int(m.get(k, 1)) < 1:
				return {"error": "crossings: %s of model %s is not a positive integer" % [k, m["id"]]}
		models.append({"id": int(m["id"]), "name": str(m.get("name", "Crossing")), "kind": str(m["kind"]),
			"width": int(m.get("width", 1)), "height": int(m.get("height", 1)), "depth": int(m.get("depth", 1)),
			"mesh": m.get("mesh", null) if m.get("mesh", null) is String else null})
		ids[int(m["id"])] = true
	var flat: Array = c.get("placements", [])
	if flat.size() % 5 != 0:
		return {"error": "crossings: placements are not groups of 5 numbers"}
	var placements: Array = []
	for k in range(0, flat.size(), 5):
		if not ids.has(int(flat[k])):
			return {"error": "crossings: a placement names an unknown model (%s)" % flat[k]}
		placements.append([int(flat[k]), int(flat[k + 1]), int(flat[k + 2]), int(flat[k + 3]), posmod(int(flat[k + 4]), 4)])
	return {"crossings": {"models": models, "placements": placements}}


## Where a crossing's model sits, in FORMAT space (cell c covers [c, c + 1]).
static func transform_of(m: Dictionary, foot: Vector3i, quarter: int) -> Transform3D:
	var q := posmod(quarter, 4)
	var b := Basis(Vector3.UP, -q * PI / 2.0)
	var d := Vector3(DIRECTIONS[q])
	var r := Vector3(-d.z, 0.0, d.x)
	var w := float(m["width"])
	var depth := float(m["depth"])
	var h := float(m["height"])
	var centre_world := Vector3(foot) + Vector3(0.5, 0.0, 0.5) + d * (depth - 1.0) / 2.0 + r * (w - 1.0) / 2.0 \
		+ Vector3(0.0, h / 2.0, 0.0)
	var centre_local := Vector3(w / 2.0, h / 2.0, -depth / 2.0)
	return Transform3D(b, centre_world - b * centre_local)

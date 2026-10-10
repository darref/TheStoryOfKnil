@tool
extends Node
## THE WORLD EDITING TOOLS in the 3D viewport — aiming, strokes, boxes, paste, keys and preview.
##
## The rules live in `mb_tools.gd` (pure, proven by `tools_conformance.json`); this node only aims,
## previews and applies. It knows nothing of the editor: `plugin.gd` hands it the edited world, the
## camera's events and an undo object — Godot's EditorUndoRedoManager in the editor, a plain UndoRedo in
## tests (both have create_action / add_do_method / add_undo_method / commit_action).
##
##   AIM      grid — the floor plane (Page Up / Page Down move it) · sculpt — the matter itself
##            Tab switches the two
##   NAVIGATE a switch, not an aim — Space turns it on and off: the viewport flies as usual (right drag +
##            W A S D, Q E) and no click paints. The aim is kept, and comes back as it was.
##   TOOLS    add (A) · dig (D) · select (S) · rect (G) · box (B)      Shift does the opposite
##   VARIANT  (V) click a tile: its next variant (base → 1 → … → base); Shift + click gives it back to the
##            random draw (the tileset rule, step 8). Always aimed at the matter.
##   BRUSH    size 1–7 ([ and ]), sphere / cube / disc
##   SHAPES   tunnel · well · bridge · balcony · stairs (`mb_shapes.gd`), always aimed at the matter:
##            Straight is one click square out of a face; Connect is two clicks, two faces anywhere (two
##            floors for stairs; Escape forgets the first)
##   KEYS     Delete · Escape · arrows move the selection (they follow the camera; Shift + up / down
##            lift) · Ctrl+C / Ctrl+X / Ctrl+V
##   EXTRUDE  up · down · facing, on the selection or the floor's matter: a click adds matter (the selection and
##            the floor follow), Shift + click extends the selection, Alt + click moves it (`Tools.extrude`)
##   WHEEL    the MarchingBlocks tool's rule (editing_conformance.json, "THE MOUSE WHEEL"): alone it zooms, except
##            during a gesture (a Rect / Box drag: its height; a Room traced: its floors; a paste: its height);
##            Ctrl: the floor; Ctrl + Shift: the Stairs' step; with a selection and Select · Rect · Box: Shift extends
##            it up / down, Alt widens it (up) or shrinks its edge (down); a shape: Alt its size (a Room: its
##            floors), Shift its length (a Room rises / sinks); Add · Dig · Select: Alt the brush size, Shift the next
##            brush shape. Navigate never takes it. Each notch says its value near the mouse (`hint`).
##
## The right mouse button is never taken: Godot's free look works in every aim.

signal changed

const Tools := preload("res://addons/marchingblocks_paint/mb_tools.gd")
const Shapes := preload("res://addons/marchingblocks_paint/mb_shapes.gd")
const Planting := preload("res://addons/marchingblocks_paint/mb_planting.gd")

const AIMS := ["grid", "sculpt"]
const MODES := ["add", "dig", "select", "rect", "box", "shape", "variant", "plant"]
## The Plant tool's placing modes (`mb_foliage.gd`): in the air, planted with a free neighbourhood, planted overflowing.
const PLANT_MODES := ["air", "free", "overflow"]
## A brush stroke dabs again once the mouse has gone this part of the brush radius (the tool's step).
const PLANT_STEP := 0.4
const REACH := 2000.0
const MAX_DRAWN := 4000
const ADD_COLOUR := Color(0.55, 0.82, 0.45, 0.35)
const DIG_COLOUR := Color(0.9, 0.35, 0.25, 0.35)
const SELECT_COLOUR := Color(0.95, 0.8, 0.3, 0.3)
const SELECTION_COLOUR := Color(0.35, 0.7, 1.0, 0.22)

var world: Node3D:
	set(value):
		if world == value:
			return
		_forget_drawing()
		world = value
		selection = {}
		_cancel()
var undo: Object
var aim := "grid"
## Space — flying through the world; nothing is aimed, nothing paints. Choosing an aim turns it off.
var navigating := false
var mode := "add"
var brush_size := 1
var shape := "sphere"
var hollow := false
## The special shape (mode "shape"): which one, one click or two, and its settings.
var special := "tunnel"
var connect_ends := false
var profile := "round"
var shape_size := 2
var shape_length := 8
var rail := true
## One-click stairs: how deep each step is, 1 to Shapes.STEP_MAX cells.
var stairs_step := 2
## The room: drawn flat on the floor grid, then raised (up) or sunk (down) by this many free floors.
var room_floors := 3
var room_up := true
## The first end of a Connect: {"cell", "face"}, empty otherwise.
var shape_anchor := {}
## The Select brush takes the EMPTY cells too ("Select empty cells too"): paint a room's footprint on the floor.
var select_empty := false
## What the last wheel notch did, said near the mouse (the plugin draws it over the viewport), where, and when.
var hint := ""
var hint_at := Vector2.ZERO
var hint_msec := -100000
var selection := {}
var clipboard: Array[Vector3i] = []
var pasting := false
## What the last operation did, for the toolbar.
var status := ""
## THE PLANT TOOL (mode "plant") — the world's MarchingBlocksFoliage plants: the model (its id; -1 or unknown: the
## first one), the placing mode, the brush (radius in cells, tries per dab), the least distance between two plants,
## the steepest ground taken, a random yaw. Click plants one; Ctrl + click (and drag) a dab of the brush; Shift +
## click (and drag) erases within the brush. Each stroke is ONE undo step.
var plant_model := -1
var plant_mode := "free"
var plant_radius := 3.0
var plant_tries := 12
var plant_spacing := 0.0
var plant_slope := 40.0
var plant_random_yaw := true
## The draws of the plant tool (yaw, scale, the brush's spots). Seeded by the tests.
var plant_draw := RandomNumberGenerator.new()

var _stroking := false
var _stroke_inverse := false
var _stroke_control := false
var _last_key := ""
var _placed := {}
var _stroke_set := {}
var _stroke_clear := {}
## What the stroke took from the other layers of the world: {layer: {cell: true}}.
var _stroke_taken := {}
var _box_start: Variant = null
var _box_end := Vector3i.ZERO
## The wheel during a Rect / Box drag: how many cells the box rises (or sinks) from the drawn corner.
var _box_lift := 0
## The wheel during a paste: how many cells the paste is lifted.
var _paste_lift := 0
var _preview: MultiMeshInstance3D
var _selection_view: MultiMeshInstance3D
var _last_mouse := Vector2(-1, -1)
## A plant stroke: the foliage node, its plants before, what the world asks (built once), the gesture ("one",
## "sow", "erase") and where it last dabbed.
var _plant_foliage: Node
var _plant_before := PackedFloat32Array()
var _plant_ask := {}
var _plant_gesture := ""
var _plant_last: Variant = null


## Feeds one viewport event. Returns true when the event is taken (the editor must not act on it).
func input(camera: Camera3D, event: InputEvent) -> bool:
	if world == null or not is_instance_valid(world):
		return false
	var key := event as InputEventKey
	if navigating:
		# Navigating takes nothing but Space (to stop) and Tab (to pick an aim): the mouse and the other keys
		# fly the viewport, as usual. Not while the right button flies — Space is not ours then.
		if key != null and key.pressed and not key.echo and key.keycode in [KEY_SPACE, KEY_TAB] \
				and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			if key.keycode == KEY_TAB:
				set_aim(AIMS[(AIMS.find(aim) + 1) % AIMS.size()])
			else:
				set_navigating(false)
			return true
		_show_preview([], ADD_COLOUR)
		return false
	if key != null:
		return _key(camera, key)
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		return _left_button(camera, button)
	if button != null and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var taken := wheel(1 if button.button_index == MOUSE_BUTTON_WHEEL_UP else -1, button.alt_pressed,
			button.shift_pressed, button.ctrl_pressed or button.meta_pressed, button.pressed)
		if taken and button.pressed:
			hint_at = button.position
			if _last_mouse.x >= 0.0:
				hover(camera, _last_mouse, false)
		return taken
	var motion := event as InputEventMouseMotion
	if motion != null:
		_last_mouse = motion.position
		hover(camera, motion.position, motion.shift_pressed)
		return _stroking or _box_start != null or _plant_gesture != ""
	return false


## Choosing an aim also stops navigating: you pick an aim to aim.
func set_aim(value: String) -> void:
	aim = value
	navigating = false
	_cancel()
	changed.emit()


func set_navigating(on: bool) -> void:
	navigating = on
	_cancel()
	if on:
		_show_preview([], ADD_COLOUR)
	changed.emit()


func set_mode(value: String) -> void:
	mode = value
	_cancel()
	changed.emit()


func _drawing_room() -> bool:
	return mode == "shape" and special == "room"


## Picks a special shape: the mode becomes "shape".
func set_special(value: String) -> void:
	special = value
	mode = "shape"
	_cancel()
	changed.emit()


func set_connect(on: bool) -> void:
	connect_ends = on
	_cancel()
	changed.emit()


# ── Aiming ──────────────────────────────────────────────────────────────────────────────────────────

## {"hit", "cell", "normal"}: the matter in sculpt (when the ray meets it), the floor otherwise; {} when
## neither is under the mouse.
func aimed(camera: Camera3D, position: Vector2, for_add: bool) -> Dictionary:
	var origin := camera.project_ray_origin(position)
	var direction := camera.project_ray_normal(position)
	if aim == "sculpt":
		var cells: Dictionary = world.cells()
		var r: Dictionary = Tools.ray(func(c: Vector3i) -> bool: return cells.has(c),
			world.world_to_cells(origin), world.world_direction_to_cells(direction), REACH,
			_placed if for_add else {})
		if r["hit"]:
			return r
	var c = world.cell_under_ray(origin, direction)
	if c == null:
		return {}
	return {"hit": false, "cell": c, "normal": Vector3i.ZERO}


## The rect ignores the aim: it always lies flat on the floor — the gesture that draws a room's floor. So does
## the room itself.
func _corner(camera: Camera3D, position: Vector2) -> Variant:
	if mode == "rect" or _drawing_room():
		return world.cell_under_ray(camera.project_ray_origin(position), camera.project_ray_normal(position))
	var p := aimed(camera, position, false)
	return null if p.is_empty() else p["cell"]


func _gesture(inverse: bool) -> String:
	match mode:
		"add":
			return "dig" if inverse else "add"
		"dig":
			return "add" if inverse else "dig"
	return "select"


# ── Hover and strokes ───────────────────────────────────────────────────────────────────────────────

func hover(camera: Camera3D, position: Vector2, shift := false) -> void:
	if mode == "plant":
		_hover_plant(camera, position, shift)
		return
	if _drawing_room():
		var corner = _corner(camera, position)
		if _box_start == null:
			_show_preview([] if corner == null else [corner], ADD_COLOUR)
			return
		if corner != null:
			_box_end = corner
		var r: Dictionary = Shapes.room(world.cells(), _box_start, _box_end, room_floors, room_up)
		status = "" if r["error"] == "" else "Room — " + SHAPE_ERRORS.get(r["error"], r["error"])
		_show_preview(r["set"].keys(), ADD_COLOUR)
		return
	if mode == "shape":
		_hover_shape(camera, position)
		return
	if mode == "variant":
		var h := _matter_hit(camera, position)
		_show_preview([] if h.is_empty() else [h["cell"]], SELECT_COLOUR)
		return
	if pasting:
		var p := aimed(camera, position, true)
		var cells: Array = []
		if not p.is_empty():
			var at := Tools.anchor("add", p) + Vector3i(0, _paste_lift, 0)
			for d in clipboard:
				cells.append(at + d)
		_show_preview(cells, ADD_COLOUR)
		return
	if mode == "rect" or mode == "box":
		var corner = _corner(camera, position)
		if _box_start != null:
			if corner != null:
				_box_end = corner
			_show_preview(Tools.box(_box_start, _lifted_end(), hollow and mode == "box").keys(),
				DIG_COLOUR if _stroke_control else SELECT_COLOUR)
		else:
			_show_preview([] if corner == null else [corner], SELECT_COLOUR)
		return
	var g := _gesture(_stroke_inverse if _stroking else shift)
	var p := aimed(camera, position, g == "add")
	if p.is_empty():
		_show_preview([], ADD_COLOUR)
		return
	var at := Tools.anchor(g, p)
	var cells := Tools.brush(at, p["normal"], brush_size, shape)
	_show_preview(cells, {"add": ADD_COLOUR, "dig": DIG_COLOUR}.get(g, SELECT_COLOUR))
	if _stroking:
		_touch(g, at, p["normal"], cells)


func _touch(g: String, at: Vector3i, normal: Vector3i, cells: Array) -> void:
	# The same cell under the same face twice in a row is nothing new.
	var key := "%s|%s" % [at, normal]
	if key == _last_key:
		return
	_last_key = key
	if g == "select":
		var full: Dictionary = world.cells()
		Tools.select_brush(selection, cells, func(c: Vector3i) -> bool: return full.has(c), select_empty,
			_stroke_control)
		_draw_selection()
		return
	var full: Dictionary = world.cells()
	var change: Dictionary = Tools.modify(g, cells, func(c: Vector3i) -> bool: return full.has(c))
	if change["set"].is_empty() and change["clear"].is_empty():
		return
	# The stroke lock: what this stroke placed is transparent to its own ray, or dragging would build a
	# tower towards the camera instead of a skin on the surface.
	_placed.merge(change["set"])
	_stroke_set.merge(change["set"])
	_stroke_clear.merge(change["clear"])
	var taken: Dictionary = world.apply_cells(change["set"].keys(), change["clear"].keys())
	for l in taken:
		if not _stroke_taken.has(l):
			_stroke_taken[l] = {}
		for c in taken[l]:
			_stroke_taken[l][c] = true


func _left_button(camera: Camera3D, b: InputEventMouseButton) -> bool:
	if b.alt_pressed:
		return false
	if mode == "plant":
		if b.pressed:
			_start_plant(camera, b.position, b.ctrl_pressed or b.meta_pressed, b.shift_pressed)
		else:
			_end_plant()
		return true
	if mode == "variant":
		if b.pressed:
			click_variant(camera, b.position, b.shift_pressed)
		return true
	if _drawing_room():
		# The room is DRAWN like the rect: press a corner, drag, release — then it rises (or sinks), one Ctrl+Z.
		if b.pressed:
			var corner = _corner(camera, b.position)
			if corner != null:
				_box_start = corner
				_box_end = corner
		elif _box_start != null:
			var r: Dictionary = Shapes.room(world.cells(), _box_start, _box_end, room_floors, room_up)
			_box_start = null
			if r["error"] != "":
				status = "Room — " + SHAPE_ERRORS.get(r["error"], r["error"])
			else:
				_commit("MarchingBlocks room", r["set"], r["clear"])
				status = "Room — %d cell(s) of shell, %d dug out%s." % [r["set"].size(), r["clear"].size(),
					"" if int(r["repaired"]) == 0 else ", %d added where it touched the world by an edge" % int(r["repaired"])]
			_show_preview([], ADD_COLOUR)
			changed.emit()
		return true
	if mode == "shape":
		if b.pressed:
			click_shape(camera, b.position)
		return true
	if b.pressed:
		if pasting:
			var p := aimed(camera, b.position, true)
			if not p.is_empty():
				var change: Dictionary = Tools.paste(world.cells(), clipboard,
					Tools.anchor("add", p) + Vector3i(0, _paste_lift, 0))
				_commit("Paste", change["set"], {})
				_set_selection(change["selection"])
				pasting = false
			return true
		if mode == "rect" or mode == "box":
			var corner = _corner(camera, b.position)
			if corner != null:
				_box_start = corner
				_box_end = corner
				_box_lift = 0
				_stroke_control = b.ctrl_pressed
				_stroke_inverse = b.shift_pressed
			return true
		_stroking = true
		_stroke_inverse = b.shift_pressed
		_stroke_control = b.ctrl_pressed
		_last_key = ""
		_placed = {}
		_stroke_set = {}
		_stroke_clear = {}
		_stroke_taken = {}
		if mode == "select" and not b.shift_pressed and not b.ctrl_pressed:
			selection = {}
		hover(camera, b.position, b.shift_pressed)
		return true
	# Released.
	if _box_start != null:
		var volume: Dictionary = Tools.box(_box_start, _lifted_end(), hollow and mode == "box")
		if volume.is_empty():
			status = "Box too large — more than %d cells. Draw a smaller one." % Tools.BOX_VOLUME_MAX
		else:
			if not _stroke_inverse and not _stroke_control:
				selection = {}
			for c in volume:
				if _stroke_control:
					selection.erase(c)
				else:
					selection[c] = true
		_box_start = null
		_draw_selection()
		changed.emit()
		return true
	if _stroking:
		_stroking = false
		# The stroke is already on screen: the action is recorded WITHOUT running it again.
		if not _stroke_set.is_empty() or not _stroke_clear.is_empty():
			_record("MarchingBlocks stroke", _stroke_set, _stroke_clear, false, 0, _stroke_taken)
		changed.emit()
		return true
	return false


# ── Special shapes ──────────────────────────────────────────────────────────────────────────────────
#
# A shape starts from a FACE, so it always aims at the matter, whatever the aim (the grid has no face).

const SHAPE_NAMES := {"tunnel": "Tunnel", "well": "Well", "bridge": "Bridge", "balcony": "Balcony",
	"stairs": "Stairs", "room": "Room"}
const SHAPE_ERRORS := {
	"too_small": "a room is at least 3 x 3 cells: draw a bigger rectangle.",
	"needs_a_wall": "click a WALL, a side face of the matter.",
	"needs_floor_or_ceiling": "click a FLOOR or a CEILING, a top or bottom face.",
	"needs_a_floor": "click two FLOORS, the top face of the matter.",
	"too_steep": "too steep: one cell up for each cell across at most. Pick two floors further apart.",
	"same_cell": "the second end must be another cell.",
	"too_far": "the two ends are too far apart.",
	"nothing_in_front": "no wall in front within reach. Raise the length, or Connect two walls.",
	"too_large": "too large. Make it smaller or shorter.",
	"unknown_shape": "unknown shape.",
}


## THE VARIANT TOOL (step 8): the tile under the mouse — its vertex, `Tools.tile_vertex` — shows its next
## variant (base → 1 → … → base); `back_to_draw` (Shift) removes the choice: the tile follows the random draw
## again. One undo step. Only a tile THIS layer placed: the ray meets this layer's cells, as the other tools do.
func click_variant(camera: Camera3D, position: Vector2, back_to_draw := false) -> void:
	var origin: Vector3 = world.world_to_cells(camera.project_ray_origin(position))
	var direction: Vector3 = world.world_direction_to_cells(camera.project_ray_normal(position))
	var cells: Dictionary = world.cells()
	var r: Dictionary = Tools.ray(func(c: Vector3i) -> bool: return cells.has(c), origin, direction, REACH)
	if not r["hit"]:
		status = "Variant — point at a tile of this layer."
		changed.emit()
		return
	var v := Tools.tile_vertex(origin, direction, r["cell"], r["normal"])
	var info: Dictionary = world.variant_at(v)
	if info.is_empty():
		status = "Variant — no tile of this layer there."
	elif int(info["variants"]) == 0:
		status = "Variant — '%s' has no variant." % info["key"]
	else:
		var before: Dictionary = (world.variant_choices as Dictionary).duplicate()
		var after := before.duplicate()
		if back_to_draw:
			if not after.has(v):
				status = "Variant — this tile already follows the random draw."
				changed.emit()
				return
			after.erase(v)
			status = "Variant — '%s' is back to the random draw." % info["key"]
		else:
			after[v] = (int(info["current"]) + 1) % (int(info["variants"]) + 1)
			status = "Variant — '%s': %s. Shift + click gives it back to the draw." % [info["key"],
				"the base tile" if int(after[v]) == 0 else "variant %d" % int(after[v])]
		if undo != null:
			undo.create_action("MarchingBlocks variant")
			undo.add_do_property(world, "variant_choices", after)
			undo.add_undo_property(world, "variant_choices", before)
			undo.commit_action()
		else:
			world.variant_choices = after
	changed.emit()


func _matter_hit(camera: Camera3D, position: Vector2) -> Dictionary:
	var cells: Dictionary = world.cells()
	var r: Dictionary = Tools.ray(func(c: Vector3i) -> bool: return cells.has(c),
		world.world_to_cells(camera.project_ray_origin(position)),
		world.world_direction_to_cells(camera.project_ray_normal(position)), REACH)
	return r if r["hit"] else {}


func _waiting_for_first_end() -> bool:
	return connect_ends and shape_anchor.is_empty() and special != "balcony"


## What the shape would do with this face: the first end of a Connect is already set, or it is one click.
func shape_request(hit: Dictionary) -> Dictionary:
	var p := {"shape": special, "profile": profile, "size": shape_size, "length": shape_length, "rail": rail,
		"step": stairs_step, "connect": false, "a": hit["cell"], "face_a": hit["normal"]}
	if connect_ends and not shape_anchor.is_empty() and special != "balcony":
		p["connect"] = true
		p["a"] = shape_anchor["cell"]
		p["face_a"] = shape_anchor["face"]
		p["b"] = hit["cell"]
		p["face_b"] = hit["normal"]
	return p


func _hover_shape(camera: Camera3D, position: Vector2) -> void:
	var hit := _matter_hit(camera, position)
	var anchor_cells: Array = [] if shape_anchor.is_empty() else [shape_anchor["cell"]]
	if hit.is_empty():
		_show_preview(anchor_cells, SELECT_COLOUR)
		return
	if _waiting_for_first_end():
		_show_preview([hit["cell"]], SELECT_COLOUR)
		return
	var r: Dictionary = Shapes.shape(world.cells(), shape_request(hit))
	if r["error"] != "":
		_show_preview([hit["cell"]], DIG_COLOUR)
	elif not r["clear"].is_empty():
		_show_preview(r["clear"].keys() + anchor_cells, DIG_COLOUR)
	else:
		_show_preview(r["set"].keys() + anchor_cells, ADD_COLOUR)


## A click: the first end of a Connect, or the shape itself — ONE undo step.
func click_shape(camera: Camera3D, position: Vector2) -> void:
	var hit := _matter_hit(camera, position)
	if hit.is_empty():
		return
	var name: String = SHAPE_NAMES.get(special, special)
	if _waiting_for_first_end():
		if Shapes.normal_for(special, world.cells(), hit["cell"], hit["normal"], true) == Vector3i.ZERO:
			status = "%s — %s" % [name, SHAPE_ERRORS[Shapes.end_error(special, true)]]
		else:
			shape_anchor = {"cell": hit["cell"], "face": hit["normal"]}
			status = "%s — first end set. Click the second one (Escape forgets it)." % name
		changed.emit()
		hover(camera, position)
		return
	var r: Dictionary = Shapes.shape(world.cells(), shape_request(hit))
	if r["error"] != "":
		status = "%s — %s" % [name, SHAPE_ERRORS.get(r["error"], r["error"])]
		changed.emit()
		return
	shape_anchor = {}
	_commit("MarchingBlocks " + name, r["set"], r["clear"])
	var n: int = r["set"].size() + r["clear"].size()
	var more: String = (", %d more so that no two cells touch by an edge only" % r["repaired"]) if r["repaired"] > 0 else ""
	status = "%s — %d cell(s) changed%s. Ctrl+Z undoes it." % [name, n, more]
	changed.emit()
	hover(camera, position)


# ── The Plant tool ──────────────────────────────────────────────────────────────────────────────────
#
# The rule is `mb_foliage.gd` (proven by foliage_conformance.json); `mb_planting.gd` gives it this world (cells, water,
# the ground of the placed tiles) and makes the gestures. Here: the strokes and the undo.

## The world's MarchingBlocksFoliage node, or null (said in the status).
func foliage() -> Node:
	return Planting.foliage_of(world)


## The model the tool plants: the chosen one, or the first of the foliage when it is unknown. -1: none.
func current_plant_model() -> int:
	var f := foliage()
	if f == null:
		return -1
	var ids: Array = Planting.models_of(f).keys()
	if ids.is_empty():
		return -1
	return plant_model if ids.has(plant_model) else int(ids[0])


func plant_settings() -> Dictionary:
	return {"model": current_plant_model(), "mode": plant_mode, "radius": plant_radius, "tries": plant_tries,
		"spacing": plant_spacing, "max_slope": plant_slope, "random_yaw": plant_random_yaw}


func _hover_plant(camera: Camera3D, position: Vector2, shift: bool) -> void:
	# Only the matter is needed to aim: the whole world (water, tiles) is asked once per stroke.
	var asked: Dictionary = _plant_ask if _plant_gesture != "" else Planting.matter(world)
	var o: Vector3 = world.world_to_cells(camera.project_ray_origin(position))
	var d: Vector3 = world.world_direction_to_cells(camera.project_ray_normal(position))
	var p = Planting.aimed_point(asked, o, d, plant_mode, world.floor_y)
	if p == null:
		_show_preview([], ADD_COLOUR)
		return
	var at := Vector3i(floori(p.x), floori(p.y - (0.0 if plant_mode == "air" else 0.5)), floori(p.z))
	var erasing := _plant_gesture == "erase" if _plant_gesture != "" else shift
	_show_preview([at], DIG_COLOUR if erasing else ADD_COLOUR)
	# A brush or erase stroke dabs again once the mouse has gone PLANT_STEP of the radius.
	if _plant_gesture in ["sow", "erase"] and _plant_last != null 			and (p as Vector3).distance_to(_plant_last) >= plant_radius * PLANT_STEP:
		_plant_dab(o, d)


## A press of the Plant tool: one plant, a dab of the brush (Ctrl), or erase (Shift). The stroke ends on release.
func _start_plant(camera: Camera3D, position: Vector2, brush: bool, erase: bool) -> void:
	_end_plant()
	var f := foliage()
	if f == null:
		status = ("Plant — this world has no MarchingBlocksFoliage node: import a world exported with foliage, or add "
			+ "one next to the layers and give it models.")
		changed.emit()
		return
	_plant_foliage = f
	_plant_before = (f.plants as PackedFloat32Array).duplicate()
	_plant_ask = Planting.ask(world)
	_plant_gesture = "erase" if erase else ("sow" if brush else "one")
	_plant_last = null
	_plant_dab(world.world_to_cells(camera.project_ray_origin(position)),
		world.world_direction_to_cells(camera.project_ray_normal(position)))
	if _plant_gesture == "one":
		_end_plant()


func _plant_dab(origin: Vector3, direction: Vector3) -> void:
	var settings := plant_settings()
	var r: Dictionary
	match _plant_gesture:
		"erase":
			r = Planting.erase_at(world, _plant_foliage, origin, direction, settings, _plant_ask)
		"sow":
			r = Planting.sow_at(world, _plant_foliage, origin, direction, settings, plant_draw, _plant_ask)
		_:
			r = Planting.plant_at(world, _plant_foliage, origin, direction, settings, plant_draw, _plant_ask)
	_plant_last = Planting.aimed_point(_plant_ask, origin, direction, plant_mode, world.floor_y)
	if r["plants"] != null:
		_plant_foliage.plants = r["plants"]
	status = r["status"]
	changed.emit()


## The end of a stroke: what it planted or erased becomes ONE undo step (already on screen: recorded, not run again).
func _end_plant() -> void:
	if _plant_gesture == "":
		return
	var f := _plant_foliage
	var before := _plant_before
	_plant_gesture = ""
	_plant_foliage = null
	_plant_ask = {}
	_plant_last = null
	if f == null or not is_instance_valid(f) or f.plants == before:
		return
	var after: PackedFloat32Array = (f.plants as PackedFloat32Array).duplicate()
	if undo == null:
		return
	undo.create_action("MarchingBlocks plants")
	undo.add_do_property(f, "plants", after)
	undo.add_undo_property(f, "plants", before)
	undo.commit_action(false)


# ── Operations (the toolbar calls these too) ────────────────────────────────────────────────────────

func operate(op: String) -> int:
	if selection.is_empty():
		status = "Nothing selected. Drag a Rect (G) on the floor, a Box (B), or paint with Select (S)."
		changed.emit()
		return 0
	var r: Dictionary = Tools.operate(world.cells(), selection, op)
	var step := 1 if op == "extrude_up" else (-1 if op == "extrude_down" else 0)
	_commit(op.capitalize(), r["set"], r["clear"], step)
	_set_selection(r["selection"])
	status = "%s — %d cell(s) changed, %d selected. Ctrl+Z undoes the cells." % [op.capitalize(),
		r["set"].size() + r["clear"].size(), selection.size()]
	changed.emit()
	return r["set"].size() + r["clear"].size()


## EXTRUDE up, down or facing (`Tools.extrude`) on the selection, or on the matter of the floor when nothing is
## selected. `how`: place (a click), extend (Shift + click, "Extend selection") or shift (Alt + click); "" reads the
## keys held now. The selection follows, and the floor follows the step up or down — ONE undo step.
func extrude(direction: String, how := "") -> void:
	if world == null:
		return
	if how == "":
		how = "extend" if Input.is_key_pressed(KEY_SHIFT) else ("shift" if Input.is_key_pressed(KEY_ALT) else "place")
	var had_selection := not selection.is_empty()
	var on: String = ("the selection (%d cells)" % selection.size()) if had_selection else "floor %d" % world.floor_y
	var r: Dictionary = Tools.extrude(world.cells(), world.floor_y, direction, selection, how)
	var step: Vector3i = r["step"]
	if step == Vector3i.ZERO:
		status = "Nothing to extrude on %s — %s" % [on, "no cell has matter behind it and air in front."
			if direction == "facing" else "it holds no matter."]
		changed.emit()
		return
	var way: String = STEP_NAMES.get(step, "")
	_commit("Extrude " + way, r["set"], r["clear"], step.y)
	if how != "place" or had_selection:
		_set_selection(r["selection"])
	match how:
		"extend":
			status = "Selection extended %s — %d cell(s) selected. No matter added." % [way, selection.size()]
		"shift":
			status = "Selection moved %s — %d cell(s). No matter added." % [way, selection.size()]
		_:
			status = ("Extrude %s on %s — %d cell(s) added. Click again to keep going; Shift + click extends the "
				+ "selection, Alt + click moves it.") % [way, on, (r["set"] as Dictionary).size()]
	changed.emit()


const STEP_NAMES := {Vector3i(0, 1, 0): "up", Vector3i(0, -1, 0): "down", Vector3i(1, 0, 0): "toward X+",
	Vector3i(-1, 0, 0): "toward X-", Vector3i(0, 0, 1): "toward Z+", Vector3i(0, 0, -1): "toward Z-"}


## SHRINK: the edge of the selection leaves (`Tools.shrink_edge`) — a rectangle loses its rim. No cell changes.
func shrink_selection() -> void:
	var before := selection.size()
	_set_selection(Tools.shrink_edge(selection))
	status = "Shrink — %d cell(s) selected (%d dropped)." % [selection.size(), before - selection.size()]
	changed.emit()


## WIDEN: a flat ring around the selection, empty cells included (`Tools.widen_flat`). No cell changes.
func widen_selection() -> void:
	_set_selection(Tools.widen_flat(selection))
	status = "Widen — %d cell(s) selected." % selection.size()
	changed.emit()


## ROOM FROM SELECTION (`Shapes.room_from_selection`): the selection seen from above becomes a room — its outline the
## walls, the whole footprint the floor and the ceiling, the inside dug out; Floors and Up / Down are the Room shape's.
## ONE undo step.
func room_from_selection() -> void:
	if world == null:
		return
	var r: Dictionary = Shapes.room_from_selection(world.cells(), selection, room_floors, room_up)
	match r["error"]:
		"empty":
			status = "Room from selection — nothing selected. Paint the footprint first: Select, with Select empty cells too."
		"too_small":
			status = "Room from selection — the footprint is too thin: a room needs at least one cell inside its walls."
		"too_large":
			status = "Room from selection — too large (more than %d cells)." % Shapes.VOLUME_MAX
		_:
			_commit("MarchingBlocks room from selection", r["set"], r["clear"])
			status = "Room from selection — %d cell(s) of shell, %d dug out%s." % [r["set"].size(), r["clear"].size(),
				"" if int(r["repaired"]) == 0 else ", %d added where it touched the world by an edge" % int(r["repaired"])]
	changed.emit()


## The far corner of a Rect / Box drag, lifted by the wheel: a flat Rect becomes a box.
func _lifted_end() -> Vector3i:
	return _box_end + Vector3i(0, _box_lift, 0)


## THE MOUSE WHEEL — the MarchingBlocks tool's rule (editing_conformance.json, "THE MOUSE WHEEL"). `notch` +1 up, -1
## down. Returns true when the notch is ours (the editor must not zoom); acts only when `act` (the press — a wheel
## notch is a press and a release).
func wheel(notch: int, alt: bool, shift: bool, ctrl: bool, act := true) -> bool:
	if world == null or navigating:
		return false
	# During a gesture: the wheel alone.
	if not (alt or shift or ctrl):
		if pasting:
			if act:
				_paste_lift += notch
				_say("Paste height %+d" % _paste_lift)
			return true
		if _box_start != null and _drawing_room():
			if act:
				room_floors = clampi(room_floors + notch, 1, Shapes.ROOM_FLOORS_MAX)
				_say("Floors %d" % room_floors)
			return true
		if _box_start != null and mode in ["rect", "box"]:
			if act:
				_box_lift += notch
				_say("Height %+d" % _box_lift if _box_lift != 0 else "Flat")
			return true
		return false
	if ctrl and shift and mode == "shape" and special == "stairs":
		if act:
			stairs_step = clampi(stairs_step + notch, 1, Shapes.STEP_MAX)
			_say("Step %d" % stairs_step)
		return true
	if ctrl:
		if act:
			_set_floor(world.floor_y + notch)
			_say("Floor %d" % world.floor_y)
		return true
	if mode == "plant":
		# The tool's: Alt the brush size, Shift its density.
		if act:
			if alt:
				plant_radius = clampf(plant_radius + 0.5 * notch, 0.5, 32.0)
				_say("Brush %.1f" % plant_radius)
			else:
				plant_tries = clampi(plant_tries + notch, 1, 200)
				_say("Density %d" % plant_tries)
		return true
	if mode == "shape":
		if special == "room":
			if act:
				if alt:
					room_floors = clampi(room_floors + notch, 1, Shapes.ROOM_FLOORS_MAX)
					_say("Floors %d" % room_floors)
				else:
					room_up = notch > 0
					_say("Rises" if room_up else "Sinks")
		elif act:
			if alt:
				shape_size = clampi(shape_size + notch, 1, 7)
				_say("Size %d" % shape_size)
			elif special == "balcony" or not connect_ends:
				shape_length = clampi(shape_length + notch, 1, Shapes.LENGTH_MAX)
				_say("Length %d" % shape_length)
		return true
	if not selection.is_empty() and mode in ["select", "rect", "box"]:
		if act:
			var before := selection.size()
			if shift:
				extrude("up" if notch > 0 else "down", "extend")
			elif notch > 0:
				widen_selection()
			else:
				shrink_selection()
			var what: String = ("Extend up" if notch > 0 else "Extend down") if shift else ("Widen" if notch > 0 else "Shrink")
			_say("%s — %d cells" % [what, selection.size()] if selection.size() != before else "Selection unchanged")
		return true
	if mode in ["add", "dig", "select"]:
		if act:
			if alt:
				brush_size = clampi(brush_size + notch, 1, 7)
				_say("Brush size %d" % brush_size)
			else:
				shape = Tools.SHAPES[posmod(Tools.SHAPES.find(shape) + notch, Tools.SHAPES.size())]
				_say(shape.capitalize())
		return true
	return false


## Says a value near the mouse (the plugin draws `hint` over the viewport for a moment) and in the toolbar.
func _say(text: String) -> void:
	hint = text
	hint_msec = Time.get_ticks_msec()
	status = text
	changed.emit()


## The floor, as one undo step (Page Up / Page Down, Ctrl + wheel).
func _set_floor(value: int) -> void:
	if undo != null:
		undo.create_action("Change floor")
		undo.add_do_property(world, "floor_y", value)
		undo.add_undo_property(world, "floor_y", world.floor_y)
		undo.commit_action()
	else:
		world.floor_y = value


func move_selection(offset: Vector3i) -> void:
	if selection.is_empty():
		return
	var r: Dictionary = Tools.move(world.cells(), selection, offset)
	_commit("Move", r["set"], r["clear"])
	_set_selection(r["selection"])


func copy_selection() -> void:
	clipboard = Tools.copy(world.cells(), selection)
	status = "Nothing to copy: the selection holds no matter." if clipboard.is_empty() \
		else "Copied %d cell(s)." % clipboard.size()
	changed.emit()


func cut_selection() -> void:
	copy_selection()
	if not clipboard.is_empty():
		operate("delete")


func start_paste() -> void:
	pasting = not clipboard.is_empty()
	_paste_lift = 0
	status = "Pasting — click in the viewport (Escape cancels)." if pasting else "The clipboard is empty."
	changed.emit()


## Erases every cell of the world, in ONE undoable action.
func clear_world() -> void:
	if world == null or world.cells().is_empty():
		status = "The world is already empty."
		changed.emit()
		return
	var n: int = world.cells().size()
	_commit("Clear cells", {}, world.cells())
	status = "%d cell(s) cleared. Ctrl+Z brings them back." % n
	changed.emit()


func clear_selection() -> void:
	_set_selection({})
	pasting = false
	changed.emit()


## One undo step that RUNS the change. `floor_step` moves the floor with an extrusion, in the same step:
## so rect, fill, extrude, fill… keeps going without Page Up, and Ctrl+Z brings the floor back too.
func _commit(name: String, set_cells: Dictionary, clear_cells: Dictionary, floor_step := 0) -> void:
	_record(name, set_cells, clear_cells, true, floor_step)


## `taken`: for a stroke already applied, what it took from the other layers ({layer: {cell: true}}); for an
## action still to run, it is read here, before running.
func _record(name: String, set_cells: Dictionary, clear_cells: Dictionary, execute: bool, floor_step := 0,
		taken: Dictionary = {}) -> void:
	var s: Array = set_cells.keys()
	var c: Array = clear_cells.keys()
	if s.is_empty() and c.is_empty() and floor_step == 0:
		return
	if undo == null:
		if execute:
			world.apply_cells(s, c)
			world.floor_y += floor_step
		return
	if execute:
		var others: Dictionary = world.taken_from_others(s)
		for l in others:
			taken[l] = {}
			for cell in others[l]:
				taken[l][cell] = true
	undo.create_action(name)
	# Undoing apply(set, clear) is apply(clear, set): the set cells were empty, the cleared ones full.
	_call_in_undo(true, s, c)
	_call_in_undo(false, c, s)
	# A CELL BELONGS TO ONE LAYER: what this step took from the other layers goes back to them on undo (and
	# redo takes it again, inside apply_cells).
	for l in taken:
		_call_in_undo(false, (taken[l] as Dictionary).keys(), [], l)
	if floor_step != 0:
		undo.add_do_property(world, "floor_y", world.floor_y + floor_step)
		undo.add_undo_property(world, "floor_y", world.floor_y)
	undo.commit_action(execute)


## ⚠ THE TWO UNDO SYSTEMS DO NOT SPEAK ALIKE: a plain UndoRedo takes a Callable, the editor's
## EditorUndoRedoManager takes (object, method, arguments…) — so that it can tell which scene it belongs to.
func _call_in_undo(doing: bool, set_cells: Array, clear_cells: Array, layer: Node = null) -> void:
	var target: Node = world if layer == null else layer
	if undo is UndoRedo:
		var call: Callable = Callable(target, "apply_cells").bind(set_cells, clear_cells)
		if doing:
			undo.add_do_method(call)
		else:
			undo.add_undo_method(call)
	elif doing:
		undo.add_do_method(target, "apply_cells", set_cells, clear_cells)
	else:
		undo.add_undo_method(target, "apply_cells", set_cells, clear_cells)


# ── Keys ────────────────────────────────────────────────────────────────────────────────────────────

func _key(camera: Camera3D, k: InputEventKey) -> bool:
	if not k.pressed:
		return false
	# Never while flying: right drag + W A S D is Godot's free look.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		return false
	if k.ctrl_pressed or k.meta_pressed:
		match k.keycode:
			KEY_C:
				copy_selection()
			KEY_X:
				cut_selection()
			KEY_V:
				start_paste()
			_:
				return false
		return true
	if k.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		if selection.is_empty():
			return false
		move_selection(arrow_offset(camera, k.keycode, k.shift_pressed))
		return true
	if k.echo:
		return false
	match k.keycode:
		KEY_A:
			set_mode("add")
		KEY_D:
			set_mode("dig")
		KEY_S:
			set_mode("select")
		KEY_G:
			set_mode("rect")
		KEY_B:
			set_mode("box")
		KEY_V:
			set_mode("variant")
		KEY_TAB:
			set_aim(AIMS[(AIMS.find(aim) + 1) % AIMS.size()])
		KEY_SPACE:
			set_navigating(true)
		KEY_BRACKETLEFT:
			if _drawing_room():
				room_floors = maxi(1, room_floors - 1)
			elif mode == "shape":
				shape_size = maxi(1, shape_size - 1)
			else:
				brush_size = maxi(1, brush_size - 1)
			changed.emit()
		KEY_BRACKETRIGHT:
			if _drawing_room():
				room_floors = mini(Shapes.ROOM_FLOORS_MAX, room_floors + 1)
			elif mode == "shape":
				shape_size = mini(7, shape_size + 1)
			else:
				brush_size = mini(7, brush_size + 1)
			changed.emit()
		KEY_PAGEUP, KEY_PAGEDOWN:
			var step := 1 if k.keycode == KEY_PAGEUP else -1
			if undo != null:
				undo.create_action("Change floor")
				undo.add_do_property(world, "floor_y", world.floor_y + step)
				undo.add_undo_property(world, "floor_y", world.floor_y)
				undo.commit_action()
			else:
				world.floor_y += step
			changed.emit()
		KEY_DELETE:
			operate("delete")
		KEY_ESCAPE:
			if pasting or _box_start != null or not shape_anchor.is_empty():
				_cancel()
			else:
				clear_selection()
		_:
			return false
	if _last_mouse.x >= 0.0:
		hover(camera, _last_mouse, k.shift_pressed)
	return true


## The arrows FOLLOW THE CAMERA: "up" moves away from you along the cell axis (X or Z) closest to where
## the camera looks; Shift + up / down lift and lower.
func arrow_offset(camera: Camera3D, keycode: int, shift: bool) -> Vector3i:
	if shift and keycode in [KEY_UP, KEY_DOWN]:
		return Vector3i(0, 1 if keycode == KEY_UP else -1, 0)
	var forward: Vector3 = world.world_direction_to_cells(-camera.global_transform.basis.z)
	var right: Vector3 = world.world_direction_to_cells(camera.global_transform.basis.x)
	var axis := func(v: Vector3) -> Vector3i:
		return Vector3i(1 if v.x >= 0.0 else -1, 0, 0) if absf(v.x) >= absf(v.z) \
			else Vector3i(0, 0, 1 if v.z >= 0.0 else -1)
	var f: Vector3i = axis.call(forward)
	var r: Vector3i = axis.call(right)
	match keycode:
		KEY_UP:
			return f
		KEY_DOWN:
			return -f
		KEY_RIGHT:
			return r
	return -r


# ── Drawing ─────────────────────────────────────────────────────────────────────────────────────────

func _set_selection(cells: Dictionary) -> void:
	selection = cells.duplicate()
	_draw_selection()


func _cancel() -> void:
	_end_plant()
	pasting = false
	shape_anchor = {}
	_box_start = null
	_stroking = false
	if _preview != null and is_instance_valid(_preview):
		_preview.visible = false


func _draw_selection() -> void:
	if world == null:
		return
	if _selection_view == null or not is_instance_valid(_selection_view):
		_selection_view = _cloud(0.98)
	_fill(_selection_view, selection.keys(), SELECTION_COLOUR)


func _show_preview(cells: Array, colour: Color) -> void:
	if world == null:
		return
	if _preview == null or not is_instance_valid(_preview):
		_preview = _cloud(1.02)
	_fill(_preview, cells, colour)


## Translucent cubes, ONE draw call however many. An INTERNAL child of the world: never saved, never
## shown in the Scene dock.
func _cloud(side: float) -> MultiMeshInstance3D:
	var box := BoxMesh.new()
	box.size = Vector3.ONE * side
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = true
	box.material = m
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = box
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	world.add_child(inst, false, Node.INTERNAL_MODE_BACK)
	return inst


func _fill(cloud: MultiMeshInstance3D, cells: Array, colour: Color) -> void:
	var n: int = mini(cells.size(), MAX_DRAWN)
	var size: float = world.cell_size
	cloud.multimesh.instance_count = n
	for i in n:
		var c: Vector3i = cells[i]
		cloud.multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * size),
			(Vector3(c) + Vector3.ONE * 0.5) * size))
		cloud.multimesh.set_instance_color(i, colour)
	cloud.visible = n > 0


func _forget_drawing() -> void:
	for view in [_preview, _selection_view]:
		if view != null and is_instance_valid(view):
			view.queue_free()
	_preview = null
	_selection_view = null

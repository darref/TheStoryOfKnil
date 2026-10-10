@tool
extends EditorPlugin
## Registers the MarchingBlocksWorld node, and gives it the MarchingBlocks editing tools.
##
## Select a MarchingBlocksWorld: a toolbar appears above the 3D viewport (`mb_toolbar.gd`), and the viewport
## paints with it (`mb_editor.gd` does the work, `mb_tools.gd` holds the rules). Selecting its "Cells" child instead
## gives Godot's own GridMap editor, as before — both paint the same cells.

const World := preload("res://addons/marchingblocks_paint/mb_world.gd")
const Editor := preload("res://addons/marchingblocks_paint/mb_editor.gd")
const WorldFile := preload("res://addons/marchingblocks_paint/mb_world_file.gd")
const Toolbar := preload("res://addons/marchingblocks_paint/mb_toolbar.gd")
const TransitionsNode := preload("res://addons/marchingblocks_paint/mb_transitions_node.gd")
const FoliageNode := preload("res://addons/marchingblocks_paint/mb_foliage_node.gd")
const WaterNode := preload("res://addons/marchingblocks_paint/mb_water_node.gd")
const IMPORT_WORLD := "Import MarchingBlocks world..."

var _editor: Node
var _bar: Toolbar
var _world_dialog: EditorFileDialog


func _enter_tree() -> void:
	add_custom_type("MarchingBlocksWorld", "Node3D", World, null)
	# What a world exported by MarchingBlocks brings next to its layers (Import MarchingBlocks world).
	add_custom_type("MarchingBlocksTransitions", "Node", TransitionsNode, null)
	add_custom_type("MarchingBlocksFoliage", "Node3D", FoliageNode, null)
	add_custom_type("MarchingBlocksWater", "Node3D", WaterNode, null)
	_editor = Editor.new()
	_editor.undo = get_undo_redo()
	add_child(_editor)
	# A wheel notch says its value near the mouse, for a moment.
	_editor.changed.connect(func() -> void: update_overlays())
	_bar = Toolbar.new()
	_bar.ui_scale = EditorInterface.get_editor_scale()
	_bar.editor = _editor
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _bar)
	_bar.visible = false
	# Project > Tools > Import MarchingBlocks world: a .mbworld folder exported by MarchingBlocks.
	_world_dialog = EditorFileDialog.new()
	_world_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	# Inside the project: the scene keeps res:// paths, so it opens on any machine.
	_world_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_world_dialog.add_filter("world.json", "MarchingBlocks world")
	_world_dialog.title = "Import a MarchingBlocks world (copy the .mbworld folder into your project first)"
	_world_dialog.file_selected.connect(_import_world)
	EditorInterface.get_base_control().add_child(_world_dialog)
	add_tool_menu_item(IMPORT_WORLD, func() -> void: _world_dialog.popup_file_dialog())


func _exit_tree() -> void:
	remove_custom_type("MarchingBlocksWorld")
	for t in ["MarchingBlocksTransitions", "MarchingBlocksFoliage", "MarchingBlocksWater"]:
		remove_custom_type(t)
	remove_tool_menu_item(IMPORT_WORLD)
	if _world_dialog != null:
		_world_dialog.queue_free()
	if _bar != null:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _bar)
		_bar.queue_free()
	if _editor != null:
		_editor.world = null
		_editor.queue_free()


func _handles(object: Object) -> bool:
	return object is Node3D and (object as Node3D).get_script() == World


func _edit(object: Object) -> void:
	_editor.world = object as Node3D if _handles(object) else null
	_bar.refresh()


func _make_visible(visible: bool) -> void:
	_bar.visible = visible
	if not visible:
		_editor.world = null


## Builds the world under a new "MarchingBlocks world" node of the edited scene — ONE undo action.
func _import_world(path: String) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		push_warning("MarchingBlocks: open or create a 3D scene first, then import the world.")
		return
	var holder := Node3D.new()
	holder.name = path.get_base_dir().get_file().get_basename().validate_node_name()
	var r := WorldFile.build(path, holder)
	if r.has("error"):
		holder.free()
		push_error("MarchingBlocks: cannot import %s — %s" % [path, r["error"]])
		return
	var ur := get_undo_redo()
	ur.create_action("Import MarchingBlocks world")
	ur.add_do_method(root, "add_child", holder, true)
	ur.add_do_method(self, "_own", holder, root)
	ur.add_do_reference(holder)
	ur.add_undo_method(root, "remove_child", holder)
	ur.commit_action()
	if not (r["without_tiles"] as Array).is_empty():
		push_warning("MarchingBlocks: %d layer(s) have no tiles in this world — their cells are there, no "
			% (r["without_tiles"] as Array).size() + "tiles: %s" % str(r["without_tiles"]))


## Every node of the import belongs to the scene, so it is saved with it.
func _own(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		_own(child, root)
	if node != root:
		node.owner = root


## The value a wheel notch just set, near the mouse, for a little more than a second.
func _forward_3d_draw_over_viewport(overlay: Control) -> void:
	if _editor == null or _editor.hint == "" or Time.get_ticks_msec() - int(_editor.hint_msec) > 1200:
		return
	var font := overlay.get_theme_font("font", "Label")
	var size := int(14 * EditorInterface.get_editor_scale())
	var at: Vector2 = _editor.hint_at + Vector2(18, -10) * EditorInterface.get_editor_scale()
	var w := font.get_string_size(_editor.hint, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	overlay.draw_rect(Rect2(at - Vector2(6, size + 2), Vector2(w + 12, size + 10)), Color(0, 0, 0, 0.6))
	overlay.draw_string(font, at, _editor.hint, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Toolbar.OLIVE)
	# Fade out: one more redraw once it has expired.
	get_tree().create_timer(1.3).timeout.connect(func() -> void: update_overlays(), CONNECT_ONE_SHOT)


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if _editor.input(camera, event):
		return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS

extends Control
class_name Cell

## Cellule du livre — COPIÉE DE SPIRIT3D (`D:/Spirit3D/BOOKS/scripts/Cell.gd`, 10 octobre 2026) : clic (ou A / Entrée
## sur la cellule sélectionnée) pour l'agrandir jusqu'à remplir sa planche ; Échap (ou B à la manette) pour la réduire.
## Une seule cellule agrandie à la fois. Mode réduit : seul l'aperçu ([member reduced_preview]) se voit, les clics
## sont absorbés par le panneau. Mode agrandi : les autres cellules du livre sont masquées et gelées.
##
## Retiré de Spirit3D : l'état d'automatisation (la chaîne d'accueil), l'ouverture « choisie à l'entrée ».
## Ajouté : [member preview_title] (le texte de la vignette), [member subviewport_native_resolution] (le jeu rendu à la
## résolution de l'écran, pas à celle de la planche design), la manette (B réduit, voir [method _is_reduce_event]).

const Inputs := preload("res://core/inputs.gd")

## Conteneur du contenu d'une cellule (cf. cell_base.tscn) : rien dessous = emplacement VIDE.
const CONTAIN_NODE_NAME := "Cell_Contain"


## Emplacement VIDE du livre : rien sous [code]Cell_Contain[/code]. Les vides ne portent pas de numéro (F1–F8) et ne
## se sélectionnent pas.
func is_empty_slot() -> bool:
	var contain := get_node_or_null(CONTAIN_NODE_NAME)
	return contain == null or contain.get_child_count() == 0


## La cellule de JEU ? ([GameCell]) — c'est elle que Start / Échap rouvre depuis le livre.
func is_game_cell() -> bool:
	return false


# --- Références (scène) -------------------------------------------------------

@export var book_ref: Book
## SubViewport principal de la cellule (le jeu). Laisser vide si la cellule n'en a pas.
@export var subviewport_container: SubViewportContainer
@export var subviewport: SubViewport

@export_group("Présentation")
@export var start_enlarged: bool = false
## Le texte de la vignette (Preview_Sticker_Label) ; vide : celui de la scène.
@export var preview_title: String = ""
## Une image sur la vignette, au-dessus du texte (la cellule de jeu : l'icône de Knil).
@export var preview_icon: Texture2D
## Affiché au centre en mode réduit ; masqué à l'agrandissement.
@export var reduced_preview: Control
## En mode réduit : garder visibles les [Control] sous le SubViewport (le monde en direct derrière la vignette).
@export var keep_subviewport_control_chain_visible_when_reduced: bool = false

@export_subgroup("Survol (mode réduit)")
## Au survol (ou sélection) : [code]Preview_Sticker[/code] grossit, le reste de [code]Cell_Preview[/code] rétrécit.
@export var hover_zoom_enabled: bool = true
@export_range(1.0, 1.5, 0.01) var hover_sticker_scale: float = 1.08
@export_range(0.5, 1.0, 0.01) var hover_others_scale: float = 0.94
@export_range(0.01, 1.0, 0.01) var hover_animation_duration: float = 0.15

@export_group("SubViewport — cadrage")
## Si > 0 : ratio largeur/hauteur du buffer. Le container est centré ; bandes si la cellule a un autre ratio.
@export var subviewport_buffer_aspect: float = 0.0
## Si > 0 : en mode agrandi, ratio W/H du buffer. À 0 : [member subviewport_buffer_aspect] (ou plein).
@export var subviewport_buffer_aspect_when_enlarged: float = 0.0
## Le SubViewport rend à la résolution de l'ÉCRAN (taille de la cellule × scale du livre) au lieu de celle de la
## planche design (1600 × 900) : sans ça, le jeu en plein écran 1920 × 1080 serait un 1600 × 900 étiré.
@export var subviewport_native_resolution: bool = false

@export_group("Comportement livre")
## Quand une autre cellule est agrandie : pause profonde de tout l'arbre de celle-ci (viewport inclus).
@export var pause_all_children_while_hidden: bool = false
## Si true : quand une autre cellule est agrandie, celle-ci n'est pas gelée.
@export var skip_freeze_when_sibling_enlarged: bool = false

@export_group("Ordre d'affichage (board)")
@export var bring_above_board_siblings_when_enlarged: bool = true
@export var enlarged_z_index: int = 80

# --- État ---------------------------------------------------------------------

var original_position: Vector2
var original_size: Vector2
var enlarged: bool = false
var animation_duration: float = 0.1

var _z_index_before_enlarge_board: int = 0
var _saved_child_index_in_board: int = 0
var _slide_root_z_before_enlarge: int = 0
var _did_raise_slide_root_z: bool = false

var _cell_motion_tween: Tween
var _hover_tween: Tween
var _hovered: bool = false
var _hover_sticker: Control
var _hover_others: Array[Control] = []
var _stored_mouse_filters: Dictionary = {}  # Control -> MOUSE_FILTER_*
var _stored_visibility: Dictionary = {}      # Control -> bool
## Vrai quand les deux photos ci-dessus sont celles de l'état DÉPLIÉ, pas encore rendues (cf. [method reset_cell]).
var _children_state_stored: bool = false
var _deep_pause_stored_process_modes: Dictionary = {}  # Node -> ProcessMode


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_sync_viewport_size()
		_refresh_hover_pivots()


func _ready() -> void:
	original_position = position
	original_size = size
	custom_minimum_size = original_size
	if get_parent():
		_saved_child_index_in_board = get_index()
	set_process_input(true)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if preview_title != "":
		var label := find_child("Preview_Sticker_Label", true, false) as Label
		if label != null:
			label.text = preview_title
	if preview_icon != null:
		_put_preview_icon()
	# Un emplacement vide : une vignette grise, sans sticker.
	if is_empty_slot():
		var sticker := find_child("Preview_Sticker", true, false) as CanvasItem
		if sticker != null:
			sticker.visible = false
		hover_zoom_enabled = false
	_collect_hover_targets()
	_refresh_hover_pivots()
	if not mouse_entered.is_connected(_on_cell_mouse_entered):
		mouse_entered.connect(_on_cell_mouse_entered)
	if not mouse_exited.is_connected(_on_cell_mouse_exited):
		mouse_exited.connect(_on_cell_mouse_exited)
	if book_ref == null:
		book_ref = _find_host_book()
	if book_ref == null:
		push_warning("Cell « %s » : aucun Book parent." % name)
	_configure_subviewport_from_exports()
	if start_enlarged:
		call_deferred("_enlarge_cell_impl", true)
	else:
		reset_cell()


## L'image de la vignette : elle remplit le sticker, le texte descend dessous.
func _put_preview_icon() -> void:
	var sticker := find_child("Preview_Sticker", true, false) as Control
	if sticker == null:
		return
	var tex := TextureRect.new()
	tex.name = "Preview_Icon"
	tex.texture = preview_icon
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex.offset_bottom = -36.0
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sticker.add_child(tex)
	sticker.move_child(tex, 0)
	var label := sticker.find_child("Preview_Sticker_Label", true, false) as Label
	if label != null:
		label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		label.offset_top = -44.0
		label.offset_bottom = -2.0
		label.offset_left = -100.0
		label.offset_right = 100.0


func _find_host_book() -> Book:
	var n := get_parent()
	while n != null:
		if n is Book:
			return n as Book
		n = n.get_parent()
	return null


func _configure_subviewport_from_exports() -> void:
	if subviewport_container == null and subviewport == null:
		return
	if subviewport_container == null or subviewport == null:
		push_warning("Cell « %s » : assigner subviewport_container et subviewport ensemble, ou les deux vides." % name)
		return
	subviewport.handle_input_locally = true
	subviewport_container.stretch = not subviewport_native_resolution
	subviewport_container.position = Vector2.ZERO
	subviewport_container.mouse_filter = Control.MOUSE_FILTER_PASS
	self_modulate = Color(1, 1, 1, 1.0)


func _input(event: InputEvent) -> void:
	if not enlarged:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if is_visible_in_tree() and get_global_rect().has_point(get_global_mouse_position()) and _can_open_cell():
				enlarge_cell()
				get_viewport().set_input_as_handled()
		return
	if _is_reduce_event(event) and _should_reset_on_escape():
		reset_cell()
		get_viewport().set_input_as_handled()


## Ce qui réduit la cellule agrandie : Échap, ou B à la manette. Surchargé par la cellule de jeu (B y ferme un
## dialogue : c'est Start qui ramène au livre).
func _is_reduce_event(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_ESCAPE:
		return true
	return event is InputEventJoypadButton and event.pressed and (event as InputEventJoypadButton).button_index == JOY_BUTTON_B


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed() and not enlarged:
		if _can_open_cell():
			enlarge_cell()


## Surcharger pour empêcher la réduction par Échap (le jeu pendant un dialogue).
func _should_reset_on_escape() -> bool:
	return true


## Lettres de la touche de coin ([CellKeyOverlay]), selon le dernier appareil touché.
func key_overlay_text() -> String:
	return "B" if Inputs.pad else "ESC"


## La touche de coin s'affiche-t-elle ?
func key_overlay_visible() -> bool:
	return true


## Réduction demandée par la touche du coin : mêmes règles que Échap.
func request_reduce_from_key_overlay() -> void:
	if not enlarged:
		return
	if not _should_reset_on_escape():
		return
	reset_cell()


## Surcharger pour bloquer l'agrandissement.
func _can_open_cell() -> bool:
	return not is_empty_slot()


## Le premier contrôle à prendre le focus à l'agrandissement (la manette navigue dans les boutons) ; null : aucun.
func first_focus() -> Control:
	return null


# --- Rect cible agrandissement ------------------------------------------------


func _board_panel_from_slide(slide: Control) -> Control:
	if slide.get_child_count() == 1 and slide.get_child(0) is Control:
		return slide.get_child(0) as Control
	return slide


## Plein rectangle du parent direct (le [code]Board[/code]).
func _enlarge_target_rect_in_parent_local() -> Rect2:
	var vp_size := get_viewport_rect().size
	if vp_size.x < 2.0 or vp_size.y < 2.0:
		return Rect2(Vector2.ZERO, vp_size)
	var parent_ctrl := get_parent() as Control
	if parent_ctrl == null:
		return Rect2(Vector2.ZERO, vp_size)
	if book_ref != null and is_instance_valid(book_ref):
		book_ref.sync_layout_from_viewport()
	return Rect2(Vector2.ZERO, parent_ctrl.size)


# --- Agrandissement / réduction -----------------------------------------------


func enlarge_cell() -> void:
	_enlarge_cell_impl(false)


func _enlarge_cell_impl(skip_animation: bool) -> void:
	if enlarged:
		return
	if not _can_open_cell():
		return
	if book_ref != null and is_instance_valid(book_ref):
		if not book_ref.can_begin_cell_enlarge(self):
			return
	enlarged = true
	# Tuer le mouvement en cours AVANT tout (Spirit3D : une réduction gelée en route reprenait la taille réduite).
	_kill_cell_motion_tween()
	if book_ref != null and is_instance_valid(book_ref):
		book_ref.notify_cell_enlarged(self)
	_hide_other_cells(true)
	_freeze_other_cells(true)
	self_modulate = Color(1, 1, 1, 0.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if subviewport_container:
		subviewport_container.mouse_filter = Control.MOUSE_FILTER_STOP
		subviewport_container.focus_mode = Control.FOCUS_ALL
		subviewport_container.grab_focus.call_deferred()
	if subviewport:
		subviewport.handle_input_locally = false
		subviewport.gui_disable_input = false
	_restore_children_mouse_filters()
	_restore_children_visibility()
	_children_state_stored = false
	_clear_hover_state()
	if reduced_preview and is_instance_valid(reduced_preview):
		reduced_preview.visible = false
	_apply_board_draw_order_for_enlarged()
	var focus := first_focus()
	if focus != null:
		focus.grab_focus.call_deferred()
	if skip_animation:
		var target_r := _enlarge_target_rect_in_parent_local()
		position = target_r.position
		size = target_r.size
		custom_minimum_size = target_r.size
		_sync_viewport_size()
		self_modulate = Color(1, 1, 1, 1.0)
	else:
		call_deferred("_deferred_run_enlarge_tween")


func _deferred_run_enlarge_tween() -> void:
	if not is_inside_tree() or not enlarged:
		return
	var target_r := _enlarge_target_rect_in_parent_local()
	_kill_cell_motion_tween()
	_cell_motion_tween = create_tween()
	_cell_motion_tween.set_ease(Tween.EASE_IN)
	_cell_motion_tween.parallel().tween_property(self, "position", target_r.position, animation_duration)
	_cell_motion_tween.parallel().tween_method(_apply_size_and_sync, size, target_r.size, animation_duration)


func reset_cell() -> void:
	_kill_cell_motion_tween()
	# UNE SEULE photo par cycle déplié → replié (Spirit3D : re-photographier l'état aplati vidait la cellule pour de bon).
	if not _children_state_stored:
		_store_children_mouse_filters()
		_store_children_visibility()
		_children_state_stored = true
	_set_children_mouse_filter_pass()
	_set_children_hidden_except_preview()
	if reduced_preview and is_instance_valid(reduced_preview):
		reduced_preview.visible = true
		_set_preview_and_children_z_index(100)
		_center_reduced_preview()
	var was_enlarged := enlarged
	enlarged = false
	if book_ref != null and is_instance_valid(book_ref) and was_enlarged:
		book_ref.notify_cell_reduced(self)
	_hide_other_cells(false)
	_freeze_other_cells(false)
	self_modulate = Color(1, 1, 1, 1.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if subviewport_container:
		subviewport_container.mouse_filter = Control.MOUSE_FILTER_PASS
		subviewport_container.focus_mode = Control.FOCUS_NONE
		if subviewport_container.has_focus():
			subviewport_container.release_focus()
	if subviewport:
		subviewport.handle_input_locally = true
		subviewport.gui_disable_input = true
	_restore_board_draw_order_after_enlarged()
	_cell_motion_tween = create_tween()
	_cell_motion_tween.set_ease(Tween.EASE_OUT)
	_cell_motion_tween.parallel().tween_property(self, "position", original_position, animation_duration)
	_cell_motion_tween.parallel().tween_method(_apply_size_and_sync, size, original_size, animation_duration)
	_cell_motion_tween.finished.connect(_on_reset_animation_finished)


## Re-photographie l'état déplié d'une cellule dont le CONTENU vient d'être modifié au runtime, puis ré-applique le repli.
func refresh_reduced_state() -> void:
	if enlarged:
		return
	_restore_children_visibility()
	_restore_children_mouse_filters()
	_children_state_stored = false
	reset_cell()


func _hide_other_cells(should_hide: bool) -> void:
	if book_ref == null:
		return
	for slide in book_ref.boards:
		var panel := _board_panel_from_slide(slide)
		for child in panel.get_children():
			if child is Cell:
				child.visible = (child == self) if should_hide else true


## Gèle les cellules de TOUTES les planches (pas seulement la courante) : sinon leurs SubViewports se rendent encore.
func _freeze_other_cells(freeze: bool) -> void:
	if book_ref == null:
		return
	for slide in book_ref.boards:
		var panel := _board_panel_from_slide(slide)
		if panel == null:
			continue
		for child in panel.get_children():
			if child == self or not (child is Cell):
				continue
			var cell := child as Cell
			if cell.skip_freeze_when_sibling_enlarged:
				continue
			if freeze:
				cell.process_mode = PROCESS_MODE_DISABLED
				if cell.subviewport:
					cell.subviewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
				if cell.pause_all_children_while_hidden:
					cell._apply_deep_process_pause(true)
			else:
				if cell.pause_all_children_while_hidden:
					cell._apply_deep_process_pause(false)
				cell.process_mode = PROCESS_MODE_INHERIT
				if cell.subviewport:
					cell.subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _apply_deep_process_pause(enable: bool) -> void:
	if not pause_all_children_while_hidden or skip_freeze_when_sibling_enlarged:
		return
	if enable:
		_deep_pause_stored_process_modes.clear()
		for n in _collect_all_nodes_depth_first(self):
			# Un nœud en PROCESS_MODE_ALWAYS a demandé à tourner quoi qu'il arrive : on le respecte.
			if n.process_mode == Node.PROCESS_MODE_ALWAYS:
				continue
			_deep_pause_stored_process_modes[n] = n.process_mode
			n.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		for n in _deep_pause_stored_process_modes:
			if is_instance_valid(n):
				n.process_mode = _deep_pause_stored_process_modes[n] as Node.ProcessMode
		_deep_pause_stored_process_modes.clear()


func _collect_all_nodes_depth_first(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	_collect_nodes_recursive(node, out)
	return out


func _collect_nodes_recursive(node: Node, out: Array[Node]) -> void:
	out.append(node)
	for c in node.get_children():
		_collect_nodes_recursive(c, out)


func _on_reset_animation_finished() -> void:
	custom_minimum_size = original_size
	_sync_viewport_size()


func _apply_size_and_sync(sz: Vector2) -> void:
	custom_minimum_size = sz
	size = sz
	_sync_viewport_size()
	if not enlarged and reduced_preview and is_instance_valid(reduced_preview) and reduced_preview.visible:
		_center_reduced_preview()


# --- Descendants : souris / visibilité (mode réduit) --------------------------


func _get_all_descendant_controls(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		# On ne descend pas DANS le SubViewport : le jeu (son HUD) n'est pas du ressort du livre.
		if child is SubViewport:
			continue
		if child is Control:
			out.append(child)
		out.append_array(_get_all_descendant_controls(child))
	return out


func _store_children_mouse_filters() -> void:
	_stored_mouse_filters.clear()
	for c in _get_all_descendant_controls(self):
		_stored_mouse_filters[c] = (c as Control).mouse_filter


func _set_children_mouse_filter_pass() -> void:
	for c in _get_all_descendant_controls(self):
		(c as Control).mouse_filter = Control.MOUSE_FILTER_PASS


func _store_children_visibility() -> void:
	_stored_visibility.clear()
	for c in _get_all_descendant_controls(self):
		_stored_visibility[c] = (c as Control).visible


func _is_preview_or_under_preview(ctrl: Control) -> bool:
	if reduced_preview == null or not is_instance_valid(reduced_preview):
		return false
	if ctrl == reduced_preview or reduced_preview.is_ancestor_of(ctrl):
		return true
	return ctrl.is_ancestor_of(reduced_preview)


func _is_ancestor_of_subviewport_container(ctrl: Control) -> bool:
	if subviewport_container == null or not is_instance_valid(subviewport_container):
		return false
	return ctrl.is_ancestor_of(subviewport_container)


func _set_children_hidden_except_preview() -> void:
	for c in _get_all_descendant_controls(self):
		var ctrl: Control = c
		if _is_preview_or_under_preview(ctrl) or ctrl is SubViewportContainer:
			continue
		if keep_subviewport_control_chain_visible_when_reduced and _is_ancestor_of_subviewport_container(ctrl):
			continue
		# La touche de coin et ses enfants vivent dans un CanvasLayer : son _process décide seul.
		if ctrl.get_parent() is CanvasLayer:
			continue
		ctrl.visible = false


func _restore_children_visibility() -> void:
	for c in _stored_visibility:
		if is_instance_valid(c):
			(c as Control).visible = _stored_visibility[c]
	_stored_visibility.clear()


func _set_preview_and_children_z_index(base_z: int) -> void:
	if not reduced_preview or not is_instance_valid(reduced_preview):
		return
	reduced_preview.z_index = base_z


func _center_reduced_preview() -> void:
	if not reduced_preview or not is_instance_valid(reduced_preview):
		return
	var ps := reduced_preview.size
	if ps.x <= 0 or ps.y <= 0:
		ps = reduced_preview.custom_minimum_size
	reduced_preview.position = (size / 2.0) - (ps / 2.0)


func _restore_children_mouse_filters() -> void:
	for c in _stored_mouse_filters:
		if is_instance_valid(c):
			(c as Control).mouse_filter = _stored_mouse_filters[c]
	_stored_mouse_filters.clear()


# --- Survol : sticker qui grossit / reste de l'aperçu qui rétrécit ------------


func _hover_preview_root() -> Control:
	var by_name := find_child("Cell_Preview", true, false)
	if by_name is Control:
		return by_name
	if reduced_preview and is_instance_valid(reduced_preview):
		return reduced_preview
	return null


func _collect_hover_targets() -> void:
	_hover_sticker = null
	_hover_others.clear()
	var root := _hover_preview_root()
	if root == null:
		return
	var sticker := root.find_child("Preview_Sticker", true, false)
	if sticker is Control:
		_hover_sticker = sticker
	for child in root.get_children():
		if child is Control and child != _hover_sticker and not (_hover_sticker and child.is_ancestor_of(_hover_sticker)):
			_hover_others.append(child)


func _refresh_hover_pivots() -> void:
	if _hover_sticker and is_instance_valid(_hover_sticker):
		_hover_sticker.pivot_offset = _hover_sticker.size / 2.0
	for c in _hover_others:
		if is_instance_valid(c):
			c.pivot_offset = c.size / 2.0


func _on_cell_mouse_entered() -> void:
	if book_ref != null and is_instance_valid(book_ref):
		book_ref.notify_cell_hovered(self)
	else:
		_set_hovered(true)


func _on_cell_mouse_exited() -> void:
	# La sélection reste (la manette en repart) ; seul un livre sans sélection perd le survol.
	if book_ref == null or not is_instance_valid(book_ref) or book_ref.selected_cell != self:
		_set_hovered(false)


func _set_hovered(value: bool) -> void:
	if not hover_zoom_enabled or _hovered == value:
		return
	_hovered = value
	_apply_hover_scales(value, true)


func _apply_hover_scales(hovered: bool, animate: bool) -> void:
	if _hover_sticker == null and _hover_others.is_empty():
		_collect_hover_targets()
	_refresh_hover_pivots()
	var sticker_target := Vector2.ONE * (hover_sticker_scale if hovered else 1.0)
	var others_target := Vector2.ONE * (hover_others_scale if hovered else 1.0)
	if _hover_tween != null and is_instance_valid(_hover_tween):
		_hover_tween.kill()
	_hover_tween = null
	if not animate or not is_inside_tree():
		if _hover_sticker and is_instance_valid(_hover_sticker):
			_hover_sticker.scale = sticker_target
		for c in _hover_others:
			if is_instance_valid(c):
				c.scale = others_target
		return
	_hover_tween = create_tween()
	_hover_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	if _hover_sticker and is_instance_valid(_hover_sticker):
		_hover_tween.parallel().tween_property(_hover_sticker, "scale", sticker_target, hover_animation_duration)
	for c in _hover_others:
		if is_instance_valid(c):
			_hover_tween.parallel().tween_property(c, "scale", others_target, hover_animation_duration)


## À l'agrandissement, l'aperçu disparaît : remettre les échelles à 1.
func _clear_hover_state() -> void:
	_hovered = false
	_apply_hover_scales(false, false)


func _kill_cell_motion_tween() -> void:
	if _cell_motion_tween != null and is_instance_valid(_cell_motion_tween):
		_cell_motion_tween.kill()
	_cell_motion_tween = null


func _slide_root_control_for_book_order() -> Control:
	var board := get_parent() as Control
	if board == null:
		return null
	var hb: Control = null
	if book_ref != null and is_instance_valid(book_ref):
		hb = book_ref.boards_hbox
	var above_board := board.get_parent() as Control
	if hb == null:
		return above_board
	if above_board == hb:
		return board
	if above_board != null and above_board.get_parent() == hb:
		return above_board
	return board


func _apply_board_draw_order_for_enlarged() -> void:
	if not bring_above_board_siblings_when_enlarged:
		return
	_z_index_before_enlarge_board = z_index
	z_index = enlarged_z_index
	var sr := _slide_root_control_for_book_order()
	if sr != null:
		_slide_root_z_before_enlarge = sr.z_index
		sr.z_index = maxi(sr.z_index, enlarged_z_index + 100)
		_did_raise_slide_root_z = true
	var board := get_parent()
	if board:
		board.move_child.call_deferred(self, -1)


func _restore_board_draw_order_after_enlarged() -> void:
	if not bring_above_board_siblings_when_enlarged:
		return
	z_index = _z_index_before_enlarge_board
	if _did_raise_slide_root_z:
		var sr := _slide_root_control_for_book_order()
		if sr != null:
			sr.z_index = _slide_root_z_before_enlarge
		_did_raise_slide_root_z = false
	var board := get_parent()
	if board:
		var idx := clampi(_saved_child_index_in_board, 0, maxi(0, board.get_child_count() - 1))
		board.move_child.call_deferred(self, idx)


# --- SubViewport : taille / cadrage -------------------------------------------


func _subviewport_aspect_for_sync() -> float:
	if not enlarged:
		return subviewport_buffer_aspect
	if subviewport_buffer_aspect_when_enlarged > 0.0:
		return subviewport_buffer_aspect_when_enlarged
	return subviewport_buffer_aspect


func _sync_viewport_size() -> void:
	if subviewport_container == null or subviewport == null:
		return
	var W: float = size.x
	var H: float = size.y
	if W < 1.0 or H < 1.0:
		return
	if subviewport_native_resolution:
		_sync_native_resolution(W, H)
		return
	## Avec [member SubViewportContainer.stretch] activé, Godot refuse la mise à jour manuelle de la taille du [SubViewport].
	var stretch_was: bool = subviewport_container.stretch
	if stretch_was:
		subviewport_container.stretch = false
	var aspect_for_sync: float = _subviewport_aspect_for_sync()
	if aspect_for_sync > 0.0:
		var a: float = aspect_for_sync
		var h_fit: float = minf(H, W / a)
		var w_fit: float = h_fit * a
		var w_i: int = maxi(1, int(floorf(w_fit)))
		var h_i: int = maxi(1, int(floorf(h_fit)))
		_center_svpc_with_size(subviewport_container, w_i, h_i)
		subviewport.size_2d_override = Vector2i(w_i, h_i)
		subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		if stretch_was:
			subviewport_container.stretch = true
		return
	_fill_svpc_parent(subviewport_container)
	var want: Vector2i = Vector2i(int(W), int(H))
	if want.x > 0 and want.y > 0:
		subviewport.size_2d_override = want
		subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if stretch_was:
		subviewport_container.stretch = true


## Le SubViewport fait la taille de la cellule EN PIXELS D'ÉCRAN ; le conteneur, mis à l'échelle inverse du livre,
## l'affiche pixel pour pixel. Les clics y arrivent en pixels du jeu (le conteneur défait sa propre échelle).
func _sync_native_resolution(W: float, H: float) -> void:
	if not is_inside_tree():
		return
	var s: float = maxf(0.01, get_global_transform_with_canvas().get_scale().x)
	var px := Vector2i(maxi(1, roundi(W * s)), maxi(1, roundi(H * s)))
	subviewport_container.stretch = false
	subviewport_container.set_anchors_preset(Control.PRESET_TOP_LEFT)
	subviewport_container.position = Vector2.ZERO
	subviewport_container.scale = Vector2(1.0 / s, 1.0 / s)
	if subviewport.size != px:
		subviewport.size = px
	subviewport_container.size = Vector2(px)
	subviewport.size_2d_override = Vector2i.ZERO
	subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _fill_svpc_parent(s: SubViewportContainer) -> void:
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.position = Vector2.ZERO


func _center_svpc_with_size(s: SubViewportContainer, w: int, h: int) -> void:
	if w < 1 or h < 1:
		return
	s.set_anchors_preset(Control.PRESET_TOP_LEFT)
	s.size = Vector2(w, h)
	var ox := roundf((size.x - float(w)) * 0.5)
	var oy := roundf((size.y - float(h)) * 0.5)
	s.position = Vector2(ox, oy)

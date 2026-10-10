extends Control
class_name Book

## LE LIVRE — le menu du jeu, COPIÉ DE SPIRIT3D (`D:/Spirit3D/BOOKS/scripts/Book.gd`, 10 octobre 2026) : des PLANCHES
## de CELLULES ([Cell]) ; une cellule s'AGRANDIT jusqu'à remplir sa planche, et la cellule de JEU ([GameCell]) porte le
## monde entier dans un SubViewport. Échap / Start réduit le jeu et montre le livre — le jeu est alors EN PAUSE.
##
## Ce qui a été GARDÉ de Spirit3D : le cadrage (une zone au ratio de la planche, centrée, bandes noires), le
## défilement des planches, une seule cellule agrandie à la fois, F1–F8 (la cellule n° N), les flèches à l'écran,
## la touche de coin ESC / MNU, le survol qui grossit la vignette.
## Ce qui a été RETIRÉ (propre à Spirit3D) : la session et les comptes, la cellule ADMIN, la chaîne d'accueil
## automatisée (BookCellsSystem, voile, bouton « Jouer »), le double appui des touches de fonction.
## Ce qui a été AJOUTÉ pour Knil :
##   - le ratio de la zone suit [member board_design_size] (16:9 : le jeu remplit l'écran ; Spirit3D était en 2:1) ;
##   - F1–F8 ne marchent QUE livre ouvert : en jeu, F1–F5 et F9 sont à la triche et à la sauvegarde ;
##   - la MANETTE et les flèches : une cellule SÉLECTIONNÉE (le survol de la souris la suit), croix / stick gauche /
##     flèches pour la changer (au bord, la planche voisine), A / Entrée pour l'ouvrir, LB / RB pour changer de
##     planche ; Start, Échap ou B referment le livre (retour au jeu).

const Inputs := preload("res://core/inputs.gd")

## Taille design d'UNE planche : elle remplit la zone livre (le scale uniforme s'en déduit) et en fixe le RATIO.
@export var board_design_size: Vector2 = Vector2(1600, 900)

## Planche affichée au lancement.
@export var start_board_index: int = 0

## Flèches de navigation à l'écran ([BookNavArrows]) — visibles seulement s'il y a plusieurs planches.
@export var show_nav_arrows: bool = true

## Pages du slider : enfants directs de [code]SliderHBox[/code].
var board_count: int = 0
var boards: Array = []
var current_index: int = 0

## Cellule actuellement agrandie ; une autre ne peut pas s'agrandir tant que celle-ci n'est pas réduite.
var enlarged_cell: Cell = null

## Cellule SÉLECTIONNÉE dans le livre ouvert (manette, flèches, survol) : A / Entrée l'ouvre.
var selected_cell: Cell = null

## Décalage horizontal du slider en coordonnées **design**.
var _slide_pan_design_x: float = 0.0
var _slider_center_base: Vector2 = Vector2.ZERO
var _slide_motion_tween: Tween

@onready var boards_hbox: Control = get_node_or_null("SliderHBox") as Control

signal board_changed(new_index)


func _ready() -> void:
	# Le livre vit pendant la pause : c'est lui qui la lève.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_retrieve_boards()
	set_process_unhandled_input(true)
	var vp := get_viewport()
	if not vp.size_changed.is_connected(_on_viewport_size_changed):
		vp.size_changed.connect(_on_viewport_size_changed)
	call_deferred("_on_viewport_size_changed")
	call_deferred("_show_board", start_board_index, false)
	_spawn_nav_arrows()


const NAV_ARROWS_SCRIPT := preload("res://ui/livre/book_nav_arrows.gd")


func _spawn_nav_arrows() -> void:
	if not show_nav_arrows:
		return
	for child in get_children():
		if child.get_script() == NAV_ARROWS_SCRIPT:
			return
	var arrows: CanvasLayer = NAV_ARROWS_SCRIPT.new()
	arrows.name = "Nav_Arrows"
	add_child(arrows)


## Indique si [param cell] peut s'agrandir : non tant qu'une autre cellule du livre est encore agrandie.
func can_begin_cell_enlarge(cell: Cell) -> bool:
	if enlarged_cell != null:
		if not is_instance_valid(enlarged_cell):
			enlarged_cell = null
		elif enlarged_cell.enlarged and enlarged_cell != cell:
			return false
	return true


func notify_cell_enlarged(cell: Cell) -> void:
	enlarged_cell = cell
	_select(null)


func notify_cell_reduced(cell: Cell) -> void:
	if enlarged_cell == cell:
		enlarged_cell = null
	# Le livre se rouvre SUR la cellule que l'on quitte : A la rouvre, la croix part de là.
	_select(cell)


## Le livre est-il OUVERT (aucune cellule agrandie) ?
func is_open() -> bool:
	return enlarged_cell == null or not is_instance_valid(enlarged_cell) or not enlarged_cell.enlarged


func _kill_slide_tween() -> void:
	if _slide_motion_tween != null and is_instance_valid(_slide_motion_tween):
		_slide_motion_tween.kill()
	_slide_motion_tween = null


func _on_viewport_size_changed() -> void:
	_apply_book_aspect_rect()
	_refresh_slider_layout()
	_apply_slider_transform()
	# Le scale du livre a pu changer sans que la taille des cellules change : celles qui rendent à la
	# résolution de l'ÉCRAN ([member Cell.subviewport_native_resolution]) doivent se recaler.
	for cell in cells_in_order():
		cell._sync_viewport_size()


## À appeler avant tout placement qui dépend du layout livre (ex. [method Cell.enlarge_cell]).
func sync_layout_from_viewport() -> void:
	_on_viewport_size_changed()


## Zone utile au ratio de la planche, centrée dans [method Viewport.get_visible_rect] (priorité à la largeur).
func _viewport_content_rect() -> Rect2:
	var vr := get_viewport().get_visible_rect()
	var vp := vr.size
	if vp.x < 2.0 or vp.y < 2.0:
		return Rect2(vr.position, vp)
	var r_target: float = maxf(0.01, board_design_size.x / maxf(1.0, board_design_size.y))
	var bw: float = vp.x
	var bh: float = bw / r_target
	if bh > vp.y:
		bh = vp.y
		bw = bh * r_target
	var pos := vr.position + Vector2((vp.x - bw) * 0.5, (vp.y - bh) * 0.5)
	return Rect2(pos, Vector2(bw, bh))


func _apply_book_aspect_rect() -> void:
	var r := _viewport_content_rect()
	if r.size.x < 2.0 or r.size.y < 2.0:
		return
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0
	anchor_bottom = 0.0
	global_position = r.position
	size = r.size


func _refresh_slider_layout() -> void:
	if size.x < 2.0 or size.y < 2.0:
		return
	var bw := size.x
	var bh := size.y
	var pw: float = maxf(1.0, board_design_size.x)
	var ph: float = maxf(1.0, board_design_size.y)
	# Le scale fait tenir UNE planche dans la zone livre — pas le strip entier.
	var s: float = minf(bw / pw, bh / ph)
	boards_hbox.scale = Vector2(s, s)
	boards_hbox.custom_minimum_size = Vector2(pw * float(maxi(1, board_count)), ph)
	_slider_center_base = Vector2((bw - pw * s) * 0.5, (bh - ph * s) * 0.5)


func _apply_slider_transform() -> void:
	var s := boards_hbox.scale.x
	boards_hbox.position = _slider_center_base + Vector2(_slide_pan_design_x * s, 0.0)


func _retrieve_boards() -> void:
	boards.clear()
	for slide in boards_hbox.get_children():
		if slide is Control:
			boards.append(slide as Control)
	board_count = boards.size()


## Grille [code]Board[/code] sous une page [CenterContainer] ; sinon la page est traitée comme panneau plat.
func _board_panel_for_slide(slide: Control) -> Control:
	if slide.get_child_count() != 1:
		return slide
	var only := slide.get_child(0)
	return only as Control if only is Control else slide


## Pas de défilement = largeur design d'une planche.
func _slide_target_offset_design_x(for_index: int) -> float:
	var idx := clampi(for_index, 0, maxi(0, boards.size() - 1))
	return -board_design_size.x * float(idx)


## [code]animate = false[/code] : saut immédiat, pour la planche de départ.
func _show_board(index: int, animate: bool = true) -> void:
	if boards.is_empty():
		return
	current_index = clampi(index, 0, boards.size() - 1)
	var target_pan := _slide_target_offset_design_x(current_index)
	_kill_slide_tween()
	if not animate:
		_set_slide_pan_and_apply(target_pan)
		board_changed.emit(current_index)
		return
	_slide_motion_tween = create_tween()
	_slide_motion_tween.set_trans(Tween.TRANS_SINE)
	_slide_motion_tween.set_ease(Tween.EASE_OUT)
	_slide_motion_tween.tween_method(_set_slide_pan_and_apply, _slide_pan_design_x, target_pan, 0.4)
	board_changed.emit(current_index)


func _set_slide_pan_and_apply(v: float) -> void:
	_slide_pan_design_x = v
	_apply_slider_transform()


## F1..F8, livre OUVERT seulement : ouverture DIRECTE de la cellule n° N (cf. [method numbered_cells]).
## Dans Spirit3D elles marchaient partout ; ici, en jeu, F1–F5 et F9 sont à la triche et à la sauvegarde.
func _input(event: InputEvent) -> void:
	Inputs.note(event)
	if not is_open():
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var kc := (event as InputEventKey).keycode
	if kc < KEY_F1 or kc > KEY_F12:
		return
	if open_cell_by_number(int(kc - KEY_F1) + 1):
		get_viewport().set_input_as_handled()


## Cellules du livre dans l'ordre de lecture (planche par planche, ordre AUTHORÉ dans la scène — jamais l'ordre
## VIVANT des enfants : une cellule agrandie passe en dernier enfant de sa planche).
func cells_in_order() -> Array:
	var out: Array = []
	if boards.is_empty():
		return out
	var start: int = clampi(start_board_index, 0, boards.size() - 1)
	for k in range(boards.size()):
		var slide = boards[(start + k) % boards.size()]
		var panel := _board_panel_for_slide(slide)
		if panel == null:
			continue
		var board_cells: Array = []
		for child in panel.get_children():
			if child is Cell:
				board_cells.append(child)
		board_cells.sort_custom(
			func(a: Cell, b: Cell) -> bool:
				return a._saved_child_index_in_board < b._saved_child_index_in_board
		)
		out.append_array(board_cells)
	return out


## Cellules NUMÉROTÉES (F1–F8) : les cellules OCCUPÉES, dans l'ordre de lecture.
func numbered_cells() -> Array:
	var out: Array = []
	for cell in cells_in_order():
		if not cell.is_empty_slot():
			out.append(cell)
	return out


## La cellule de JEU du livre ([method Cell.is_game_cell]), ou null.
func find_game_cell() -> Cell:
	for cell in cells_in_order():
		if cell.is_game_cell():
			return cell
	return null


## Agrandit directement la cellule numéro [param n] (1 = première cellule OCCUPÉE).
func open_cell_by_number(n: int) -> bool:
	var cells := numbered_cells()
	if n < 1 or n > cells.size():
		return false
	return open_cell(cells[n - 1])


## Agrandit [param cell] : réduit d'abord l'éventuelle cellule agrandie (mêmes règles qu'Échap), glisse jusqu'à sa
## planche, puis l'agrandit.
func open_cell(cell: Cell) -> bool:
	if cell == null or not is_instance_valid(cell):
		return false
	if enlarged_cell != null and is_instance_valid(enlarged_cell) and enlarged_cell.enlarged:
		if enlarged_cell == cell:
			return true
		if not enlarged_cell._should_reset_on_escape():
			return false
		enlarged_cell.reset_cell()
	var board_idx := _board_index_of_cell(cell)
	if board_idx >= 0 and board_idx != current_index:
		_show_board(board_idx)
	cell.enlarge_cell()
	return true


## Ferme le livre : retour à la cellule de jeu.
func resume_game() -> bool:
	return open_cell(find_game_cell())


## Amène le livre sur la planche qui contient [param cell]. Vrai si la planche a changé.
func show_board_of_cell(cell: Cell, animate: bool = true) -> bool:
	if cell == null or not is_instance_valid(cell):
		return false
	var idx := _board_index_of_cell(cell)
	if idx < 0 or idx == current_index:
		return false
	_show_board(idx, animate)
	return true


## Indice de la planche (slide) qui contient [param cell], ou -1.
func _board_index_of_cell(cell: Cell) -> int:
	for i in range(boards.size()):
		var slide: Control = boards[i]
		if slide == cell or slide.is_ancestor_of(cell):
			return i
	return -1


# --- La navigation au clavier et à la manette (livre ouvert) ------------------------------------------------------


## Croix / stick gauche / flèches : la sélection ; A / Entrée : l'ouvrir ; LB / RB : la planche ; Start / Échap / B :
## retour au jeu. [method Node._unhandled_input] : une cellule agrandie (le jeu, un menu à boutons) passe avant.
func _unhandled_input(event: InputEvent) -> void:
	if not is_open() or not (event.is_pressed()):
		return
	var handled := true
	if event.is_action_pressed("ui_left", true):
		_move_selection(Vector2.LEFT)
	elif event.is_action_pressed("ui_right", true):
		_move_selection(Vector2.RIGHT)
	elif event.is_action_pressed("ui_up", true):
		_move_selection(Vector2.UP)
	elif event.is_action_pressed("ui_down", true):
		_move_selection(Vector2.DOWN)
	elif event.is_action_pressed("ui_accept"):
		if selected_cell != null and is_instance_valid(selected_cell):
			open_cell(selected_cell)
	elif _is_button(event, JOY_BUTTON_LEFT_SHOULDER):
		slide_prev()
	elif _is_button(event, JOY_BUTTON_RIGHT_SHOULDER):
		slide_next()
	elif event.is_action_pressed("menu") or _is_button(event, JOY_BUTTON_B) \
			or (event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE and not event.is_echo()):
		resume_game()
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


static func _is_button(event: InputEvent, button: JoyButton) -> bool:
	return event is InputEventJoypadButton and event.pressed and (event as InputEventJoypadButton).button_index == button


## Sélectionne [param cell] (null : aucune) — la vignette grossit comme au survol.
func _select(cell: Cell) -> void:
	if selected_cell == cell:
		return
	if selected_cell != null and is_instance_valid(selected_cell):
		selected_cell._set_hovered(false)
	selected_cell = cell
	if cell != null:
		cell._set_hovered(true)


## Appelé par une cellule que la souris survole : la sélection suit la souris.
func notify_cell_hovered(cell: Cell) -> void:
	if is_open() and not cell.is_empty_slot():
		_select(cell)


## La cellule occupée la plus proche dans la direction [param dir], sur la planche courante ; au bord, la planche
## voisine (sa cellule la plus proche du côté d'où l'on vient).
func _move_selection(dir: Vector2) -> void:
	var here: Array = _occupied_cells_of_board(current_index)
	if here.is_empty():
		return
	if selected_cell == null or not is_instance_valid(selected_cell) or not here.has(selected_cell):
		_select(here[0])
		return
	var from: Vector2 = selected_cell.original_position + selected_cell.original_size * 0.5
	var best: Cell = null
	var best_score := INF
	for c: Cell in here:
		if c == selected_cell:
			continue
		var d: Vector2 = c.original_position + c.original_size * 0.5 - from
		var along := d.dot(dir)
		if along <= 1.0:
			continue
		var score := along + absf(d.dot(Vector2(dir.y, dir.x))) * 2.0
		if score < best_score:
			best_score = score
			best = c
	if best != null:
		_select(best)
		return
	if dir.x != 0.0 and (slide_prev() if dir.x < 0.0 else slide_next()):
		var there: Array = _occupied_cells_of_board(current_index)
		if not there.is_empty():
			# Même rangée d'abord, puis le bord d'où l'on arrive (à gauche si l'on va à droite).
			var key := func(c: Cell) -> float:
				return absf(c.original_position.y + c.original_size.y * 0.5 - from.y) * 10000.0 + c.original_position.x * dir.x
			there.sort_custom(func(a: Cell, b: Cell) -> bool: return key.call(a) < key.call(b))
			_select(there[0])


func _occupied_cells_of_board(idx: int) -> Array:
	var out: Array = []
	if idx < 0 or idx >= boards.size():
		return out
	for c in _board_panel_for_slide(boards[idx]).get_children():
		if c is Cell and not (c as Cell).is_empty_slot():
			out.append(c)
	out.sort_custom(func(a: Cell, b: Cell) -> bool: return a._saved_child_index_in_board < b._saved_child_index_in_board)
	return out


## Planche précédente. [code]false[/code] si refusé (cellule agrandie) ou déjà en butée à gauche.
func slide_prev() -> bool:
	if not can_slide_boards() or current_index <= 0:
		return false
	_show_board(current_index - 1)
	return true


## Planche suivante. [code]false[/code] si refusé (cellule agrandie) ou déjà en butée à droite.
func slide_next() -> bool:
	if not can_slide_boards() or current_index >= boards.size() - 1:
		return false
	_show_board(current_index + 1)
	return true


## Pas de changement de page tant qu'une cellule du livre est agrandie.
func can_slide_boards() -> bool:
	if boards.size() < 2:
		return false
	return is_open()

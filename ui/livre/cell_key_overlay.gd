extends CanvasLayer
class_name CellKeyOverlay

## COPIÉ DE SPIRIT3D (`D:/Spirit3D/BOOKS/base/cell_key_overlay.gd`, 10 octobre 2026) ; ses lettres suivent le dernier
## appareil touché (ESC / B ; MNU / START sur la cellule de jeu), relues à chaque image.
##
## Pastille « touche de clavier » (50×50 px écran) posée dans un coin de la [Cell] agrandie : un clic la réduit (comme Échap).
## Visible uniquement quand la cellule est agrandie ; [member idle_alpha] au repos, [member hover_alpha] au survol.
##
## [CanvasLayer] et non simple [Control] : certaines cellules peignent leur propre calque par-dessus leur contenu
## (ex. [code]NarratorOverlay[/code] du récit, calque 100, fond opaque) — un enfant Control de la cellule passerait dessous.
## Le calque reste sous le voile de chargement (120) et les pop-ups (128).

## Côté du carré, en pixels **écran** (indépendant du zoom du livre).
const SIZE_PX: float = 50.0
## Marge entre la touche et les bords de la cellule, en pixels écran.
const MARGIN_PX: float = 14.0

## Lettres imprimées sur la touche. Vide : résolu automatiquement — « MNU » sur les cellules de jeu, « ESC » ailleurs.
@export var key_text: String = ""
@export_range(0.0, 1.0, 0.01) var idle_alpha: float = 0.35
@export_range(0.0, 1.0, 0.01) var hover_alpha: float = 1.0
@export var fade_duration: float = 0.12

@onready var _root: Control = $Root
@onready var _label: Label = $Root/Label

## Cellule hôte (premier ancêtre [Cell]).
var _cell: Cell
var _fade_tween: Tween


func _ready() -> void:
	_cell = _find_host_cell()
	if _cell == null:
		push_warning("CellKeyOverlay « %s » : aucune Cell parente — la touche reste masquée." % name)
		visible = false
		set_process(false)
		return
	_label.text = _resolve_key_text()
	_root.tooltip_text = "Revenir au livre"
	_root.modulate.a = idle_alpha
	_root.mouse_entered.connect(_on_mouse_entered)
	_root.mouse_exited.connect(_on_mouse_exited)
	_root.gui_input.connect(_on_root_gui_input)
	visible = false


func _process(_delta: float) -> void:
	var show_key: bool = _cell.enlarged and _cell.key_overlay_visible()
	visible = show_key
	if not show_key:
		return
	## La cellule remet ses enfants Control visibles à l’agrandissement ([method Cell._restore_children_visibility]) ;
	## forcé ici pour les cellules démarrées agrandies, qui n’ont jamais mémorisé de visibilité.
	if not _root.visible:
		_root.visible = true
	var t := _resolve_key_text()
	if _label.text != t:
		_label.text = t
		_label.add_theme_font_size_override("font_size", 15 if t.length() <= 3 else 11)
	_sync_rect()


## Le [CanvasLayer] ignore la transform des parents : on recopie le rect **écran** de la cellule et on s’ancre en bas à droite.
## Coin choisi car libre sur toutes les cellules : le HUD du jeu occupe les coins hauts (Infos_Left / Infos_Right) et
## le bas-centre (chat, inventaire), et le récit sa barre de contrôle en haut.
func _sync_rect() -> void:
	var xf := _cell.get_global_transform_with_canvas()
	var sc := xf.get_scale()
	var bottom_right := xf.origin + _cell.size * sc
	_root.size = Vector2(SIZE_PX, SIZE_PX)
	_root.position = bottom_right - Vector2(SIZE_PX + MARGIN_PX, SIZE_PX + MARGIN_PX)


func _find_host_cell() -> Cell:
	var n := get_parent()
	while n != null:
		if n is Cell:
			return n as Cell
		n = n.get_parent()
	return null


func _resolve_key_text() -> String:
	if not key_text.is_empty():
		return key_text
	return _cell.key_overlay_text()


func _on_root_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_cell.request_reduce_from_key_overlay()
		get_viewport().set_input_as_handled()


func _on_mouse_entered() -> void:
	_fade_to(hover_alpha)


func _on_mouse_exited() -> void:
	_fade_to(idle_alpha)


func _fade_to(target_alpha: float) -> void:
	if _fade_tween != null and is_instance_valid(_fade_tween):
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_root, "modulate:a", target_alpha, fade_duration)

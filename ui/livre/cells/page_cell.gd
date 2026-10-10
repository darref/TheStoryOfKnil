extends Cell
class_name PageCell

## Une cellule-PAGE du livre : un titre et une colonne de contenu, BÂTIS EN CODE (comme les cellules de Spirit3D) sous
## `Cell_Contain` — dans [method _build], AVANT le `_ready` de [Cell], qui photographie l'état déplié.
## À l'agrandissement, le premier bouton prend le focus : la manette navigue (croix / stick), A valide, B referme.

const PAGE_BG := Color(0.11, 0.09, 0.07, 1.0)
const INK := Color(0.96, 0.9, 0.78)
const ACCENT := Color(1.0, 0.78, 0.35)

var _column: VBoxContainer


func _ready() -> void:
	var contain := get_node(CONTAIN_NODE_NAME) as Control
	var bg := Panel.new()
	bg.name = "Page_Fond"
	var sb := StyleBoxFlat.new()
	sb.bg_color = PAGE_BG
	bg.add_theme_stylebox_override("panel", sb)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	contain.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	contain.add_child(center)
	_column = VBoxContainer.new()
	_column.custom_minimum_size = Vector2(760, 0)
	_column.add_theme_constant_override("separation", 18)
	center.add_child(_column)
	var title := label(preview_title if preview_title != "" else String(name), 46, ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_column.add_child(title)
	_build(_column)
	super._ready()


## À surcharger : remplir la page.
func _build(_col: VBoxContainer) -> void:
	pass


func first_focus() -> Control:
	return _first_button(_column)


func _first_button(n: Node) -> Control:
	if n == null:
		return null
	for c in n.get_children():
		if c is BaseButton and (c as BaseButton).focus_mode != Control.FOCUS_NONE and not (c as BaseButton).disabled:
			return c
		if c is Slider:
			return c
		var deeper := _first_button(c)
		if deeper != null:
			return deeper
	return null


static func label(text: String, font_size := 26, color := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	return l


static func button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", 28)
	b.custom_minimum_size = Vector2(0, 58)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.22, 0.17, 0.12)
	normal.border_color = Color(0.55, 0.42, 0.28)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(10)
	normal.set_content_margin_all(10)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.32, 0.24, 0.15)
	# Le focus (la manette) se voit autant que le survol (la souris).
	var focus := normal.duplicate() as StyleBoxFlat
	focus.bg_color = Color(0.32, 0.24, 0.15)
	focus.border_color = ACCENT
	focus.set_border_width_all(4)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_color_override("font_color", INK)
	b.pressed.connect(on_press)
	return b

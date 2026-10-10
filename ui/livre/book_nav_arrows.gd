extends CanvasLayer
class_name BookNavArrows

## COPIÉ DE SPIRIT3D (`D:/Spirit3D/BOOKS/base/book_nav_arrows.gd`, 10 octobre 2026).
##
## Flèches de navigation entre les planches du [Book], dans la **charte des touches ESC / MNU**
## ([CellKeyOverlay]) : même capuchon de clavier ([code]key_cap.svg[/code]), mêmes 50×50 px **écran**,
## mêmes alphas repos/survol et même fondu. Un chevron dessiné remplace les lettres.
##
## Jusqu'ici le défilement entre planches n'existait qu'au clavier ([method Book._unhandled_input],
## ←↑ / →↓) : aucune affordance à l'écran ne disait qu'il y avait des planches à gauche et à droite.
##
## [CanvasLayer] et non enfant Control du livre pour la même raison que [CellKeyOverlay] : le
## [code]SliderHBox[/code] est **mis à l'échelle** (et translaté) par [method Book._apply_slider_transform] ;
## une flèche posée dedans grandirait/défilerait avec les planches. Ici la taille reste en pixels écran
## et la position est recopiée du rect écran du livre à chaque frame.
##
## Calque 109 : juste sous la touche ESC/MNU (110). Les deux ne coexistent jamais — les flèches ne
## s'affichent que quand AUCUNE cellule n'est agrandie, la touche que quand une l'est.

## Côté du chevron, en pixels **écran** — identique à [constant CellKeyOverlay.SIZE_PX].
const SIZE_PX: float = 50.0
## Marge entre la flèche et le bord du livre, en pixels écran.
const MARGIN_PX: float = 14.0
## Calque : sous la touche ESC/MNU (110), au-dessus des planches (0).
const LAYER: int = 109
## Capuchon de touche vierge, partagé avec [CellKeyOverlay] — c'est lui qui fait la parenté visuelle.
const KEY_CAP: Texture2D = preload("res://ui/livre/key_cap.svg")

@export_range(0.0, 1.0, 0.01) var idle_alpha: float = 0.35
@export_range(0.0, 1.0, 0.01) var hover_alpha: float = 1.0
@export var fade_duration: float = 0.12

var _book: Book
var _prev: Arrow
var _next: Arrow


func _ready() -> void:
	layer = LAYER
	_book = _find_host_book()
	if _book == null:
		push_warning("BookNavArrows « %s » : aucun Book parent — les flèches restent masquées." % name)
		visible = false
		set_process(false)
		return
	_prev = _add_arrow(-1, "Planche précédente (← · LB)")
	_next = _add_arrow(1, "Planche suivante (→ · RB)")
	visible = false


## [param direction] : -1 planche précédente, +1 suivante.
func _add_arrow(direction: int, tooltip: String) -> Arrow:
	var a := Arrow.new(direction, KEY_CAP)
	a.custom_minimum_size = Vector2(SIZE_PX, SIZE_PX)
	a.tooltip_text = tooltip
	a.focus_mode = Control.FOCUS_NONE
	a.modulate.a = idle_alpha
	a.pressed.connect(_on_arrow_pressed.bind(direction))
	a.mouse_entered.connect(_fade_to.bind(a, hover_alpha))
	a.mouse_exited.connect(_fade_to.bind(a, idle_alpha))
	add_child(a)
	# Après add_child : entrer dans l'arbre re-dérive le rect d'un Control.
	a.size = Vector2(SIZE_PX, SIZE_PX)
	return a


## Le livre gère lui-même le refus (cellule agrandie) et la butée aux extrémités.
func _on_arrow_pressed(direction: int) -> void:
	if direction < 0:
		_book.slide_prev()
	else:
		_book.slide_next()


## Les flèches suivent le rect **écran** du livre : elles ne bougent pas avec le pan des planches.
func _process(_delta: float) -> void:
	if not _book.can_slide_boards():
		visible = false
		return
	visible = true
	var xf := _book.get_global_transform_with_canvas()
	var sc := xf.get_scale()
	var book_size := _book.size * sc
	var y := xf.origin.y + (book_size.y - SIZE_PX) * 0.5
	_prev.position = Vector2(xf.origin.x + MARGIN_PX, y)
	_next.position = Vector2(xf.origin.x + book_size.x - SIZE_PX - MARGIN_PX, y)
	# Pas de flèche vers le vide : masquée en butée (et non désactivée — la touche fantôme intriguerait).
	_prev.visible = _book.current_index > 0
	_next.visible = _book.current_index < _book.board_count - 1


func _find_host_book() -> Book:
	var n := get_parent()
	while n != null:
		if n is Book:
			return n as Book
		n = n.get_parent()
	return null


func _fade_to(a: Arrow, target_alpha: float) -> void:
	if a._fade_tween != null and is_instance_valid(a._fade_tween):
		a._fade_tween.kill()
	a._fade_tween = create_tween()
	a._fade_tween.tween_property(a, "modulate:a", target_alpha, fade_duration)


## Touche de clavier vierge surmontée d'un chevron peint : le capuchon vient de la même texture que
## ESC / MNU, seul le glyphe change. Dessiné plutôt qu'écrit (« ‹ ») pour rester net à toute taille et
## indépendant de la police du thème.
class Arrow extends BaseButton:
	const CHEVRON_COLOR := Color(0.93, 0.95, 1.0)
	const OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.65)
	const CHEVRON_WIDTH: float = 3.2
	const OUTLINE_WIDTH: float = 6.0

	## -1 = chevron vers la gauche, +1 = vers la droite.
	var direction: int = -1
	var _cap: Texture2D
	var _fade_tween: Tween

	func _init(dir: int, cap: Texture2D) -> void:
		direction = dir
		_cap = cap

	func _draw() -> void:
		if _cap != null:
			draw_texture_rect(_cap, Rect2(Vector2.ZERO, size), false)
		# Chevron centré : demi-largeur 5,5 px, demi-hauteur 9 px sur une touche de 50.
		# dx est l'abscisse des DEUX EXTRÉMITÉS ; la pointe est en `c.x - dx`. D'où le signe inversé :
		# direction -1 (précédent) veut la pointe à gauche, donc les extrémités à droite.
		var c := size * 0.5
		var dx: float = -5.5 * float(signi(direction))
		var pts := PackedVector2Array([
			Vector2(c.x + dx, c.y - 9.0),
			Vector2(c.x - dx, c.y),
			Vector2(c.x + dx, c.y + 9.0),
		])
		draw_polyline(pts, OUTLINE_COLOR, OUTLINE_WIDTH, true)
		draw_polyline(pts, CHEVRON_COLOR, CHEVRON_WIDTH, true)

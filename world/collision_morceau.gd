extends Node
## LA COLLISION D'UN MORCEAU CUIT, EN DONNÉES — ses triangles, en pièces de taille bornée, faits formes CONCAVES sur le
## fil principal, pas à la lecture. Enfant du StaticBody3D du morceau (la piste « collision ») ; les formes vont au corps
## par ses « propriétaires de formes » (`create_shape_owner`), sans nœud.
##
## ⚠ POURQUOI (9 octobre 2026, les à-coups de la traversée du Val) : une forme concave créée par la lecture EN FOND
## (`load_threaded_request`, un fil) laisse son travail au moteur physique, qui le fait d'un bloc, sur le fil principal,
## quand le morceau entre dans l'arbre — mesuré : 0,1 ms lu sur le fil principal, jusqu'à 24 ms lu dans un fil (45 ms
## dans la traversée). Lire tout sur le fil principal coûtait pire (13 ms en moyenne, 44 au pire). Ici, la lecture reste
## en fond (des tableaux, rien pour la physique), et le ChunkStreamer bâtit les pièces à petites doses (`build_next`),
## les plus proches d'abord ; pour un saut ou le morceau sous les pieds, tout d'un coup (`build_all`).

## Les triangles, 3 sommets chacun, en pièces d'au plus `PIECE` triangles (la cuisson les découpe).
@export var pieces: Array[PackedVector3Array] = []

const PIECE := 3000

## Vrai : le ChunkStreamer bâtit lui-même, à petites doses ; faux (le défaut) : tout se bâtit à l'entrée dans l'arbre.
var budgeted := false
var _next := 0
var _owner := -1
var _shapes: Array[Shape3D] = []


func _ready() -> void:
	if not budgeted:
		build_all()


func pending() -> bool:
	return _next < pieces.size()


## Bâtit la pièce suivante (~1,5 ms pour 3 000 triangles).
func build_next() -> void:
	if not pending() or not is_inside_tree():
		return
	var body := get_parent() as CollisionObject3D
	if _owner < 0:
		_owner = body.create_shape_owner(self)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(pieces[_next])
	body.shape_owner_add_shape(_owner, shape)
	_shapes.append(shape)
	_next += 1


func build_all() -> void:
	while pending():
		build_next()


## Combien de triangles portent les pièces (pour les comptes).
func triangle_count() -> int:
	var n := 0
	for p in pieces:
		n += p.size() / 3
	return n

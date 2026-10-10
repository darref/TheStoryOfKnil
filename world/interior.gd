class_name Interior
extends Area3D
## UN INTÉRIEUR — un bâtiment, une grotte, une salle. Y entrer passe la caméra en troisième personne,
## en sortir la rend en vue de dessus (la caméra écoute `interior_entered` / `interior_exited`).
## SOUS TERRE est un intérieur AUTOMATIQUE, sans volume posé : le ChunkStreamer dit `set_underground` d'après le
## sous-sol cuit (les galeries courent sous presque toute la carte : on ne les borde pas à la main).

@export var interior_id := ""
@export_enum("maison", "auberge", "boutique", "temple", "palais", "prison", "grotte", "mine", "ruine")
var interior_type := "maison"
## L'entité qui possède les lieux (son id d'Interactable) : chez qui l'on est, pour le moteur.
@export var owner_id := ""

static var _stack: Array = []
static var _underground := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)


func _on_enter(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_stack.erase(self)
	_stack.append(self)
	_publish()
	EventBus.interior_entered.emit(interior_id, interior_type)


func _on_exit(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_stack.erase(self)
	_publish()
	EventBus.interior_exited.emit(interior_id)


static func is_inside() -> bool:
	return not _stack.is_empty() or _underground


static func is_underground() -> bool:
	return _underground


## Sous terre, ou plus. Un volume posé (une salle creusée sous terre) l'emporte sur « souterrain ».
static func set_underground(on: bool) -> void:
	if on == _underground:
		return
	_underground = on
	_publish()
	if on:
		EventBus.interior_entered.emit("souterrain", "souterrain")
	else:
		EventBus.interior_exited.emit("souterrain")


static func _publish() -> void:
	var top: Interior = _stack.back() if not _stack.is_empty() else null
	var under := top == null and _underground
	GameState.set_value("place.interior", top != null or _underground)
	GameState.set_value("place.interior_id", top.interior_id if top else ("souterrain" if under else ""))
	GameState.set_value("place.interior_type", top.interior_type if top else ("souterrain" if under else ""))
	GameState.set_value("place.interior_owner", top.owner_id if top else "")

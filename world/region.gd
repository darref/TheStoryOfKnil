class_name Region
extends Area3D
## UNE RÉGION DU MONDE — un volume posé sur le terrain : une ville, la capitale, une forêt, un lac…
##
## Quand le joueur y entre, `place.region_*` change dans le GameState : le moteur de décision le lit
## (« où nous sommes »). Les régions peuvent s'emboîter (un quartier dans la capitale) : la dernière où l'on
## est entré l'emporte, et en ressortir rend la précédente.

@export var region_id := ""
@export_enum("ville", "capitale", "village", "foret", "lac", "montagne", "desert", "plaine", "cote", "marais", "sauvage")
var region_type := "sauvage"
## Ce que le lieu dit de lui (lu sous `place.tags` par le moteur) : « portuaire », « en_guerre »…
@export var tags: PackedStringArray = []

static var _stack: Array = []


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # le joueur
	monitorable = false
	body_entered.connect(_on_enter)
	body_exited.connect(_on_exit)


func _on_enter(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_stack.erase(self)
	_stack.append(self)
	_publish()
	EventBus.region_entered.emit(region_id, region_type)


func _on_exit(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_stack.erase(self)
	_publish()
	EventBus.region_exited.emit(region_id)


static func _publish() -> void:
	var top: Region = _stack.back() if not _stack.is_empty() else null
	GameState.set_value("place.region_id", top.region_id if top else "")
	GameState.set_value("place.region_type", top.region_type if top else "sauvage")
	GameState.set_value("place.tags", Array(top.tags) if top else [])

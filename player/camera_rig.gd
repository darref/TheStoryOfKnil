class_name CameraRig
extends Node3D
## LA CAMÉRA — deux vues, un fondu entre elles, et la bascule AUTOMATIQUE :
##   dehors          vue de dessus (TOPDOWN), à angle fixe, qui suit le joueur ;
##   dans un intérieur  troisième personne (THIRD_PERSON), derrière le joueur, qui évite les murs.
## Elle écoute `interior_entered` / `interior_exited` ; rien d'autre ne la commande.
##
## ET DEUX ZOOMS, INDÉPENDANTS :
##   la MOLETTE        rapproche / éloigne la caméra, en continu (`zoom`, de `zoom_min` à `zoom_max`), dans les deux vues ;
##   CTRL + MOLETTE    deux états : vers le bas, la VUE HAUTE (très haut au-dessus du joueur, `high_height`) ; vers le
##                     haut, le retour à la hauteur du joueur — le zoom de la molette est gardé tel quel.
## À LA MANETTE : le stick droit ↑ ↓ zoome (`pad_zoom_speed`), ← → tourne la troisième personne (`pad_turn_speed`) ;
## Back bascule la vue haute.
## Ce que la caméra voit au sol est dit par `EventBus.view_radius_changed` : le ChunkStreamer charge assez loin pour lui.

enum Mode { TOPDOWN, THIRD_PERSON }

@export var target: Node3D
@export_group("Vue de dessus")
@export var top_height := 14.0
@export var top_distance := 9.0
@export var top_yaw_degrees := 0.0
@export_group("Troisième personne")
@export var tp_distance := 3.2
@export var tp_height := 2.3
@export var tp_look_height := 1.4
@export var tp_follow := 6.0
@export var mouse_sensitivity := 0.004
@export_group("Zoom (molette)")
@export var zoom_min := 0.35
@export var zoom_max := 4.0
## Chaque cran multiplie (vers le bas) ou divise (vers le haut) le zoom par ce facteur.
@export var zoom_step := 1.15
@export var zoom_speed := 8.0
## Manette : crans de zoom par seconde, stick à fond ; tours de la troisième personne par seconde.
@export var pad_zoom_speed := 6.0
@export var pad_turn_speed := 0.45
@export_group("Vue haute (Ctrl + molette)")
@export var high_height := 130.0
@export var high_distance := 45.0
@export var high_time := 1.2
@export_group("")
@export var blend_time := 0.8
@export var follow_speed := 8.0

var mode := Mode.TOPDOWN
var high := false
var zoom := 1.0
var _zoom := 1.0
var _blend := 0.0  # 0 vue de dessus, 1 troisième personne
var _high := 0.0   # 0 à hauteur du joueur, 1 vue haute
var _tp_yaw := 0.0
var _focus := Vector3.ZERO
var _said_radius := -1.0

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	top_level = true
	EventBus.interior_entered.connect(func(_id: String, _t: String) -> void: _update_mode())
	EventBus.interior_exited.connect(func(_id: String) -> void: _update_mode())
	if target:
		_focus = target.global_position
		_tp_yaw = target.rotation.y


func _update_mode() -> void:
	set_mode(Mode.THIRD_PERSON if Interior.is_inside() else Mode.TOPDOWN)


func set_mode(m: Mode) -> void:
	if m == mode:
		return
	mode = m
	if mode == Mode.THIRD_PERSON and target:
		_tp_yaw = target.rotation.y  # la vue se pose derrière le joueur, dans le sens de sa marche


func set_high(on: bool) -> void:
	high = on


func _unhandled_input(event: InputEvent) -> void:
	if mode == Mode.THIRD_PERSON and event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_tp_yaw -= event.relative.x * mouse_sensitivity
	if event.is_action_pressed("high_view"):
		set_high(not high)
		get_viewport().set_input_as_handled()
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or not (mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]):
		return
	var down := mb.button_index == MOUSE_BUTTON_WHEEL_DOWN
	if mb.ctrl_pressed:
		set_high(down)
	else:
		zoom = clampf(zoom * (zoom_step if down else 1.0 / zoom_step), zoom_min, zoom_max)
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if target == null:
		return
	var goal := 1.0 if mode == Mode.THIRD_PERSON else 0.0
	_blend = move_toward(_blend, goal, delta / maxf(blend_time, 0.01))
	_high = move_toward(_high, 1.0 if high else 0.0, delta / maxf(high_time, 0.01))
	# La manette : le stick droit zoome (↑ ↓) et tourne la troisième personne (← →).
	var zs := Input.get_action_strength("zoom_out") - Input.get_action_strength("zoom_in")
	if absf(zs) > 0.0:
		zoom = clampf(zoom * pow(zoom_step, zs * pad_zoom_speed * delta), zoom_min, zoom_max)
	var turn := Input.get_action_strength("camera_right") - Input.get_action_strength("camera_left")
	if mode == Mode.THIRD_PERSON and absf(turn) > 0.0:
		_tp_yaw -= turn * pad_turn_speed * TAU * delta
	_zoom = lerpf(_zoom, zoom, clampf(zoom_speed * delta, 0.0, 1.0))
	_focus = _focus.lerp(target.global_position, clampf(follow_speed * delta, 0.0, 1.0))
	if mode == Mode.THIRD_PERSON and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and absf(turn) < 0.01 \
			and target is CharacterBody3D and (target as CharacterBody3D).velocity.length() > 0.5:
		_tp_yaw = lerp_angle(_tp_yaw, target.rotation.y, clampf(tp_follow * delta * 0.3, 0.0, 1.0))
	var a := _topdown_transform()
	var b := _third_person_transform()
	var t := smoothstep(0.0, 1.0, _blend)
	var base := Transform3D(a.basis.slerp(b.basis, t).orthonormalized(), a.origin.lerp(b.origin, t))
	var h := smoothstep(0.0, 1.0, _high)
	if h > 0.0:
		var c := _high_transform()
		base = Transform3D(base.basis.slerp(c.basis, h).orthonormalized(), base.origin.lerp(c.origin, h))
	global_transform = base
	_say_view_radius()


## Le rayon du sol que la caméra voit autour du joueur (à peu près : sa distance au point visé, l'ouverture, le format).
func view_radius() -> float:
	var aspect := 1.78
	if camera and camera.get_viewport():
		var size := camera.get_viewport().get_visible_rect().size
		aspect = size.x / maxf(size.y, 1.0)
	return global_position.distance_to(_focus) * tan(deg_to_rad(camera.fov if camera else 55.0) * 0.5) * aspect


func _say_view_radius() -> void:
	var r := view_radius()
	if absf(r - _said_radius) > 2.0:
		_said_radius = r
		EventBus.view_radius_changed.emit(r)


func _topdown_transform() -> Transform3D:
	var yaw := deg_to_rad(top_yaw_degrees)
	var eye := _focus + Vector3(sin(yaw) * top_distance * _zoom, top_height * _zoom, cos(yaw) * top_distance * _zoom)
	return Transform3D(Basis.looking_at(_focus - eye, Vector3.UP), eye)


func _high_transform() -> Transform3D:
	var yaw := deg_to_rad(top_yaw_degrees)
	var eye := _focus + Vector3(sin(yaw) * high_distance, high_height, cos(yaw) * high_distance)
	return Transform3D(Basis.looking_at(_focus - eye, Vector3.UP), eye)


func _third_person_transform() -> Transform3D:
	var z := clampf(_zoom, 0.5, 2.5)
	var pivot := _focus + Vector3.UP * tp_look_height
	var back := Vector3(-sin(_tp_yaw), 0, -cos(_tp_yaw))
	var eye := _focus + Vector3.UP * (tp_look_height + (tp_height - tp_look_height) * z) + back * tp_distance * z
	# Le mur entre le joueur et la caméra : la caméra s'avance jusqu'à lui.
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pivot, eye, 1)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		eye = hit["position"] + (pivot - eye).normalized() * 0.2
	return Transform3D(Basis.looking_at(pivot - eye, Vector3.UP), eye)

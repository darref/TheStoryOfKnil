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
##
## LE BRAS-RESSORT — repris du Play test de MarchingBlocks (`app/vue.gd`, `_suivre`), dans TOUTES les vues : la caméra
## ne passe jamais à travers le décor.
## - UNE SPHÈRE, PAS UN RAYON (`arm_radius`) : le plan proche a une largeur ; un rayon le laissait traverser la paroi.
##   Elle part de la TÊTE du joueur (dans sa capsule, donc jamais dans la roche) vers l'œil ; l'œil se pose où elle
##   s'arrête, l'orientation gardée.
## - RENTRER TOUT DE SUITE, RESSORTIR EN DOUCEUR (`arm_return`) : rentrer en retard, c'est une image à travers la
##   paroi ; ressortir d'un coup, un saut de caméra à chaque pilier franchi.
## LA BASCULE VERTICALE (comme dans Spirit3D) : dehors, si le décor coupe la vue OBLIQUE vers Knil (un rayon vers son
## torse), la caméra passe DROIT AU-DESSUS de lui (même distance, le haut de l'écran gardé : les commandes ne tournent
## pas) ; libre à nouveau, elle revient à l'oblique (`overhead`, `overhead_*`).
## LE TREMBLEMENT : le joueur avance aux pas de la PHYSIQUE (60 par seconde), la caméra à chaque IMAGE. Avec
## l'interpolation physique (project.godot, `physics/common/physics_interpolation`), la caméra suit la position
## INTERPOLÉE du joueur ; elle-même, posée dans `_process`, n'est pas interpolée.

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
@export_group("Bascule verticale")
## Le décor coupe la vue oblique vers Knil depuis ce temps : la caméra passe droit au-dessus de lui.
@export var overhead_enter_delay := 0.08
## La vue oblique est libre depuis ce temps : la caméra y revient.
@export var overhead_exit_delay := 0.5
## La durée du fondu entre l'oblique et la verticale.
@export var overhead_time := 0.35
## La hauteur du point de Knil que la vue doit voir (le torse, au-dessus des pieds).
@export var overhead_los_height := 1.0
@export_group("Bras-ressort")
## Le rayon de la sphère : plus que le demi plan proche, plus fin que la capsule du joueur (0,35).
@export var arm_radius := 0.2
## La hauteur d'où part le bras (la tête, au-dessus des pieds).
@export var arm_head := 1.4
## La vitesse à laquelle le bras ressort (par seconde) ; il rentre, lui, sans délai.
@export var arm_return := 6.0
## Ce que la caméra évite : le monde (couche 1) — pas les troncs (couche 5), qu'elle traverse.
@export_flags_3d_physics var arm_mask := 1
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
var _arm := -1.0  # la longueur du bras, < 0 : pas encore posé
## Vrai : la vue de dessus est passée VERTICALE (le décor cachait Knil) ; `_overhead` en est le fondu (0 à 1).
var overhead := false
var _overhead := 0.0
var _overhead_clock := 0.0

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # posée à chaque image, elle n'a rien à lisser
	EventBus.interior_entered.connect(func(_id: String, _t: String) -> void: _update_mode())
	EventBus.interior_exited.connect(func(_id: String) -> void: _update_mode())
	if target:
		_focus = _target_position()
		_tp_yaw = target.rotation.y


## Où est le joueur À CETTE IMAGE : sa position interpolée entre deux pas de physique (sinon, il avance par à-coups).
func _target_position() -> Vector3:
	if target.is_physics_interpolated_and_enabled():
		return target.get_global_transform_interpolated().origin
	return target.global_position


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
	_focus = _focus.lerp(_target_position(), clampf(follow_speed * delta, 0.0, 1.0))
	if mode == Mode.THIRD_PERSON and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and absf(turn) < 0.01 \
			and target is CharacterBody3D and (target as CharacterBody3D).velocity.length() > 0.5:
		_tp_yaw = lerp_angle(_tp_yaw, target.rotation.y, clampf(tp_follow * delta * 0.3, 0.0, 1.0))
	_update_overhead(delta)
	var a := _topdown_transform()
	var b := _third_person_transform()
	var t := smoothstep(0.0, 1.0, _blend)
	var base := Transform3D(a.basis.slerp(b.basis, t).orthonormalized(), a.origin.lerp(b.origin, t))
	var h := smoothstep(0.0, 1.0, _high)
	if h > 0.0:
		var c := _high_transform()
		base = Transform3D(base.basis.slerp(c.basis, h).orthonormalized(), base.origin.lerp(c.origin, h))
	global_transform = _spring_arm(base, delta)
	_say_view_radius()


## LE BRAS-RESSORT (voir en tête) : l'œil ramené sur la ligne tête → œil, là où la sphère du bras bute.
func _spring_arm(t: Transform3D, delta: float) -> Transform3D:
	var head := _target_position() + Vector3.UP * arm_head
	var offset := t.origin - head
	var full := offset.length()
	if full < 0.001:
		return t
	var free := full * _free_part(head, offset)
	if _arm < 0.0 or free < _arm:
		_arm = free  # rentrer : sans délai
	else:
		_arm = minf(free, lerpf(_arm, free, clampf(arm_return * delta, 0.0, 1.0)))  # ressortir : en douceur
	return Transform3D(t.basis, head + offset / full * _arm)


## La part libre (0..1) du déplacement de la sphère du bras, de `from` de `motion`, contre le décor.
func _free_part(from: Vector3, motion: Vector3) -> float:
	var world := get_world_3d()
	if world == null:
		return 1.0
	var q := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = arm_radius
	q.shape = sphere
	q.transform = Transform3D(Basis(), from)
	q.motion = motion
	q.collision_mask = arm_mask
	var r := world.direct_space_state.cast_motion(q)
	return 1.0 if r.is_empty() else r[0]


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


## La vue de dessus : OBLIQUE, ou VERTICALE quand le décor cache Knil (`overhead`, fondu par `_overhead`).
func _topdown_transform() -> Transform3D:
	var oblique := _oblique_transform()
	var k := smoothstep(0.0, 1.0, _overhead)
	if k <= 0.0:
		return oblique
	var yaw := deg_to_rad(top_yaw_degrees)
	var eye := _focus + Vector3.UP * oblique.origin.distance_to(_focus)
	# Droit en bas, le haut de l'écran gardé dans le sens de l'oblique : les commandes ne tournent pas.
	var vertical := Transform3D(Basis.looking_at(Vector3.DOWN, Vector3(-sin(yaw), 0, -cos(yaw))), eye)
	return Transform3D(oblique.basis.slerp(vertical.basis, k).orthonormalized(), oblique.origin.lerp(vertical.origin, k))


func _oblique_transform() -> Transform3D:
	var yaw := deg_to_rad(top_yaw_degrees)
	var eye := _focus + Vector3(sin(yaw) * top_distance * _zoom, top_height * _zoom, cos(yaw) * top_distance * _zoom)
	return Transform3D(Basis.looking_at(_focus - eye, Vector3.UP), eye)


## LA BASCULE VERTICALE : le décor coupe-t-il la vue OBLIQUE vers Knil ? On regarde toujours depuis l'oblique — en
## vertical aussi : c'est elle qui dit quand revenir. Entrer vite, sortir après un délai (le long d'un mur, la vue ne
## clignote pas).
func _update_overhead(delta: float) -> void:
	var blocked := false
	var world := get_world_3d()
	if world != null and mode == Mode.TOPDOWN:
		var chest := _target_position() + Vector3.UP * overhead_los_height
		var q := PhysicsRayQueryParameters3D.create(_oblique_transform().origin, chest, arm_mask)
		blocked = not world.direct_space_state.intersect_ray(q).is_empty()
	_overhead_clock = _overhead_clock + delta if blocked != overhead else 0.0
	if _overhead_clock >= (overhead_enter_delay if blocked else overhead_exit_delay):
		overhead = blocked
		_overhead_clock = 0.0
	_overhead = move_toward(_overhead, 1.0 if overhead else 0.0, delta / maxf(overhead_time, 0.01))


func _high_transform() -> Transform3D:
	var yaw := deg_to_rad(top_yaw_degrees)
	var eye := _focus + Vector3(sin(yaw) * high_distance, high_height, cos(yaw) * high_distance)
	return Transform3D(Basis.looking_at(_focus - eye, Vector3.UP), eye)


func _third_person_transform() -> Transform3D:
	var z := clampf(_zoom, 0.5, 2.5)
	var pivot := _focus + Vector3.UP * tp_look_height
	var back := Vector3(-sin(_tp_yaw), 0, -cos(_tp_yaw))
	var eye := _focus + Vector3.UP * (tp_look_height + (tp_height - tp_look_height) * z) + back * tp_distance * z
	# Le mur entre le joueur et la caméra : c'est le bras-ressort qui s'en charge (`_spring_arm`), dans toutes les vues.
	return Transform3D(Basis.looking_at(pivot - eye, Vector3.UP), eye)

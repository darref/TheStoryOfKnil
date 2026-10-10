class_name Player
extends CharacterBody3D
## KNIL — se déplace, SAUTE, sent ce qui l'entoure, parle à ce qui est à portée.
##
## LA TRICHE (`core/triche.gd`) : le vol, le fantôme (on traverse tout), la vitesse.
## LES LIMITES DU MONDE (`world_bounds`, posées par le ChunkStreamer depuis le monde cuit) : quoi qu'il arrive — un bug,
## un saut sur le cadre, la triche —, le joueur est ramené en dedans, à chaque image.
## LE SAUT (Espace) : une impulsion pour `jump_height` (1,4 m : une marche du monde MB fait une case, 1 m). Deux
## tolérances le rendent juste à la main : on saute encore `coyote_time` après avoir quitté un bord, et un appui fait
## `jump_buffer` avant de toucher le sol est retenu. Tombé SOUS le monde (`fall_limit` sous le dernier sol touché),
## le joueur revient à ce sol.
##
## `interact` fait parler l'Interactable le plus proche (`Interactable.interact`) ; pendant un dialogue, il ne bouge
## pas. L'ANIMATION est un branchement : un AnimationTree enfant reçoit `parameters/move/blend_position`
## (0 arrêt, 0,5 marche, 1 course) et `parameters/conditions/airborne` ; sans lui, un AnimationPlayer enfant joue
## « idle » / « walk » / « run » / « jump » s'il les a — cherché aussi DANS le modèle (`Modele`, le .glb importé),
## et ces noms se changent (`anim_idle`…) : un export de Mixamo ou de Tripo a les siens.

@export var walk_speed := 3.5
@export var run_speed := 7.0
@export var turn_speed := 10.0
@export var acceleration := 20.0
@export_group("Saut")
@export var jump_height := 1.4
@export var coyote_time := 0.12
@export var jump_buffer := 0.12
## La part de la commande gardée en l'air (0 : aucune, 1 : comme au sol).
@export var air_control := 0.6
@export var fall_limit := 30.0
@export_group("Animation")
@export var anim_idle := "idle"
@export var anim_walk := "walk"
@export var anim_run := "run"
@export var anim_jump := "jump"
## La vitesse au sol de la marche et de la course TELLES QU'ANIMÉES (m/s, à l'échelle du modèle) : la lecture
## s'accélère ou ralentit pour que les pieds suivent le sol, jusqu'à `anim_max_speed_scale` (au-delà, ils glissent).
@export var anim_walk_ground_speed := 0.0
@export var anim_run_ground_speed := 0.0
@export var anim_max_speed_scale := 2.0
@export_group("")

const Triche := preload("res://core/triche.gd")
## Ce que le joueur heurte : le monde (couche 1) et les troncs des arbres (couche 5, valeur 16).
const WORLD_MASK := 1 | 16

@onready var _sense: Area3D = $Sense
@onready var _anim_tree: AnimationTree = get_node_or_null("AnimationTree")
@onready var _anim_player: AnimationPlayer = _find_anim_player()

var focus: Interactable = null
var _gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
var _anim_current := ""
var _since_floor := 0.0
var _jump_wanted := 99.0
var _last_floor := Vector3.ZERO
var _jumped := false
## Les limites du monde, vue de dessus (x, z) ; vide : aucune.
var world_bounds := Rect2()


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = WORLD_MASK
	_sense.collision_layer = 0
	_sense.collision_mask = 4
	EventBus.game_loaded.connect(_on_loaded)


func _physics_process(delta: float) -> void:
	var talking := focus != null and focus.is_talking()
	var input := Vector2.ZERO if talking else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := _camera_relative(input)
	var speed := (run_speed if Input.is_action_pressed("run") else walk_speed) * Triche.vitesse
	var target := dir * speed
	if Triche.vol and not talking:
		_fly(target, delta)
		return
	var grip := 1.0 if is_on_floor() else air_control
	velocity.x = move_toward(velocity.x, target.x, acceleration * grip * delta)
	velocity.z = move_toward(velocity.z, target.z, acceleration * grip * delta)
	if is_on_floor():
		_since_floor = 0.0
		_jumped = false
		_last_floor = global_position
	else:
		_since_floor += delta
		velocity.y -= _gravity * delta
	_jump_wanted += delta
	if not talking and not Triche.vol and Input.is_action_just_pressed("jump"):
		_jump_wanted = 0.0
	if _jump_wanted <= jump_buffer and _since_floor <= coyote_time and not _jumped:
		velocity.y = sqrt(2.0 * _gravity * jump_height)
		_jumped = true
		_jump_wanted = 99.0
		_since_floor = coyote_time + 1.0
	move_and_slide()
	if global_position.y < _last_floor.y - fall_limit:
		teleport(_last_floor + Vector3.UP * 0.5)  # tombé sous le monde : retour au dernier sol touché
	_keep_inside()
	if dir.length_squared() > 0.001:
		var yaw := atan2(dir.x, dir.z)
		rotation.y = lerp_angle(rotation.y, yaw, clampf(turn_speed * delta, 0.0, 1.0))
	GameState.data["place"]["position"] = [global_position.x, global_position.y, global_position.z]
	_update_focus()
	_animate(Vector2(velocity.x, velocity.z).length() / run_speed, not is_on_floor())


## LE VOL (triche) : pas de gravité, Espace / A monte, C / gâchette gauche descend ; le fantôme traverse tout.
func _fly(target: Vector3, delta: float) -> void:
	collision_mask = 0 if Triche.fantome else WORLD_MASK
	var vertical := (Input.get_action_strength("jump") - Input.get_action_strength("fly_down")) * run_speed * Triche.vitesse
	velocity = velocity.move_toward(Vector3(target.x, vertical, target.z), acceleration * 2.0 * Triche.vitesse * delta)
	move_and_slide()
	_keep_inside()
	if Vector2(velocity.x, velocity.z).length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(velocity.x, velocity.z), clampf(turn_speed * delta, 0.0, 1.0))
	GameState.data["place"]["position"] = [global_position.x, global_position.y, global_position.z]
	_update_focus()
	_animate(Vector2(velocity.x, velocity.z).length() / run_speed, true)


## Ramené en dedans des limites du monde — radicalement : la position, et la vitesse qui pousse dehors.
func _keep_inside() -> void:
	if world_bounds.size == Vector2.ZERO:
		return
	var p := global_position
	var q := Vector3(clampf(p.x, world_bounds.position.x, world_bounds.end.x), p.y,
		clampf(p.z, world_bounds.position.y, world_bounds.end.y))
	if q != p:
		global_position = q
		if q.x != p.x:
			velocity.x = 0.0
		if q.z != p.z:
			velocity.z = 0.0
	if not Triche.fantome:
		collision_mask = WORLD_MASK


func _unhandled_input(event: InputEvent) -> void:
	if Triche.touche(event):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact") and focus != null:
		focus.interact()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cancel") and focus != null and focus.is_talking():
		focus.close()
		get_viewport().set_input_as_handled()


## Le déplacement suit la caméra : vue de dessus ou troisième personne, « avant » est ce qu'elle regarde.
func _camera_relative(input: Vector2) -> Vector3:
	if input == Vector2.ZERO:
		return Vector3.ZERO
	var cam := get_viewport().get_camera_3d()
	var b := cam.global_basis if cam else Basis.IDENTITY
	var forward := Vector3(-b.z.x, 0, -b.z.z).normalized()
	var right := Vector3(b.x.x, 0, b.x.z).normalized()
	return (right * input.x - forward * input.y).limit_length(1.0)


func _update_focus() -> void:
	var best: Interactable = null
	var best_d := INF
	for a in _sense.get_overlapping_areas():
		if a is Interactable:
			var d := global_position.distance_squared_to(a.global_position)
			if d < best_d:
				best = a
				best_d = d
	if best != focus:
		if focus != null:
			focus.close()
		focus = best
		EventBus.focus_changed.emit(focus)


func _on_loaded() -> void:
	var p: Array = GameState.get_value("place.position", [0, 0, 0])
	teleport(Vector3(p[0], p[1], p[2]))


func teleport(p: Vector3) -> void:
	global_position = p
	_last_floor = p
	velocity = Vector3.ZERO
	reset_physics_interpolation()


func _animate(speed_ratio: float, airborne := false) -> void:
	if _anim_tree:
		_anim_tree.set("parameters/move/blend_position", speed_ratio)
		_anim_tree.set("parameters/conditions/airborne", airborne)
		return
	if _anim_player == null:
		return
	var want := anim_jump if airborne and _jumped else \
		(anim_run if speed_ratio > 0.6 else (anim_walk if speed_ratio > 0.05 else anim_idle))
	if want != _anim_current and _anim_player.has_animation(want):
		_anim_current = want
		_anim_player.play(want, 0.2)
	# les pieds suivent le sol : la marche et la course jouées à la vitesse réelle (bornée)
	var ground := anim_run_ground_speed if _anim_current == anim_run else 		(anim_walk_ground_speed if _anim_current == anim_walk else 0.0)
	_anim_player.speed_scale = clampf(speed_ratio * run_speed / ground, 0.5, anim_max_speed_scale) if ground > 0.0 else 1.0


func _find_anim_player() -> AnimationPlayer:
	var own := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if own:
		return own
	var model := get_node_or_null("Modele")
	return model.find_child("AnimationPlayer", true, false) as AnimationPlayer if model else null

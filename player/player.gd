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
##
## LE COMBAT — deux gestes de bourrin :
## - LE COUP DE GENOU (`attack` : F, clic gauche, RT) : une ARMÉE (`knee_windup`), Knil s'élance d'un pas
##   (`knee_lunge`), le genou FRAPPE (`knee_active`) — chaque Frappable dans la zone devant lui, une fois par coup —,
##   puis il se RÉTABLIT (`knee_recovery`). Il ne se dirige pas pendant le coup ; un appui fait pendant le
##   rétablissement est retenu (on enchaîne les coups).
## - EN BOULE (`guard` tenu : R, LT) : Knil se recroqueville, le bouclier sur la tête. Il ne bouge plus, ne saute
##   plus, ne frappe plus ; après `guard_enter_time`, tout coup reçu (`take_hit`) est PARÉ — de n'importe quel côté :
##   en boule, il n'a pas de face. Il est seulement poussé (`guard_pushback`).
## SANS ANIMATION (`anim_knee`, `anim_guard` absentes du modèle), une DOUBLURE : le modèle s'écrase en boule, se
## penche au coup de genou — la mécanique se joue et se voit dès maintenant ; l'animation, venue, la remplace.

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
@export_group("Combat")
## Les dégâts d'un coup de genou, en demi-cœurs.
@export var knee_damage := 2
@export var knee_windup := 0.12
@export var knee_active := 0.14
@export var knee_recovery := 0.28
## La vitesse de l'élan pendant l'armée et la frappe (m/s, vers l'avant).
@export var knee_lunge := 3.0
## La zone du genou : une boule de `knee_radius`, à `knee_reach` devant Knil, à `knee_height` du sol.
@export var knee_reach := 0.75
@export var knee_radius := 0.55
@export var knee_height := 0.6
## La poussée donnée à ce qui est frappé (m/s).
@export var knee_knockback := 6.0
## Le temps de se mettre en boule : frappé avant, le coup passe.
@export var guard_enter_time := 0.15
## La part de la poussée gardée quand le bouclier pare (0 : il ne bouge pas, 1 : comme sans bouclier).
@export var guard_pushback := 0.3
## Frappé sans parer : invulnérable ce temps-là (les coups d'après ne comptent pas).
@export var hurt_invulnerability := 0.6
@export_group("Animation")
@export var anim_idle := "idle"
@export var anim_walk := "walk"
@export var anim_run := "run"
@export var anim_jump := "jump"
@export var anim_knee := "genou"
@export var anim_guard := "boule"
## La vitesse au sol de la marche et de la course TELLES QU'ANIMÉES (m/s, à l'échelle du modèle) : la lecture
## s'accélère ou ralentit pour que les pieds suivent le sol, jusqu'à `anim_max_speed_scale` (au-delà, ils glissent).
@export var anim_walk_ground_speed := 0.0
@export var anim_run_ground_speed := 0.0
@export var anim_max_speed_scale := 2.0
@export_group("")

const Triche := preload("res://core/triche.gd")
## Ce que le joueur heurte : le monde (couche 1) et les troncs des arbres (couche 5, valeur 16).
const WORLD_MASK := 1 | 16

enum Action { NONE, KNEE, GUARD }

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
## Le geste en cours, et depuis quand.
var action := Action.NONE
var _action_time := 0.0
var _attack_wanted := false
var _knee_hits: Array[Node] = []
var _knee_zone: Area3D
var _hurt_time := 99.0
## La doublure (sans animation) : la pose du modèle au repos, et la part de la pose de combat (0 à 1).
var _model: Node3D
var _model_scale := Vector3.ONE
var _model_rotation := Vector3.ZERO
var _stand_in := 0.0
var _stand_in_kind := Action.NONE


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = WORLD_MASK
	_sense.collision_layer = 0
	_sense.collision_mask = 4
	EventBus.game_loaded.connect(_on_loaded)
	_knee_zone = _make_knee_zone()
	_model = get_node_or_null("Modele") as Node3D
	if _model:
		_model_scale = _model.scale
		_model_rotation = _model.rotation


func _physics_process(delta: float) -> void:
	var talking := focus != null and focus.is_talking()
	var input := Vector2.ZERO if talking else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := _camera_relative(input)
	var speed := (run_speed if Input.is_action_pressed("run") else walk_speed) * Triche.vitesse
	var target := dir * speed
	_hurt_time += delta
	if Triche.vol and not talking:
		_end_action()
		_fly(target, delta)
		return
	_update_action(delta, talking)
	if action != Action.NONE:
		dir = Vector3.ZERO  # en plein geste, Knil ne se dirige pas
		target = _forward() * knee_lunge if action == Action.KNEE and _action_time < knee_windup + knee_active \
			else Vector3.ZERO
	var grip := 1.0 if is_on_floor() or action == Action.KNEE else air_control
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
	if not talking and not Triche.vol and action == Action.NONE and Input.is_action_just_pressed("jump"):
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
	_pose_stand_in(delta)


## LE COMBAT — le geste en cours avance ; un nouveau commence (le genou, ou la boule tant que la touche est tenue).
func _update_action(delta: float, talking: bool) -> void:
	if talking:
		_end_action()
		_attack_wanted = false
		return
	if Input.is_action_just_pressed("attack"):
		_attack_wanted = true
	var guard_held := Input.is_action_pressed("guard")
	_action_time += delta
	match action:
		Action.KNEE:
			var t := _action_time - knee_windup
			if t >= 0.0 and t < knee_active:
				_knee_strike()
			if _action_time >= knee_windup + knee_active + knee_recovery:
				_end_action()
			elif _action_time < knee_windup + knee_active:
				_attack_wanted = false  # retenu seulement pendant le rétablissement
		Action.GUARD:
			if not guard_held:
				_end_action()
			_attack_wanted = false  # en boule, on ne frappe pas
	if action == Action.NONE:
		if guard_held:
			_start(Action.GUARD)
			EventBus.player_guard_changed.emit(true)
		elif _attack_wanted:
			_attack_wanted = false
			_start(Action.KNEE)
			_knee_hits.clear()
			EventBus.player_attacked.emit("genou")


func _start(a: Action) -> void:
	action = a
	_action_time = 0.0
	_jump_wanted = 99.0
	_anim_current = ""  # un coup enchaîné rejoue son animation depuis le début
	if a != Action.NONE:
		_stand_in_kind = a


func _end_action() -> void:
	if action == Action.GUARD:
		EventBus.player_guard_changed.emit(false)
	action = Action.NONE
	_action_time = 0.0


## Le genou frappe tout Frappable dans sa zone, une fois par coup.
func _knee_strike() -> void:
	for a in _knee_zone.get_overlapping_areas():
		var f := a as Frappable
		if f == null or _knee_hits.has(f):
			continue
		_knee_hits.append(f)
		var push := (f.global_position - global_position) * Vector3(1, 0, 1)
		push = (push.normalized() if push.length_squared() > 0.0001 else _forward()) * knee_knockback
		f.take_hit(knee_damage, push + Vector3.UP * knee_knockback * 0.3, self)
		EventBus.player_hit.emit(f, "genou")


func _make_knee_zone() -> Area3D:
	var zone := Area3D.new()
	zone.name = "Genou"
	zone.collision_layer = 0
	zone.collision_mask = Frappable.LAYER
	zone.monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = knee_radius
	shape.shape = sphere
	shape.position = Vector3(0, knee_height, knee_reach)  # le modèle regarde vers +Z, le sens d'avance
	zone.add_child(shape)
	add_child(zone)
	return zone


## L'avant de Knil (il regarde vers +Z local).
func _forward() -> Vector3:
	return global_basis.z * Vector3(1, 0, 1)


## Vrai : en boule depuis assez longtemps, le bouclier pare.
func is_guarding() -> bool:
	return action == Action.GUARD and _action_time >= guard_enter_time


## KNIL EST FRAPPÉ (par un ennemi, un piège…) : `damage` en demi-cœurs, `knockback` la poussée (m/s, dans le
## monde). En boule, le bouclier pare tout ; sinon la vie baisse et Knil est invulnérable un moment. Rend les
## demi-cœurs perdus. ⚠ À zéro, rien encore : la mort est à faire.
func take_hit(damage: int, knockback := Vector3.ZERO) -> int:
	if is_guarding():
		velocity += knockback * guard_pushback
		EventBus.player_damaged.emit(0, true)
		return 0
	if _hurt_time < hurt_invulnerability or Triche.fantome:
		return 0
	_hurt_time = 0.0
	var hp := int(GameState.get_value("player.health", 0))
	var lost := mini(damage, hp)
	GameState.set_value("player.health", hp - lost)
	velocity += knockback
	EventBus.player_damaged.emit(lost, false)
	return lost


## LA DOUBLURE, tant que les animations manquent : en boule, le modèle s'écrase (plus bas, plus large) ; au coup de
## genou, il se cabre (le genou part devant, le buste en arrière) puis revient. Rien si l'animation existe.
func _pose_stand_in(delta: float) -> void:
	if _model == null:
		return
	var want := 0.0
	if action == Action.GUARD and not _has_anim(anim_guard):
		want = 1.0
	elif action == Action.KNEE and not _has_anim(anim_knee):
		want = 1.0 if _action_time < knee_windup + knee_active else 0.0
	var span := guard_enter_time if _stand_in_kind == Action.GUARD else knee_windup
	_stand_in = move_toward(_stand_in, want, delta / maxf(span, 0.01))
	var k := _stand_in
	if _stand_in_kind == Action.GUARD:
		_model.scale = _model_scale * Vector3(1.0 + 0.2 * k, 1.0 - 0.45 * k, 1.0 + 0.2 * k)
		_model.rotation = _model_rotation
	else:
		_model.scale = _model_scale
		_model.rotation = _model_rotation + Vector3(-0.35 * k, 0, 0)


func _has_anim(anim: String) -> bool:
	return _anim_player != null and _anim_player.has_animation(anim)


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
	_pose_stand_in(delta)


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
		_anim_tree.set("parameters/conditions/knee", action == Action.KNEE)
		_anim_tree.set("parameters/conditions/guarding", action == Action.GUARD)
		return
	if _anim_player == null:
		return
	var want := anim_jump if airborne and _jumped else \
		(anim_run if speed_ratio > 0.6 else (anim_walk if speed_ratio > 0.05 else anim_idle))
	if action == Action.KNEE and _anim_player.has_animation(anim_knee):
		want = anim_knee
	elif action == Action.GUARD and _anim_player.has_animation(anim_guard):
		want = anim_guard
	elif action != Action.NONE:
		want = anim_idle  # la doublure se joue sur l'attente
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

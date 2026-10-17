class_name Ennemi
extends CharacterBody3D
## UN ENNEMI DE MÊLÉE — il attend chez lui (`home`, là où on l'a posé), VOIT Knil (à `detect_radius`, rien du décor
## entre eux), COURT vers lui, et à portée le FRAPPE : une armée qui se voit (`attack_windup`, il se tourne vers
## Knil), la frappe (`attack_active` : Knil devant lui, à `attack_reach`, une fois par coup → `Player.take_hit`, que
## la boule sous le bouclier pare), le rétablissement. Il reprend son souffle (`attack_cooldown`), en garde face à
## Knil, puis recommence. Knil trop loin (`lose_radius`) ou caché trop longtemps (`lose_time`) : il rentre chez lui
## en marchant.
##
## FRAPPÉ (son `Frappable` enfant, couche 6) : il perd de la vie, recule, chancelle (`hurt_time` — l'armée en cours
## est COUPÉE : frapper le premier, ça paie) et ne lâche plus Knil, vu ou pas. À zéro : il tombe (`anim_death`),
## ne heurte plus rien, s'enfonce dans le sol et disparaît (`corpse_time`). Rien n'est sauvé : revenu au jeu, il est
## là de nouveau.
##
## LE MONDE PAR MORCEAUX : loin du joueur (`sleep_distance`) il DORT (rien ne bouge, l'animation s'arrête) ; et tant
## que la collision n'est pas chargée sous lui, il ne tombe pas (il attend en l'air, où on l'a posé). Semé de si
## loin qu'il s'endort hors de chez lui : il y est ramené d'un coup, vie refaite (personne ne le voit).
## Une marche d'une case (1 m) sur son chemin : il la saute.
##
## Il dit tout sur l'EventBus (`enemy_alerted`, `enemy_attacked`, `enemy_damaged`, `enemy_died`) ; l'animation
## se joue par noms (`anim_*`), cherchés dans la bibliothèque `animations` posée sur l'AnimationPlayer du modèle
## (`Modele`).

@export var max_health := 6
@export_group("Vue")
@export var detect_radius := 9.0
@export var lose_radius := 16.0
## Caché derrière le décor plus que ça pendant la poursuite : il abandonne.
@export var lose_time := 3.0
@export_group("Déplacement")
@export var chase_speed := 4.5
@export var walk_speed := 1.8
@export var turn_speed := 8.0
@export var acceleration := 18.0
## La marche qu'il saute (m).
@export var hop_height := 1.3
@export var sleep_distance := 45.0
@export_group("Coup")
## Il s'arrête et frappe à cette distance de Knil (m, à plat).
@export var attack_range := 1.3
## Les dégâts en demi-cœurs.
@export var attack_damage := 2
@export var attack_windup := 0.36
@export var attack_active := 0.16
@export var attack_recovery := 0.4
@export var attack_cooldown := 0.6
## La frappe touche Knil jusqu'à cette distance, dans ce cône devant lui (degrés, de part et d'autre).
@export var attack_reach := 1.6
@export var attack_cone := 60.0
@export var attack_knockback := 7.0
@export_group("Coups reçus")
@export var hurt_time := 0.45
## La part de la poussée de Knil qu'il encaisse (1 : toute).
@export var knockback_taken := 1.0
@export var corpse_time := 4.0
@export_group("Animation")
@export var animations: AnimationLibrary
@export var anim_idle := "garde"
@export var anim_walk := "marche"
@export var anim_run := "course"
@export var anim_attack := "coup"
@export var anim_hurt := "touche"
@export var anim_death := "mort"
## La vitesse au sol de la marche et de la course TELLES QU'ANIMÉES (m/s, à l'échelle) : la lecture suit.
@export var anim_walk_ground_speed := 1.05
@export var anim_run_ground_speed := 3.5
## Le coup joué à cette vitesse (le pied de Knil, recalé : 0,72 s, le sommet à 0,34 s → 0,43 s à ×0,8).
@export var attack_anim_speed := 0.8
@export_group("")

## La couche des ennemis (7, valeur 64) : Knil les heurte, ils se heurtent entre eux.
const LAYER := 64
## Ce qu'il heurte : le monde (1), le joueur (2), les troncs (16), les autres ennemis.
const MASK := 1 | 2 | 16 | LAYER
const LIBRARY := "ennemi"

enum State { IDLE, CHASE, ATTACK, HURT, RETURN, DEAD }

var state := State.IDLE
var health := 0
var home := Vector3.ZERO
var _state_time := 0.0
var _hit_done := false
var _cooldown := 0.0
var _unseen := 0.0
var _sight_clock := 0.0
var _sees_player := false
var _ground_clock := 0.0
var _ground_below := false
var _asleep := false
var _anim_current := ""
var _gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
var _anim: AnimationPlayer
var _frappable: Frappable


func _ready() -> void:
	add_to_group("ennemis")
	collision_layer = LAYER
	collision_mask = MASK
	health = max_health
	home = global_position
	var model := get_node_or_null("Modele")
	_anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer if model else null
	if _anim and animations and not _anim.has_animation_library(LIBRARY):
		_anim.add_animation_library(LIBRARY, animations)
	for c in get_children():
		if c is Frappable:
			_frappable = c
			_frappable.struck.connect(_on_struck)


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		_dead(delta)
		return
	var player := _player()
	var far := player == null or global_position.distance_to(player.global_position) > sleep_distance
	if far != _asleep:
		_asleep = far
		if far and state != State.IDLE:
			_go_home()  # semé de très loin : il ne resterait pas figé en chemin (la collision ne suit pas si loin)
		if _anim:
			if far:
				_anim.pause()
			elif _anim.assigned_animation != "":
				_anim.play()
	if far:
		return
	_state_time += delta
	_cooldown -= delta
	_update_sight(player, delta)
	var target := Vector3.ZERO  # la vitesse voulue, à plat
	var face := Vector3.ZERO    # où il regarde
	var to_player := _flat(player.global_position - global_position)
	var player_down := int(GameState.get_value("player.health", 1)) <= 0
	match state:
		State.IDLE:
			if _sees_player and to_player.length() <= detect_radius and not player_down:
				_set_state(State.CHASE)
				EventBus.enemy_alerted.emit(self)
		State.CHASE:
			if player_down or to_player.length() > lose_radius or _unseen > lose_time:
				_set_state(State.RETURN)
			elif to_player.length() <= attack_range:
				face = to_player
				if _cooldown <= 0.0:
					_set_state(State.ATTACK)
					_hit_done = false
					EventBus.enemy_attacked.emit(self)
			else:
				target = to_player.normalized() * chase_speed
				face = to_player
		State.ATTACK:
			if _state_time < attack_windup:
				face = to_player  # il se tourne vers Knil pendant l'armée ; plus pendant la frappe : on l'esquive
			elif _state_time < attack_windup + attack_active:
				if not _hit_done:
					_try_hit(player)
			elif _state_time >= attack_windup + attack_active + attack_recovery:
				_cooldown = attack_cooldown
				_set_state(State.CHASE)
		State.HURT:
			if _state_time >= hurt_time:
				_set_state(State.CHASE)
				_unseen = 0.0
		State.RETURN:
			var to_home := _flat(home - global_position)
			if _sees_player and to_player.length() <= detect_radius and not player_down:
				_set_state(State.CHASE)
				EventBus.enemy_alerted.emit(self)
			elif to_home.length() < 0.4:
				_set_state(State.IDLE)
			else:
				target = to_home.normalized() * walk_speed
				face = to_home
	var grip := acceleration * (0.3 if state == State.HURT else 1.0)
	velocity.x = move_toward(velocity.x, target.x, grip * delta)
	velocity.z = move_toward(velocity.z, target.z, grip * delta)
	if is_on_floor():
		if target.length_squared() > 0.01 and _blocked(target):
			velocity.y = sqrt(2.0 * _gravity * hop_height)  # une marche : il la saute
	elif _has_ground(delta):
		velocity.y -= _gravity * delta
	else:
		velocity = Vector3.ZERO  # la collision n'est pas encore chargée sous lui : il attend
	move_and_slide()
	if face.length_squared() > 0.0001:
		rotation.y = lerp_angle(rotation.y, atan2(face.x, face.z), clampf(turn_speed * delta, 0.0, 1.0))
	_animate()


## Hors de vue (endormi) : chez lui d'un coup, en garde.
func _go_home() -> void:
	global_position = home
	velocity = Vector3.ZERO
	health = max_health
	_set_state(State.IDLE)
	reset_physics_interpolation()


func _set_state(s: State) -> void:
	state = s
	_state_time = 0.0
	_anim_current = ""


## LA FRAPPE : Knil devant lui, à portée, à peu près à sa hauteur — une fois par coup.
func _try_hit(player: Player) -> void:
	var d := player.global_position - global_position
	var flat := _flat(d)
	if flat.length() > attack_reach or absf(d.y) > 1.5:
		return
	var forward := _flat(global_basis.z).normalized()
	if flat.length() > 0.2 and rad_to_deg(forward.angle_to(flat.normalized())) > attack_cone:
		return
	_hit_done = true
	var push := (flat.normalized() if flat.length() > 0.01 else forward) * attack_knockback
	player.take_hit(attack_damage, push + Vector3.UP * attack_knockback * 0.25)


func _on_struck(damage: int, knockback: Vector3, _source: Node) -> void:
	if state == State.DEAD:
		return
	health -= damage
	velocity = knockback * knockback_taken
	EventBus.enemy_damaged.emit(self, damage)
	if health <= 0:
		_die()
	else:
		_set_state(State.HURT)
		_unseen = 0.0


func _die() -> void:
	_set_state(State.DEAD)
	collision_layer = 0
	collision_mask = 1  # il tombe encore sur le sol, ne gêne plus personne
	if _frappable:
		_frappable.set_deferred("monitorable", false)
	EventBus.enemy_died.emit(self)
	_animate()


## Mort : il reste à terre, puis s'enfonce dans le sol et disparaît.
func _dead(delta: float) -> void:
	_state_time += delta
	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
	velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
	if _state_time > corpse_time:
		collision_mask = 0
		velocity = Vector3.DOWN * 0.5
		if _state_time > corpse_time + 3.0:
			queue_free()
	elif not is_on_floor():
		velocity.y -= _gravity * delta
	move_and_slide()


## Voit-il Knil ? Un rayon des yeux au torse, contre le décor (couche 1), toutes les 0,2 s.
func _update_sight(player: Player, delta: float) -> void:
	_sight_clock -= delta
	if _sight_clock <= 0.0:
		_sight_clock = 0.2
		var from := global_position + Vector3.UP * 1.5
		var to := player.global_position + Vector3.UP * 1.0
		_sees_player = from.distance_to(to) <= lose_radius + 2.0 and get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(from, to, 1)).is_empty()
	_unseen = 0.0 if _sees_player else _unseen + delta


## Du sol sous lui (la collision chargée) ? Un rayon vers le bas, toutes les 0,25 s.
func _has_ground(delta: float) -> bool:
	_ground_clock -= delta
	if _ground_clock <= 0.0:
		_ground_clock = 0.25
		var from := global_position + Vector3.UP * 0.5
		_ground_below = not get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 80.0, 1)).is_empty()
	return _ground_below


## Un mur bas devant lui, dans le sens où il veut aller : une marche à sauter ?
func _blocked(target: Vector3) -> bool:
	for i in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		if n.y < 0.3 and _flat(n).normalized().dot(target.normalized()) < -0.5:
			return true
	return false


func _animate() -> void:
	if _anim == null:
		return
	var want := anim_idle
	var speed := 1.0
	var flat_speed := _flat(velocity).length()
	match state:
		State.ATTACK:
			want = anim_attack
			speed = attack_anim_speed
		State.HURT:
			want = anim_hurt
		State.DEAD:
			want = anim_death
		_:
			if flat_speed > walk_speed * 1.3:
				want = anim_run
				speed = flat_speed / anim_run_ground_speed
			elif flat_speed > 0.3:
				want = anim_walk
				speed = flat_speed / anim_walk_ground_speed
	var full := LIBRARY + "/" + want if _anim.has_animation(LIBRARY + "/" + want) else want
	if not _anim.has_animation(full):
		return
	_anim.speed_scale = clampf(speed, 0.25, 3.0)
	if full != _anim_current:
		_anim_current = full
		_anim.play(full, 0.15)


func _player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)

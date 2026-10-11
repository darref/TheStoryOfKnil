@tool
extends EditorScenePostImport
## LES ANIMATIONS DE KNIL, REMISES EN ÉTAT À L'IMPORT de `assets/personnages/knil/knil.glb` (les préréglages de
## Tripo, squelette Mixamo). Outil d'éditeur : ne part pas dans le jeu. Mesuré sur l'export du 10 octobre 2026 :
## - les BOUCLES (`LOOPS`) : en boucle, la fin coupée là où la pose revient le plus près du début, puis FONDUE vers
##   la première pose sur `SEAM` secondes (`run_001` ne retombait pas sur sa première image : 0,2 m d'écart aux pieds) ;
## - SUR PLACE : les hanches ramenées à l'aplomb de leur repos en x et z (`run_001` courait 0,41 m devant le modèle,
##   0,78 m devant la capsule une fois mis à l'échelle) ;
## - LE SAUT (`saut`) : `jump_001` est une suite de cinq petits bonds ; on en garde UN, de l'impulsion au sommet
##   (`JUMP_FROM` → `JUMP_TO`), les hanches tenues à leur hauteur de repos — c'est la physique qui monte le corps.
##   Non bouclé : la pose du sommet tient jusqu'au sol.
## - LES ANIMATIONS DE MIXAMO (`MIXAMO`) : Knil passé dans Mixamo garde le MÊME squelette (65 os `mixamorig_*`,
##   mêmes repos) — l'animation se recopie telle quelle, chemins des pistes remis sur le squelette du .glb. On en garde
##   un morceau, ACCÉLÉRÉ pour tenir dans le geste du jeu, hanches à l'aplomb (c'est `player.gd` qui fait l'élan).
##   « genou » : `Illegal Knee` (2,25 s : garde, le genou droit monte de 0,38 à 0,75 s, redescend à 1,27 s, puis la
##   garde tient) → 0,30–1,35 s joué ×2,1 = 0,5 s ; le genou est haut de 0,14 à 0,29 s, le sommet à 0,21 s — dans la
##   frappe de `player.gd` (0,12 à 0,26 s).
##   « pied » : `Kicking` (2,2 s : le pied droit monte de 0,45 à 0,95 s, ~0,95 m de haut et 1 m devant à l'échelle,
##   revient au sol vers 1,5 s) → 0,40–1,55 s joué ×1,6 = 0,72 s ; le pied est haut de 0,22 à 0,41 s, le sommet à
##   0,34 s — la frappe du pied dans `player.gd`. ⚠ Un .fbx changé ne réimporte pas `knil.glb` : le réimporter (clic droit →
##   Réimporter dans l'éditeur, ou effacer `.godot/imported/knil.glb-*.scn` puis `--import` ; effacer le .md5 ne suffit pas).

const HIPS := "mixamorig_Hips"
const LOOPS := ["idle_001", "walk_001", "run_001", "swagger_001"]
const JUMP_SOURCE := "jump_001"
const JUMP_NAME := "saut"
const JUMP_FROM := 0.5
const JUMP_TO := 0.8
## Le nom dans le jeu → [le .fbx de Mixamo, début, fin (s), accélération].
const MIXAMO := {
	"genou": ["res://assets/personnages/knil/animations/illegal_knee.fbx", 0.30, 1.35, 2.1],
	"pied": ["res://assets/personnages/knil/animations/kicking.fbx", 0.40, 1.55, 1.6],
}
const FPS := 30.0
const SEAM := 0.15


func _post_import(scene: Node) -> Object:
	var player := scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var skeleton := scene.find_child("Skeleton3D", true, false) as Skeleton3D
	if player == null or skeleton == null:
		push_warning("knil_animations : ni AnimationPlayer ni Skeleton3D — rien fait")
		return scene
	var rest := skeleton.get_bone_rest(skeleton.find_bone(HIPS)).origin
	var library := player.get_animation_library("")
	for name in LOOPS:
		if library.has_animation(name):
			var a := library.get_animation(name)
			_in_place(a, rest, false)
			_trim_loop(a)
			_blend_seam(a)
			a.loop_mode = Animation.LOOP_LINEAR
	if library.has_animation(JUMP_SOURCE):
		var jump := _slice(library.get_animation(JUMP_SOURCE), JUMP_FROM, JUMP_TO)
		_in_place(jump, rest, true)
		library.add_animation(JUMP_NAME, jump)
	var skeleton_path := str(player.get_node(player.root_node).get_path_to(skeleton))
	for name in MIXAMO:
		var m: Array = MIXAMO[name]
		var source := _mixamo_animation(m[0])
		if source == null:
			push_warning("knil_animations : %s introuvable — « %s » manque (réimporter knil.glb)" % [m[0], name])
			continue
		var a := _slice(source, m[1], m[2], m[3])
		for i in a.get_track_count():
			a.track_set_path(i, NodePath(skeleton_path + ":" + str(a.track_get_path(i)).get_slice(":", 1)))
		_in_place(a, rest, false)
		library.add_animation(name, a)
	return scene


## La première animation d'un .fbx de Mixamo (« mixamo_com »).
func _mixamo_animation(path: String) -> Animation:
	if not ResourceLoader.exists(path):
		return null
	var scene := (load(path) as PackedScene).instantiate()
	var player := scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var a: Animation = null
	if player and not player.get_animation_list().is_empty():
		a = player.get_animation(player.get_animation_list()[0])
	scene.free()
	return a


func _hips_track(a: Animation) -> int:
	for i in a.get_track_count():
		if a.track_get_type(i) == Animation.TYPE_POSITION_3D and str(a.track_get_path(i)).ends_with(":" + HIPS):
			return i
	return -1


## Les hanches à l'aplomb de leur repos (x, z) — et à sa hauteur si `hold_height`.
func _in_place(a: Animation, rest: Vector3, hold_height: bool) -> void:
	var i := _hips_track(a)
	if i < 0:
		return
	for k in a.track_get_key_count(i):
		var p: Vector3 = a.track_get_key_value(i, k)
		a.track_set_key_value(i, k, Vector3(rest.x, rest.y if hold_height else p.y, rest.z))


## Coupe la fin là où la pose (rotations des os, hauteur des hanches) revient le plus près de la première image,
## cherché dans le dernier tiers.
func _trim_loop(a: Animation) -> void:
	var best_t := a.length
	var best := INF
	var t := a.length
	while t >= a.length * 0.66:
		var d := _pose_distance(a, 0.0, t)
		if d < best - 1e-4:
			best = d
			best_t = t
		t -= 1.0 / FPS
	a.length = best_t


## Les clés des `SEAM` dernières secondes glissent vers la valeur du début : la boucle se referme sans à-coup.
func _blend_seam(a: Animation) -> void:
	var from := a.length - SEAM
	for i in a.get_track_count():
		var type := a.track_get_type(i)
		if type != Animation.TYPE_ROTATION_3D and type != Animation.TYPE_POSITION_3D:
			continue
		var first = a.track_get_key_value(i, 0)
		for k in a.track_get_key_count(i):
			var kt := a.track_get_key_time(i, k)
			if kt <= from or kt > a.length + 1e-4:
				continue
			var s := smoothstep(0.0, 1.0, (kt - from) / SEAM)
			var v = a.track_get_key_value(i, k)
			a.track_set_key_value(i, k, v.slerp(first, s) if type == Animation.TYPE_ROTATION_3D else v.lerp(first, s))


func _pose_distance(a: Animation, t0: float, t1: float) -> float:
	var d := 0.0
	for i in a.get_track_count():
		match a.track_get_type(i):
			Animation.TYPE_ROTATION_3D:
				d += a.rotation_track_interpolate(i, t0).angle_to(a.rotation_track_interpolate(i, t1))
			Animation.TYPE_POSITION_3D:
				d += a.position_track_interpolate(i, t0).distance_to(a.position_track_interpolate(i, t1)) * 4.0
	return d


## Un morceau [from, to] d'une animation, rééchantillonné à `FPS`, ramené à commencer en 0, joué `speed` fois plus vite.
func _slice(source: Animation, from: float, to: float, speed := 1.0) -> Animation:
	var a := Animation.new()
	a.length = (to - from) / speed
	for i in source.get_track_count():
		var type := source.track_get_type(i)
		if type not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
			continue
		var j := a.add_track(type)
		a.track_set_path(j, source.track_get_path(i))
		var t := 0.0
		while t <= a.length + 1e-4:
			var kt := minf(t, a.length)
			var at := from + kt * speed
			match type:
				Animation.TYPE_POSITION_3D:
					a.position_track_insert_key(j, kt, source.position_track_interpolate(i, at))
				Animation.TYPE_ROTATION_3D:
					a.rotation_track_insert_key(j, kt, source.rotation_track_interpolate(i, at))
				Animation.TYPE_SCALE_3D:
					a.scale_track_insert_key(j, kt, source.scale_track_interpolate(i, at))
			t += 1.0 / FPS
	return a

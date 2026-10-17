extends SceneTree
## LE RECALAGE D'ANIMATIONS — d'un modèle de Tripo à un autre (squelette Mixamo, 65 os `mixamorig_*`, mêmes noms).
## Outil : ne part pas dans le jeu. Les deux squelettes ont les mêmes os mais PAS les mêmes repos (vu, Knil → le
## dealer : jusqu'à 118° d'écart sur un os de la main droite, presque tout en ROULIS autour de l'os ; les directions
## restent à moins de 8°, sauf les jambes du dealer, plus écartées de 16°). Recopier les rotations telles quelles
## tordrait les membres : on recopie le MOUVEMENT VU DANS LE MONDE. Pour chaque os, D = G_source × G_repos_source⁻¹
## (ce dont l'os a tourné depuis son repos, dans l'espace du squelette), puis G_cible = D × G_repos_cible, et la
## rotation locale de la cible s'en déduit (G_parent⁻¹ × G). Les hanches : leur déplacement depuis le repos, mis à
## l'échelle de la hauteur des hanches. Échantillonné à `FPS`.
##
##   "$GODOT" --headless --path D:/TheStoryOfKnil --script res://tools/import/recaler_animations.gd -- \
##       --source=res://assets/personnages/knil/knil.glb --cible=res://assets/personnages/dealer/dealer.fbx \
##       --sortie=res://assets/personnages/dealer/dealer_animations.res \
##       --anims=course:run_001,marche:walk_001,coup:pied,touche:hit_to_side_001,mort:defeat_03_001 \
##       [--propres=garde:0]
##
## `--anims` : nom dans la sortie : nom chez la source (les boucles de la source restent des boucles).
## `--propres` : les animations de la CIBLE elle-même gardées (nom : indice dans sa liste), en boucle.
## Les pistes de la sortie visent le squelette de la cible depuis la racine de son AnimationPlayer.
## ⚠ Une animation de Knil changée (réimport de `knil.glb`) ne se recopie pas d'elle-même : relancer l'outil.

const FPS := 30.0
const HIPS := "mixamorig_Hips"


func _init() -> void:
	var opts := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			opts[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
	for k in ["source", "cible", "sortie", "anims"]:
		if not opts.has(k):
			printerr("recaler : --%s manque" % k)
			quit(1)
			return
	var src_scene: Node = (load(opts["source"]) as PackedScene).instantiate()
	var dst_scene: Node = (load(opts["cible"]) as PackedScene).instantiate()
	var src_player := src_scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var dst_player := dst_scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var src_skel := src_scene.find_child("Skeleton3D", true, false) as Skeleton3D
	var dst_skel := dst_scene.find_child("Skeleton3D", true, false) as Skeleton3D
	var src_path := str(src_player.get_node(src_player.root_node).get_path_to(src_skel))
	var dst_path := str(dst_player.get_node(dst_player.root_node).get_path_to(dst_skel))
	var lib := AnimationLibrary.new()
	for pair: String in (opts["anims"] as String).split(","):
		var out_name := pair.get_slice(":", 0)
		var in_name := pair.get_slice(":", 1)
		if not src_player.has_animation(in_name):
			printerr("recaler : « %s » absente de la source" % in_name)
			quit(1)
			return
		var a := retarget(src_player.get_animation(in_name), src_skel, src_path, dst_skel, dst_path)
		lib.add_animation(out_name, a)
		print("recaler : %s ← %s (%.2f s, %d pistes%s)" % [out_name, in_name, a.length, a.get_track_count(),
			", boucle" if a.loop_mode != Animation.LOOP_NONE else ""])
	if opts.has("propres"):
		var own := dst_player.get_animation_list()
		for pair: String in (opts["propres"] as String).split(","):
			var a := dst_player.get_animation(own[int(pair.get_slice(":", 1))]).duplicate() as Animation
			a.loop_mode = Animation.LOOP_LINEAR
			lib.add_animation(pair.get_slice(":", 0), a)
			print("recaler : %s ← la cible elle-même (%.2f s)" % [pair.get_slice(":", 0), a.length])
	var err := ResourceSaver.save(lib, opts["sortie"])
	print("recaler : %d animations → %s (%s)" % [lib.get_animation_list().size(), opts["sortie"], error_string(err)])
	src_scene.free()
	dst_scene.free()
	quit(0 if err == OK else 1)


static func retarget(src: Animation, src_skel: Skeleton3D, src_path: String, dst_skel: Skeleton3D,
		dst_path: String) -> Animation:
	var order := _parents_first(dst_skel)
	var src_rest := _global_rest(src_skel)
	var dst_rest := _global_rest(dst_skel)
	var src_hips := src_skel.find_bone(HIPS)
	var dst_hips := dst_skel.find_bone(HIPS)
	var scale := dst_skel.get_bone_global_rest(dst_hips).origin.y / maxf(src_skel.get_bone_global_rest(src_hips).origin.y, 0.001)
	# Les pistes de la source, par os.
	var rot_track := {}
	var pos_track := -1
	for t in src.get_track_count():
		var bone := str(src.track_get_path(t)).get_slice(":", 1)
		if not str(src.track_get_path(t)).begins_with(src_path + ":"):
			continue
		if src.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			rot_track[bone] = t
		elif src.track_get_type(t) == Animation.TYPE_POSITION_3D and bone == HIPS:
			pos_track = t
	var out := Animation.new()
	out.length = src.length
	out.loop_mode = src.loop_mode
	var out_rot := {}
	for i in order:
		var bone := dst_skel.get_bone_name(i)
		if rot_track.has(bone):
			var t := out.add_track(Animation.TYPE_ROTATION_3D)
			out.track_set_path(t, NodePath(dst_path + ":" + bone))
			out_rot[i] = t
	var out_pos := -1
	if pos_track >= 0:
		out_pos = out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(out_pos, NodePath(dst_path + ":" + HIPS))
	var frames := int(ceil(src.length * FPS))
	for f in frames + 1:
		var time := minf(f / FPS, src.length)
		# La pose de la source, dans l'espace du squelette.
		var src_global := {}
		for i in _parents_first(src_skel):
			var bone := src_skel.get_bone_name(i)
			var local := src.rotation_track_interpolate(rot_track[bone], time) if rot_track.has(bone) \
				else src_skel.get_bone_rest(i).basis.get_rotation_quaternion()
			var parent := src_skel.get_bone_parent(i)
			src_global[bone] = (src_global[src_skel.get_bone_name(parent)] * local if parent >= 0 else local).normalized()
		var dst_global := {}
		for i in order:
			var bone := dst_skel.get_bone_name(i)
			var j := src_skel.find_bone(bone)
			var g: Quaternion
			if j >= 0:
				var delta: Quaternion = src_global[bone] * src_rest[j].inverse()
				g = (delta * dst_rest[i]).normalized()
			else:
				var p := dst_skel.get_bone_parent(i)
				g = (dst_global[p] if p >= 0 else Quaternion.IDENTITY) * dst_skel.get_bone_rest(i).basis.get_rotation_quaternion()
			dst_global[i] = g
			if out_rot.has(i):
				var p := dst_skel.get_bone_parent(i)
				var local: Quaternion = (dst_global[p].inverse() * g).normalized() if p >= 0 else g
				out.rotation_track_insert_key(out_rot[i], time, local)
		if out_pos >= 0:
			var moved := src.position_track_interpolate(pos_track, time) - src_skel.get_bone_rest(src_hips).origin
			out.position_track_insert_key(out_pos, time, dst_skel.get_bone_rest(dst_hips).origin + moved * scale)
	return out


## Les rotations de repos dans l'espace du squelette, par os.
static func _global_rest(skel: Skeleton3D) -> Array[Quaternion]:
	var out: Array[Quaternion] = []
	out.resize(skel.get_bone_count())
	for i in _parents_first(skel):
		var local := skel.get_bone_rest(i).basis.get_rotation_quaternion()
		var p := skel.get_bone_parent(i)
		out[i] = (out[p] * local if p >= 0 else local).normalized()
	return out


static func _parents_first(skel: Skeleton3D) -> Array[int]:
	var out: Array[int] = []
	var stack: Array[int] = []
	for i in skel.get_bone_count():
		if skel.get_bone_parent(i) < 0:
			stack.append(i)
	while not stack.is_empty():
		var i: int = stack.pop_back()
		out.append(i)
		for c in skel.get_bone_children(i):
			stack.append(c)
	return out

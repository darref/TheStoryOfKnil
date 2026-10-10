@tool
class_name OutlineHull
extends RefCounted
## LE CONTOUR NOIR — la boîte à outils de la « coque inversée », reprise de Spirit3D (HEART_WORLD, 10 octobre 2026).
##
## Sans état ; [SubtreeOutline] en est le client (« tout ce qui est intéressant porte le même trait »).
##
## [b]La coque est un enfant INTERNE[/b] ([constant Node.INTERNAL_MODE_BACK]) : invisible pour `get_children()`,
## pour l'éditeur et pour la sauvegarde de scène — rien ne se grave dans les .tscn. Elle porte le mesh RECUIT quand
## la géométrie s'y prête (arêtes vives, non skinnée), sinon le mesh d'origine, liée au MÊME squelette que le corps.
## Le mesh du nœud n'est JAMAIS touché.
##
## [b]⚠ Pourquoi pas `material_overlay`[/b] (mesuré dans Spirit3D) : un overlay est une SURFACE DE PLUS sur le
## corps, il en hérite l'ombre portée et se redessine à chaque cascade du soleil — 10 passes de géométrie au lieu
## de 6 à quatre cascades, pour une ombre que le corps projette déjà. Il ne reste que pour les meshes à BLEND SHAPES,
## qu'une coque enfant ne sait pas suivre.

const SHADER_PLAIN := "res://world/contour/outline_hull.gdshader"
const SHADER_SMOOTH := "res://world/contour/outline_hull_smooth.gdshader"

# ─── Le profil de la CHARTE ─── (l'UNIQUE source des chiffres : la même que Spirit3D)
const DEFAULT_COLOR := Color(0.0, 0.0, 0.0, 1.0)
const DEFAULT_INTENSITY := 1.0
## Largeur en PIXELS d'écran : la même de près, de loin, en vue de dessus comme en troisième personne.
const DEFAULT_WIDTH_PX := 2.0
const DEFAULT_WIDTH_WORLD := 0.0
const DEFAULT_MIN_WIDTH_PX := 0.0
const DEFAULT_MAX_WIDTH_PX := 12.0
const DEFAULT_MAX_SCREEN_COVER := 0.10
const DEFAULT_DEPTH_BIAS := 0.0015

const HULL_NODE_NAME := "_Contour_"
const META_HULL := "_outline_hull_v2"

## Au-delà, le recuit coûterait une pause visible ; on retombe sur les normales du mesh.
const MAX_BAKE_VERTICES := 200000
## Deux normales sont « déjà lisses » au-dessus de ce produit scalaire.
const SMOOTH_EPSILON := 0.9995

# Clé = id du mesh source ; valeur = [weakref(source), weakref(recuit) ou null si inutile].
static var _bake_cache: Dictionary = {}
# Clé = (mesh, variante, profil) ; un matériau par mesh et par profil, partagé entre instances.
static var _material_cache: Dictionary = {}


static func make_material(smooth: bool) -> ShaderMaterial:
	var shader := load(SHADER_SMOOTH if smooth else SHADER_PLAIN) as Shader
	if shader == null:
		push_error("[OutlineHull] shader introuvable : %s" % (SHADER_SMOOTH if smooth else SHADER_PLAIN))
		return null
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat


# ─── Recuit des normales lissées ──────────────────────────────────────────────

## Variante de [param src] portant dans CUSTOM0 la normale moyennée par POSITION — ce qui referme la coque aux
## arêtes vives (un coin de cube existe en trois exemplaires, poussés chacun le long de SA normale, ils s'écartent).
## [code]null[/code] si c'est inutile (déjà lisse) ou impossible (skinné, blend shapes, trop lourd…).
static func smooth_normal_mesh(src: Mesh) -> Mesh:
	if src == null:
		return null
	var key := src.get_instance_id()
	if _bake_cache.has(key):
		var entry: Array = _bake_cache[key]
		if (entry[0] as WeakRef).get_ref() == src:
			if entry[1] == null:
				return null
			var cached: Variant = (entry[1] as WeakRef).get_ref()
			if cached != null:
				return cached as Mesh
		_bake_cache.erase(key)
	var baked := _bake(src)
	_bake_cache[key] = [weakref(src), (weakref(baked) if baked != null else null)]
	return baked


static func _bake(src: Mesh) -> Mesh:
	var surface_count := src.get_surface_count()
	if surface_count == 0 or has_blend_shapes(src):
		return null
	# ⚠ Un mesh SKINNÉ ne se recuit jamais : le moteur ne déforme que VERTEX, NORMAL et TANGENT, CUSTOM0 resterait
	# en pose de repos pendant que le corps s'anime (le trait s'épaissit d'un côté, disparaît de l'autre).
	if is_skinned_mesh(src):
		return null
	# Passe 1 — les normales accumulées par position, SUR TOUTES LES SURFACES (sinon un trou à la couture de deux
	# matériaux).
	var quantum := maxf(src.get_aabb().size.length(), 0.0001) / 4096.0
	var accumulated := {}
	var per_surface: Array = []
	var total := 0
	for s in surface_count:
		if src is ArrayMesh and (src as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			return null
		var arrays := src.surface_get_arrays(s)
		if arrays.is_empty():
			return null
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: Variant = arrays[Mesh.ARRAY_NORMAL]
		if norms == null or (norms as PackedVector3Array).size() != verts.size() or verts.is_empty():
			return null
		total += verts.size()
		if total > MAX_BAKE_VERTICES:
			return null
		var normals: PackedVector3Array = norms
		for i in verts.size():
			var k := _key(verts[i], quantum)
			accumulated[k] = (accumulated[k] as Vector3) + normals[i] if accumulated.has(k) else normals[i]
		per_surface.append(arrays)
	# Passe 2 — l'écriture. Si aucune normale ne bouge, le mesh était déjà lisse : pas de doublon.
	var out := ArrayMesh.new()
	var any_split := false
	for s in per_surface.size():
		var arrays: Array = per_surface[s]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var custom := PackedFloat32Array()
		custom.resize(verts.size() * 3)
		for i in verts.size():
			var acc: Vector3 = accumulated[_key(verts[i], quantum)]
			var smooth := acc.normalized() if acc.length_squared() > 1e-12 else normals[i]
			if smooth.dot(normals[i]) < SMOOTH_EPSILON:
				any_split = true
			custom[i * 3] = smooth.x
			custom[i * 3 + 1] = smooth.y
			custom[i * 3 + 2] = smooth.z
		arrays[Mesh.ARRAY_CUSTOM0] = custom
		var flags := Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		out.surface_set_material(s, src.surface_get_material(s))
	return out if any_split else null


static func _key(v: Vector3, quantum: float) -> Vector3i:
	return Vector3i(roundi(v.x / quantum), roundi(v.y / quantum), roundi(v.z / quantum))


## Lu sur le FORMAT des surfaces : le seul test qui ne recopie pas les tableaux du mesh.
static func is_skinned_mesh(mesh: Mesh) -> bool:
	var am := mesh as ArrayMesh
	if am == null:
		return false
	for s in am.get_surface_count():
		if (am.surface_get_format(s) & Mesh.ARRAY_FORMAT_BONES) != 0:
			return true
	return false


static func has_blend_shapes(mesh: Mesh) -> bool:
	if mesh == null or not mesh.has_method("get_blend_shape_count"):
		return false
	return int(mesh.call("get_blend_shape_count")) > 0


# ─── Matériaux partagés ───────────────────────────────────────────────────────

## Le matériau de coque PARTAGÉ pour [param mesh] et le profil [param cfg] (les clés sont les noms des uniformes).
static func shared_material(mesh: Mesh, smooth: bool, cfg: Dictionary) -> ShaderMaterial:
	if mesh == null:
		return null
	var keys := cfg.keys()
	keys.sort()  # deux profils égaux écrits dans un autre ordre : un seul matériau
	var parts := PackedStringArray()
	for k in keys:
		parts.append("%s=%s" % [str(k), str(cfg[k])])
	var key := "%d|%s|%s" % [mesh.get_instance_id(), str(smooth), "|".join(parts)]
	if _material_cache.has(key):
		var entry: Array = _material_cache[key]
		if (entry[0] as WeakRef).get_ref() == mesh:
			var cached: Variant = (entry[1] as WeakRef).get_ref()
			if cached != null:
				return cached as ShaderMaterial
		_material_cache.erase(key)
	var mat := make_material(smooth)
	if mat == null:
		return null
	push_uniforms(mat, cfg, mesh)
	_material_cache[key] = [weakref(mesh), weakref(mat)]
	return mat


static func push_uniforms(mat: ShaderMaterial, cfg: Dictionary, mesh: Mesh) -> void:
	mat.set_shader_parameter("outline_color", cfg.get("outline_color", DEFAULT_COLOR))
	mat.set_shader_parameter("outline_intensity", cfg.get("outline_intensity", DEFAULT_INTENSITY))
	mat.set_shader_parameter("width_pixels", cfg.get("width_pixels", DEFAULT_WIDTH_PX))
	mat.set_shader_parameter("width_world", cfg.get("width_world", DEFAULT_WIDTH_WORLD))
	mat.set_shader_parameter("width_min_pixels", cfg.get("width_min_pixels", DEFAULT_MIN_WIDTH_PX))
	mat.set_shader_parameter("width_max_pixels", cfg.get("width_max_pixels", DEFAULT_MAX_WIDTH_PX))
	mat.set_shader_parameter("max_screen_cover", cfg.get("max_screen_cover", DEFAULT_MAX_SCREEN_COVER))
	mat.set_shader_parameter("depth_bias", cfg.get("depth_bias", DEFAULT_DEPTH_BIAS))
	mat.set_shader_parameter("fade_start", cfg.get("fade_start", 0.0))
	mat.set_shader_parameter("fade_end", cfg.get("fade_end", 0.0))
	mat.set_shader_parameter("vertex_color_mask", cfg.get("vertex_color_mask", false))
	# Demi-diagonale et centre de l'AABB, en unités LOCALES (l'échelle du nœud est reprise par le shader).
	mat.set_shader_parameter("object_radius", mesh.get_aabb().size.length() * 0.5)
	mat.set_shader_parameter("object_center", mesh.get_aabb().get_center())


# ─── Pose ─────────────────────────────────────────────────────────────────────

## Pose [param material] sur [param mi] ; rend la coque enfant, ou [code]null[/code] si la pose s'est faite en
## `material_overlay` (blend shapes). [param hull_mesh] non nul : la coque porte ce mesh RECUIT.
## [param cull_beyond] > 0 : la coque n'est plus soumise au-delà (la fin du fondu, où le trait est déjà nul).
static func pose(mi: MeshInstance3D, material: ShaderMaterial, hull_mesh: Mesh,
		cull_beyond: float = 0.0) -> MeshInstance3D:
	if mi == null or material == null or mi.mesh == null:
		return null
	if hull_mesh == null and has_blend_shapes(mi.mesh) \
			and (mi.material_overlay == null or mi.material_overlay == material):
		var previous := find_hull(mi)
		if previous != null:
			previous.queue_free()
		mi.material_overlay = material
		return null
	if mi.material_overlay == material:
		mi.material_overlay = null
	var hull := find_hull(mi)
	if hull == null:
		hull = MeshInstance3D.new()
		hull.name = HULL_NODE_NAME
		hull.set_meta(META_HULL, true)
		hull.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.add_child(hull, false, Node.INTERNAL_MODE_BACK)
	# ⚠ À CHAQUE pose : une coque qui projette une ombre coûte une passe par cascade du soleil.
	hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hull.mesh = hull_mesh if hull_mesh != null else mi.mesh
	hull.material_override = material
	hull.layers = mi.layers
	hull.visibility_range_begin = mi.visibility_range_begin
	var body_end := mi.visibility_range_end
	hull.visibility_range_end = body_end if cull_beyond <= 0.0 \
		else (cull_beyond if body_end <= 0.0 else minf(body_end, cull_beyond))
	# Un mesh skinné suit le MÊME squelette que le corps, sinon la coque reste en pose de repos.
	var target := mi.get_node_or_null(mi.skeleton)
	if target is Skeleton3D:
		hull.skin = mi.skin
		hull.skeleton = hull.get_path_to(target)
	else:
		hull.skin = null
		hull.skeleton = NodePath()
	return hull


## Retire le contour posé par ce système : la coque, et l'overlay s'il est bien le NÔTRE.
static func unpose(mi: MeshInstance3D) -> void:
	var hull := find_hull(mi)
	if hull != null:
		hull.queue_free()
	if is_hull_material(mi.material_overlay):
		mi.material_overlay = null


## La coque de [param mi] : cherchée parmi les enfants INTERNES (`get_children()` sans argument ne la voit pas).
static func find_hull(mi: MeshInstance3D) -> MeshInstance3D:
	if mi == null:
		return null
	for child in mi.get_children(true):
		if child is MeshInstance3D and bool(child.get_meta(META_HULL, false)):
			return child
	return null


static func is_hull_material(m: Material) -> bool:
	var sm := m as ShaderMaterial
	if sm == null or sm.shader == null:
		return false
	return sm.shader.resource_path in [SHADER_PLAIN, SHADER_SMOOTH]

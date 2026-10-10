class_name SubtreeOutline
extends Node
## LE CONTOUR NOIR DE LA CHARTE sur TOUS les meshes d'un sous-arbre — repris de Spirit3D (HEART_WORLD), où tout ce
## qui est intéressant (personnages, coffres, stations, portails) porte le même trait discret : 2 px d'écran, noir.
##
## Usage : un nœud sous l'objet. Sans réglage, il contourne son [code]owner[/code] (à défaut, son parent).
## [Interactable] en pose un de lui-même : tout ce à quoi on parle est souligné, sans rien poser à la main.
##
## Ce qu'il ne touche pas : l'intérieur d'un [SubViewport] (un aperçu d'UI, pas le monde) ; tout nœud portant la
## méta [code]_outline_skip[/code], et son sous-arbre (un halo, un effet qu'on ne veut pas souligner) ; les coques
## elles-mêmes (INTERNES, donc invisibles pour [method Node.get_children]).
##
## Le matériau est PARTAGÉ par (mesh, profil) : les réglages valent pour tout le sous-arbre — c'est le but d'une
## charte. Après un mesh ajouté en cours de jeu (une arme en main, un accessoire), appeler [method refresh].

@export var enabled := true
## Racine du sous-arbre à contourner. Vide : l'[code]owner[/code], à défaut le parent.
@export var target_root: Node3D

## Distance (m) où le trait commence à s'éteindre, et où il a disparu. [member fade_end] <= [member fade_start] :
## il ne s'éteint jamais. ⚠ [member fade_end] borne aussi la PORTÉE de la coque : au-delà, elle n'est plus dessinée
## du tout (un trait de largeur nulle coûterait encore sa géométrie, son squelette et son appel de dessin).
@export var fade_start := 0.0
@export var fade_end := 0.0

@export_group("Contour")
@export var outline_color: Color = OutlineHull.DEFAULT_COLOR
@export_range(0.0, 32.0, 0.05) var outline_width: float = OutlineHull.DEFAULT_WIDTH_PX
## Part de la largeur en MÈTRES (s'ajoute aux pixels) : elle rétrécit avec la distance. 0 = la charte.
@export_range(0.0, 1.0, 0.001) var outline_width_world: float = OutlineHull.DEFAULT_WIDTH_WORLD
@export_range(0.0, 1.0, 0.005) var max_screen_cover: float = OutlineHull.DEFAULT_MAX_SCREEN_COVER

const SKIP_META := "_outline_skip"

## Un modèle chargé en retard met quelques dixièmes de seconde à arriver ; au-delà, il n'arrivera plus.
const MAX_RETRIES := 8
const RETRY_DELAY_SEC := 0.3
## Le recuit balaie TOUS les sommets en GDScript : au-delà, on garde les normales du mesh (au pire de petits trous
## aux arêtes vives, jamais une pause).
const MASS_BAKE_MAX_VERTICES := 20000

var _retries_left := MAX_RETRIES


func _ready() -> void:
	refresh.call_deferred()


## (Re)pose le contour sur tout le sous-arbre. Idempotent : repasser ne coûte ni matériau ni coque de plus.
func refresh() -> void:
	if not is_inside_tree():
		return
	var root := _root()
	if root == null:
		return
	if not enabled:
		_clear_recursive(root)
		return
	var applied := _apply_recursive(root, 0)
	# Aucun mesh : le modèle n'est sans doute pas encore là. Réessayer, puis abandonner.
	if applied == 0 and _retries_left > 0:
		_retries_left -= 1
		get_tree().create_timer(RETRY_DELAY_SEC).timeout.connect(refresh, CONNECT_ONE_SHOT)


func clear_outline() -> void:
	var root := _root()
	if root != null:
		_clear_recursive(root)


func _root() -> Node:
	if target_root != null and is_instance_valid(target_root):
		return target_root
	if owner != null and is_instance_valid(owner):
		return owner
	return get_parent()


func _apply_recursive(node: Node, applied: int) -> int:
	if node == null or node.has_meta(SKIP_META) or node is SubViewport:
		return applied
	if node is MeshInstance3D and _apply_to_mesh(node):
		applied += 1
	for child in node.get_children():
		applied = _apply_recursive(child, applied)
	return applied


func _apply_to_mesh(mi: MeshInstance3D) -> bool:
	var mesh := mi.mesh
	if mesh == null or mesh.get_surface_count() == 0 or bool(mi.get_meta(OutlineHull.META_HULL, false)):
		return false
	var baked := OutlineHull.smooth_normal_mesh(mesh) if _bakeable(mesh) else null
	var mat := OutlineHull.shared_material(mesh, baked != null, _profile())
	if mat == null:
		return false
	OutlineHull.pose(mi, mat, baked, fade_end if fade_end > fade_start else 0.0)
	return true


func _bakeable(mesh: Mesh) -> bool:
	var am := mesh as ArrayMesh
	if am == null:
		return true  # un PrimitiveMesh tient en quelques centaines de sommets
	var total := 0
	for s in am.get_surface_count():
		total += am.surface_get_array_len(s)
		if total > MASS_BAKE_MAX_VERTICES:
			return false
	return true


func _clear_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		OutlineHull.unpose(node)
	for child in node.get_children():
		_clear_recursive(child)


func _profile() -> Dictionary:
	return {
		"outline_color": outline_color,
		"width_pixels": outline_width,
		"width_world": outline_width_world,
		"max_screen_cover": max_screen_cover,
		"fade_start": fade_start,
		"fade_end": fade_end,
	}

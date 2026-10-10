// Contour « coque inversée » — variante NORMALES DU MESH.
// Utilisée quand le mesh est déjà lisse (aucune normale dédoublée) : la coque est
// alors continue et il n'y a rien à recuire. Posée en `material_overlay` sur le
// MeshInstance3D lui-même — donc zéro nœud ajouté, et le squelette, les blend
// shapes et les LOD du mesh d'origine sont suivis gratuitement.
// Cf. outline_hull_smooth.gdshader pour les meshes à arêtes vives.
//
// `cull_front` : on ne dessine que les faces arrière, seule façon de garantir que la
// coque reste DERRIÈRE le corps. Sur la limite que cela impose aux meshes sans
// géométrie arrière, cf. l'include.
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;

#include "res://world/contour/outline_hull_common.gdshaderinc"

void vertex() {
	// Les built-ins sont consommés ICI et transmis en scalaires : passés tels quels à
	// une fonction de l'include, ils arrivent à zéro (cf. l'avertissement dans l'include).
	// `abs` sur l'échelle Y de la projection : sur Vulkan, Godot y met un signe NÉGATIF
	// (l'espace clip a son Y vers le bas) — sans ça le facteur mètre→pixel sort négatif
	// et toute la coque s'effondre à zéro, silencieusement.
	mat4 modelview = VIEW_MATRIX * MODEL_MATRIX;
	float node_scale = max(max(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz)),
		length(MODEL_MATRIX[2].xyz));
	float proj_px_scale = abs(PROJECTION_MATRIX[1][1]) * 0.5 * VIEWPORT_SIZE.y;
	bool ortho = abs(PROJECTION_MATRIX[3][3]) > 0.5;

	VERTEX += hull_vertex_offset(
		hull_safe_normal(NORMAL, vec3(0.0)), VERTEX, COLOR.r,
		modelview, mat3(VIEW_MATRIX) * MODEL_NORMAL_MATRIX,
		node_scale, proj_px_scale, ortho);
}

void fragment() {
	ALBEDO = outline_color.rgb * outline_intensity;
}

// Contour « coque inversée » — variante NORMALES LISSÉES RECUITES.
// CUSTOM0.xyz porte la normale moyennée sur tous les sommets partageant la même
// POSITION, recuite par `outline_hull.gd`. C'est ce qui referme les trous aux
// arêtes vives : sur un cube (ou un bâtiment Tripo à faces dures) chaque coin
// existe en 3 exemplaires avec 3 normales orthogonales, et pousser chacun le long
// de SA normale écarte les trois copies — la coque se déchire au coin.
// NORMAL sert de repli si le recuit n'a rien écrit pour ce sommet.
// Sur `cull_front`, cf. outline_hull.gdshader.
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
		hull_safe_normal(CUSTOM0.xyz, NORMAL), VERTEX, COLOR.r,
		modelview, mat3(VIEW_MATRIX) * MODEL_NORMAL_MATRIX,
		node_scale, proj_px_scale, ortho);
}

void fragment() {
	ALBEDO = outline_color.rgb * outline_intensity;
}

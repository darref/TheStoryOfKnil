// ============================================================================
// Contour « coque inversée » — cœur commun (repris de Spirit3D, 10 octobre 2026)
// ============================================================================
// Remplace l'ancien `improved_inverted_hull_simplest_outline_shader_improved`,
// qui se résumait à `VERTEX += NORMAL * weight * COLOR.r`.
//
// Ce que cette version corrige, un défaut par point :
//
//  1. LARGEUR EN PIXELS. L'ancienne poussait les sommets de `weight` MÈTRES : le
//     trait devenait invisible au loin, énorme de près, et changeait d'épaisseur
//     selon l'échelle du nœud (les nœuds mis à l'échelle, comme le modèle de Knil (×1,9)). Ici la largeur voulue est
//     convertie en mètres à la profondeur du sommet via le facteur mètre→pixel de
//     la projection, donc l'épaisseur à l'écran est constante. Un terme
//     `width_world` (mètres) reste disponible et s'ajoute au terme pixel.
//
//  2. GÉOMÉTRIE PLATE. Un quad face caméra a toutes ses normales dirigées vers
//     l'objectif : leur projection à l'écran est nulle, donc une coque par normales
//     ne l'élargit PAS, elle le rapproche seulement de la caméra. Quand la normale
//     ne donne plus de direction d'écran exploitable, on bascule progressivement
//     sur la direction « depuis le centre de l'objet », toujours définie.
//
//  3. BIAIS DE PROFONDEUR RELATIF. La coque est repoussée de `depth_bias` × la
//     distance, le long du rayon de vue, ce qui supprime le z-fight de la coque
//     contre sa propre surface sur les géométries minces.
//
//  4. PLAFOND PAR TAILLE APPARENTE (`max_screen_cover` + `object_radius`) : un
//     objet minuscule à l'horizon ne peut plus se transformer en pâté noir.
//
//  5. ÉCHELLES NON UNIFORMES. La normale passe par la matrice de normales, et le
//     décalage repasse en espace modèle par l'inverse de la modelview : une échelle
//     non uniforme ou négative ne déforme plus le trait.
//
//  6. GARDE-FOUS NaN : normale nulle, direction dégénérée, modelview dégénérée.
//     Chacun produisait un sommet invalide, donc un triangle géant à l'écran.
//
// LIMITE ASSUMÉE : un mesh SANS géométrie arrière (quad, bannière, carte de
// feuillage — une seule nappe de triangles) n'a rien à dessiner sous `cull_front`,
// il n'a donc pas de contour. Rendre son MATÉRIAU double face n'y change rien : ce
// sont les mêmes triangles, toujours orientés vers la caméra. C'est inhérent à la
// coque inversée, pas un réglage ; un contour pour ces cas-là demande une passe
// écran (détection de bords ou JFA). Tout mesh fermé — donc tout ce que le projet
// contourne aujourd'hui — est couvert.
//
// Le trou aux ARÊTES VIVES se règle côté géométrie, pas ici : cf. `outline_hull.gd`,
// qui recuit des normales lissées soudées par position dans CUSTOM0.
//
// ⚠ QUATRE PIÈGES DE GODOT 4.7, tous vérifiés AU RENDU (aucun ne lève d'erreur :
// chacun se traduit par une coque simplement absente), et qui expliquent la forme
// du code :
//   1. écrire `POSITION` (espace clip) depuis un spatial shader n'a AUCUN effet ;
//      la coque ressortait non décalée, donc cachée derrière le corps ;
//   2. `render_mode skip_vertex_transform` met `PROJECTION_MATRIX` et
//      `VIEWPORT_SIZE` À ZÉRO dans le vertex ;
//   3. passer un built-in (`PROJECTION_MATRIX`, `VIEWPORT_SIZE`) TEL QUEL en
//      argument d'une fonction d'include le fait arriver à zéro : il faut le
//      consommer dans `vertex()` et ne transmettre que des scalaires ;
//   4. sur Vulkan, `PROJECTION_MATRIX[1][1]` est NÉGATIF (le Y de l'espace clip
//      pointe vers le bas) — d'où le `abs()` côté appelant.
// D'où la forme retenue : pipeline de transformation normal, built-ins digérés dans
// `vertex()`, et cette fonction rend un décalage en espace MODÈLE à ajouter à VERTEX.

uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
// Multiplie la couleur. > 1.0 déborde en HDR et allume le glow du WorldEnvironment.
uniform float outline_intensity : hint_range(0.0, 8.0, 0.05) = 1.0;

// Largeur = width_pixels (constante à l'écran) + width_world (mètres, décroît avec
// la distance comme n'importe quelle longueur du monde).
uniform float width_pixels : hint_range(0.0, 32.0, 0.05) = 2.0;
uniform float width_world : hint_range(0.0, 1.0, 0.001) = 0.0;
uniform float width_min_pixels : hint_range(0.0, 32.0, 0.05) = 0.0;
uniform float width_max_pixels : hint_range(0.0, 64.0, 0.05) = 12.0;

// Plafond « le trait ne mange pas l'objet ». object_radius est en unités LOCALES
// (demi-diagonale de l'AABB du mesh) ; l'échelle du nœud est reprise du MODEL_MATRIX.
uniform float max_screen_cover : hint_range(0.0, 1.0, 0.005) = 0.10;
uniform float object_radius = 0.0;
// Centre de l'AABB, en unités locales : origine du repli radial.
uniform vec3 object_center = vec3(0.0);

uniform float depth_bias : hint_range(0.0, 0.05, 0.0001) = 0.0015;

// Extinction douce au loin : la largeur tombe à 0 entre fade_start et fade_end
// (mètres). À 0 le trait DISPARAÎT — pas besoin de transparence, donc ni passe
// transparente ni tri. Laisser fade_end <= fade_start pour désactiver.
uniform float fade_start = 0.0;
uniform float fade_end = 0.0;

// Compat : l'ancien shader multipliait la largeur par COLOR.r. Sur un mesh à
// couleurs de sommet sombres, le contour disparaissait sans raison visible.
uniform bool vertex_color_mask = false;


// Normale sûre : `primary` si elle est exploitable, sinon `fallback`, sinon zéro.
vec3 hull_safe_normal(vec3 primary, vec3 fallback) {
	if (dot(primary, primary) > 1e-8) {
		return normalize(primary);
	}
	if (dot(fallback, fallback) > 1e-8) {
		return normalize(fallback);
	}
	return vec3(0.0);
}


vec2 hull_safe_dir(vec2 v) {
	float l = length(v);
	return l > 1e-6 ? v / l : vec2(0.0);
}


// Décalage à ajouter à VERTEX, en espace MODÈLE. [param n_local] est la normale
// (recuite ou non) en espace local.
//
// ⚠ Les built-ins de projection ne sont PAS pris en paramètre mais pré-digérés en
// scalaires par l'appelant : passer `PROJECTION_MATRIX` ou `VIEWPORT_SIZE` tels
// quels en argument d'une fonction d'un `.gdshaderinc` les fait arriver à ZÉRO
// (Godot 4.7 ne les compte pas comme « utilisés » et n'émet pas leur lecture).
// Vérifié au rendu : la largeur s'effondrait silencieusement à 0.
// [param proj_px_scale] = PROJECTION_MATRIX[1][1] × 0.5 × VIEWPORT_SIZE.y.
// [param node_scale] = la plus grande des trois longueurs de base du MODEL_MATRIX.
vec3 hull_vertex_offset(
		vec3 n_local,
		vec3 vertex_local,
		float mask,
		mat4 modelview,
		mat3 mv_normal,
		float node_scale,
		float proj_px_scale,
		bool ortho) {
	mat3 mv3 = mat3(modelview);
	// Nœud d'échelle nulle : la modelview n'est plus inversible.
	if (abs(determinant(mv3)) < 1e-12) {
		return vec3(0.0);
	}

	vec4 view_pos = modelview * vec4(vertex_local, 1.0);
	float dist = ortho ? 1.0 : max(-view_pos.z, 1e-4);

	// Combien de pixels fait un mètre, perpendiculaire à la vue, à cette profondeur.
	// Les axes X et Y de l'espace vue sont alignés à l'écran et partagent ce facteur
	// (proj[0][0] × largeur_viewport == proj[1][1] × hauteur_viewport sur une
	// projection symétrique), donc un décalage isotrope en vue le reste à l'écran.
	float meter_to_px = proj_px_scale / dist;
	if (meter_to_px < 1e-6) {
		return vec3(0.0);
	}

	float w = width_pixels + width_world * meter_to_px;
	if (vertex_color_mask) {
		w *= mask;
	}
	w = clamp(w, width_min_pixels, width_max_pixels);

	if (object_radius > 0.0 && max_screen_cover > 0.0) {
		w = min(w, object_radius * node_scale * meter_to_px * max_screen_cover);
	}

	if (fade_end > fade_start) {
		w *= 1.0 - smoothstep(fade_start, fade_end, dist);
	}

	vec3 n_view = mv_normal * n_local;
	// `facing` ≈ 0 quand la normale pointe droit vers/contre la caméra (elle ne dit
	// alors rien de la direction d'élargissement), ≈ 1 sur une silhouette.
	float facing = length(n_view.xy);
	vec2 radial = view_pos.xy - (modelview * vec4(object_center, 1.0)).xy;
	vec2 dir = hull_safe_dir(mix(
		hull_safe_dir(radial),
		hull_safe_dir(n_view.xy),
		smoothstep(0.05, 0.35, facing)));

	// Écartement À PROFONDEUR CONSTANTE, puis recul le long du rayon de vue. Rester à
	// profondeur constante est ce qui garde la coque derrière le corps : suivre le plan
	// tangent (pourtant plus « juste » sur une surface plane) la ferait passer DEVANT
	// toute surface convexe, le plan tangent d'un convexe étant entièrement à
	// l'extérieur — essayé, la coque recouvrait l'objet en aplat.
	vec3 delta_view = vec3(dir * (w / meter_to_px), -dist * depth_bias);
	return inverse(mv3) * delta_view;
}

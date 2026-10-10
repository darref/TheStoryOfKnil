shader_type canvas_item;

// Vitesse de défilement de la ligne (cycle par seconde)
uniform float speed : hint_range(0.1, 2.0) = 0.4;
// Intensité de la brillance (0 = rien, 1 = fort)
uniform float shine_strength : hint_range(0.0, 1.0) = 0.2;
// Épaisseur de la bande de brillance
uniform float band_width : hint_range(0.01, 0.3) = 0.08;
// Pic au centre de la bande : 1 = dégradé linéaire d’un bord à l’autre, plus élevé = cœur beaucoup plus brillant que les bords
uniform float band_center_peak : hint_range(1.0, 5.0) = 5.0;

void fragment() {
	// Coordonnée le long de la diagonale (bas-gauche -> haut-droite), normalisée 0..1
	float diag = (UV.x + UV.y) * 0.5;
	// Position de la ligne qui défile
	float pos = fract(TIME * speed);
	float d = abs(diag - pos);
	d = min(d, 1.0 - d);
	// Masque d’épaisseur (même extension qu’avant), puis courbe vers un maximum au centre de la bande
	float band_mask = 1.0 - smoothstep(0.0, band_width, d);
	float shine = pow(band_mask, band_center_peak) * shine_strength;
	COLOR.rgb += vec3(shine);
}

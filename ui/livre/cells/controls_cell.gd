extends PageCell

## COMMANDES — le clavier et la manette, d'après `core/inputs.gd` (à tenir à jour avec lui).

const LIGNES := [
	["Se déplacer", "W A S D (Z Q S D) · flèches", "stick gauche"],
	["Courir", "Maj", "clic du stick gauche · RB"],
	["Sauter", "Espace", "A"],
	["Parler", "E", "X"],
	["Fermer", "Échap", "B"],
	["Torche", "T", "Y"],
	["Tourner la vue (3e pers.)", "clic droit + souris", "stick droit ← →"],
	["Zoom", "molette", "stick droit ↑ ↓"],
	["Vue haute", "Ctrl + molette", "Back"],
	["Le livre (menu, pause)", "Échap", "Start"],
	["Sauvegarde rapide", "F5 / F9", "—"],
	["Triche : vol · fantôme · vitesse · +1 h", "F1 · F2 · F3 · F4", "LB · — · clic stick droit · —"],
]


func _build(col: VBoxContainer) -> void:
	_column.custom_minimum_size = Vector2(1100, 0)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 8)
	for h in ["", "Clavier / souris", "Manette"]:
		grid.add_child(label(h, 24, ACCENT))
	for l: Array in LIGNES:
		for i in 3:
			grid.add_child(label(l[i], 22 if i > 0 else 24))
	col.add_child(grid)
	var back := button("Retour au livre", func() -> void: reset_cell())
	col.add_child(back)

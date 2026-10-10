extends PageCell

## QUITTER — ouvrir la cellule vaut confirmation : un bouton pour partir, un pour rester.


func _build(col: VBoxContainer) -> void:
	var l := label("Knil s'en va déjà ? Personne ne le regrettera.", 26)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(l)
	col.add_child(button("Rester", func() -> void: reset_cell()))
	col.add_child(button("Quitter le jeu", func() -> void: get_tree().quit()))

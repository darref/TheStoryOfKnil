extends Node
## LA SAUVEGARDE — un fichier JSON par emplacement : l'état de la partie et l'horloge. Rien d'autre n'est
## gardé : le monde se reconstruit depuis eux (le germe refait les mêmes tirages, l'historique les mêmes
## contextes).

const DIR := "user://saves"


func path_of(slot: String) -> String:
	return DIR.path_join(slot + ".json")


func save(slot := "rapide") -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f := FileAccess.open(path_of(slot), FileAccess.WRITE)
	if f == null:
		push_error("SaveSystem: impossible d'écrire %s" % path_of(slot))
		return false
	f.store_string(JSON.stringify({"version": 1, "clock": GameClock.to_save(), "state": GameState.to_save()}, "\t"))
	return true


func load_slot(slot := "rapide") -> bool:
	if not FileAccess.file_exists(path_of(slot)):
		return false
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path_of(slot))) != OK:
		push_error("SaveSystem: %s illisible" % path_of(slot))
		return false
	DecisionEngine.close_encounter()
	GameClock.from_save(json.data.get("clock", {}))
	GameState.from_save(json.data.get("state", {}))
	return true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quicksave"):
		save()
	elif event.is_action_pressed("quickload"):
		load_slot()

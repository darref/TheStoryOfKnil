extends PageCell

## SAUVEGARDES — la sauvegarde rapide (F5 / F9 en jeu) et trois emplacements, par le SaveSystem (un JSON chacun).
## Charger referme le livre et rend la main au jeu.

const SLOTS := [["rapide", "Rapide (F5 / F9)"], ["emplacement_1", "Emplacement 1"],
	["emplacement_2", "Emplacement 2"], ["emplacement_3", "Emplacement 3"]]

var _rows: Dictionary = {}  # slot -> {info: Label, load: Button}
var _status: Label


func _build(col: VBoxContainer) -> void:
	for s: Array in SLOTS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var name_l := label(s[1], 26)
		name_l.custom_minimum_size = Vector2(250, 0)
		row.add_child(name_l)
		var info := label("", 20)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var save_b := button("Sauver", _on_save.bind(s[0]))
		save_b.custom_minimum_size = Vector2(150, 54)
		row.add_child(save_b)
		var load_b := button("Charger", _on_load.bind(s[0]))
		load_b.custom_minimum_size = Vector2(150, 54)
		row.add_child(load_b)
		col.add_child(row)
		_rows[s[0]] = {"info": info, "load": load_b}
	_status = label("", 22, ACCENT)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_status)
	_refresh()


func _enlarge_cell_impl(skip_animation: bool) -> void:
	_refresh()
	_status.text = ""
	super._enlarge_cell_impl(skip_animation)


func _refresh() -> void:
	for slot: String in _rows:
		var path := SaveSystem.path_of(slot)
		var exists := FileAccess.file_exists(path)
		_rows[slot]["info"].text = Time.get_datetime_string_from_unix_time(
			FileAccess.get_modified_time(path) + _utc_offset(), true) if exists else "— vide —"
		_rows[slot]["load"].disabled = not exists


static func _utc_offset() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


func _on_save(slot: String) -> void:
	_status.text = "Sauvé." if SaveSystem.save(slot) else "Échec de la sauvegarde."
	_refresh()


func _on_load(slot: String) -> void:
	if not SaveSystem.load_slot(slot):
		_status.text = "Rien à charger."
		return
	if book_ref != null:
		book_ref.resume_game()

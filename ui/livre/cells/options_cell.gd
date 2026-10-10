extends PageCell

## OPTIONS — plein écran, synchro verticale, volume, résolution du rendu 3D. Gardées dans `user://options.cfg` et
## REMISES au lancement (le livre est la scène principale : cette cellule est prête avant la première image de jeu).

const FICHIER := "user://options.cfg"

var _cfg := ConfigFile.new()


func _build(col: VBoxContainer) -> void:
	_cfg.load(FICHIER)
	col.add_child(_check("Plein écran", "plein_ecran",
		DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]))
	col.add_child(_check("Synchro verticale", "vsync", DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED))
	col.add_child(_slider("Volume", "volume", 1.0, 0.0, 1.0, 0.05))
	col.add_child(_slider("Résolution 3D", "echelle_3d", 1.0, 0.5, 1.0, 0.05))
	_apply_all.call_deferred()


func _check(text: String, key: String, fallback: bool) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.focus_mode = Control.FOCUS_ALL
	c.add_theme_font_size_override("font_size", 28)
	c.add_theme_color_override("font_color", INK)
	c.add_theme_color_override("font_focus_color", ACCENT)
	c.button_pressed = bool(_cfg.get_value("options", key, fallback))
	c.toggled.connect(func(on: bool) -> void: _store(key, on))
	return c


func _slider(text: String, key: String, fallback: float, lo: float, hi: float, step: float) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	var l := label(text, 28)
	l.custom_minimum_size = Vector2(260, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.focus_mode = Control.FOCUS_ALL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(0, 32)
	s.value = float(_cfg.get_value("options", key, fallback))
	var pct := label("%d %%" % roundi(s.value * 100.0), 24)
	pct.custom_minimum_size = Vector2(90, 0)
	s.value_changed.connect(func(v: float) -> void:
		pct.text = "%d %%" % roundi(v * 100.0)
		_store(key, v))
	row.add_child(s)
	row.add_child(pct)
	return row


func _store(key: String, value: Variant) -> void:
	_cfg.set_value("options", key, value)
	_cfg.save(FICHIER)
	_apply(key, value)


func _apply_all() -> void:
	if not _cfg.has_section("options"):
		return
	for key in _cfg.get_section_keys("options"):
		_apply(key, _cfg.get_value("options", key))


func _apply(key: String, value: Variant) -> void:
	match key:
		"plein_ecran":
			var full := DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
			if bool(value) != full:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if value else DisplayServer.WINDOW_MODE_WINDOWED)
		"vsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if value else DisplayServer.VSYNC_DISABLED)
		"volume":
			AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(value), 0.0001)))
			AudioServer.set_bus_mute(0, float(value) <= 0.0)
		"echelle_3d":
			var game: Cell = book_ref.find_game_cell() if book_ref != null else null
			if game != null and game.subviewport != null:
				game.subviewport.scaling_3d_scale = float(value)

class_name ActionBar
extends PanelContainer
## LA BARRE D'ACTIONS — une rangée horizontale de boutons CARRÉS, un par action que le moteur propose.
## « Mépriser » est toujours là, en dernier : la barre n'est jamais vide. Touches 1 à 8, ou clic ; à la MANETTE, la
## croix ← → déplace la case choisie (encadrée), A la valide.
## Chaque case montre l'icône de l'action (glyphe provisoire, ou `icon_path` quand l'art existe) ; son nom
## est dans l'infobulle et sous la barre.

const Inputs := preload("res://core/inputs.gd")

@export var button_size := 72

var _row: HBoxContainer
var _caption: Label
var _actions: Array = []
var _sel := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(col)
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 8)
	col.add_child(_row)
	_caption = Label.new()
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_caption)
	visible = false
	EventBus.encounter_opened.connect(_on_opened)
	EventBus.encounter_closed.connect(func(_id: String) -> void: _clear())


func _on_opened(_target_id: String, actions: Array) -> void:
	_clear()
	_actions = actions
	for i in actions.size():
		var a: Dictionary = actions[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(button_size, button_size)
		b.tooltip_text = "%d — %s" % [i + 1, a.get("label", a.get("id", ""))]
		b.focus_mode = Control.FOCUS_NONE
		var icon_path := str(a.get("icon_path", ""))
		if icon_path != "" and ResourceLoader.exists(icon_path):
			b.icon = load(icon_path)
			b.expand_icon = true
		else:
			b.text = str(a.get("icon", "?"))
			b.add_theme_font_size_override("font_size", int(button_size * 0.45))
		b.pressed.connect(DecisionEngine.choose.bind(i))
		b.mouse_entered.connect(func() -> void: _select(i))
		_row.add_child(b)
	_sel = 0
	visible = true
	_select(0)


## La case choisie : encadrée, son nom sous la barre, avec la touche qui valide et celle qui fait partir.
func _select(i: int) -> void:
	if _actions.is_empty():
		return
	_sel = posmod(i, _actions.size())
	for k in _row.get_child_count():
		var b := _row.get_child(k) as Button
		b.modulate = Color.WHITE if k == _sel else Color(0.72, 0.72, 0.72)
		b.scale = Vector2.ONE * (1.08 if k == _sel else 1.0)
		b.pivot_offset = b.custom_minimum_size / 2
	var a: Dictionary = _actions[_sel]
	if Inputs.pad:
		_caption.text = "%s · ← → choisir · A valider · %s partir" % [a.get("label", ""), Inputs.label("interact")]
	else:
		_caption.text = "%s · 1–%d choisir · %s partir" % [a.get("label", ""), _actions.size(), Inputs.label("interact")]


## L'appareil a changé (clavier ↔ manette) : la légende suit.
func refresh_caption() -> void:
	if visible:
		_select(_sel)


func _clear() -> void:
	for c in _row.get_children():
		c.queue_free()
	_actions = []
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("bar_prev"):
		get_viewport().set_input_as_handled()
		_select(_sel - 1)
		return
	if event.is_action_pressed("bar_next"):
		get_viewport().set_input_as_handled()
		_select(_sel + 1)
		return
	if event.is_action_pressed("bar_confirm") and event is InputEventJoypadButton:
		get_viewport().set_input_as_handled()
		DecisionEngine.choose(_sel)
		return
	for i in mini(_actions.size(), 8):
		if event.is_action_pressed("choice_%d" % (i + 1)):
			get_viewport().set_input_as_handled()
			DecisionEngine.choose(i)
			return

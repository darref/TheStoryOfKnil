extends CanvasLayer
## L'INTERFACE — provisoire dans sa forme, définitive dans ses branchements : elle n'écoute que l'EventBus et
## ne lit que le GameState. En haut : le jour, l'heure, l'or, la fatigue. Au centre : ce qu'on peut faire
## ici. En bas : la barre d'actions. Pendant le sommeil : un voile léger, le monde défile derrière.

const ActionBarScript := preload("res://ui/action_bar.gd")
const Inputs := preload("res://core/inputs.gd")
const Triche := preload("res://core/triche.gd")

var _clock: Label
var _gold: Label
var _fatigue: ProgressBar
var _place: Label
var _prompt: Label
var _toast: Label
var _veil: ColorRect
var _toast_left := 0.0
var _bar: Control
var _focus: Node = null
var _cheat: Label


func _ready() -> void:
	var top := HBoxContainer.new()
	top.position = Vector2(16, 12)
	top.add_theme_constant_override("separation", 24)
	add_child(top)
	_clock = _label(top)
	_gold = _label(top)
	_fatigue = ProgressBar.new()
	_fatigue.custom_minimum_size = Vector2(160, 18)
	_fatigue.show_percentage = false
	top.add_child(_fatigue)
	_place = _label(top)
	_cheat = _label(top)
	_cheat.add_theme_color_override("font_color", Color(1.0, 0.55, 0.3))

	_veil = ColorRect.new()
	_veil.color = Color(0.02, 0.02, 0.08, 0.35)
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.visible = false
	add_child(_veil)

	_prompt = _label(self)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place_rect(_prompt, Rect2(-300, -170, 600, 24))

	_toast = _label(self)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place_rect(_toast, Rect2(-400, 60, 800, 24))

	var bar := ActionBarScript.new()
	_bar = bar
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.position.y -= 24
	add_child(bar)

	EventBus.focus_changed.connect(_on_focus)
	EventBus.notice.connect(_on_notice)
	EventBus.sleep_warning.connect(_on_sleep_warning)
	EventBus.sleep_started.connect(_on_sleep_started)
	EventBus.sleep_finished.connect(_on_sleep_finished)
	EventBus.action_resolved.connect(func(_t: String, a: String, _r: Dictionary) -> void: toast("→ " + a))
	EventBus.region_entered.connect(func(id: String, t: String) -> void: toast("%s (%s)" % [id, t]))


func _process(delta: float) -> void:
	_clock.text = "Jour %d · %02d:%02d · %s · %s" % [GameClock.day() + 1, GameClock.hour(), GameClock.minute(),
		GameClock.phase(), GameClock.season()]
	_gold.text = "%d or" % int(GameState.get_value("player.wealth.gold", 0))
	_fatigue.max_value = SleepSystem.limit_hours()
	_fatigue.value = SleepSystem.awake_hours()
	_cheat.text = Triche.etat()
	_place.text = str(GameState.get_value("place.region_type", "")) + \
		(" · " + str(GameState.get_value("place.interior_type", "")) if GameState.get_value("place.interior", false) else "")
	if _toast_left > 0.0:
		_toast_left -= delta
		_toast.modulate.a = clampf(_toast_left, 0.0, 1.0)


## Le dernier appareil touché (clavier ou manette) : les noms de touches à l'écran suivent.
func _input(event: InputEvent) -> void:
	if Inputs.note(event):
		_on_focus(_focus)
		_bar.refresh_caption()


func toast(text: String, seconds := 3.0) -> void:
	if text == "":
		return
	_toast.text = text
	_toast_left = seconds


func _on_focus(target: Node) -> void:
	_focus = target
	if target == null:
		_prompt.text = ""
		return
	var it := target as Interactable
	var p := it.current_problem()
	_prompt.text = "%s — %s%s" % [Inputs.label("interact"), it.describe()["name"],
		(" (%s)" % p.get("label", "")) if not p.is_empty() else ""]


func _on_notice(text: String, seconds: float) -> void:
	toast(text, seconds)


func _on_sleep_warning(hours_left: float) -> void:
	if hours_left < 0.0:
		toast("Pas encore fatigué.")
	else:
		toast("Il faudra dormir d'ici %d heures." % int(ceil(hours_left)), 5.0)


func _on_sleep_started(kind: String, forced: bool) -> void:
	_veil.visible = true
	toast("Tu t'effondres de fatigue…" if forced else "Tu t'endors (%s)." % kind, 4.0)


func _on_sleep_finished(outcome: Dictionary) -> void:
	_veil.visible = false
	toast(str(outcome.get("message", "")) if str(outcome.get("message", "")) != "" else "Réveillé.", 5.0)


## Les marges d'un contrôle ancré : `r` est relatif à son point d'ancrage.
static func _place_rect(c: Control, r: Rect2) -> void:
	c.offset_left = r.position.x
	c.offset_top = r.position.y
	c.offset_right = r.end.x
	c.offset_bottom = r.end.y


static func _label(parent: Node) -> Label:
	var l := Label.new()
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	parent.add_child(l)
	return l

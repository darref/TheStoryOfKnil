extends CanvasLayer
## L'INTERFACE — provisoire dans sa forme, définitive dans ses branchements : elle n'écoute que l'EventBus et
## ne lit que le GameState. En haut : les cœurs, l'argent, l'heure, le lieu ; à droite, le COMPTEUR d'images/s. Au centre : à qui l'on peut parler.
## En bas : la boîte de dialogue.

const Inputs := preload("res://core/inputs.gd")
const Triche := preload("res://core/triche.gd")

var _hearts: Label
var _money: Label
var _clock: Label
var _place: Label
var _prompt: Label
var _toast: Label
var _toast_left := 0.0
var _box: PanelContainer
var _speaker: Label
var _line: Label
var _focus: Node = null
var _cheat: Label
var _fps: Label
var _worst_ms := 0.0  # la pire image de la dernière demi-seconde
var _fps_left := 0.0


func _ready() -> void:
	var top := HBoxContainer.new()
	top.position = Vector2(16, 12)
	top.add_theme_constant_override("separation", 24)
	add_child(top)
	_hearts = _label(top)
	_hearts.add_theme_color_override("font_color", Color(0.95, 0.25, 0.25))
	_money = _label(top)
	_clock = _label(top)
	_place = _label(top)
	_cheat = _label(top)
	_cheat.add_theme_color_override("font_color", Color(1.0, 0.55, 0.3))

	# Le compteur : images/s (moyenne de Godot sur une seconde) et la pire image récente — un à-coup s'y voit.
	_fps = _label(self)
	_fps.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_fps.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place_rect(_fps, Rect2(-236, 12, 220, 24))

	_prompt = _label(self)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place_rect(_prompt, Rect2(-300, -170, 600, 24))

	_toast = _label(self)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place_rect(_toast, Rect2(-400, 60, 800, 24))

	# La boîte de dialogue : qui parle, ce qu'il dit.
	_box = PanelContainer.new()
	_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_place_rect(_box, Rect2(-380, -150, 760, 120))
	_box.visible = false
	add_child(_box)
	var v := VBoxContainer.new()
	_box.add_child(v)
	_speaker = _label(v)
	_speaker.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_line = _label(v)
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	EventBus.focus_changed.connect(_on_focus)
	EventBus.notice.connect(func(text: String, seconds: float) -> void: toast(text, seconds))
	EventBus.dialogue_shown.connect(_on_dialogue)
	EventBus.dialogue_closed.connect(_on_dialogue_closed)
	EventBus.region_entered.connect(func(id: String, t: String) -> void: toast("%s (%s)" % [id, t]))


func _process(delta: float) -> void:
	var hp := int(GameState.get_value("player.health", 0))
	var hp_max := int(GameState.get_value("player.max_health", 0))
	_hearts.text = "♥".repeat(hp / 2) + ("♡" if hp % 2 == 1 else "") + "·".repeat((hp_max - hp) / 2)
	_money.text = "%d pièces" % int(GameState.get_value("player.money", 0))
	_clock.text = "Jour %d · %02d:%02d" % [GameClock.day() + 1, GameClock.hour(), GameClock.minute()]
	_cheat.text = Triche.etat()
	_place.text = str(GameState.get_value("place.region_type", "")) + \
		(" · " + str(GameState.get_value("place.interior_type", "")) if GameState.get_value("place.interior", false) else "")
	_worst_ms = maxf(_worst_ms, delta * 1000.0)
	_fps_left -= delta
	if _fps_left <= 0.0:
		_fps.text = "%d img/s · pire %.0f ms" % [Engine.get_frames_per_second(), _worst_ms]
		_fps.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6) if _worst_ms <= 33.4 else Color(1.0, 0.6, 0.4))
		_worst_ms = 0.0
		_fps_left = 0.5
	if _toast_left > 0.0:
		_toast_left -= delta
		_toast.modulate.a = clampf(_toast_left, 0.0, 1.0)


## Le dernier appareil touché (clavier ou manette) : les noms de touches à l'écran suivent.
func _input(event: InputEvent) -> void:
	if Inputs.note(event):
		_on_focus(_focus)


func toast(text: String, seconds := 3.0) -> void:
	if text == "":
		return
	_toast.text = text
	_toast_left = seconds


func _on_focus(target: Node) -> void:
	_focus = target
	if target == null or _box.visible:
		_prompt.text = ""
		return
	_prompt.text = "%s — %s" % [Inputs.label("interact"), (target as Interactable).title()]


func _on_dialogue(speaker: String, text: String) -> void:
	_speaker.text = speaker
	_line.text = text
	_box.visible = true
	_prompt.text = ""


func _on_dialogue_closed() -> void:
	_box.visible = false
	_on_focus(_focus)


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

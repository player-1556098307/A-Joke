class_name RPSModal
extends PanelContainer

signal gesture_selected(gesture: int)

enum Gesture { ROCK = 0, SCISSORS = 1, PAPER = 2 }

var _attacker_name: String = ""
var _defender_name: String = ""
var _buttons: Array[Button] = []
var _info_label: Label
var _btn_box: HBoxContainer

const C_BG = Color("#FFFDF5")
const C_GOLD = Color("#8B6514")
const C_GOLD_BRT = Color("#BA7517")
const C_TEXT = Color("#2C2C2A")
const C_TEXT_DIM = Color("#5F5E5A")

func _init() -> void:
	_setup_ui()

func _setup_ui() -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = C_BG
	style.border_color = C_GOLD * Color(1, 1, 1, 0.5)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 20.0
	style.content_margin_top = 16.0
	style.content_margin_right = 20.0
	style.content_margin_bottom = 16.0
	add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	add_child(vbox)

	var title = Label.new()
	title.text = "猜拳对决"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", C_GOLD_BRT)
	vbox.add_child(title)

	_info_label = Label.new()
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info_label.add_theme_font_size_override("font_size", 14)
	_info_label.add_theme_color_override("font_color", C_TEXT)
	vbox.add_child(_info_label)

	_btn_box = HBoxContainer.new()
	_btn_box.add_theme_constant_override("separation", 12)
	_btn_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(_btn_box)

	var gestures = [
		{"name": "石头", "gesture": Gesture.ROCK},
		{"name": "剪刀", "gesture": Gesture.SCISSORS},
		{"name": "布", "gesture": Gesture.PAPER},
	]

	for g in gestures:
		var btn = Button.new()
		btn.text = g["name"]
		btn.custom_minimum_size = Vector2(100, 50)
		btn.add_theme_font_size_override("font_size", 16)
		btn.add_theme_color_override("font_color", C_TEXT)
		btn.add_theme_color_override("font_hover_color", C_GOLD_BRT)

		var n_style = StyleBoxFlat.new()
		n_style.bg_color = Color("#F1EFE8")
		n_style.border_color = C_GOLD * Color(1, 1, 1, 0.4)
		n_style.set_border_width_all(1)
		n_style.set_corner_radius_all(8)
		btn.add_theme_stylebox_override("normal", n_style)

		var h_style = n_style.duplicate()
		h_style.bg_color = Color("#E6E2D4")
		h_style.border_color = C_GOLD
		btn.add_theme_stylebox_override("hover", h_style)

		btn.pressed.connect(_on_gesture_pressed.bind(g["gesture"]))
		_btn_box.add_child(btn)
		_buttons.append(btn)

func show_for(attacker_name: String, defender_name: String) -> void:
	_attacker_name = attacker_name
	_defender_name = defender_name
	_info_label.text = "%s   VS   %s" % [attacker_name, defender_name]
	for btn in _buttons:
		btn.disabled = false
	visible = true
	# Center the scale pivot so animation expands from center
	pivot_offset = size / 2.0
	modulate = Color(1, 1, 1, 0)
	scale = Vector2(0.6, 0.6)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "modulate", Color.WHITE, 0.25)
	tw.tween_property(self, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func hide_modal() -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "modulate", Color(1, 1, 1, 0), 0.12)
	tw.tween_property(self, "scale", Vector2(0.85, 0.85), 0.12).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): visible = false)

func set_waiting() -> void:
	for btn in _buttons:
		btn.disabled = true

func _on_gesture_pressed(gesture: int) -> void:
	for btn in _buttons:
		btn.disabled = true
	gesture_selected.emit(gesture)

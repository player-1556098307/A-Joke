class_name SkillSelectModal
extends PanelContainer

signal skill_confirmed(skill_index: int)
signal attack_cancelled()

var _skills: Array = []
var _current_energy: int = 0
var _rps_cost: int = 1
var _skill_buttons: Array[Button] = []
var _energy_label: Label
var _skill_list: VBoxContainer

const C_BG = Color("#FFFDF5")
const C_GOLD = Color("#8B6514")
const C_GOLD_BRT = Color("#BA7517")
const C_TEXT = Color("#2C2C2A")
const C_TEXT_DIM = Color("#5F5E5A")
const C_RED = Color("#E05555")

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
	vbox.add_theme_constant_override("separation", 10)
	add_child(vbox)

	var title = Label.new()
	title.text = "选择技能"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", C_GOLD_BRT)
	vbox.add_child(title)

	_energy_label = Label.new()
	_energy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_energy_label.add_theme_font_size_override("font_size", 13)
	_energy_label.add_theme_color_override("font_color", C_TEXT_DIM)
	vbox.add_child(_energy_label)

	_skill_list = VBoxContainer.new()
	_skill_list.add_theme_constant_override("separation", 6)
	vbox.add_child(_skill_list)

	var cancel_btn = Button.new()
	cancel_btn.text = "取消攻击"
	cancel_btn.custom_minimum_size = Vector2(0, 36)
	cancel_btn.add_theme_font_size_override("font_size", 13)
	cancel_btn.add_theme_color_override("font_color", C_RED)
	cancel_btn.add_theme_color_override("font_hover_color", Color.WHITE)

	var c_style = StyleBoxFlat.new()
	c_style.bg_color = Color(0, 0, 0, 0)
	c_style.border_color = C_RED * Color(1, 1, 1, 0.4)
	c_style.set_border_width_all(1)
	c_style.set_corner_radius_all(6)
	cancel_btn.add_theme_stylebox_override("normal", c_style)
	cancel_btn.pressed.connect(func(): attack_cancelled.emit())
	vbox.add_child(cancel_btn)

func show_for(skills: Array, current_energy: int) -> void:
	_skills = skills
	_current_energy = current_energy
	_skill_buttons.clear()

	for child in _skill_list.get_children():
		child.queue_free()

	# RPS attack fee was already paid; only skill cost matters now
	_energy_label.text = "当前气: %d （发起攻击已消耗1气）" % current_energy

	for i in range(skills.size()):
		var skill: SkillData = skills[i]
		var can_afford := current_energy >= skill.energy_cost

		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_skill_list.add_child(row)

		var name_label = Label.new()
		name_label.text = skill.skill_name
		name_label.custom_minimum_size = Vector2(120, 0)
		name_label.add_theme_font_size_override("font_size", 14)
		name_label.add_theme_color_override("font_color", C_TEXT if can_afford else C_TEXT_DIM)
		row.add_child(name_label)

		var desc_label = Label.new()
		desc_label.text = skill.description
		desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc_label.add_theme_font_size_override("font_size", 11)
		desc_label.add_theme_color_override("font_color", C_TEXT_DIM)
		desc_label.tooltip_text = skill.description
		row.add_child(desc_label)

		var cost_label = Label.new()
		cost_label.text = "气: %d" % skill.energy_cost
		cost_label.custom_minimum_size = Vector2(50, 0)
		cost_label.add_theme_font_size_override("font_size", 12)
		cost_label.add_theme_color_override("font_color", C_RED if not can_afford else C_GOLD)
		row.add_child(cost_label)

		var btn = Button.new()
		btn.text = "选择"
		btn.custom_minimum_size = Vector2(60, 32)
		btn.disabled = not can_afford
		btn.add_theme_font_size_override("font_size", 12)
		btn.add_theme_color_override("font_color", C_TEXT if can_afford else C_TEXT_DIM)

		var n_style = StyleBoxFlat.new()
		n_style.bg_color = Color("#F1EFE8") if can_afford else Color("#D3D1C7")
		n_style.border_color = C_GOLD * Color(1, 1, 1, 0.4 if can_afford else 0.15)
		n_style.set_border_width_all(1)
		n_style.set_corner_radius_all(6)
		btn.add_theme_stylebox_override("normal", n_style)

		var h_style = n_style.duplicate()
		h_style.bg_color = Color("#E6E2D4")
		h_style.border_color = C_GOLD
		btn.add_theme_stylebox_override("hover", h_style)

		var sidx = i
		btn.pressed.connect(func(): skill_confirmed.emit(sidx))
		row.add_child(btn)
		_skill_buttons.append(btn)

	# Re-center after content rebuild
	reset_size()
	await get_tree().process_frame
	var s := get_combined_minimum_size()
	offset_left = -s.x / 2.0
	offset_top = -s.y / 2.0
	offset_right = s.x / 2.0
	offset_bottom = s.y / 2.0
	visible = true

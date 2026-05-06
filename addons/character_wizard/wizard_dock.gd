@tool
extends Control

## 角色/技能可视化编辑器 —— 在 Godot 编辑器中直接填表创建角色与技能
## 用法：启用插件后，在右侧 Dock 中找到 "Character Wizard" 面板

var editor_interface: EditorInterface

const CHAR_DIR := "res://resources/characters/"
const SKILL_DIR := "res://resources/characters/skills/"

# ============================================================
# UI 根节点
# ============================================================
var tab_char_btn: Button
var tab_skill_btn: Button
var char_panel: Control
var skill_panel: Control

# ============================================================
# 角色面板 UI
# ============================================================
var char_list: ItemList
var char_name_edit: LineEdit
var char_hp_spin: SpinBox
var char_atk_cost_spin: SpinBox
var char_portrait_edit: LineEdit
var char_emoji_edit: LineEdit
var char_tags_edit: LineEdit
var char_skills_list: ItemList
var char_skills_dropdown: OptionButton
var char_save_btn: Button
var char_delete_btn: Button

# 角色面板状态
var char_paths: PackedStringArray = []
var current_char_path: String = ""
var char_skill_refs: Array = []        # SkillData 引用
var char_skill_names: PackedStringArray = []

# ============================================================
# 技能面板 UI
# ============================================================
var skill_list: ItemList
var skill_name_edit: LineEdit
var skill_desc_edit: TextEdit
var skill_cost_spin: SpinBox
var skill_min_range_spin: SpinBox
var skill_max_range_spin: SpinBox
var skill_effects_list: ItemList
var skill_save_btn: Button
var skill_delete_btn: Button

# 技能面板状态
var skill_paths: PackedStringArray = []
var current_skill_path: String = ""
var skill_effect_refs: Array = []      # SkillEffect 引用

# ============================================================
# 效果编辑弹窗 UI
# ============================================================
var effect_popup: ConfirmationDialog
var effect_type_opt: OptionButton
var effect_value_spin: SpinBox
var effect_target_opt: OptionButton
var effect_duration_spin: SpinBox
var effect_unlock_label: Label
var effect_unlock_dropdown: OptionButton
var effect_splash_spin: SpinBox
var editing_effect_index: int = -1

# 效果类型映射
const EFFECT_NAMES := ["直接伤害", "护盾", "麻痹", "改变距离", "治疗", "延迟伤害", "解锁技能", "影分身"]
const TARGET_NAMES := ["单一敌人", "所有敌人", "自身", "溅射敌人"]

# ============================================================
# 构建界面
# ============================================================
func setup(ei: EditorInterface) -> void:
	editor_interface = ei
	name = "角色/技能编辑器"

	# 确保整个面板填满 dock 区域
	set_anchors_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = Vector2(420, 350)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	print("[Character Wizard] 插件面板初始化成功 — 请在右侧面板查找「角色/技能编辑器」标签页")

	# ---- 标签栏 ----
	var tab_bar := HBoxContainer.new()
	root.add_child(tab_bar)

	tab_char_btn = Button.new()
	tab_char_btn.text = "角色编辑"
	tab_char_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_char_btn.pressed.connect(_show_char_panel)
	tab_bar.add_child(tab_char_btn)

	tab_skill_btn = Button.new()
	tab_skill_btn.text = "技能编辑"
	tab_skill_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_skill_btn.pressed.connect(_show_skill_panel)
	tab_bar.add_child(tab_skill_btn)

	# ---- 角色面板 ----
	char_panel = _build_char_panel()
	root.add_child(char_panel)

	# ---- 技能面板 ----
	skill_panel = _build_skill_panel()
	skill_panel.hide()
	root.add_child(skill_panel)

	# ---- 效果编辑弹窗 ----
	_build_effect_popup()
	root.add_child(effect_popup)

	_show_char_panel()
	_refresh_char_list()
	_refresh_skill_list()

# ============================================================
# 构建角色面板
# ============================================================
func _build_char_panel() -> Control:
	var panel := HSplitContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# -- 左侧列表 --
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(130, 0)
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(left)

	var lbl := Label.new()
	lbl.text = "角色列表"
	left.add_child(lbl)

	char_list = ItemList.new()
	char_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	char_list.item_selected.connect(_on_char_selected)
	char_list.item_activated.connect(_on_char_selected)
	left.add_child(char_list)

	var new_char_btn := Button.new()
	new_char_btn.text = "+ 新建角色"
	new_char_btn.pressed.connect(_on_new_char)
	left.add_child(new_char_btn)

	# -- 右侧表单 --
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(form)
	_add_separator_preset(form)  # top spacer to match scroll look

	char_name_edit = _add_line_field(form, "角色名称", "输入角色名称")
	char_hp_spin = _add_spin_field(form, "最大生命值", 1, 999, 10)
	char_atk_cost_spin = _add_spin_field(form, "普攻能量消耗", 0, 99, 1)

	# 头像
	var port_label := Label.new()
	port_label.text = "头像路径"
	form.add_child(port_label)
	var port_hbox := HBoxContainer.new()
	form.add_child(port_hbox)
	char_portrait_edit = LineEdit.new()
	char_portrait_edit.placeholder_text = "res://path/to/portrait.jpg"
	char_portrait_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	port_hbox.add_child(char_portrait_edit)
	var port_btn := Button.new()
	port_btn.text = "浏览..."
	port_btn.pressed.connect(_on_char_portrait_browse)
	port_hbox.add_child(port_btn)

	char_emoji_edit = _add_line_field(form, "头像 Emoji", "例如：🦊")

	# 标签
	var tags_label := Label.new()
	tags_label.text = "标签（逗号分隔，如：战士, 法师）"
	form.add_child(tags_label)
	char_tags_edit = LineEdit.new()
	char_tags_edit.placeholder_text = "战士, 法师, 坦克, 刺客"
	char_tags_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(char_tags_edit)

	# 技能管理
	var skills_label := Label.new()
	skills_label.text = "已装备技能"
	form.add_child(skills_label)

	char_skills_list = ItemList.new()
	char_skills_list.custom_minimum_size = Vector2(0, 80)
	char_skills_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_child(char_skills_list)

	var skill_ctl := HBoxContainer.new()
	form.add_child(skill_ctl)
	char_skills_dropdown = OptionButton.new()
	char_skills_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skill_ctl.add_child(char_skills_dropdown)
	var add_skill_btn := Button.new()
	add_skill_btn.text = "添加技能 →"
	add_skill_btn.pressed.connect(_on_add_skill_to_char)
	skill_ctl.add_child(add_skill_btn)
	var rm_skill_btn := Button.new()
	rm_skill_btn.text = "移除"
	rm_skill_btn.pressed.connect(_on_remove_skill_from_char)
	skill_ctl.add_child(rm_skill_btn)

	_add_separator_preset(form)

	# 操作按钮
	var actions := HBoxContainer.new()
	form.add_child(actions)
	char_save_btn = Button.new()
	char_save_btn.text = "保存角色"
	char_save_btn.pressed.connect(_on_save_char)
	actions.add_child(char_save_btn)
	char_delete_btn = Button.new()
	char_delete_btn.text = "删除角色"
	char_delete_btn.pressed.connect(_on_delete_char)
	actions.add_child(char_delete_btn)

	return panel

# ============================================================
# 构建技能面板
# ============================================================
func _build_skill_panel() -> Control:
	var panel := HSplitContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# -- 左侧列表 --
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(130, 0)
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(left)

	var lbl := Label.new()
	lbl.text = "技能列表"
	left.add_child(lbl)

	skill_list = ItemList.new()
	skill_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	skill_list.item_selected.connect(_on_skill_selected)
	skill_list.item_activated.connect(_on_skill_selected)
	left.add_child(skill_list)

	var new_btn := Button.new()
	new_btn.text = "+ 新建技能"
	new_btn.pressed.connect(_on_new_skill)
	left.add_child(new_btn)

	# -- 右侧表单 --
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(form)
	_add_separator_preset(form)

	skill_name_edit = _add_line_field(form, "技能名称", "输入技能名称")
	skill_cost_spin = _add_spin_field(form, "能量消耗", 0, 99, 1)
	skill_min_range_spin = _add_spin_field(form, "最小距离", 0, 99, 1)
	skill_max_range_spin = _add_spin_field(form, "最大距离（999=无限）", 0, 999, 2)

	# 描述
	var desc_label := Label.new()
	desc_label.text = "技能描述"
	form.add_child(desc_label)
	skill_desc_edit = TextEdit.new()
	skill_desc_edit.custom_minimum_size = Vector2(0, 50)
	skill_desc_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skill_desc_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	form.add_child(skill_desc_edit)

	# 效果列表
	var fx_label := Label.new()
	fx_label.text = "效果列表"
	form.add_child(fx_label)

	skill_effects_list = ItemList.new()
	skill_effects_list.custom_minimum_size = Vector2(0, 100)
	skill_effects_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skill_effects_list.item_activated.connect(_on_edit_effect)
	form.add_child(skill_effects_list)

	var fx_btns := HBoxContainer.new()
	form.add_child(fx_btns)
	var add_fx := Button.new()
	add_fx.text = "+ 添加效果"
	add_fx.pressed.connect(_on_add_effect)
	fx_btns.add_child(add_fx)
	var edit_fx := Button.new()
	edit_fx.text = "编辑效果"
	edit_fx.pressed.connect(_on_edit_effect)
	fx_btns.add_child(edit_fx)
	var rm_fx := Button.new()
	rm_fx.text = "移除效果"
	rm_fx.pressed.connect(_on_remove_effect)
	fx_btns.add_child(rm_fx)

	_add_separator_preset(form)

	var actions := HBoxContainer.new()
	form.add_child(actions)
	skill_save_btn = Button.new()
	skill_save_btn.text = "保存技能"
	skill_save_btn.pressed.connect(_on_save_skill)
	actions.add_child(skill_save_btn)
	skill_delete_btn = Button.new()
	skill_delete_btn.text = "删除技能"
	skill_delete_btn.pressed.connect(_on_delete_skill)
	actions.add_child(skill_delete_btn)

	return panel

# ============================================================
# 构建效果编辑弹窗
# ============================================================
func _build_effect_popup() -> void:
	effect_popup = ConfirmationDialog.new()
	effect_popup.title = "编辑技能效果"
	effect_popup.ok_button_text = "确定"
	effect_popup.cancel_button_text = "取消"
	effect_popup.confirmed.connect(_on_effect_popup_confirmed)

	var vbox := VBoxContainer.new()
	effect_popup.add_child(vbox)

	effect_type_opt = _add_option_field(vbox, "效果类型", EFFECT_NAMES)
	effect_value_spin = _add_spin_field(vbox, "数值", -999, 9999, 1)
	effect_target_opt = _add_option_field(vbox, "目标", TARGET_NAMES)
	effect_duration_spin = _add_spin_field(vbox, "持续回合", 0, 99, 1)
	effect_splash_spin = _add_spin_field(vbox, "溅射范围", 0, 9, 1)

	var unlbl := Label.new()
	unlbl.text = "解锁技能（仅【解锁技能】类型需要）"
	vbox.add_child(unlbl)
	effect_unlock_label = unlbl
	effect_unlock_dropdown = OptionButton.new()
	effect_unlock_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(effect_unlock_dropdown)

	# 效果类型或目标切换时，显示/隐藏相关字段
	effect_type_opt.item_selected.connect(_update_effect_field_visibility)
	effect_target_opt.item_selected.connect(_update_effect_field_visibility)

# ============================================================
# 表单辅助方法
# ============================================================
func _add_line_field(parent: Control, label: String, placeholder: String) -> LineEdit:
	var lbl := Label.new()
	lbl.text = label
	parent.add_child(lbl)
	var le := LineEdit.new()
	le.placeholder_text = placeholder
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(le)
	return le

func _add_spin_field(parent: Control, label: String, vmin: int, vmax: int, default: int) -> SpinBox:
	var lbl := Label.new()
	lbl.text = label
	parent.add_child(lbl)
	var sb := SpinBox.new()
	sb.min_value = vmin
	sb.max_value = vmax
	sb.value = default
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(sb)
	return sb

func _add_option_field(parent: Control, label: String, items: Array) -> OptionButton:
	var lbl := Label.new()
	lbl.text = label
	parent.add_child(lbl)
	var opt := OptionButton.new()
	for it in items:
		opt.add_item(it)
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(opt)
	return opt

func _add_separator_preset(parent: Control) -> void:
	var sep := HSeparator.new()
	parent.add_child(sep)

# ============================================================
# 标签页切换
# ============================================================
func _show_char_panel() -> void:
	char_panel.show()
	skill_panel.hide()

func _show_skill_panel() -> void:
	char_panel.hide()
	skill_panel.show()

# ============================================================
# 数据刷新
# ============================================================
func _refresh_char_list() -> void:
	char_list.clear()
	char_paths.clear()

	if not _dir_exists(CHAR_DIR):
		return

	var dir := DirAccess.open(CHAR_DIR)
	if dir == null:
		return
	for file in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var path := CHAR_DIR + file
		var res := load(path)
		if res is CharacterData:
			char_paths.append(path)
			char_list.add_item(res.character_name)

func _refresh_skill_list() -> void:
	skill_list.clear()
	skill_paths.clear()
	_ensure_dir(SKILL_DIR)

	var dir := DirAccess.open(SKILL_DIR)
	if dir == null:
		return
	for file in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var path := SKILL_DIR + file
		var res := load(path)
		if res is SkillData:
			skill_paths.append(path)
			skill_list.add_item(res.skill_name)

	_refresh_skill_dropdowns()

func _refresh_skill_dropdowns() -> void:
	# 角色面板的技能下拉
	char_skills_dropdown.clear()
	char_skills_dropdown.add_item("-- 选择技能 --")
	for i in skill_paths.size():
		var res := load(skill_paths[i]) as SkillData
		char_skills_dropdown.add_item(res.skill_name if res else skill_paths[i])

	# 效果弹窗的解锁技能下拉
	effect_unlock_dropdown.clear()
	effect_unlock_dropdown.add_item("（无）")
	for i in skill_paths.size():
		var res := load(skill_paths[i]) as SkillData
		effect_unlock_dropdown.add_item(res.skill_name if res else skill_paths[i])

func _refresh_char_skills_display() -> void:
	char_skills_list.clear()
	char_skill_names.clear()
	for sk in char_skill_refs:
		if sk is SkillData:
			var label: String = sk.skill_name
			if sk.resource_path.is_empty():
				label += " （内嵌）"
			char_skill_names.append(label)
			char_skills_list.add_item(label)

func _refresh_effects_list() -> void:
	skill_effects_list.clear()
	for fx in skill_effect_refs:
		skill_effects_list.add_item(_describe_effect(fx))

# ============================================================
# 角色事件处理
# ============================================================
func _on_char_selected(idx: int) -> void:
	if idx < 0 or idx >= char_paths.size():
		return
	current_char_path = char_paths[idx]
	var res := load(current_char_path) as CharacterData
	if res == null:
		return

	char_name_edit.text = res.character_name
	char_hp_spin.value = res.max_hp
	char_atk_cost_spin.value = res.basic_attack_cost
	char_portrait_edit.text = res.portrait.resource_path if res.portrait else ""
	char_emoji_edit.text = res.avatar_emoji
	char_tags_edit.text = ",".join(res.tags)

	char_skill_refs.clear()
	for sk in res.skills:
		if sk is SkillData:
			char_skill_refs.append(sk)
	_refresh_char_skills_display()
	_refresh_skill_dropdowns()

func _on_new_char() -> void:
	current_char_path = ""
	char_name_edit.text = ""
	char_hp_spin.value = 10
	char_atk_cost_spin.value = 1
	char_portrait_edit.text = ""
	char_emoji_edit.text = ""
	char_tags_edit.text = ""
	char_skill_refs.clear()
	_refresh_char_skills_display()

func _on_save_char() -> void:
	var name := char_name_edit.text.strip_edges()
	if name.is_empty():
		_alert("请输入角色名称")
		return

	var ch: CharacterData
	if not current_char_path.is_empty():
		ch = load(current_char_path) as CharacterData
		if ch == null:
			ch = CharacterData.new()
	else:
		ch = CharacterData.new()

	ch.character_name = name
	ch.max_hp = int(char_hp_spin.value)
	ch.basic_attack_cost = int(char_atk_cost_spin.value)

	var ptext := char_portrait_edit.text.strip_edges()
	if not ptext.is_empty() and ResourceLoader.exists(ptext):
		ch.portrait = load(ptext)
	else:
		ch.portrait = null

	ch.avatar_emoji = char_emoji_edit.text.strip_edges()

	var tag_text := char_tags_edit.text.strip_edges()
	if tag_text.is_empty():
		ch.tags = []
	else:
		var tlist: Array[String] = []
		for t in tag_text.split(","):
			var stripped := t.strip_edges()
			if not stripped.is_empty():
				tlist.append(stripped)
		ch.tags = tlist

	ch.skills = []
	for sk in char_skill_refs:
		if sk is SkillData:
			ch.skills.append(sk)

	# 确定保存路径
	var save_path: String
	if current_char_path.is_empty():
		var safe_name := _to_filename(name)
		save_path = CHAR_DIR + safe_name + ".tres"
	else:
		save_path = current_char_path

	_ensure_dir(CHAR_DIR)
	var err := ResourceSaver.save(ch, save_path)
	if err != OK:
		_alert("保存失败，错误码: " + str(err))
		return

	current_char_path = save_path
	_refresh_char_list()
	# 选中刚保存的项
	for i in char_paths.size():
		if char_paths[i] == save_path:
			char_list.select(i)
			break
	_alert("角色「%s」已保存" % name)

func _on_delete_char() -> void:
	if current_char_path.is_empty():
		_alert("请先在左侧列表选择一个角色")
		return
	var name := char_name_edit.text
	var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(current_char_path))
	if err != OK:
		_alert("删除失败，请检查文件是否被占用")
		return
	current_char_path = ""
	_on_new_char()
	_refresh_char_list()
	_alert("角色「%s」已删除" % name)

func _on_add_skill_to_char() -> void:
	var idx := char_skills_dropdown.selected
	if idx <= 0 or idx - 1 >= skill_paths.size():
		return  # 未选择有效技能
	var sk := load(skill_paths[idx - 1]) as SkillData
	if sk == null:
		return
	# 避免重复添加
	for existing in char_skill_refs:
		if existing is SkillData and existing.skill_name == sk.skill_name:
			_alert("该技能已添加")
			return
	char_skill_refs.append(sk)
	_refresh_char_skills_display()

func _on_remove_skill_from_char() -> void:
	var sel := char_skills_list.get_selected_items()
	if sel.is_empty():
		return
	var idx := sel[0]
	if idx >= 0 and idx < char_skill_refs.size():
		char_skill_refs.remove_at(idx)
		_refresh_char_skills_display()

func _on_char_portrait_browse() -> void:
	var fd := EditorFileDialog.new()
	fd.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	fd.access = EditorFileDialog.ACCESS_RESOURCES
	fd.add_filter("*.png,*.jpg,*.jpeg,*.webp", "图片文件")
	fd.file_selected.connect(func(path: String):
		char_portrait_edit.text = path
	)
	editor_interface.get_base_control().add_child(fd)
	fd.popup_centered_ratio(0.6)

# ============================================================
# 技能事件处理
# ============================================================
func _on_skill_selected(idx: int) -> void:
	if idx < 0 or idx >= skill_paths.size():
		return
	current_skill_path = skill_paths[idx]
	var res := load(current_skill_path) as SkillData
	if res == null:
		return

	skill_name_edit.text = res.skill_name
	skill_desc_edit.text = res.description
	skill_cost_spin.value = res.energy_cost
	skill_min_range_spin.value = res.min_range
	skill_max_range_spin.value = res.max_range

	skill_effect_refs.clear()
	for fx in res.effects:
		if fx is SkillEffect:
			skill_effect_refs.append(fx)
	_refresh_effects_list()

func _on_new_skill() -> void:
	current_skill_path = ""
	skill_name_edit.text = ""
	skill_desc_edit.text = ""
	skill_cost_spin.value = 1
	skill_min_range_spin.value = 1
	skill_max_range_spin.value = 1
	skill_effect_refs.clear()
	_refresh_effects_list()

func _on_save_skill() -> void:
	var name := skill_name_edit.text.strip_edges()
	if name.is_empty():
		_alert("请输入技能名称")
		return

	var sk: SkillData
	if not current_skill_path.is_empty():
		sk = load(current_skill_path) as SkillData
		if sk == null:
			sk = SkillData.new()
	else:
		sk = SkillData.new()

	sk.skill_name = name
	sk.description = skill_desc_edit.text
	sk.energy_cost = int(skill_cost_spin.value)
	sk.min_range = int(skill_min_range_spin.value)
	sk.max_range = int(skill_max_range_spin.value)

	sk.effects = []
	for fx in skill_effect_refs:
		if fx is SkillEffect:
			sk.effects.append(fx)

	var save_path: String
	if current_skill_path.is_empty():
		var safe_name := _to_filename(name)
		save_path = SKILL_DIR + safe_name + ".tres"
	else:
		save_path = current_skill_path

	_ensure_dir(SKILL_DIR)
	var err := ResourceSaver.save(sk, save_path)
	if err != OK:
		_alert("保存失败，错误码: " + str(err))
		return

	current_skill_path = save_path
	_refresh_skill_list()
	for i in skill_paths.size():
		if skill_paths[i] == save_path:
			skill_list.select(i)
			break
	_alert("技能「%s」已保存" % name)

func _on_delete_skill() -> void:
	if current_skill_path.is_empty():
		_alert("请先在左侧列表选择一个技能")
		return
	var name := skill_name_edit.text
	var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(current_skill_path))
	if err != OK:
		_alert("删除失败")
		return
	current_skill_path = ""
	_on_new_skill()
	_refresh_skill_list()
	_alert("技能「%s」已删除" % name)

# ============================================================
# 效果管理
# ============================================================
func _on_add_effect() -> void:
	editing_effect_index = -1
	_reset_effect_popup()
	effect_popup.popup_centered_ratio(0.5)

func _on_edit_effect(idx: int = -1) -> void:
	if idx < 0:
		var sel := skill_effects_list.get_selected_items()
		if sel.is_empty():
			_alert("请先选择要编辑的效果")
			return
		idx = sel[0]
	if idx < 0 or idx >= skill_effect_refs.size():
		return
	editing_effect_index = idx
	var fx := skill_effect_refs[idx] as SkillEffect
	if fx == null:
		return

	effect_type_opt.select(fx.effect_type)
	effect_value_spin.value = fx.value
	effect_target_opt.select(fx.target)
	effect_duration_spin.value = fx.duration
	effect_splash_spin.value = fx.splash_range

	if fx.unlock_skill is SkillData:
		for i in skill_paths.size():
			var s := load(skill_paths[i]) as SkillData
			if s and s.skill_name == fx.unlock_skill.skill_name:
				effect_unlock_dropdown.select(i + 1)
				break

	_update_effect_field_visibility(fx.effect_type)
	effect_popup.popup_centered_ratio(0.5)

func _on_remove_effect() -> void:
	var sel := skill_effects_list.get_selected_items()
	if sel.is_empty():
		return
	var idx := sel[0]
	if idx >= 0 and idx < skill_effect_refs.size():
		skill_effect_refs.remove_at(idx)
		_refresh_effects_list()

func _reset_effect_popup() -> void:
	effect_type_opt.select(0)
	effect_value_spin.value = 1
	effect_target_opt.select(0)
	effect_duration_spin.value = 1
	effect_splash_spin.value = 1
	effect_unlock_dropdown.select(0)
	_update_effect_field_visibility(0)

func _update_effect_field_visibility(_idx: int = -1) -> void:
	var etype := effect_type_opt.selected
	var is_delayed := (etype == SkillEffect.EffectType.DELAYED_DAMAGE)
	var is_unlock := (etype == SkillEffect.EffectType.UNLOCK_SKILL)

	effect_duration_spin.editable = is_delayed
	effect_unlock_label.visible = is_unlock
	effect_unlock_dropdown.visible = is_unlock
	effect_splash_spin.editable = (effect_target_opt.selected == SkillEffect.EffectTarget.ENEMY_SPLASH)

func _on_effect_popup_confirmed() -> void:
	var fx := SkillEffect.new()
	fx.effect_type = effect_type_opt.selected
	fx.value = int(effect_value_spin.value)
	fx.target = effect_target_opt.selected
	fx.duration = int(effect_duration_spin.value)
	fx.splash_range = int(effect_splash_spin.value)

	if fx.effect_type == SkillEffect.EffectType.UNLOCK_SKILL:
		var unlock_idx := effect_unlock_dropdown.selected
		if unlock_idx > 0 and unlock_idx - 1 < skill_paths.size():
			fx.unlock_skill = load(skill_paths[unlock_idx - 1]) as SkillData
		else:
			fx.unlock_skill = null
	else:
		fx.unlock_skill = null

	if editing_effect_index >= 0 and editing_effect_index < skill_effect_refs.size():
		skill_effect_refs[editing_effect_index] = fx
	else:
		skill_effect_refs.append(fx)
	_refresh_effects_list()

# ============================================================
# 辅助方法
# ============================================================
func _describe_effect(fx: Resource) -> String:
	if not fx is SkillEffect:
		return "（无效效果）"
	var f := fx as SkillEffect
	var parts: Array[String] = []
	parts.append(EFFECT_NAMES[f.effect_type] if f.effect_type < EFFECT_NAMES.size() else "???")
	parts.append("数值:" + str(f.value))
	parts.append(TARGET_NAMES[f.target] if f.target < TARGET_NAMES.size() else "目标???")
	if f.effect_type == SkillEffect.EffectType.DELAYED_DAMAGE:
		parts.append("延迟:" + str(f.duration) + "回合")
	if f.effect_type == SkillEffect.EffectType.UNLOCK_SKILL and f.unlock_skill:
		parts.append("解锁:" + f.unlock_skill.skill_name)
	if f.target == SkillEffect.EffectTarget.ENEMY_SPLASH:
		parts.append("溅射:" + str(f.splash_range))
	return " | ".join(parts)

func _dir_exists(path: String) -> bool:
	return DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path))

func _ensure_dir(path: String) -> void:
	var abs_path := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(abs_path):
		DirAccess.make_dir_recursive_absolute(abs_path)

func _to_filename(name: String) -> String:
	# 简单清理，确保文件名合法
	var result := name.replace("/", "_").replace("\\", "_").replace(":", "_")
	result = result.replace("*", "_").replace("?", "_").replace("\"", "_")
	result = result.replace("<", "_").replace(">", "_").replace("|", "_")
	return result

func _alert(msg: String) -> void:
	var dlg := AcceptDialog.new()
	dlg.dialog_text = msg
	dlg.title = "提示"
	editor_interface.get_base_control().add_child(dlg)
	dlg.popup_centered()

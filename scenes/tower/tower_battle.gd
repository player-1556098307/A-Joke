## TowerBattle — 慈悲尖塔战斗场景
## 复用 GameUI 对局界面 + TowerManager 层推进
## 支持层间过渡动画、进场/退场对话、通关/失败结算、战斗中剧情触发
extends Control

@onready var _ui: Control = $GameUI
@onready var tower_mgr: TowerManager = $TowerManager

var _floor_label: Label
var _transition: TowerFloorTransition
var _dialogue_box: DialogueBox
var _portrait: TextureRect
var _glow: ColorRect
var _glow_base_a: float = 0.0  ## 光晕基础透明度
var _glow_timer: float = 0.0
var _phase: String = "idle"  ## "idle", "transition", "entry_dialogue", "battle", "exit_dialogue", "reward", "result"
var _reward_ui: TowerRewardUI
var _buff_btn: Button
var _buff_panel: Panel
var _buff_panel_box: VBoxContainer  ## 面板内布局容器（Panel 非容器，须用 VBox 排布子控件）
var _buff_panel_visible: bool = false

## 每角色独立祝福选择：当前选祝福的角色索引（0=队长, 1=队友1, 2=队友2）
var _reward_player_index: int = 0
## 本层队伍中 team_id=1 的玩家数量
var _party_size: int = 1

## 测试快速模式：跳过所有过渡动画和对话，直接启动战斗/推进层
var fast_mode: bool = false

## 战斗中剧情触发标记
var _enemy_hp50_triggered: bool = false    ## 敌人HP首次低于50%
var _player_eliminated_triggered: bool = false  ## 玩家队有人被淘汰
var _zeus_phase_transition_triggered: bool = false  ## 宙斯阶段转换对话
var _zeus_transition_prev_phase: String = "battle"  ## 转换前的phase，对话结束后恢复
var _enemy_name: String = ""
## 二阶段BGM播放器
var _bgm_player: AudioStreamPlayer

func _ready() -> void:
	# 根节点全屏锚定（Control 继承，子 Control 才能正确布局）
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 顶层提示层（独立全屏 Control，mouse 穿透，覆盖在 GameUI 之上）
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	_floor_label = Label.new()
	_floor_label.text = "慈悲尖塔"
	_floor_label.add_theme_font_size_override("font_size", 14)
	_floor_label.add_theme_color_override("font_color", Color("#FAC775"))
	_floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_floor_label.anchor_left = 0.0
	_floor_label.anchor_top = 0.0
	_floor_label.anchor_right = 1.0
	_floor_label.offset_top = 6.0
	_floor_label.offset_bottom = 30.0
	_floor_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(_floor_label)

	# 层间过渡动画
	_transition = TowerFloorTransition.new()
	_transition.transition_finished.connect(_on_transition_finished)
	add_child(_transition)

	# 梅塔特隆立绘（全屏背景，半透明，退场/战斗中叙事对话时淡入淡出）
	_portrait = TextureRect.new()
	var portrait_tex: Texture2D = load("res://resources/portraits/metatron_gate.png")
	if portrait_tex:
		_portrait.texture = portrait_tex
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.self_modulate = Color(1, 1, 1, 0)
	_portrait.z_index = 0
	_portrait.visible = false
	add_child(_portrait)

	# 金色光晕（全屏背景，脉冲呼吸）
	_glow = ColorRect.new()
	_glow.color = Color("#FAC775")
	_glow.self_modulate = Color(1, 1, 1, 0)
	_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.z_index = 0
	_glow.visible = false
	add_child(_glow)

	# 退场/战斗中叙事 DialogueBox
	_dialogue_box = DialogueBox.new()
	_dialogue_box.dialogue_finished.connect(_on_dialogue_generic_finished)
	_dialogue_box.line_shown.connect(_on_line_shown)
	_dialogue_box.visible = false
	_dialogue_box.z_index = 2
	add_child(_dialogue_box)

	# 层间奖励选择 UI（红黑风格）
	_reward_ui = TowerRewardUI.new()
	_reward_ui.reward_selected.connect(_on_reward_selected)
	_reward_ui.z_index = 3
	_reward_ui.visible = false
	add_child(_reward_ui)

	# 查看已获取 buff 的小按钮（右下角）
	_buff_btn = Button.new()
	_buff_btn.text = "✦ 祝福"
	_buff_btn.add_theme_font_size_override("font_size", 13)
	_buff_btn.add_theme_color_override("font_color", Color("#FAC775"))
	_buff_btn.add_theme_color_override("font_hover_color", Color("#FFD080"))
	_buff_btn.add_theme_stylebox_override("normal", _make_buff_btn_style(Color("#1A0A0A"), Color("#8B2020")))
	_buff_btn.add_theme_stylebox_override("hover", _make_buff_btn_style(Color("#2A1010"), Color("#FF4040")))
	_buff_btn.add_theme_stylebox_override("pressed", _make_buff_btn_style(Color("#0D0A08"), Color("#8B2020")))
	_buff_btn.anchor_left = 1.0
	_buff_btn.anchor_right = 1.0
	_buff_btn.anchor_top = 1.0
	_buff_btn.anchor_bottom = 1.0
	_buff_btn.offset_left = -100
	_buff_btn.offset_right = -10
	_buff_btn.offset_top = -40
	_buff_btn.offset_bottom = -10
	_buff_btn.z_index = 4
	_buff_btn.visible = false
	_buff_btn.pressed.connect(_toggle_buff_panel)
	add_child(_buff_btn)

	# buff 浮窗面板（默认隐藏，点击按钮切换）
	_buff_panel = _build_buff_panel()
	add_child(_buff_panel)

	# 连接 TowerManager 信号
	tower_mgr.floor_changed.connect(_on_floor_changed)
	tower_mgr.floor_cleared.connect(_on_floor_cleared)
	tower_mgr.tower_victory.connect(_on_tower_victory)
	tower_mgr.tower_defeat.connect(_on_tower_defeat)
	# 设为手动推进：由过渡动画+对话控制层间流程
	tower_mgr.set_auto_advance(false)

	# 连接 GameManager 战斗中信号（剧情触发）
	GameManager.player_eliminated.connect(_on_player_eliminated)
	GameManager.round_resolved.connect(_on_round_resolved)
	# 宙斯一阶段→二阶段转换对话
	GameManager.zeus_phase_transition_required.connect(_on_zeus_phase_transition)

	# 二阶段BGM播放器（默认静音，仅在阶段转换时播放）
	_bgm_player = AudioStreamPlayer.new()
	var bgm_audio: AudioStream = load("res://assets/audio/bgm/zeus_phase2_bgm.mp3")
	if bgm_audio:
		_bgm_player.stream = bgm_audio
	_bgm_player.volume_db = -6.0
	add_child(_bgm_player)

	# 应用塔模式暗色主题
	_ui.apply_tower_theme()

	# 启动第1层
	if fast_mode:
		_begin_floor_battle(1)
	else:
		_start_first_floor()

# ============================================================
#  层启动
# ============================================================

## 正常模式：第1层过渡动画启动
func _start_first_floor() -> void:
	var entry_dlg: Dictionary = _get_floor_entry_dialogue(1)
	_transition.start(1, "小怪群", entry_dlg)
	_phase = "transition"

## 获取指定层的进场对话（不依赖 tower_mgr 已启动）
func _get_floor_entry_dialogue(floor_num: int) -> Dictionary:
	var data := TowerDialogueData.new()
	return data.get_floor_entry(floor_num)

## 过渡动画完成 → 开始当前层战斗
func _on_transition_finished() -> void:
	if _phase != "transition":
		return
	_begin_floor_battle(tower_mgr.get_current_floor() if tower_mgr.is_running() else 1)

## 开始指定层的战斗（从过渡动画或 fast_mode 调用）
## floor_num 仅用于标签显示，实际推进由 TowerManager 内部管理
func _begin_floor_battle(_floor_num: int) -> void:
	_phase = "battle"
	_enemy_hp50_triggered = false
	_player_eliminated_triggered = false
	if not tower_mgr.is_running():
		var party: Array = SceneManager.last_tower_config.get("players", [])
		tower_mgr.start_tower(party)
	else:
		tower_mgr.start_next_floor()
	_inject_tower_buffs()
	_ui.setup_players(GameManager.get_alive_players())
	_enemy_name = tower_mgr.get_current_enemy_name()
	_floor_label.text = "慈悲尖塔 第%d层 — %s" % [tower_mgr.get_current_floor(), _enemy_name]
	# 战斗阶段显示 buff 查看按钮（有祝福时才显示）
	_update_buff_btn_visibility()

## 注入慈悲尖塔层间奖励 buff 到玩家队（每角色独立注入）
func _inject_tower_buffs() -> void:
	# 兼容旧结构：若存在全局 tower_buffs 则迁移到 per_player
	var old_buffs: Array = SceneManager.last_tower_config.get("tower_buffs", [])
	if not old_buffs.is_empty():
		var per_player: Array = SceneManager.last_tower_config.get("tower_buffs_per_player", [])
		if per_player.is_empty():
			# 迁移：旧 buff 全部给队长（索引0）
			per_player = [[]]
			per_player[0] = old_buffs.duplicate(true)
			SceneManager.last_tower_config["tower_buffs_per_player"] = per_player
		SceneManager.last_tower_config.erase("tower_buffs")
	# 按队伍顺序注入各自 buff
	var per_player_buffs: Array = SceneManager.last_tower_config.get("tower_buffs_per_player", [])
	var team_idx: int = 0
	for p in GameManager.get_alive_players():
		if p.team_id != 1:
			continue
		var buffs: Array = []
		if team_idx < per_player_buffs.size() and per_player_buffs[team_idx] is Array:
			buffs = per_player_buffs[team_idx]
		for b in buffs:
			_apply_buff(p, b)
		team_idx += 1
	# 刷新 UI 显示（护盾/分身等可视化字段）
	_ui.setup_players(GameManager.get_alive_players())
	# 后期小怪攻击力强化（第3-4轮 +1/+2 普攻增伤）
	_inject_enemy_attack_bonus()

## 应用单个 buff 到 PlayerState
func _apply_buff(p: PlayerState, buff: Dictionary) -> void:
	match buff.get("id", ""):
		"blade_power", "blade_power_2":
			p.damage_bonus_basic += buff.get("value", 1.0)
		"charge_bonus":
			p.charge_bonus += buff.get("value", 1)
		"shield_wall":
			p.damage_reduction += buff.get("value", 1.0)
		"regen", "regen_2":
			p.regen_per_round += buff.get("value", 1.0)
		"clone":
			p.clone_count += buff.get("value", 1)
		"swift", "swift_2":
			p.add_energy(buff.get("value", 2))
		"protect", "protect_2":
			p.shield += buff.get("value", 2)
		"vitality", "vitality_2":
			var max_bonus: float = buff.get("value", 3.0)
			p.max_hp_bonus += max_bonus
			p.hp += max_bonus  # 同步补血
		"lifesteal":
			p.lifesteal_per_hit += buff.get("value", 1.0)
		"soul_slash":
			# 一次性技能祝福：将斩魂技能副本加入 unlocked_skills（防重复）
			_add_limited_skill_buff(p, "斩魂", "res://resources/characters/skills/斩魂.tres")
		"spring":
			# 一次性技能祝福：将回春技能副本加入 unlocked_skills（防重复）
			_add_limited_skill_buff(p, "回春", "res://resources/characters/skills/回春.tres")

## 后期小怪攻击力强化：第3-4轮小怪普攻增伤
func _inject_enemy_attack_bonus() -> void:
	var floor_num := tower_mgr.get_current_floor()
	var atk_bonus := tower_mgr.get_small_enemy_attack_bonus(floor_num)
	if atk_bonus <= 0:
		return
	for p in GameManager.get_alive_players():
		if p.team_id != 2:
			continue
		p.damage_bonus_basic += atk_bonus

## 一次性技能祝福：将限定技加入玩家 unlocked_skills（防重复，每层注入幂等）
func _add_limited_skill_buff(p: PlayerState, skill_name: String, skill_path: String) -> void:
	# 检查是否已存在同名技能（避免每层重复注入）
	for existing in p.unlocked_skills:
		if existing != null and existing.skill_name == skill_name:
			return
	var skill_res := load(skill_path) as SkillData
	if skill_res == null:
		push_warning("[塔] 一次性技能祝福资源加载失败：%s" % skill_path)
		return
	# 创建副本（避免修改原始资源）
	var copy := SkillData.new()
	copy.skill_name = skill_res.skill_name
	copy.description = skill_res.description
	copy.energy_cost = skill_res.energy_cost
	copy.min_range = skill_res.min_range
	copy.max_range = skill_res.max_range
	copy.is_limited = skill_res.is_limited
	# 复制效果列表
	var effects_copy: Array[SkillEffect] = []
	for e in skill_res.effects:
		var ec := SkillEffect.new()
		ec.effect_type = e.effect_type
		ec.value = e.value
		ec.target = e.target
		ec.duration = e.duration
		ec.bonus_if_paralyzed = e.bonus_if_paralyzed
		effects_copy.append(ec)
	copy.effects = effects_copy
	p.unlocked_skills.append(copy)

# ============================================================
#  Buff 查看浮窗
# ============================================================

## buff 按钮样式辅助
func _make_buff_btn_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_width_left = 1
	s.border_width_right = 1
	s.border_width_top = 1
	s.border_width_bottom = 1
	s.border_color = border
	s.corner_radius_top_left = 6
	s.corner_radius_top_right = 6
	s.corner_radius_bottom_left = 6
	s.corner_radius_bottom_right = 6
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s

## 构建 buff 浮窗面板（默认隐藏）
func _build_buff_panel() -> Panel:
	var panel := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#0D0A08", 0.95)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color("#8B2020")
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	# 浮窗位置：左侧战斗日志旁（避开右侧手势选择区 774~956）
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = 204.0
	panel.offset_right = 204.0 + 250.0
	panel.offset_top = 200.0
	panel.offset_bottom = 200.0 + 270.0
	panel.z_index = 5
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.visible = false
	# 内部 ScrollContainer：祝福条目过多时可滚动
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	panel.add_child(scroll)
	# VBox 容器：负责标题/分隔线/buff条目/提示的垂直布局（放在 ScrollContainer 内）
	_buff_panel_box = VBoxContainer.new()
	_buff_panel_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_buff_panel_box.add_theme_constant_override("separation", 6)
	_buff_panel_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(_buff_panel_box)
	return panel

## 切换 buff 浮窗显示/隐藏
func _toggle_buff_panel() -> void:
	_buff_panel_visible = not _buff_panel_visible
	if _buff_panel_visible:
		_refresh_buff_panel()
		_buff_panel.visible = true
	else:
		_buff_panel.visible = false

## 刷新浮窗内容：清空并重建已获取 buff 列表（每角色独立显示）
func _refresh_buff_panel() -> void:
	# 清空旧内容：立即移出并释放，避免 queue_free 延迟导致新旧节点短暂共存
	var old_children := _buff_panel_box.get_children()
	for child in old_children:
		_buff_panel_box.remove_child(child)
		child.queue_free()

	var per_player_buffs: Array = SceneManager.last_tower_config.get("tower_buffs_per_player", [])
	# 兼容旧结构
	var old_buffs: Array = SceneManager.last_tower_config.get("tower_buffs", [])
	if not old_buffs.is_empty() and per_player_buffs.is_empty():
		per_player_buffs = [old_buffs]

	# 标题
	var title := Label.new()
	title.text = "已获祝福"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color("#FAC775"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buff_panel_box.add_child(title)

	# 分隔线
	var sep := ColorRect.new()
	sep.color = Color("#8B2020")
	sep.custom_minimum_size = Vector2(0, 1)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buff_panel_box.add_child(sep)

	# 按角色分组显示
	var has_any_buff: bool = false
	var party: Array = SceneManager.last_tower_config.get("players", [])
	for i in range(party.size()):
		var entry = party[i]
		if entry is Dictionary and not entry.has("character"):
			continue
		var char_data: CharacterData = entry["character"] if entry is Dictionary else null
		if char_data == null:
			continue
		var buffs: Array = []
		if i < per_player_buffs.size() and per_player_buffs[i] is Array:
			buffs = per_player_buffs[i]
		if buffs.is_empty():
			continue
		has_any_buff = true
		# 角色名标题
		var char_label := Label.new()
		char_label.text = "▸ %s" % char_data.character_name
		char_label.add_theme_font_size_override("font_size", 13)
		char_label.add_theme_color_override("font_color", Color("#FAC775"))
		char_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_buff_panel_box.add_child(char_label)
		# 逐条显示该角色的 buff
		for b in buffs:
			var reward: Dictionary = _find_reward_by_id(b.get("id", ""))
			if reward.is_empty():
				continue
			var row := HBoxContainer.new()
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_theme_constant_override("separation", 6)
			row.offset_left = 12
			# 图标
			var icon := Label.new()
			icon.text = reward.get("icon", "?")
			icon.add_theme_font_size_override("font_size", 16)
			icon.add_theme_color_override("font_color", reward.get("color", Color("#FAC775")))
			icon.custom_minimum_size = Vector2(24, 0)
			icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(icon)
			# 名称
			var name := Label.new()
			name.text = reward.get("name", "")
			name.add_theme_font_size_override("font_size", 13)
			name.add_theme_color_override("font_color", Color("#E8E2D5"))
			name.custom_minimum_size = Vector2(70, 0)
			name.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(name)
			# 效果
			var desc := Label.new()
			desc.text = reward.get("desc", "")
			desc.add_theme_font_size_override("font_size", 12)
			desc.add_theme_color_override("font_color", Color("#9A9182"))
			desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(desc)
			_buff_panel_box.add_child(row)
	if not has_any_buff:
		var empty_label := Label.new()
		empty_label.text = "尚未获得祝福"
		empty_label.add_theme_font_size_override("font_size", 13)
		empty_label.add_theme_color_override("font_color", Color("#9A9182"))
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_buff_panel_box.add_child(empty_label)

	# 关闭提示
	var hint := Label.new()
	hint.text = "再次点击关闭"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color("#605040"))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buff_panel_box.add_child(hint)

## 根据 buff id 从奖励池查找完整信息（图标/名称/效果）
func _find_reward_by_id(buff_id: String) -> Dictionary:
	for reward in TowerRewardUI.REWARD_POOL:
		if reward.get("id", "") == buff_id:
			return reward
	return {}

## 隐藏 buff 面板（奖励选择/对话/过渡等阶段时调用）
func _hide_buff_panel() -> void:
	_buff_panel_visible = false
	_buff_panel.visible = false

## 更新 buff 按钮可见性（有已获取祝福且在战斗阶段时显示）
func _update_buff_btn_visibility() -> void:
	var per_player: Array = SceneManager.last_tower_config.get("tower_buffs_per_player", [])
	var old_buffs: Array = SceneManager.last_tower_config.get("tower_buffs", [])
	var has_buffs: bool = not per_player.is_empty() or not old_buffs.is_empty()
	_buff_btn.visible = _phase == "battle" and has_buffs
	if not _buff_btn.visible:
		_hide_buff_panel()

# ============================================================
#  层间推进
# ============================================================

func _on_floor_changed(floor_num: int, enemy_name: String) -> void:
	_floor_label.text = "慈悲尖塔 第%d层 — %s" % [floor_num, enemy_name]
	_ui.setup_players(GameManager.get_alive_players())

## 层胜利：显示退场对话 → 奖励选择 → 推进下一层
func _on_floor_cleared(floor_num: int, enemy_name: String) -> void:
	if fast_mode:
		_show_reward_selection()
		return
	_hide_buff_panel()
	_buff_btn.visible = false
	_phase = "exit_dialogue"
	var exit_dlg: Dictionary = tower_mgr.get_exit_dialogue()
	if exit_dlg.is_empty():
		_show_reward_selection()
	else:
		_dialogue_box.visible = true
		_dialogue_box.start(exit_dlg)

## 退场对话结束 → 弹出奖励选择（或直接推进）
func _on_dialogue_generic_finished() -> void:
	_dialogue_box.visible = false
	_fade_portrait(false)
	if _phase == "exit_dialogue":
		_show_reward_selection()
	elif _phase == "zeus_transition":
		_on_zeus_transition_dialogue_finished()
	# 战斗中的叙事对话不改变 phase，只是弹出后消失

## 弹出层间奖励选择界面（每角色独立选祝福）
## 精英层（第4/8/12层）通关后可随机到高级祝福
func _show_reward_selection() -> void:
	_phase = "reward"
	_hide_buff_panel()
	_buff_btn.visible = false
	# 队伍人数从配置获取（不受某层角色死亡影响）
	var party: Array = SceneManager.last_tower_config.get("players", [])
	_party_size = party.size()
	if _party_size == 0:
		_party_size = 1
	_reward_player_index = 0
	_show_reward_for_current_player()

## 为当前角色弹出祝福选择（人类手动选 / AI自动选）
func _show_reward_for_current_player() -> void:
	if fast_mode:
		# fast_mode：自动选择第一个奖励（测试用）
		var pool := TowerRewardUI.REWARD_POOL
		var buff: Dictionary = pool[0]
		_on_reward_selected(buff)
		return
	# 判断当前角色是否为AI
	var party: Array = SceneManager.last_tower_config.get("players", [])
	var is_ai: bool = false
	if _reward_player_index < party.size():
		var entry = party[_reward_player_index]
		if entry is Dictionary:
			is_ai = not entry.get("is_human", true)
	if is_ai:
		# AI队友自动选祝福：从可选池中随机选一个
		var cleared_floor: int = tower_mgr.get_current_floor()
		var is_elite_floor: bool = cleared_floor > 0 and cleared_floor < TowerManager.MAX_FLOORS and cleared_floor % 4 == 0
		var obtained_ids: Array = _get_all_obtained_ids()
		var choices: Array[Dictionary] = _reward_ui._pick_random_rewards(3, is_elite_floor, obtained_ids)
		if choices.is_empty():
			_on_reward_selected({})
			return
		choices.shuffle()
		var ai_buff: Dictionary = choices[0]
		# AI选择日志
		var ai_name: String = "AI队友"
		if _reward_player_index < party.size():
			var e = party[_reward_player_index]
			if e is Dictionary and e.has("character"):
				ai_name = (e["character"] as CharacterData).character_name
		print("[塔] %s（AI）自动选择祝福：%s" % [ai_name, ai_buff.get("name", "?")])
		_on_reward_selected(ai_buff)
		return
	# 人类玩家：弹窗手动选
	# 更新副标题显示当前选祝福的角色名
	var char_name: String = "角色%d" % (_reward_player_index + 1)
	if _reward_player_index < party.size():
		var entry = party[_reward_player_index]
		if entry is Dictionary and entry.has("character"):
			char_name = (entry["character"] as CharacterData).character_name
	_reward_ui.set_subtitle("%s 选择祝福（%d/%d）" % [char_name, _reward_player_index + 1, _party_size])
	_reward_ui.visible = true
	var cleared_floor2: int = tower_mgr.get_current_floor()
	var is_elite_floor2: bool = cleared_floor2 > 0 and cleared_floor2 < TowerManager.MAX_FLOORS and cleared_floor2 % 4 == 0
	# 已获取的 buff id 列表（所有角色的 unique 奖励全局不重复）
	var obtained_ids2: Array = _get_all_obtained_ids()
	_reward_ui.start(is_elite_floor2, obtained_ids2)

## 获取所有角色已获取的 buff id 列表（unique 奖励全局不重复）
func _get_all_obtained_ids() -> Array:
	var ids: Array = []
	var per_player_buffs: Array = SceneManager.last_tower_config.get("tower_buffs_per_player", [])
	for buffs in per_player_buffs:
		if buffs is Array:
			for b in buffs:
				if b is Dictionary and b.has("id"):
					ids.append(b.get("id"))
	return ids

## 奖励选择完成 → 保存 buff 到当前角色的列表 → 下一个角色选 / 推进下一层
func _on_reward_selected(buff: Dictionary) -> void:
	_reward_ui.visible = false
	# 持久化 buff 到 SceneManager（按角色索引存储）
	var per_player: Array = SceneManager.last_tower_config.get("tower_buffs_per_player", [])
	# 确保数组足够大
	while per_player.size() <= _reward_player_index:
		per_player.append([])
	if per_player[_reward_player_index] is Array:
		(per_player[_reward_player_index] as Array).append(buff)
	else:
		per_player[_reward_player_index] = [buff]
	SceneManager.last_tower_config["tower_buffs_per_player"] = per_player
	# 下一个角色选祝福
	_reward_player_index += 1
	if _reward_player_index < _party_size:
		_show_reward_for_current_player()
	else:
		# 所有角色选完 → 推进下一层
		_proceed_to_next_floor()

## 推进到下一层（正常模式=过渡动画，fast_mode=直接启动）
func _proceed_to_next_floor() -> void:
	if tower_mgr.get_current_floor() >= TowerManager.MAX_FLOORS:
		tower_mgr.tower_victory.emit()
		return
	var next_floor: int = tower_mgr.get_current_floor() + 1
	if fast_mode:
		_begin_floor_battle(next_floor)
		return
	var enemy_name: String = tower_mgr.peek_next_floor_name()
	var entry_dlg := _get_floor_entry_dialogue(next_floor)
	_phase = "transition"
	_transition.start(next_floor, enemy_name, entry_dlg)

# ============================================================
#  通关 / 失败
# ============================================================

func _on_tower_victory() -> void:
	_phase = "result"
	_stop_bgm()
	if fast_mode:
		_go_to_victory_result()
		return
	var victory_dlg: Dictionary = tower_mgr.get_victory_dialogue()
	if not victory_dlg.is_empty():
		_dialogue_box.visible = true
		_dialogue_box.start(victory_dlg)
		_dialogue_box.dialogue_finished.connect(_on_victory_dialogue_finished, CONNECT_ONE_SHOT)
	else:
		_go_to_victory_result()

func _on_victory_dialogue_finished() -> void:
	_fade_portrait(false)
	_go_to_victory_result()

func _go_to_victory_result() -> void:
	SceneManager.pending_game_result = {
		"tower_victory": true,
		"floors_cleared": tower_mgr.get_current_floor(),
	}
	SceneManager.go_to("res://scenes/tower/tower_result.tscn")

func _on_tower_defeat() -> void:
	_stop_bgm()
	SceneManager.tower_death_count += 1
	SceneManager.last_tower_config["failed_floor"] = tower_mgr.get_current_floor()
	SceneManager.pending_game_result = {
		"tower_defeat": true,
		"failed_floor": tower_mgr.get_current_floor(),
		"enemy_name": tower_mgr.get_current_enemy_name(),
	}
	SceneManager.go_to("res://scenes/tower/tower_result.tscn")

# ============================================================
#  战斗中剧情触发
# ============================================================

## 每回合结算后检查敌人血量（round_resolved 信号带 result 参数）
func _on_round_resolved(_result: Dictionary) -> void:
	if fast_mode or _phase != "battle" or _enemy_hp50_triggered:
		return
	# 查找 team_id=2 的敌人
	for p in GameManager.get_alive_players():
		if p.team_id == 2 and p.hp <= p.character.max_hp * 0.5:
			_enemy_hp50_triggered = true
			_show_enemy_low_hp_narrative(p)
			break

## 敌人HP低于50%时的叙事
func _show_enemy_low_hp_narrative(enemy: PlayerState) -> void:
	var texts := {
		"破败王者（怒）": {
			"speaker": "",
			"lines": [
				{ "text": "（铁甲裂纹中渗出暗红色的光——那不是血，是怨恨本身在燃烧）" },
				{ "text": "不……这不可能！我才是——" },
			]
		},
		"漩涡鸣人（仙人模式）": {
			"speaker": "",
			"lines": [
				{ "text": "（仙人模式的金光开始溃散，少年终于从梦中惊醒）" },
				{ "text": "我……我还是不够强吗……" },
			]
		},
		"司马懿（狂）": {
			"speaker": "",
			"lines": [
				{ "text": "（司马懿的笑容没有变，但眼底的算计终于出现了裂痕）" },
				{ "text": "雕虫小技……（他的声音在抖）" },
			]
		},
	}
	var data: Dictionary = texts.get(enemy.character.character_name, {})
	if data.is_empty():
		return
	_dialogue_box.visible = true
	_dialogue_box.start(data)

## 玩家队有人被淘汰时的叙事（player_eliminated 信号带 player_id 参数）
func _on_player_eliminated(_player_id: int) -> void:
	if fast_mode or _phase != "battle" or _player_eliminated_triggered:
		return
	_player_eliminated_triggered = true
	var data := {
		"speaker": "旁白",
		"lines": [
			{ "text": "又一个人倒下了。塔的墙壁似乎在收缩。" },
		]
	}
	_dialogue_box.visible = true
	_dialogue_box.start(data)

## 宙斯一阶段→二阶段转换：弹出过渡对话 + 播放二阶段BGM
func _on_zeus_phase_transition(_zeus_id: int) -> void:
	if fast_mode:
		return
	_zeus_phase_transition_triggered = true
	_play_bgm()
	var data := TowerDialogueData.new().get_zeus_phase_transition_dialogue()
	if data.is_empty():
		return
	# 暂存当前 phase，对话结束后恢复
	_zeus_transition_prev_phase = _phase
	_phase = "zeus_transition"
	_dialogue_box.visible = true
	_dialogue_box.start(data)

## 播放二阶段BGM（幂等：已在播放则跳过）
func _play_bgm() -> void:
	if _bgm_player == null or _bgm_player.stream == null:
		return
	if not _bgm_player.playing:
		_bgm_player.play()

## 停止二阶段BGM
func _stop_bgm() -> void:
	if _bgm_player != null and _bgm_player.playing:
		_bgm_player.stop()

## 宙斯阶段转换对话结束 → 恢复战斗 phase + 刷新UI
func _on_zeus_transition_dialogue_finished() -> void:
	_dialogue_box.visible = false
	_fade_portrait(false)
	_phase = _zeus_transition_prev_phase
	# 刷新UI：宙斯换了角色.tres，头像/血量/技能列表需要更新
	_ui.setup_players(GameManager.get_alive_players())

# ============================================================
#  梅塔特隆立绘
# ============================================================

func _process(delta: float) -> void:
	# 光晕脉冲呼吸
	if _glow != null and is_instance_valid(_glow) and _glow.visible:
		_glow_timer += delta
		var pulse := _glow_base_a + 0.04 * sin(_glow_timer * 2.0)
		_glow.self_modulate.a = pulse

## 对话行显示时：梅塔特隆说话→立绘淡入，其他（旁白/敌人）→淡出
func _on_line_shown(speaker: String, _text: String, _index: int) -> void:
	if speaker == "神官 · 梅塔特隆":
		_fade_portrait(true)
	else:
		_fade_portrait(false)

## 立绘淡入/淡出
func _fade_portrait(visible_in: bool) -> void:
	if _portrait == null or not is_instance_valid(_portrait):
		return
	_portrait.visible = true
	_glow.visible = true
	var target_a := 0.8 if visible_in else 0.0
	_glow_base_a = 0.15 if visible_in else 0.0
	var tw := create_tween()
	tw.tween_property(_portrait, "self_modulate:a", target_a, 0.5).set_trans(Tween.TRANS_SINE)

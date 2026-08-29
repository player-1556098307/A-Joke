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

## 跨层战报统计累积器：每层结束时从 MatchRecord 收集 team_id=1 的玩家统计
## key = 角色名，value = { char_name, is_human, damage_dealt, damage_taken, damage_blocked, healing, win_count }
var _tower_stats: Dictionary = {}
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
## 敌人祝福随机数生成器（后期小怪自带祝福）
var _rng := RandomNumberGenerator.new()

## ── 联机模式 ──
## 服务器权威：楼层推进/祝福三选一/整局结束由 TowerMatchHost 驱动，
## 客户端本地 TowerManager 仅作确定性镜像（同种子生成相同敌人）
var _is_net: bool = false
var _net_client: NetworkGameClient
var _my_player_index: int = 0
var _net_floor_enemy_buffs: Array = []  # 服务器下发的本层敌人祝福（替代本地随机）
var _net_waiting_label: Label

## 战斗中剧情触发标记
var _enemy_hp50_triggered: bool = false    ## 敌人HP首次低于50%
var _player_eliminated_triggered: bool = false  ## 玩家队有人被淘汰
var _zeus_phase_transition_triggered: bool = false  ## 宙斯阶段转换对话
var _zeus_transition_prev_phase: String = "battle"  ## 转换前的phase，对话结束后恢复
var _enemy_name: String = ""
## 二阶段BGM播放器
var _bgm_player: AudioStreamPlayer

func _ready() -> void:
	_rng.randomize()
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

	# 监听 game_over 信号：每层结束时累积战报统计
	GameManager.game_over.connect(_on_game_over_for_stats)

	# 连接 GameManager 战斗中信号（剧情触发）
	GameManager.player_eliminated.connect(_on_player_eliminated)
	GameManager.round_resolved.connect(_on_round_resolved)
	# 宙斯一阶段→二阶段转换对话
	GameManager.zeus_phase_transition_required.connect(_on_zeus_phase_transition)
	# 免死金牌/涅槃触发 → 在持久化 buff 条目上标记已消耗（一次性祝福用完回池的依据）
	GameManager.tower_blessing_triggered.connect(_on_tower_blessing_triggered)

	# 二阶段BGM播放器（默认静音，仅在阶段转换时播放）
	_bgm_player = AudioStreamPlayer.new()
	var bgm_audio: AudioStream = load("res://assets/audio/bgm/zeus_phase2_bgm.mp3")
	if bgm_audio:
		_bgm_player.stream = bgm_audio
	_bgm_player.volume_db = -6.0
	add_child(_bgm_player)

	# 应用塔模式暗色主题
	_ui.apply_tower_theme()

	# 联机模式：接网络客户端，等待服务器事件驱动（不本地启动第1层）
	_is_net = SceneManager.last_game_config.get("mode", "") == "tower" \
		and SceneManager.last_game_config.get("is_network", false)
	if _is_net:
		_setup_net_mode()
		_show_net_waiting("等待服务器开始战斗...")
		return

	# 启动第1层
	if fast_mode:
		_begin_floor_battle(1)
	else:
		_start_first_floor()

# ============================================================
#  联机模式
# ============================================================

## 接入网络：NetworkGameClient 节点路径与服务器 NetworkGameHost 一致（同 main.gd 模式）
func _setup_net_mode() -> void:
	var config := SceneManager.last_game_config
	var room_code: String = config.get("room_code", "")
	_my_player_index = int(config.get("my_player_id", 0))
	_net_client = NetworkGameClient.new()
	_net_client.name = "Room_" + room_code if room_code != "" else "CurrentGameHost"
	_net_client.my_player_id = _my_player_index
	RoomManager.add_child(_net_client)
	_ui.net_client = _net_client
	# 经典对局信号（与 main.gd 完全一致——缺少任何一个，对应决策弹窗将永远不出现，
	# 服务器会停在等待决策的阶段造成整局卡死）
	_net_client.phase_changed.connect(_ui._on_phase_changed)
	_net_client.gesture_decided.connect(_ui._mark_decided)
	_net_client.gestures_revealed.connect(_ui._on_gestures_revealed)
	_net_client.action_result.connect(_ui._on_action_result)
	_net_client.full_state_received.connect(_ui._on_full_state_sync)
	_net_client.state_hash_received.connect(_ui._on_state_hash_received)
	_net_client.game_over_received.connect(_ui._on_game_over_result)
	_net_client.end_phase_bell_received.connect(_ui._on_end_phase_bell_decision_required)
	_net_client.ftg_intercept_received.connect(_ui._on_ftg_intercept_required)
	_net_client.rasengan_counter_received.connect(_ui._on_rasengan_counter_required)
	_net_client.project_skill_received.connect(_ui._on_project_skill_required)
	_net_client.phantom_dodge_received.connect(_ui._on_phantom_dodge_required)
	_net_client.backtrack_received.connect(_ui._on_backtrack_required)
	_net_client.hiroari_received.connect(_ui._on_hiroari_targets_required)
	_net_client.dream_end_received.connect(_ui._on_dream_end_required)
	_net_client.lake_blessing_received.connect(_ui._on_lake_blessing_required)
	_net_client.sword_forge_received.connect(_ui._on_sword_forge_required)
	# 塔事件（服务器权威驱动）
	_net_client.tower_floor_start_received.connect(_on_net_floor_start)
	_net_client.tower_floor_cleared_received.connect(_on_net_floor_cleared)
	_net_client.tower_reward_offer_received.connect(_on_net_reward_offer)
	_net_client.tower_reward_picked_received.connect(_on_net_reward_picked)
	_net_client.tower_run_ended_received.connect(_on_net_run_ended)
	_net_client.tower_run_sync_received.connect(_on_net_run_sync)
	# 断线重连
	NetworkManager.connected_to_game_server.connect(_on_net_reconnected)
	NetworkManager.disconnected_from_game_server.connect(_on_net_disconnected_in_battle)
	_net_client.player_disconnected_notice.connect(_on_net_player_disconnected)
	_net_client.player_reconnected_notice.connect(_on_net_player_reconnected)
	# 本地镜像与服务器保持一致的输入策略（出拳由真人提交，AI 由服务器代打）
	tower_mgr.config_overrides = {"auto_rps": false}

func _exit_tree() -> void:
	GameManager.game_over.disconnect(_on_game_over_for_stats)
	GameManager.player_eliminated.disconnect(_on_player_eliminated)
	GameManager.round_resolved.disconnect(_on_round_resolved)
	GameManager.zeus_phase_transition_required.disconnect(_on_zeus_phase_transition)
	GameManager.tower_blessing_triggered.disconnect(_on_tower_blessing_triggered)
	if NetworkManager.connected_to_game_server.is_connected(_on_net_reconnected):
		NetworkManager.connected_to_game_server.disconnect(_on_net_reconnected)
	if NetworkManager.disconnected_from_game_server.is_connected(_on_net_disconnected_in_battle):
		NetworkManager.disconnected_from_game_server.disconnect(_on_net_disconnected_in_battle)
	if _net_client != null and is_instance_valid(_net_client):
		_net_client.queue_free()
		_net_client = null

## 传输层断开：显示重连遮罩（NetworkManager 自动指数退避重连，不踢回主菜单）
func _on_net_disconnected_in_battle() -> void:
	_show_net_waiting("连接中断，正在重连...（断线期间你的角色由 AI 托管）")

## 传输层重连成功：凭 token 请求重回对局，服务器会重绑 peer 并补发快照
func _on_net_reconnected() -> void:
	if _net_client == null or not is_instance_valid(_net_client):
		return
	var token: String = _net_client.reconnect_token
	if token == "":
		token = NetworkManager._load_pref("reconnect_token", "")
	if token == "":
		return
	_show_net_waiting("已重连，正在同步战斗状态...")
	await get_tree().create_timer(0.5).timeout
	if _net_client != null and is_instance_valid(_net_client):
		_net_client.rpc_id(1, "on_player_join", multiplayer.get_unique_id(), token)

## 重连后：以服务器快照重建本地塔镜像
func _on_net_run_sync(floor_num: int, enemy_name: String, seed_val: int, buffs_per_player: Array) -> void:
	SceneManager.last_tower_config["tower_buffs_per_player"] = buffs_per_player
	_hide_net_waiting()
	if not tower_mgr.is_running():
		tower_mgr.set_seed(seed_val)
		var party: Array = SceneManager.last_tower_config.get("players", [])
		tower_mgr.start_tower(party)
	while tower_mgr.get_current_floor() < floor_num:
		tower_mgr.start_next_floor()
	_inject_tower_buffs()
	_ui.setup_players(GameManager.get_alive_players())
	_enemy_name = tower_mgr.get_current_enemy_name()
	_floor_label.text = "慈悲尖塔 第%d层 — %s" % [floor_num, _enemy_name]
	_phase = "battle"
	_update_buff_btn_visibility()

## 队友断线/重连提示
func _on_net_player_disconnected(player_id: int) -> void:
	_show_net_waiting("玩家 %d 断线，AI 托管中..." % player_id)
	var t := get_tree().create_timer(4.0)
	t.timeout.connect(func():
		if _net_waiting_label != null and _net_waiting_label.text.begins_with("玩家 %d" % player_id):
			_hide_net_waiting()
	)

func _on_net_player_reconnected(player_id: int) -> void:
	_show_net_waiting("玩家 %d 已重连" % player_id)
	var t := get_tree().create_timer(3.0)
	t.timeout.connect(func():
		if _net_waiting_label != null and _net_waiting_label.text.begins_with("玩家 %d" % player_id):
			_hide_net_waiting()
	)

## 服务器开始新楼层 → 播放进场过渡 → 镜像推进 TowerManager
func _on_net_floor_start(floor_num: int, enemy_name: String, seed_val: int, enemy_buffs: Array) -> void:
	_hide_net_waiting()
	if not tower_mgr.is_running():
		tower_mgr.set_seed(seed_val)
	_net_floor_enemy_buffs = enemy_buffs
	if fast_mode:
		_begin_floor_battle(floor_num)
		return
	var entry_dlg := _get_floor_entry_dialogue(floor_num)
	_phase = "transition"
	_transition.start(floor_num, enemy_name, entry_dlg)

## 层胜利（服务器权威）→ 退场对话 → 等待祝福编排
func _on_net_floor_cleared(_floor_num: int) -> void:
	_hide_buff_panel()
	_buff_btn.visible = false
	var exit_dlg: Dictionary = tower_mgr.get_exit_dialogue()
	if exit_dlg.is_empty():
		_phase = "reward_wait"
		_show_net_waiting("等待队伍选择祝福...")
		return
	_phase = "exit_dialogue"
	_dialogue_box.visible = true
	_dialogue_box.start(exit_dlg)

## 服务器发来本角色的祝福三选一
func _on_net_reward_offer(player_index: int, char_name: String, choices: Array) -> void:
	if player_index != _my_player_index:
		return
	_hide_net_waiting()
	_phase = "reward"
	_reward_ui.set_subtitle("%s 选择祝福" % char_name)
	_reward_ui.visible = true
	var typed: Array[Dictionary] = []
	for c in choices:
		if c is Dictionary:
			typed.append(c)
	_reward_ui.start_with_choices(typed)

## 服务器广播权威祝福结果（含他人/AI）→ 镜像到本地持久化
func _on_net_reward_picked(player_index: int, buff: Dictionary) -> void:
	if buff.is_empty():
		return
	var per_player: Array = SceneManager.last_tower_config.get("tower_buffs_per_player", [])
	while per_player.size() <= player_index:
		per_player.append([])
	if per_player[player_index] is Array:
		(per_player[player_index] as Array).append(buff)
	else:
		per_player[player_index] = [buff]
	SceneManager.last_tower_config["tower_buffs_per_player"] = per_player
	if player_index == _my_player_index:
		_reward_ui.visible = false
		_phase = "reward_wait"
		_show_net_waiting("等待其他成员选择祝福...")

## 整局结束（服务器权威）→ 走本地结算
func _on_net_run_ended(victory: bool, _floor_num: int) -> void:
	_hide_net_waiting()
	if victory:
		_on_tower_victory()
	else:
		_on_tower_defeat()

func _show_net_waiting(text: String) -> void:
	if _net_waiting_label == null:
		_net_waiting_label = Label.new()
		_net_waiting_label.add_theme_font_size_override("font_size", 16)
		_net_waiting_label.add_theme_color_override("font_color", Color("#FAC775"))
		_net_waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_net_waiting_label.anchor_left = 0.0
		_net_waiting_label.anchor_right = 1.0
		_net_waiting_label.anchor_top = 0.5
		_net_waiting_label.anchor_bottom = 0.5
		_net_waiting_label.offset_top = -20.0
		_net_waiting_label.offset_bottom = 20.0
		_net_waiting_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_net_waiting_label.z_index = 6
		add_child(_net_waiting_label)
	_net_waiting_label.text = text
	_net_waiting_label.visible = true

func _hide_net_waiting() -> void:
	if _net_waiting_label != null:
		_net_waiting_label.visible = false

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
		# 换层前：清理已消耗的一次性技能祝福（斩魂/回春用完即弃，回到祝福池可再抽）
		_cleanup_consumed_limited_buffs()
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
	# 后期小怪自带祝福：联机模式应用服务器下发的分配（保证双端一致），单机本地随机
	if _is_net:
		for entry in _net_floor_enemy_buffs:
			var ep := GameManager.get_player(entry.get("player_id", -1))
			if ep == null:
				continue
			for b in entry.get("buffs", []):
				_apply_buff(ep, b)
	else:
		_inject_enemy_buffs()

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
		"immortal_medal":
			# 免死金牌：一次性被动，免疫一次致命伤害
			p.immortal_medal = true
		"pojun":
			# 破军：普攻可暴击
			p.pojun_active = true
		"bati":
			# 霸体：免疫一切控制效果
			p.bati_active = true
		"niepan":
			# 涅槃：死亡时以半血重生（一次性被动）
			p.niepan_active = true

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

## 后期小怪自带祝福：第3-4轮（cycle≥3）的小怪层，敌人随机获得 0-2 个普通祝福
## 仅对小怪层生效，精英层和Boss层不加（它们有自己的技能体系）
func _inject_enemy_buffs() -> void:
	var floor_num := tower_mgr.get_current_floor()
	# 精英层（第4/8/12/16层）和Boss层不加祝福
	if floor_num > 0 and floor_num <= TowerManager.MAX_FLOORS and floor_num % 4 == 0:
		return
	# 计算循环轮次（1-4）：ceili(floor / 4)
	var cycle := ceili(float(floor_num) / 4.0)
	if cycle < 3:
		return
	# 从 REWARD_POOL 中筛选普通祝福（tier=normal，排除一次性消耗品 soul_slash/spring/immortal_medal）
	var normal_pool: Array[Dictionary] = []
	for reward in TowerRewardUI.REWARD_POOL:
		if reward.get("tier", "normal") != "normal":
			continue
		var rid: String = reward.get("id", "")
		# 排除一次性消耗品（小怪不适合拥有一次性技能/被动）
		if rid in ["soul_slash", "spring", "immortal_medal"]:
			continue
		normal_pool.append(reward)
	if normal_pool.is_empty():
		return
	# 为每个敌人随机分配 0-2 个祝福
	for p in GameManager.get_alive_players():
		if p.team_id != 2:
			continue
		var buff_count := _rng.randi_range(0, 2)
		var chosen: Array = []
		# 不重复选取
		var pool_copy := normal_pool.duplicate(true)
		pool_copy.shuffle()
		for i in range(min(buff_count, pool_copy.size())):
			chosen.append(pool_copy[i])
		for buff in chosen:
			_apply_buff(p, buff)

## 换层前清理已消耗的一次性祝福
## 斩魂/回春是消耗品：用完一次永久失效，从持久化 buff 列表移除 → 祝福池可再次随机到
## 免死金牌/涅槃是一次性被动：触发后消费（_consumed 标记）同样移除回池
func _cleanup_consumed_limited_buffs() -> void:
	var consumed_buff_ids := { "soul_slash": true, "spring": true, "immortal_medal": true, "niepan": true }
	var per_player: Array = SceneManager.last_tower_config.get("tower_buffs_per_player", [])
	if per_player.is_empty():
		return
	var alive_players := GameManager.get_alive_players()
	for p in alive_players:
		if p.team_id != 1:
			continue
		# 找到该玩家对应的 buff 列表索引（按 team_id=1 的队伍顺序）
		var team_idx := 0
		for ap in alive_players:
			if ap.team_id != 1:
				continue
			if ap == p:
				break
			team_idx += 1
		if team_idx >= per_player.size() or not (per_player[team_idx] is Array):
			continue
		var buffs: Array = per_player[team_idx]
		# 检查该玩家是否有已使用/已触发的一次性祝福
		# - 技能型消耗品（斩魂/回春）：用 limited_skills_used 判断（安全：新选未注入时列表为空不会误判）
		# - 被动型（免死金牌/涅槃）：只认持久化 _consumed 标记（触发时由 tower_blessing_triggered 写入）。
		#   不能回退到 PlayerState 判断——bool 字段默认 false 无法区分"未持有"与"已触发清除"，
		#   且奖励选择后到注入前 PlayerState 尚未持有该祝福，回退会把刚选未触发的误判为已消耗而错误回池
		var to_remove := []
		for b in buffs:
			if not (b is Dictionary):
				continue
			var bid: String = b.get("id", "")
			if not consumed_buff_ids.has(bid):
				continue
			var consumed: bool = false
			match bid:
				"soul_slash":
					consumed = "斩魂" in p.limited_skills_used
				"spring":
					consumed = "回春" in p.limited_skills_used
				"immortal_medal", "niepan":
					consumed = b.get("_consumed", false)
			if consumed:
				to_remove.append(b)
		for b in to_remove:
			buffs.erase(b)
	SceneManager.last_tower_config["tower_buffs_per_player"] = per_player

## 一次性被动祝福触发回调：免死金牌/涅槃触发时，在持久化 buff 条目上标记已消耗
func _on_tower_blessing_triggered(player_id: int, blessing_name: String) -> void:
	var buff_id: String = ""
	match blessing_name:
		"免死金牌":
			buff_id = "immortal_medal"
		"涅槃":
			buff_id = "niepan"
	if buff_id == "":
		return
	_mark_buff_consumed(player_id, buff_id)

## 将指定玩家持久化列表中的 buff 条目标记为已消耗（一次性祝福用完回池的依据）
## 注意：不能依赖 PlayerState 判断——奖励选择后到下一层注入前，PlayerState 尚未持有该祝福，
## 若按 "字段被清除" 判断会把刚选未触发的祝福误判为已消耗并错误回池
func _mark_buff_consumed(player_id: int, buff_id: String) -> void:
	var per_player: Array = SceneManager.last_tower_config.get("tower_buffs_per_player", [])
	if per_player.is_empty():
		return
	# 按 team_id=1 的队伍顺序定位该玩家对应的 buff 列表索引
	var team_idx := 0
	var found := false
	for p in GameManager.get_alive_players():
		if p.team_id != 1:
			continue
		if p.player_id == player_id:
			found = true
			break
		team_idx += 1
	if not found or team_idx >= per_player.size() or not (per_player[team_idx] is Array):
		return
	for b in per_player[team_idx]:
		if b is Dictionary and b.get("id", "") == buff_id:
			b["_consumed"] = true
			break
	SceneManager.last_tower_config["tower_buffs_per_player"] = per_player

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
		# 行退场对话时也要暂停自动出拳
		GameManager.tower_dialogue_paused = true

## 退场对话结束 → 弹出奖励选择（或直接推进）
func _on_dialogue_generic_finished() -> void:
	_dialogue_box.visible = false
	_fade_portrait(false)
	# 确保对话结束后恢复自动出拳（防止暂停标记残留）
	GameManager.tower_dialogue_paused = false
	if _phase == "exit_dialogue":
		if _is_net:
			# 联机：祝福编排由服务器驱动，等待 TOWER_REWARD_OFFER
			_phase = "reward_wait"
			_show_net_waiting("等待队伍选择祝福...")
		else:
			_show_reward_selection()
	elif _phase == "zeus_transition":
		_on_zeus_transition_dialogue_finished()
	else:
		# 战斗中的叙事对话（敌人HP<50%/玩家淘汰等）：恢复后立即继续自动出拳
		GameManager.resume_auto_rps()

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
	if _is_net:
		# 联机：提交给服务器，等待权威回执（TOWER_REWARD_PICKED）后再镜像
		_net_client.submit_reward_pick(_my_player_index, buff)
		_phase = "reward_wait"
		_show_net_waiting("等待其他成员选择祝福...")
		return
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
## 联机模式下永远不由本地推进（由服务器 TOWER_FLOOR_START 驱动）
func _proceed_to_next_floor() -> void:
	if _is_net:
		return
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
#  跨层战报统计
# ============================================================

## 每层 game_over 信号触发时：收集 team_id=1 玩家统计到累积器
func _on_game_over_for_stats(_winner_id: int, record: MatchRecord) -> void:
	if record == null:
		return
	for pid in record.player_stats:
		var ps: PlayerMatchStats = record.player_stats[pid]
		if ps == null:
			continue
		var player := GameManager.get_player(pid)
		if player == null or player.team_id != 1:
			continue
		var key := ps.character.character_name if ps.character != null else ps.player_name
		if not _tower_stats.has(key):
			_tower_stats[key] = {
				"char_name": key,
				"is_human": ps.is_human,
				"damage_dealt": 0.0,
				"damage_taken": 0.0,
				"damage_blocked": 0.0,
				"healing": 0.0,
				"win_count": 0,
			}
		var entry: Dictionary = _tower_stats[key]
		entry["damage_dealt"] += ps.total_damage_dealt
		entry["damage_taken"] += ps.total_damage_taken
		entry["damage_blocked"] += ps.total_damage_blocked
		entry["healing"] += ps.total_healing
		entry["win_count"] += ps.win_count

## 构建战报统计数组（用于传递给结果界面）
func _build_tower_stats_array() -> Array:
	var result: Array = []
	for key in _tower_stats:
		result.append(_tower_stats[key])
	return result

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
		"tower_stats": _build_tower_stats_array(),
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
		"tower_stats": _build_tower_stats_array(),
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
	# 战斗中叙事对话：暂停自动出拳
	GameManager.tower_dialogue_paused = true

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
	# 玩家被淘汰叙事：暂停自动出拳
	GameManager.tower_dialogue_paused = true

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
	GameManager.tower_dialogue_paused = true
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
	# 对话已结束，恢复自动出拳（若当前处于出拳阶段）
	GameManager.resume_auto_rps()
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

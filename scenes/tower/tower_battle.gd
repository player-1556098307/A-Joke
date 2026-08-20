## TowerBattle — 慈悲尖塔战斗场景
## 复用 GameUI 对局界面 + TowerManager 层推进
## 支持层间过渡动画、进场/退场对话、通关/失败结算、战斗中剧情触发
extends Node

@onready var _ui: Control = $GameUI
@onready var tower_mgr: TowerManager = $TowerManager

var _floor_label: Label
var _transition: TowerFloorTransition
var _dialogue_box: DialogueBox
var _phase: String = "idle"  ## "idle", "transition", "entry_dialogue", "battle", "exit_dialogue", "result"

## 测试快速模式：跳过所有过渡动画和对话，直接启动战斗/推进层
var fast_mode: bool = false

## 战斗中剧情触发标记
var _enemy_hp50_triggered: bool = false    ## 敌人HP首次低于50%
var _player_eliminated_triggered: bool = false  ## 玩家队有人被淘汰
var _enemy_name: String = ""

func _ready() -> void:
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

	# 退场/战斗中叙事 DialogueBox
	_dialogue_box = DialogueBox.new()
	_dialogue_box.dialogue_finished.connect(_on_dialogue_generic_finished)
	_dialogue_box.visible = false
	add_child(_dialogue_box)

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
	_transition.start(1, "破败王者（怒）", entry_dlg)
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
	_ui.setup_players(GameManager.get_alive_players())
	_enemy_name = tower_mgr.get_current_enemy_name()
	_floor_label.text = "慈悲尖塔 第%d层 — %s" % [tower_mgr.get_current_floor(), _enemy_name]

# ============================================================
#  层间推进
# ============================================================

func _on_floor_changed(floor_num: int, enemy_name: String) -> void:
	_floor_label.text = "慈悲尖塔 第%d层 — %s" % [floor_num, enemy_name]
	_ui.setup_players(GameManager.get_alive_players())

## 层胜利：显示退场对话 → 推进下一层
func _on_floor_cleared(floor_num: int, enemy_name: String) -> void:
	if fast_mode:
		_proceed_to_next_floor()
		return
	_phase = "exit_dialogue"
	var exit_dlg: Dictionary = tower_mgr.get_exit_dialogue()
	if exit_dlg.is_empty():
		_proceed_to_next_floor()
	else:
		_dialogue_box.visible = true
		_dialogue_box.start(exit_dlg)

## 退场对话结束 → 推进下一层
func _on_dialogue_generic_finished() -> void:
	_dialogue_box.visible = false
	if _phase == "exit_dialogue":
		_proceed_to_next_floor()
	# 战斗中的叙事对话不改变 phase，只是弹出后消失

## 推进到下一层（正常模式=过渡动画，fast_mode=直接启动）
func _proceed_to_next_floor() -> void:
	if tower_mgr.get_current_floor() >= TowerManager.MAX_FLOORS:
		tower_mgr.tower_victory.emit()
		return
	var next_floor: int = tower_mgr.get_current_floor() + 1
	if fast_mode:
		_begin_floor_battle(next_floor)
		return
	var enemy_names := ["破败王者（怒）", "漩涡鸣人（仙人模式）", "司马懿（狂）"]
	var enemy_name: String = enemy_names[next_floor - 1] if next_floor - 1 < enemy_names.size() else "???"
	var entry_dlg := _get_floor_entry_dialogue(next_floor)
	_phase = "transition"
	_transition.start(next_floor, enemy_name, entry_dlg)

# ============================================================
#  通关 / 失败
# ============================================================

func _on_tower_victory() -> void:
	_phase = "result"
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
	_go_to_victory_result()

func _go_to_victory_result() -> void:
	SceneManager.pending_game_result = {
		"tower_victory": true,
		"floors_cleared": tower_mgr.get_current_floor(),
	}
	SceneManager.go_to("res://scenes/tower/tower_result.tscn")

func _on_tower_defeat() -> void:
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

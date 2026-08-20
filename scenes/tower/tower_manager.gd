## TowerManager — 慈悲尖塔 PvE 闯关模式核心
## 逐层挑战精英敌人（1-3层），复用 GameManager 猜拳回合制
## 玩家队（team=1）vs 敌人（team=2）；全员死亡=失败，通关3层=胜利
## 支持层间对话、层间过渡动画、退场对话
class_name TowerManager
extends Node

signal floor_changed(floor_num: int, enemy_name: String)
signal floor_cleared(floor_num: int, enemy_name: String)  ## 层胜利，敌人被击败
signal tower_victory
signal tower_defeat

const MAX_FLOORS := 3
const ENEMY_PATHS := [
	"res://resources/characters/tower/破败王者（怒）.tres",
	"res://resources/characters/tower/漩涡鸣人（仙人模式）.tres",
	"res://resources/characters/tower/司马懿（狂）.tres",
]

## 对话数据资源
var _dialogue_data: TowerDialogueData

var _player_chars: Array[CharacterData] = []
var _current_floor: int = 0
var _current_enemy_name: String = ""
var _running: bool = false
## 队伍配置：Array[Dictionary]，每项 { character: CharacterData, is_human: bool }
var _party: Array[Dictionary] = []
## 是否自动推进到下一层（true=层胜后立即start_next_floor，false=仅emit floor_cleared等外部调用）
var _auto_advance: bool = true

## 开始闯关：传入队伍配置（1-3人，每项含角色与控制者类型）
func start_tower(party: Array) -> void:
	if party.is_empty():
		return
	_party.clear()
	for entry in party:
		if entry is Dictionary and entry.get("character", null) != null:
			_party.append(entry)
	if _party.is_empty():
		return
	_current_floor = 0
	_running = true
	# 加载对话数据
	_dialogue_data = TowerDialogueData.new()
	# 立即启动第1层（保持向后兼容）
	_start_first_floor()

## 内部启动第1层（start_tower 调用）
func _start_first_floor() -> void:
	_start_next_floor_impl()

## 启动下一层战斗（或通关判定）
## 可由外部调用（如 TowerBattle 在层间过渡完成后）
func start_next_floor() -> void:
	_start_next_floor_impl()

## 实际推进逻辑
func _start_next_floor_impl() -> void:
	if _current_floor >= MAX_FLOORS:
		_running = false
		tower_victory.emit()
		return
	_current_floor += 1
	var enemy_char := load(ENEMY_PATHS[_current_floor - 1]) as CharacterData
	if enemy_char == null:
		_running = false
		tower_defeat.emit()
		return
	_current_enemy_name = enemy_char.character_name
	# 构建对局配置：玩家 team=1，敌人 team=2
	var players: Array = []
	for i in range(_party.size()):
		var entry: Dictionary = _party[i]
		var is_ai: bool = not entry.get("is_human", true)
		players.append({
			"name": ("AI·" if is_ai else "玩家") + "%s" % (entry.get("character", null) as CharacterData).character_name,
			"character": entry.get("character", null),
			"is_human": entry.get("is_human", true),
			"team_id": 1,
		})
	players.append({
		"name": enemy_char.character_name,
		"character": enemy_char,
		"is_human": false,
		"team_id": 2,
	})
	GameManager.setup_game({ "players": players, "tower_mode": true })
	GameManager.game_over.connect(_on_game_over, CONNECT_ONE_SHOT)
	floor_changed.emit(_current_floor, _current_enemy_name)

## 每层对局结束：存活队伍判定胜负
func _on_game_over(_winner_id: int, _record: MatchRecord) -> void:
	if not _running:
		return
	var alive := GameManager.get_alive_players()
	if alive.size() > 0 and alive[0].team_id == 1:
		# 玩家队存活 → 层胜利
		floor_cleared.emit(_current_floor, _current_enemy_name)
		if _auto_advance:
			_start_next_floor_impl()
	else:
		_running = false
		tower_defeat.emit()

## 设置是否自动推进（tower_battle 场景设为 false，由过渡动画控制推进）
func set_auto_advance(v: bool) -> void:
	_auto_advance = v

## 是否正在闯关（tower_battle 用）
func is_running() -> bool:
	return _running

## 当前层数
func get_current_floor() -> int:
	return _current_floor

## 当前层敌人名
func get_current_enemy_name() -> String:
	return _current_enemy_name

## 当前层退场对话（敌人临终遗言）
func get_exit_dialogue() -> Dictionary:
	if _dialogue_data == null:
		return {}
	return _dialogue_data.get_floor_exit(_current_floor)

## 通关对话
func get_victory_dialogue() -> Dictionary:
	if _dialogue_data == null:
		return {}
	return _dialogue_data.get_victory_dialogue()

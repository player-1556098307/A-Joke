## TowerManager — 慈悲尖塔 PvE 闯关模式核心
## 16层闯关：3层小怪+1层精英怪循环，第16层为大Boss（暂未实现=通关）
## 小怪随机生成（同层不重复），精英怪固定顺序不重复
## 玩家队（team=1）vs 敌人（team=2）；全员死亡=失败，通关16层=胜利
class_name TowerManager
extends Node

signal floor_changed(floor_num: int, enemy_name: String)
signal floor_cleared(floor_num: int, enemy_name: String)  ## 层胜利，敌人被击败
signal tower_victory
signal tower_defeat

const MAX_FLOORS := 16

## 精英怪（固定顺序，第4/8/12层）
const ELITE_PATHS := [
	"res://resources/characters/tower/破败王者（怒）.tres",
	"res://resources/characters/tower/漩涡鸣人（仙人模式）.tres",
	"res://resources/characters/tower/司马懿（狂）.tres",
]

## 小怪池（8种，索引0-7）
const SMALL_ENEMY_PATHS := [
	"res://resources/characters/tower/训练兵.tres",
	"res://resources/characters/tower/铁盾兵.tres",
	"res://resources/characters/tower/爆破手.tres",
	"res://resources/characters/tower/术师.tres",
	"res://resources/characters/tower/医疗兵.tres",
	"res://resources/characters/tower/狂战士.tres",
	"res://resources/characters/tower/影刃.tres",
	"res://resources/characters/tower/石像鬼.tres",
]

## 前期小怪索引池（第1-2轮：训练兵~医疗兵）
const EARLY_POOL := [0, 1, 2, 3, 4]
## 全部小怪索引池（第3-4轮：加入狂战士/影刃/石像鬼）
const FULL_POOL := [0, 1, 2, 3, 4, 5, 6, 7]

## 对话数据资源
var _dialogue_data: TowerDialogueData

var _player_chars: Array[CharacterData] = []
var _current_floor: int = 0
var _current_enemy_name: String = ""
var _current_enemy_chars: Array[CharacterData] = []
var _running: bool = false
## 队伍配置：Array[Dictionary]，每项 { character: CharacterData, is_human: bool }
var _party: Array[Dictionary] = []
## 是否自动推进到下一层（true=层胜后立即start_next_floor，false=仅emit floor_cleared等外部调用）
var _auto_advance: bool = true
## 已使用的精英怪数量（递增，保证不重复）
var _used_elite_count: int = 0
## 随机数生成器
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

## 设置随机种子（测试用）
func set_seed(seed_val: int) -> void:
	_rng.seed = seed_val

# ============================================================
#  层类型判定
# ============================================================

## 是否为精英怪层（第4/8/12层）
func _is_elite_floor(floor_num: int) -> bool:
	return floor_num > 0 and floor_num < MAX_FLOORS and floor_num % 4 == 0

## 是否为大Boss层（第16层）
func _is_boss_floor(floor_num: int) -> bool:
	return floor_num == MAX_FLOORS

## 获取循环轮次（1-4）
func _get_cycle(floor_num: int) -> int:
	return ceili(float(floor_num) / 4.0)

## 获取小怪数量范围 [min, max]
func _get_small_enemy_count_range(cycle: int) -> Array:
	if cycle <= 2:
		return [1, 2]
	else:
		return [3, 4]

## 获取可用小怪索引池
func _get_pool_indices(cycle: int) -> Array:
	if cycle <= 2:
		return EARLY_POOL.duplicate()
	else:
		return FULL_POOL.duplicate()

## 预览下一层敌人名称（过渡动画用，不实际推进）
func peek_next_floor_name() -> String:
	var next_floor := _current_floor + 1
	if next_floor > MAX_FLOORS:
		return ""
	if _is_boss_floor(next_floor):
		return "???"
	if _is_elite_floor(next_floor):
		var elite_idx := _used_elite_count
		if elite_idx < ELITE_PATHS.size():
			var elite_char := load(ELITE_PATHS[elite_idx]) as CharacterData
			if elite_char:
				return elite_char.character_name
		return "精英怪"
	return "小怪群"

# ============================================================
#  小怪随机生成
# ============================================================

## 生成本层小怪（同层不重复种类）
func _generate_small_enemies(floor_num: int) -> Array[CharacterData]:
	var cycle := _get_cycle(floor_num)
	var range_arr := _get_small_enemy_count_range(cycle)
	var min_count: int = range_arr[0]
	var max_count: int = range_arr[1]
	var count: int = _rng.randi_range(min_count, max_count)

	var pool := _get_pool_indices(cycle)
	pool.shuffle()

	var result: Array[CharacterData] = []
	for i in range(min(count, pool.size())):
		var idx: int = pool[i]
		var char_data := load(SMALL_ENEMY_PATHS[idx]) as CharacterData
		if char_data != null:
			# 后期小怪：克隆并叠加 HP 加成（按轮次递增）
			var hp_bonus := get_small_enemy_hp_bonus(floor_num)
			if hp_bonus > 0:
				var boosted := char_data.duplicate(false) as CharacterData
				boosted.max_hp = char_data.max_hp + hp_bonus
				result.append(boosted)
			else:
				result.append(char_data)
	return result

## 获取指定层小怪的 HP 加成（正数=小怪层，0=精英层）
func get_small_enemy_hp_bonus(floor_num: int) -> int:
	if floor_num <= 0:
		return 0
	return get_cycle_hp_bonus(_get_cycle(floor_num))

## 按轮次获取 HP 加成（第1轮+0，第2轮+3，第3轮+6，第4轮+10）
func get_cycle_hp_bonus(cycle: int) -> int:
	match cycle:
		1: return 0
		2: return 3
		3: return 6
		4: return 10
		_: return 10

## 按轮次获取攻击力加成（第1-2轮+0，第3轮+2，第4轮+3）
## 仅对小怪层生效，精英/Boss层不加
func get_cycle_attack_bonus(cycle: int) -> float:
	match cycle:
		1, 2: return 0.0
		3: return 2.0
		4: return 3.0
		_: return 3.0

## 获取指定层小怪的攻击力加成（正数=小怪层后期，0=前期/精英层）
func get_small_enemy_attack_bonus(floor_num: int) -> float:
	if floor_num <= 0 or _is_elite_floor(floor_num) or _is_boss_floor(floor_num):
		return 0.0
	return get_cycle_attack_bonus(_get_cycle(floor_num))

## 小怪站位优化：远程/辅助大概率放中间（离玩家更远），近战放两端
## 环形座位中，敌人数组首尾两端紧邻玩家（距离1），中间位置距离最远
## 70%概率执行优化站位，30%完全随机增加变化性
func _arrange_enemy_positions(enemies: Array[CharacterData]) -> Array[CharacterData]:
	if enemies.size() <= 1:
		return enemies
	# 30%概率完全随机站位
	if _rng.randf() < 0.3:
		enemies.shuffle()
		return enemies
	# 分为远程组和近战组
	var ranged: Array[CharacterData] = []
	var melee: Array[CharacterData] = []
	for c in enemies:
		if _is_ranged_character(c):
			ranged.append(c)
		else:
			melee.append(c)
	# 如果全是同类型，无需重排
	if ranged.is_empty() or melee.is_empty():
		return enemies
	# 各组随机打乱
	ranged.shuffle()
	melee.shuffle()
	# 近战分前后两半：前半放数组头部，后半（逆序）放数组尾部
	var front_count: int = ceili(float(melee.size()) / 2.0)
	var front_melee: Array[CharacterData] = melee.slice(0, front_count)
	var back_melee: Array[CharacterData] = melee.slice(front_count, melee.size())
	back_melee.reverse()
	# 结果 = [近战前半] + [远程中间] + [近战后半逆序]
	var result: Array[CharacterData] = []
	result.append_array(front_melee)
	result.append_array(ranged)
	result.append_array(back_melee)
	return result

## 判断角色是否为远程/辅助型（有射程≥2的技能）
func _is_ranged_character(c: CharacterData) -> bool:
	for skill in c.skills:
		if skill.max_range >= 2:
			return true
	return false

## 测试用：直接指定小怪索引列表生成（不做随机）
func _generate_small_enemies_with_indices(indices: Array[int]) -> Array[CharacterData]:
	var result: Array[CharacterData] = []
	for idx in indices:
		if idx >= 0 and idx < SMALL_ENEMY_PATHS.size():
			var char_data := load(SMALL_ENEMY_PATHS[idx]) as CharacterData
			if char_data != null:
				result.append(char_data)
	return result

# ============================================================
#  闯关流程
# ============================================================

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
	_used_elite_count = 0
	_running = true
	_dialogue_data = TowerDialogueData.new()
	_start_first_floor()

func _start_first_floor() -> void:
	_start_next_floor_impl()

## 启动下一层战斗（或通关判定）
func start_next_floor() -> void:
	_start_next_floor_impl()

## 实际推进逻辑
func _start_next_floor_impl() -> void:
	if _current_floor >= MAX_FLOORS:
		_running = false
		tower_victory.emit()
		return
	_current_floor += 1

	# 大Boss层（第16层）：暂时跳过=通关
	if _is_boss_floor(_current_floor):
		_running = false
		tower_victory.emit()
		return

	# 生成本层敌人
	var enemies: Array[CharacterData] = []
	if _is_elite_floor(_current_floor):
		# 精英怪层：按顺序取，不重复
		var elite_idx := _used_elite_count
		if elite_idx < ELITE_PATHS.size():
			var elite_char := load(ELITE_PATHS[elite_idx]) as CharacterData
			if elite_char != null:
				enemies.append(elite_char)
			_used_elite_count += 1
	else:
		# 小怪层：随机生成
		enemies = _generate_small_enemies(_current_floor)

	if enemies.is_empty():
		_running = false
		tower_defeat.emit()
		return

	_current_enemy_chars = enemies
	# 小怪站位优化：远程/辅助大概率站中间（离玩家更远），近战放两端
	if not _is_elite_floor(_current_floor) and not _is_boss_floor(_current_floor):
		enemies = _arrange_enemy_positions(enemies)
		_current_enemy_chars = enemies
	_current_enemy_name = ""
	for i in range(enemies.size()):
		if i > 0:
			_current_enemy_name += "、"
		_current_enemy_name += enemies[i].character_name

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
	for enemy_char in enemies:
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

# ============================================================
#  外部接口
# ============================================================

## 设置是否自动推进
func set_auto_advance(v: bool) -> void:
	_auto_advance = v

## 是否正在闯关
func is_running() -> bool:
	return _running

## 当前层数
func get_current_floor() -> int:
	return _current_floor

## 当前层敌人名（多怪时逗号分隔）
func get_current_enemy_name() -> String:
	return _current_enemy_name

## 当前层敌人角色列表
func get_current_enemy_chars() -> Array[CharacterData]:
	return _current_enemy_chars

## 当前层退场对话
func get_exit_dialogue() -> Dictionary:
	if _dialogue_data == null:
		return {}
	return _dialogue_data.get_floor_exit(_current_floor)

## 通关对话
func get_victory_dialogue() -> Dictionary:
	if _dialogue_data == null:
		return {}
	return _dialogue_data.get_victory_dialogue()

## Boss半血对话触发验证：确保只检测Boss(team_id=2)血量，不受队友血量影响
## 覆盖场景：
##   1. 队友半血+Boss满血 → 不触发
##   2. Boss半血+队友满血 → 触发
##   3. 两人都半血+Boss满血 → 不触发
##   4. 队友淘汰+Boss满血 → 不触发
extends Node

var _pass: int = 0
var _fail: int = 0

func _ready() -> void:
	print("=== Boss半血对话触发验证 ===")
	await get_tree().process_frame

	var naruto := load("res://resources/characters/漩涡鸣人.tres") as CharacterData
	var sasuke := load("res://resources/characters/宇智波佐助.tres") as CharacterData
	SceneManager.last_tower_config = {
		"players": [
			{ "character": naruto, "is_human": true },
			{ "character": sasuke, "is_human": false },
		]
	}
	SceneManager.tower_death_count = 0

	var battle = (load("res://scenes/tower/tower_battle.tscn") as PackedScene).instantiate()
	battle.fast_mode = true
	add_child(battle)

	for i in range(100):
		await get_tree().process_frame
		if battle._phase == "battle":
			break
	await get_tree().create_timer(0.3).timeout
	battle.fast_mode = false

	var gm := GameManager
	var boss: PlayerState = null
	var teammate: PlayerState = null
	var human: PlayerState = null
	for p in gm.get_alive_players():
		if p.team_id == 2:
			boss = p
		elif p.is_human:
			human = p
		else:
			teammate = p

	_assert(boss != null, "H1: Boss存在")
	_assert(teammate != null, "H2: AI队友存在")
	_assert(boss.team_id == 2, "H3: Boss team_id=2")
	_assert(teammate.team_id == 1, "H4: 队友 team_id=1")

	# 场景1：Boss满血，队友半血 → 不触发
	_reset_battle(boss, teammate, human, battle,
		_hp_full(boss), _hp_full(teammate) * 0.3, _hp_full(human))
	_assert(not _trigger_and_check(battle), "H5: 队友半血+Boss满血 → 不触发")

	# 场景2：Boss半血，队友满血 → 触发
	_reset_battle(boss, teammate, human, battle,
		_hp_full(boss) * 0.3, _hp_full(teammate), _hp_full(human))
	_assert(_trigger_and_check(battle), "H6: Boss半血+队友满血 → 触发")

	# 场景3：两人都半血，Boss满血 → 不触发
	_reset_battle(boss, teammate, human, battle,
		_hp_full(boss), _hp_full(teammate) * 0.3, _hp_full(human) * 0.3)
	battle._player_eliminated_triggered = true  # 避免淘汰对话干扰
	_assert(not _trigger_and_check(battle), "H7: 两人都半血+Boss满血 → 不触发")

	# 场景4：队友淘汰+Boss满血 → 不触发Boss对话
	_reset_battle(boss, teammate, human, battle,
		_hp_full(boss), 0.0, _hp_full(human))
	teammate.is_alive = false
	battle._player_eliminated_triggered = true
	_assert(not _trigger_and_check(battle), "H8: 队友淘汰+Boss满血 → 不触发Boss对话")

	print("=== 验证结束：PASS=%d FAIL=%d ===" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)

func _hp_full(p: PlayerState) -> float:
	return p.character.max_hp

func _reset_battle(boss: PlayerState, teammate: PlayerState, human: PlayerState, battle: Node, boss_hp: float, teammate_hp: float, human_hp: float) -> void:
	boss.hp = boss_hp
	boss.is_alive = true
	teammate.hp = teammate_hp
	teammate.is_alive = true
	human.hp = human_hp
	human.is_alive = true
	battle._enemy_hp50_triggered = false
	battle._player_eliminated_triggered = false
	if battle._dialogue_box.is_active():
		battle._dialogue_box.force_finish()

func _trigger_and_check(battle: Node) -> bool:
	battle._on_round_resolved({"is_draw": false, "winners": [0], "losers": [1]})
	return battle._dialogue_box.is_active()

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("PASS: " + msg)
	else:
		_fail += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)

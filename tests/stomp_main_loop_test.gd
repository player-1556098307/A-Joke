## 秽土柱间·跺脚真实主循环测试
## 重现用户场景：R1 柱间普攻（激活跺脚）→ R2 对手攻击柱间 → R3 柱间应强制判胜
## 与 edo_hashirama_test 的"模拟"测试不同，本测试走 GameManager 真实状态机
extends Node

var _pass_count: int = 0
var _fail_count: int = 0

func _ready() -> void:
	print("=== 秽土柱间跺脚真实主循环测试 ===")
	await get_tree().process_frame

	var edo_char := load("res://resources/characters/千手柱间（秽土转生）.tres") as CharacterData
	var naruto_char := load("res://resources/characters/漩涡鸣人.tres") as CharacterData
	if edo_char == null or naruto_char == null:
		print("FATAL: 角色资源加载失败")
		get_tree().quit(1)
		return

	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "秽土柱间", "character": edo_char, "is_human": true},
			{"name": "鸣人", "character": naruto_char, "is_human": true},
		],
	})
	await get_tree().process_frame
	var edo: PlayerState = gm.get_player(0)
	var nar: PlayerState = gm.get_player(1)

	# ═══ R1：柱间赢 → 普攻 → 激活跺脚（stomp_active=2）═══
	edo.current_gesture = PlayerState.Gesture.ROCK
	nar.current_gesture = PlayerState.Gesture.SCISSORS
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "R1a: 柱间获胜（实际=%d）" % gm.get("_sole_winner_id"))
	edo.energy = 0
	gm.submit_action(0, PlayerState.ActionType.USE_SKILL, _find_skill_index(edo, "普攻"), 1)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(edo.stomp_active >= 1, "R1b: 普攻后跺脚激活（本回合结束递减后>=1，实际=%d）" % edo.stomp_active)
	_assert(nar.hp == 5.0, "R1c: 普攻1伤（6→5，实际=%.1f）" % nar.hp)

	# ═══ R2：鸣人赢 → 普攻柱间 → 跺脚受击触发（+1气 + force_win）═══
	# 信号捕获：记录受击触发瞬间 stomp_active 与本次回合结算广播的胜者
	# 注意：GDScript lambda 按值捕获局部变量，须用数组容器传递
	var stomp_on_hit: Array = [-1]
	gm.player_charged.connect(func(pid: int, e: int):
		if pid == 0 and stomp_on_hit[0] < 0:
			stomp_on_hit[0] = edo.stomp_active)
	var last_round_winners: Array = [[]]
	gm.round_resolved.connect(func(r: Dictionary): last_round_winners[0] = r.get("winners", []).duplicate())
	edo.current_gesture = PlayerState.Gesture.SCISSORS
	nar.current_gesture = PlayerState.Gesture.ROCK
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 1, "R2a: 鸣人获胜（实际=%d）" % gm.get("_sole_winner_id"))
	var edo_energy_before: int = edo.energy
	var edo_hp_before: float = edo.hp
	nar.energy = 1  # 鸣人普攻需 1 气
	gm.submit_action(1, PlayerState.ActionType.USE_SKILL, _find_skill_index(nar, "普攻"), 0)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert(edo.hp == edo_hp_before - 1.0, "R2b: 柱间受1伤（%.1f→%.1f）" % [edo_hp_before, edo.hp])
	_assert(stomp_on_hit[0] >= 1, "R2c: 受击瞬间跺脚仍激活（实际=%d）" % stomp_on_hit[0])
	_assert(edo.energy == edo_energy_before + 1, "R2d: 跺脚受击+1气（%d→%d）" % [edo_energy_before, edo.energy])
	_assert(edo.force_win_next_round, "R2e: 跺脚受击设置force_win_next_round（实际=%s）" % str(edo.force_win_next_round))

	# ═══ R3：柱间出剪刀（本应输给石头）→ 强制判胜 ═══
	edo.current_gesture = PlayerState.Gesture.SCISSORS
	nar.current_gesture = PlayerState.Gesture.ROCK
	gm.call("_resolve_round")
	_assert(gm.get("_sole_winner_id") == 0, "R3a: 跺脚强制判胜柱间获胜（实际=%d）" % gm.get("_sole_winner_id"))
	_assert(not edo.force_win_next_round, "R3b: force_win已消耗（实际=%s）" % str(edo.force_win_next_round))
	# UI/联机广播一致性：round_resolved 广播的胜者应为柱间（而非原始猜拳胜者鸣人）
	_assert(last_round_winners[0] == [0], "R3c: 强制判胜后广播胜者=柱间（实际=%s）" % str(last_round_winners[0]))

	print("=== 跺脚真实主循环测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)

func _find_skill_index(player: PlayerState, skill_name: String) -> int:
	var all := player.get_all_skills()
	for i in range(all.size()):
		if all[i].skill_name == skill_name:
			return i
	return -1

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass_count += 1
		print("PASS: " + msg)
	else:
		_fail_count += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)

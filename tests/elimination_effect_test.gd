## 淘汰特效冒烟测试
## 验证：_play_elimination_effect 触发后卡片动画正常播放，不崩溃、不阻塞游戏循环
## 检查点：
##   E1: 淘汰后卡片存在且不再移除
##   E2: 动画过程中 scale 发生变化（碎裂效果）
##   E3: 动画完成后卡片处于灰色淡化态
##   E4: 动画完成后 position 回正
##   E5: 游戏循环未被阻塞（另一玩家卡片正常刷新）
extends Node

var _pass_count: int = 0
var _fail_count: int = 0
var _ui: Control = null

func _ready() -> void:
	print("=== 淘汰特效冒烟测试 ===")
	await get_tree().process_frame

	var naruto_char := load("res://resources/characters/漩涡鸣人.tres") as CharacterData
	var sasuke_char := load("res://resources/characters/宇智波佐助.tres") as CharacterData
	var sakura_char := load("res://resources/characters/春野樱.tres") as CharacterData
	if naruto_char == null or sasuke_char == null or sakura_char == null:
		print("FATAL: 角色资源加载失败")
		get_tree().quit(1)
		return

	var gm := GameManager
	gm.setup_game({
		"players": [
			{"name": "鸣人", "character": naruto_char, "is_human": true},
			{"name": "佐助", "character": sasuke_char, "is_human": false},
			{"name": "樱",   "character": sakura_char, "is_human": false},
		]
	})
	await get_tree().process_frame

	_ui = (load("res://scenes/game_ui.tscn") as PackedScene).instantiate()
	add_child(_ui)
	await get_tree().process_frame
	# 手动构建玩家卡片（正常由 main.gd 调用）
	_ui.setup_players(gm.get_alive_players())
	await get_tree().process_frame
	_ui._human_player_id = 0

	# 记录原始 modulate 和 position
	var card_sasuke: Control = _ui._player_cards.get(1)
	var card_naruto: Control = _ui._player_cards.get(0)
	if card_sasuke == null or card_naruto == null:
		print("FATAL: 卡片不存在")
		get_tree().quit(1)
		return
	var orig_mod := card_sasuke.modulate
	var orig_pos := card_sasuke.position
	var orig_scale := card_sasuke.scale

	# 触发淘汰：佐助HP归零
	var sasuke: PlayerState = gm.get_player(1)
	sasuke.hp = 0.0
	gm.call("_check_elimination")
	await get_tree().process_frame

	# E1: 卡片仍然存在
	_assert(_ui._player_cards.get(1) != null, "E1: 淘汰后卡片仍然存在")

	# E2: 动画过程中检查 scale 变化（等0.35s——阶段2碎裂放大后）
	await get_tree().create_timer(0.38).timeout
	var mid_scale := card_sasuke.scale
	_assert(mid_scale != orig_scale, "E2: 动画中 scale 发生变化（%.2f → %.2f）" % [orig_scale.x, mid_scale.x])

	# E3: 等动画完成（总1.4s + 缓冲0.2s）
	await get_tree().create_timer(1.3).timeout
	var final_mod := card_sasuke.modulate
	var final_scale := card_sasuke.scale
	var final_pos := card_sasuke.position
	# 最终 modulate 应该是灰色（R<0.5）
	_assert(final_mod.r < 0.5 and final_mod.g < 0.5, "E3: 最终卡片变灰（modulate=%.2f,%.2f,%.2f）" % [final_mod.r, final_mod.g, final_mod.b])
	# 最终 scale 应该缩小
	_assert(final_scale.x < orig_scale.x, "E3b: 最终卡片缩小（%.2f → %.2f）" % [orig_scale.x, final_scale.x])

	# E4: position 应回正
	_assert(abs(final_pos.x - orig_pos.x) < 1.0 and abs(final_pos.y - orig_pos.y) < 1.0, "E4: position 回正（原=%.0f,%.0f 终=%.0f,%.0f）" % [orig_pos.x, orig_pos.y, final_pos.x, final_pos.y])

	# E5: 另一玩家（鸣人）卡片正常，游戏未崩溃
	var naruto_card: Control = _ui._player_cards.get(0)
	_assert(naruto_card != null and is_instance_valid(naruto_card), "E5a: 鸣人卡片正常存在")
	var hp_label: Label = naruto_card.get_node_or_null("HpText")
	_assert(hp_label != null and hp_label.text.contains("HP"), "E5b: 鸣人卡片HP标签正常（%s）" % (hp_label.text if hp_label else "?"))

	print("=== 淘汰特效冒烟测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass_count += 1
		print("PASS: " + msg)
	else:
		_fail_count += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)

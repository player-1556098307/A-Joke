## GameManager（自动加载）— 游戏主循环状态机
## 管理所有玩家、AI、加赛、行动结算、淘汰判定、延迟伤害、对局数据收集
## 通过20个信号驱动UI，UI不直接查询GameManager状态
extends Node

## 游戏阶段枚举：驱动整个游戏主循环的状态机
enum GamePhase {
	SETUP,               ## 初始化
	GESTURE_INPUT,       ## 等待玩家出拳
	RESOLVING,           ## 结算手势胜负
	TIEBREAK_INPUT,      ## 加赛出拳
	TIEBREAK_RESOLVING,  ## 加赛结算
	PREPARATION,         ## 准备阶段（猜拳赢家回合开始，所有有准备技能的玩家按逆时针轮询释放）
	ACTION_INPUT,        ## 等待胜者选择行动
	APPLYING,            ## 执行行动效果
	ELIMINATION,         ## 淘汰检测
	END_PHASE,           ## 回合结束前（钟结算+招架决策）
	ROUND_END,           ## 回合结束（触发延迟伤害）
	GAME_OVER            ## 游戏结束
}

## 阶段变化时发射
signal phase_changed(new_phase: GamePhase)
## 玩家提交手势后发射
signal gesture_submitted(player_id: int, gesture: PlayerState.Gesture)
## 回合结算完成时发射，包含胜负结果
signal round_resolved(result: Dictionary)
## 胜者需要进行行动选择时发射
signal action_required(player_id: int)
## 技能效果全部应用后发射，传递效果日志数组
signal skill_applied(logs: Array[Dictionary])
## 玩家充能后发射
signal player_charged(player_id: int, new_energy: int)
## 玩家被淘汰时发射
signal player_eliminated(player_id: int)
## 游戏结束时发射，传递胜者ID和对局记录
signal game_over(winner_id: int, record: MatchRecord)
## 加赛开始时发射，传递候选玩家ID列表
signal tiebreak_started(candidate_ids: Array[int])
## 加赛结束后发射，传递胜出者ID
signal tiebreak_resolved(winner_id: int)
## 玩家获得护盾时发射
signal player_shielded(player_id: int, shield_value: float)
## 玩家被麻痹时发射
signal player_paralyzed(player_id: int, turns: int)
## 玩家被击飞时发射
signal player_knocked_down(player_id: int, turns: int)
## 距离变化时发射
signal distance_changed(from_id: int, to_id: int, new_distance: int)
## 玩家因麻痹跳过出拳时发射
signal player_skipped(player_id: int)
## 延迟伤害触发时发射
signal delayed_damage_triggered(player_id: int, damage: float, remaining_hp: float)
## 影分身被破坏时发射
signal clone_destroyed(player_id: int)
## 技能解锁时发射
signal skill_unlocked(player_id: int, skill_name: String)
## 玩家获得钟时发射
signal bell_gained(player_id: int, bell_count: int)
## 玩家进入防反状态时发射
signal counter_stance_entered(player_id: int)
## 防反触发时发射
signal counter_stance_triggered(target_id: int, attacker_id: int)
## 防反状态结束时发射（自己下回合行动开始时）
signal counter_stance_ended(player_id: int)
## 玩家失去技能时发射
signal skill_disabled(player_id: int, turns: int)
## END_PHASE招架选择请求（UI弹确认框）
signal end_phase_bell_decision_required(player_id: int, bell_count: int)
## END_PHASE招架选择完成（UI/网络回传）
signal end_phase_bell_decision_made(player_id: int, use_bell: bool)

## ── 迈特凯专属信号 ───────────────────────────────────────────
## 玩家进入无敌状态
signal player_invincible(player_id: int, turns: int)
## 玩家进入燃烧状态
signal player_burning(player_id: int)
## 玩家进入狂战士状态
signal player_berserker(player_id: int)
## 八门计数变化
signal gate_changed(player_id: int, gate_count: int)
## 八门全开（第八门特效触发）
signal eighth_gate_opened(player_id: int)
## 玩家失去技能（永久移除）
signal skill_lost(player_id: int, skill_name: String)
## 血付决策完成（UI/网络回传）
signal hp_payment_made(player_id: int, hp_paid: float)
## 燃烧/狂战士扣血
signal burn_damage_triggered(player_id: int, damage: float, remaining_hp: float, reason: String)

## ── 波风水门专属信号 ───────────────────────────────────────────
## 飞雷神标记数量变化
signal ftg_marks_changed(player_id: int, marks: int)
## 飞雷神标记被施加
signal ftg_mark_applied(target_id: int, attacker_id: int)
## 飞雷神标记被拔除
signal ftg_mark_removed(player_id: int)
## 飞雷神换位触发
signal ftg_swap_triggered(swapper_id: int, swapped_id: int, original_target_id: int)
## 飞雷神闪避触发
signal ftg_dodge_triggered(player_id: int, attacker_id: int)
## 飞雷神拦截决策请求（UI弹窗：选择换位/闪避/不操作）
signal ftg_intercept_required(target_id: int, attacker_id: int, marked_player_ids: Array[int], attacker_is_marked: bool)
## 飞雷神拦截决策完成（UI/网络回传）
signal ftg_intercept_made(target_id: int, choice: int, swap_target_id: int)
## 闪避成功后是否释放螺旋丸反击的二次确认请求（仅人类玩家）
signal rasengan_counter_required(target_id: int, attacker_id: int, minato_energy: int)
## 闪避后反击决策完成（UI/网络回传）
signal rasengan_counter_made(target_id: int, use_counter: bool)
## 九尾阶段变化
signal nine_tails_stage_changed(player_id: int, stage: int)
## 九尾无敌开始
signal nine_tails_invincible_started(player_id: int)
## 九尾无敌结束
signal nine_tails_invincible_ended(player_id: int)
## 九尾攻击触发
signal nine_tails_attack(player_id: int, stage: int, damage: float, target_ids: Array[int])

## ── 卫宫（射手）专属信号 ─────────────────────────────────────────────
## 投影技能选择请求（UI弹窗：选目标玩家+选技能）
signal project_skill_required(player_id: int, target_ids: Array[int])
## 投影技能选择完成（UI/网络回传，skill_path 为被复制技能的资源路径）
signal project_skill_made(player_id: int, target_id: int, skill_path: String)
## 无限剑制结界开启
signal binding_field_started(player_id: int, turns: int, target_ids: Array[int])
## 无限剑制结界结束
signal binding_field_ended(player_id: int)
## 投影成功获得技能
signal projected_skill_gained(player_id: int, skill_name: String)
## 投影技能消失（投影技能用掉后）
signal projected_skill_lost(player_id: int, skill_name: String)

## ── 宇智波泉奈专属信号 ─────────────────────────────────────────────
## 荣耀解锁状态变化（true=已解锁, false=已使用待重新解锁）
signal glory_unlocked_changed(player_id: int, unlocked: bool)
## 荣耀夺取触发：行动权转移+伤害+封技
signal glory_takeover(caster_id: int, target_id: int, damage: float, absorbed: float, clone_broken: bool)
## 荣耀释放确认请求：准备阶段轮询到人类泉奈时发射，等待玩家选择是否释放
signal glory_required(player_id: int, target_id: int)
## 宇智波流招架状态进入
signal uchiha_stance_entered(player_id: int)
## 宇智波流触发（反击封技+无法选择）
signal uchiha_counter_triggered(target_id: int, attacker_id: int)

## ── 宇智波止水专属信号 ─────────────────────────────────────────────
## 日晕舞中断点选择请求（UI弹窗：选择1段后/2段后/不中断），仅人类玩家
signal hiano_interrupt_required(player_id: int, target_id: int, max_interrupt: int)
## 日晕舞中断点选择完成（UI/网络回传，interrupt_at 0=不中断 1/2=第N段后中断）
signal hiano_interrupt_made(player_id: int, interrupt_at: int)
## 须佐能乎·斩 释放：本回合无敌 + 延迟伤害已挂
signal susanoo_slash_used(player_id: int, damage: float)
## 须佐能乎·螺旋 释放：多段伤害+封技+解锁九十九
signal susanoo_spiral_used(player_id: int, target_id: int, hit_count: int)
## 须佐能乎·九十九 释放
signal susanoo_ninety_nine_used(player_id: int, target_id: int, hit_count: int)
## 别天神夺舍确认请求（UI弹窗：选择是否夺舍），仅人类
signal kotoamatsukami_required(player_id: int, target_id: int)
## 别天神夺舍确认完成（UI/网络回传，takeover=true=夺舍 false=放弃）
signal kotoamatsukami_made(player_id: int, takeover: bool)
## 别天神夺舍成功（转移角色、恢复半血、继承气）
signal kotoamatsukami_takeover(player_id: int, target_id: int)
## 夺舍体死亡，回退到夺舍前止水状态
signal takeover_reverted(player_id: int)

## ── 新止水（天劫）专属信号 ─────────────────────────────────────────────
## 别天神回溯确认请求（UI弹窗：选择是否回溯），仅人类玩家
signal backtrack_required(player_id: int)
## 别天神回溯确认完成（UI/网络回传，use_backtrack=true=回溯 false=跳过）
signal backtrack_made(player_id: int, use_backtrack: bool)
## 别天神回溯执行成功（恢复全体玩家状态）
signal backtrack_performed(player_id: int, round: int)
## 幻影数量变化
signal phantom_changed(player_id: int, phantom_count: int)
## 幻影闪避触发（消耗1气+1幻影，完全免疫本次伤害）
signal phantom_dodge_triggered(player_id: int, attacker_id: int)
## 幻影闪避决策请求（UI弹窗：选择是否消耗1气+1幻影闪避），仅人类玩家
signal phantom_dodge_required(player_id: int, attacker_id: int)
## 幻影闪避决策完成（UI/网络回传，dodge=true=闪避 false=不闪避）
signal phantom_dodge_made(player_id: int, dodge: bool)
## 日影舞释放：对指定玩家分配4段斩击
signal hiroari_used(player_id: int, target_ids: Array[int])
## 日影舞目标选择请求（UI弹窗：逐段选择4个目标，可重复），仅人类玩家
signal hiroari_targets_required(player_id: int, target_ids: Array[int])
## 日影舞目标选择完成（UI/网络回传，targets 为4个目标ID数组）
signal hiroari_targets_made(player_id: int, targets: Array[int])

## ── 黑塔专属信号 ───────────────────────────────────────────────
## 送你砖石触发：对范围内（距离≤1）的其他玩家各造成1点伤害
signal herta_diamond_triggered(player_id: int, target_ids: Array[int])

## ── 大黑塔专属信号 ───────────────────────────────────────────────
## 目标获得【解】标记（大黑塔伤害导致）
signal jiedu_applied(target_id: int, herta_id: int)
## 格局打开回气：【解】玩家受伤，大黑塔获得1气
signal open_mind_triggered(herta_id: int)
## 魔法释放：主目标+所有【解】玩家AOE
signal magic_used(caster_id: int, main_target_id: int)

## 所有玩家状态数组
var _players: Array[PlayerState] = []
## 当前游戏阶段
var _current_phase: GamePhase = GamePhase.SETUP
## 加赛候选玩家ID列表
var _tiebreak_candidates: Array[int] = []
## 猜拳唯一胜者（非加赛时为-1）
var _sole_winner_id: int = -1
## AI控制器实例
var _ai_controller: AIController
## 距离系统实例
var _distance_system: DistanceSystem

## 结算延时计时器（2秒过渡动画）
var _resolve_timer: Timer
## 对局数据记录
var _match_record: MatchRecord
## 当前回合编号
var _current_round_number: int = 0
## 前一个阶段（用于判断是否为新回合）
var _prev_phase: int = -1
## 当前回合快照
var _current_snapshot: RoundSnapshot
## 调试开关：AI强制出剪刀
var _debug_force_scissors: bool = false

## 联机模式标志（服务器设置为 true，关闭单机"人类死亡即结束"逻辑）
var _is_network_game: bool = false
## 慈悲尖塔模式标志（PvE组队：人类死亡不结束，队友可继续；敌人全灭=层胜利由外部管理器处理）
var _is_tower_mode: bool = false
## END_PHASE 招架决策队列（待决策的有钟玩家）
var _bell_decision_players: Array[PlayerState] = []
## 当前招架决策游标
var _bell_decision_index: int = 0
## 上回合行动胜者ID（用于追踪连续回合）
var _prev_winner_id: int = -1

## ── 飞雷神拦截状态 ──────────────────────────────────────────
## 飞雷神拦截选项枚举
enum FTGChoice { NONE = 0, SWAP = 1, DODGE = 2, SKIP = 3 }
## 闪避后反击决策（提交给 rasengan_counter_made 的 use_counter 使用）
enum FTGCounter { NO = 0, YES = 1 }
## 当前待处理的拦截上下文
var _ftg_pending: Dictionary = {}
## 拦截完成后回调的后续执行函数
var _ftg_resume_fn: Callable = Callable()

## ── 宇智波止水阶段状态 ──────────────────────────────────────────
## 日晕舞中断点选择枚举
enum HianoInterrupt { NONE = 0, AFTER_1 = 1, AFTER_2 = 2 }
## 日晕舞当前等待中断点决策的上下文（null=无进行中的日晕舞）
var _hiano_pending: Dictionary = {}
## 别天神夺舍待确认上下文（等待UI/网络选择是否夺舍）
var _koto_pending: Dictionary = {}

## ── 新止水（天劫）阶段状态 ──────────────────────────────────────────
## 回溯待确认上下文（等待UI/网络选择是否回溯）
var _backtrack_pending: Dictionary = {}
## 当前回合开始前的全体玩家快照（在猜拳结算后、进入准备阶段前拍摄）
## 用于新止水·别天神回溯：恢复上一行动玩家回合开始前的状态
## 格式：{ "winner_id": int, "round": int, "states": {pid: Dictionary}, "distance": Dictionary }
var _last_round_pre_snapshot: Dictionary = {}
## 上回合开始前的全体玩家快照（每次 _capture_round_pre_snapshot 时由 _last_round_pre_snapshot 滚动而来）
## 别天神回溯恢复的目标状态：撤销上一回合
## 格式：{ "winner_id": int, "round": int, "states": {pid: Dictionary}, "distance": Dictionary }
var _prev_round_pre_snapshot: Dictionary = {}
## 上回合的回合玩家ID（用于判断"上回合是否是自己回合"，决定回溯可用性）
var _prev_round_winner_id: int = -1
## 日影舞当前等待目标选择的上下文（null=无进行中的日影舞）
var _hiroari_pending: Dictionary = {}
## 日影舞目标选择枚举：4段各自的目标ID（-1=未选择）
var _hiroari_target_ids: Array[int] = [-1, -1, -1, -1]
## 幻影闪避待确认上下文（等待UI/网络选择是否闪避）
var _phantom_dodge_pending: Dictionary = {}

## ── 卫宫（射手）阶段状态 ──────────────────────────────────────────
## 准备阶段当前进行中的玩家ID（-1=无）
var _prep_current_player_id: int = -1
## 准备阶段当前玩家的待释放技能索引（-1=无）
var _prep_current_skill_index: int = -1
## 投影待定上下文（等待UI/网络选择目标与技能）
var _project_pending: Dictionary = {}

func _ready() -> void:
	_ai_controller = AIController.new()
	_resolve_timer = Timer.new()
	_resolve_timer.one_shot = true
	_resolve_timer.wait_time = 0.5  # 动画与流程解耦：0.5s后立即结算，动画照常播放
	_resolve_timer.timeout.connect(_on_resolve_timer_timeout)
	add_child(_resolve_timer)
	# 招架决策回调：UI/网络提交后继续推进队列
	end_phase_bell_decision_made.connect(_on_bell_decision_made)
	# 飞雷神拦截决策回调
	ftg_intercept_made.connect(_on_ftg_intercept_made)
	# 闪避后反击决策回调
	rasengan_counter_made.connect(_on_rasengan_counter_made)
	# 投影技能选择回调
	project_skill_made.connect(_on_project_skill_made)
	# 日晕舞中断点决策回调
	hiano_interrupt_made.connect(_on_hiano_interrupt_made)
	# 别天神夺舍决策回调
	kotoamatsukami_made.connect(_on_kotoamatsukami_made)
	# 别天神回溯决策回调
	backtrack_made.connect(_on_backtrack_made)
	# 幻影闪避决策回调
	phantom_dodge_made.connect(_on_phantom_dodge_made)
	# 日影舞目标选择回调
	hiroari_targets_made.connect(_on_hiroari_targets_made)

## 结算延时回调：2秒过渡动画后执行实际结算
func _on_resolve_timer_timeout() -> void:
	if _current_phase == GamePhase.RESOLVING:
		_resolve_round()
	elif _current_phase == GamePhase.TIEBREAK_RESOLVING:
		_resolve_tiebreak()

## 初始化游戏：创建玩家状态、距离系统、对局记录，进入首次出拳阶段
func setup_game(config: Dictionary) -> void:
	_players.clear()
	_tiebreak_candidates.clear()
	_sole_winner_id = -1
	_current_phase  = GamePhase.SETUP
	_current_round_number = 0
	_prev_winner_id = -1
	_prev_round_winner_id = -1
	_last_round_pre_snapshot = {}
	_prev_round_pre_snapshot = {}
	_is_tower_mode = config.get("tower_mode", false)

	var player_configs: Array = config["players"]
	for i in range(player_configs.size()):
		var pc: Dictionary = player_configs[i]
		var state := PlayerState.new(i, pc["name"], pc["character"], pc["is_human"])
		if pc.has("team_id"):
			state.team_id = pc["team_id"]
		_players.append(state)

	# 波风水门初始化飞雷神标记
	for p in _players:
		if _is_minato(p):
			p.ftg_marks = 3
			ftg_marks_changed.emit(p.player_id, 3)

	_distance_system = DistanceSystem.new()
	var seat_order: Array[int] = []
	for p in _players:
		seat_order.append(p.player_id)
	_distance_system.setup(seat_order)

	_debug_force_scissors = config.get("debug_force_scissors", false)
	# 尖塔祝福：拥有尖塔祝福技能的角色开局获得2个气
	for p in _players:
		if _has_tower_blessing(p):
			p.add_energy(2)
			player_charged.emit(p.player_id, p.energy)
	_init_match_record()
	_enter_phase.call_deferred(GamePhase.GESTURE_INPUT)

## ── 状态机 ─────────────────────────────────────────────────────────────────────
## 核心状态机入口：根据新阶段分派相应逻辑
func _enter_phase(phase: GamePhase) -> void:
	_prev_phase = _current_phase
	_current_phase = phase
	if phase == GamePhase.GESTURE_INPUT:
		if _prev_phase != GamePhase.RESOLVING and _prev_phase != GamePhase.TIEBREAK_RESOLVING:
			_current_round_number += 1
		_apply_paralyze()
	phase_changed.emit(phase)

	match phase:
		GamePhase.GESTURE_INPUT:      _process_ai_gestures()
		GamePhase.RESOLVING:          _resolve_timer.start()
		GamePhase.TIEBREAK_INPUT:     _start_tiebreak_input()
		GamePhase.TIEBREAK_RESOLVING: _resolve_timer.start()
		GamePhase.PREPARATION:        _start_preparation_phase()
		GamePhase.ACTION_INPUT:       _start_action_input()
		GamePhase.APPLYING:           _apply_actions()
		GamePhase.ELIMINATION:        _check_elimination()
		GamePhase.END_PHASE:         _process_end_phase()
		GamePhase.ROUND_END:          _end_round()
		GamePhase.GAME_OVER:          _finish_game()

## 应用麻痹：被麻痹的玩家自动出 SKIP，发射 player_skipped 信号
func _apply_paralyze() -> void:
	for player in _players:
		if player.is_alive and player.paralyze_turns > 0:
			player.current_gesture = PlayerState.Gesture.SKIP
			player_skipped.emit(player.player_id)

## 处理AI出拳：每个AI延时后提交手势（延时由SettingsManager决定）
func _process_ai_gestures() -> void:
	var delay := SettingsManager.get_ai_delay()
	var _has_human_alive := false
	for p in _players:
		if p.is_alive and p.is_human:
			_has_human_alive = true
			break
	for player in _players:
		if player.is_alive and not player.is_human and player.current_gesture == PlayerState.Gesture.NONE:
			var gesture := PlayerState.Gesture.SCISSORS if _debug_force_scissors and _has_human_alive else _ai_controller.decide_gesture(player)
			get_tree().create_timer(delay).timeout.connect(
				_delayed_submit_gesture.bind(player.player_id, gesture), CONNECT_ONE_SHOT)
	if _current_phase == GamePhase.GESTURE_INPUT and _all_gestures_submitted():
		_enter_phase(GamePhase.RESOLVING)

func _delayed_submit_gesture(pid: int, gesture: PlayerState.Gesture) -> void:
	if _current_phase == GamePhase.GESTURE_INPUT:
		submit_gesture(pid, gesture)

func _all_gestures_submitted() -> bool:
	for player in _players:
		if player.is_alive and player.current_gesture == PlayerState.Gesture.NONE:
			return false
	return true

func _all_tiebreak_gestures_submitted() -> bool:
	for id in _tiebreak_candidates:
		var player := get_player(id)
		if player != null and player.is_alive and player.current_gesture == PlayerState.Gesture.NONE:
			return false
	return true

## 结算本回合手势：调用 RoundResolver，处理平局/单胜/多加赛三种结果
func _resolve_round() -> void:
	var gestures: Dictionary = {}
	for player in _players:
		if player.is_alive:
			gestures[player.player_id] = player.current_gesture

	var result := RoundResolver.resolve_gestures(gestures)
	round_resolved.emit(result)
	_record_round_snapshot(result)

	# ── 反馈（司马懿）：猜拳未获得回合 → 获得1个怒标记（至多4）──
	var tower_winners: Array = result.get("winners", [])
	for p in _players:
		if p.is_alive and _tower_has_skill(p, "反馈") and not tower_winners.has(p.player_id) and p.fury_marks < 4:
			p.fury_marks += 1

	# ── 跺脚/无限剑制 强制判胜：force_win_next_round 的玩家直接成为唯一赢家 ──
	var force_win_id: int = -1
	for player in _players:
		if player.is_alive and player.force_win_next_round:
			force_win_id = player.player_id
			player.force_win_next_round = false
			break
	if force_win_id >= 0:
		# 清除其他玩家的手势，仅保留跺脚/无限剑制玩家为唯一赢家
		var force_result := { "winners": [force_win_id], "losers": [], "is_draw": false }
		_sole_winner_id = force_win_id
		var ws: PlayerMatchStats = _match_record.player_stats.get(_sole_winner_id)
		if ws:
			ws.win_count += 1
		_capture_round_pre_snapshot()
		_enter_phase(GamePhase.PREPARATION)
		return

	if result["is_draw"]:
		if result.get("all_skipped", false):
			for player in _players:
				if player.is_alive and player.paralyze_turns > 0:
					player.paralyze_turns -= 1
				player.reset_round_data()
			_enter_phase(GamePhase.GESTURE_INPUT)
		else:
			for player in _players:
				if player.is_alive:
					player.current_gesture = PlayerState.Gesture.NONE
			_enter_phase(GamePhase.GESTURE_INPUT)
	elif (result["winners"] as Array).size() == 1:
		_sole_winner_id = int((result["winners"] as Array)[0])
		var ws: PlayerMatchStats = _match_record.player_stats.get(_sole_winner_id)
		if ws:
			ws.win_count += 1
		_capture_round_pre_snapshot()
		_enter_phase(GamePhase.PREPARATION)
	else:
		_tiebreak_candidates.clear()
		for id in (result["winners"] as Array):
			_tiebreak_candidates.append(int(id))
		for player in _players:
			player.current_gesture = PlayerState.Gesture.NONE
		tiebreak_started.emit(_tiebreak_candidates)
		_enter_phase(GamePhase.TIEBREAK_INPUT)

## 启动加赛出拳阶段：AI延时提交加赛手势
func _start_tiebreak_input() -> void:
	var delay := SettingsManager.get_ai_delay()
	var _has_human_in_tiebreak := false
	for tid in _tiebreak_candidates:
		var tp := get_player(tid)
		if tp != null and tp.is_human:
			_has_human_in_tiebreak = true
			break
	for id in _tiebreak_candidates:
		var player := get_player(id)
		if player != null and player.is_alive and not player.is_human:
			var gesture := PlayerState.Gesture.SCISSORS if _debug_force_scissors and _has_human_in_tiebreak else _ai_controller.decide_gesture(player)
			get_tree().create_timer(delay).timeout.connect(
				_delayed_submit_tiebreak_gesture.bind(id, gesture), CONNECT_ONE_SHOT)

func _delayed_submit_tiebreak_gesture(pid: int, gesture: PlayerState.Gesture) -> void:
	if _current_phase == GamePhase.TIEBREAK_INPUT:
		submit_tiebreak_gesture(pid, gesture)

## 结算加赛手势：单胜者进入行动阶段，平局或仍多胜者继续加赛循环
func _resolve_tiebreak() -> void:
	var gestures: Dictionary = {}
	for id in _tiebreak_candidates:
		var player := get_player(id)
		if player != null and player.is_alive:
			gestures[id] = player.current_gesture

	var result := RoundResolver.resolve_gestures(gestures)

	# Record tiebreak snapshot
	var snap := RoundSnapshot.new()
	snap.round_number = _current_round_number
	snap.is_tiebreak = true
	for id in _tiebreak_candidates:
		var player := get_player(id)
		if player != null and player.is_alive:
			snap.gestures[id] = player.current_gesture
	snap.winners.assign(result.get("winners", []))
	snap.is_draw = result.get("is_draw", false)
	if not snap.is_draw:
		for id in snap.gestures:
			if not snap.winners.has(int(id)):
				snap.losers.append(int(id))
	for player in _players:
		var ss := PlayerStateSnapshot.new()
		ss.player_id = player.player_id
		ss.hp = player.hp
		ss.energy = player.energy
		ss.has_shield = (player.shield != 0)
		ss.paralyze_turns = player.paralyze_turns
		ss.knockdown_turns = player.knockdown_turns
		ss.is_alive = player.is_alive
		ss.bell_count = player.bell_count
		ss.counter_stance = player.counter_stance
		ss.skill_disabled_turns = player.skill_disabled_turns
		ss.gate_count = player.gate_count
		ss.invincible_turns = player.invincible_turns
		ss.burning = player.burning
		ss.berserker = player.berserker
		ss.consecutive_rounds = player.consecutive_rounds
		ss.lost_skills = player.lost_skills.duplicate()
		ss.ftg_marks = player.ftg_marks
		ss.ftg_marked_by = player.ftg_marked_by.duplicate()
		ss.nine_tails_stage = player.nine_tails_stage
		ss.nine_tails_invincible = player.nine_tails_invincible
		ss.max_energy = player.max_energy
		ss.stomp_active = player.stomp_active
		ss.force_win_next_round = player.force_win_next_round
		ss.glory_unlocked = player.glory_unlocked
		ss.untargetable_turns = player.untargetable_turns
		snap.player_states_after.append(ss)
	_match_record.round_snapshots.append(snap)
	_match_record.tiebreak_count += 1

	if result["is_draw"]:
		for id in _tiebreak_candidates:
			var player := get_player(id)
			if player != null:
				player.current_gesture = PlayerState.Gesture.NONE
		_enter_phase(GamePhase.TIEBREAK_INPUT)
	elif (result["winners"] as Array).size() == 1:
		_sole_winner_id = int((result["winners"] as Array)[0])
		var tws: PlayerMatchStats = _match_record.player_stats.get(_sole_winner_id)
		if tws:
			tws.tiebreak_win_count += 1
			tws.win_count += 1
		tiebreak_resolved.emit(_sole_winner_id)
		_capture_round_pre_snapshot()
		_enter_phase(GamePhase.PREPARATION)
	else:
		_tiebreak_candidates.clear()
		for id in (result["winners"] as Array):
			_tiebreak_candidates.append(int(id))
		for id in _tiebreak_candidates:
			var player := get_player(id)
			if player != null:
				player.current_gesture = PlayerState.Gesture.NONE
		tiebreak_started.emit(_tiebreak_candidates)
		_enter_phase(GamePhase.TIEBREAK_INPUT)

## ── 准备阶段（任意回合开始）──────────────────────────────────────────────
## 所有有准备阶段技能的玩家按"从回合主开始逆时针轮询"依次释放（每技能每回合一次，可跳过）
## 无准备技能或全部跳过时自动进入行动阶段
func _start_preparation_phase() -> void:
	_prep_current_player_id = -1
	_prep_current_skill_index = -1
	# 从回合主（_sole_winner_id）开始逆时针轮询
	var start_idx: int = _sole_winner_id
	var n: int = _players.size()
	var order: Array[PlayerState] = []
	for i in range(n):
		var pid: int = (start_idx + n - i) % n
		for p in _players:
			if p.is_alive and p.player_id == pid:
				order.append(p)
				break
	# 找到第一个有准备技能的玩家
	for p in order:
		if p.is_alive and _get_preparation_skill(p) != null:
			_prep_current_player_id = p.player_id
			_prep_current_skill_index = _get_preparation_skill_index(p)
			_begin_prep_player(p)
			return
	# 无玩家有准备技能，直接进入行动阶段
	_enter_phase(GamePhase.ACTION_INPUT)

## 获取玩家可用的准备阶段技能
## 目前支持：泉奈"荣耀"（在他人回合准备阶段自动触发，自动锁定回合主）+ 卫宫"投影"（自己回合）
## + 新止水"别天神（回溯）"（自己回合，上回合不是自己且快照存在）
## 气不足时视为不可用（否则 _process_prep_next 会无限轮回到该玩家导致栈溢出）
func _get_preparation_skill(player: PlayerState) -> SkillData:
	# 泉奈荣耀：仅在"其他玩家回合"（非自己回合）的准备阶段可触发
	# 荣耀被 get_all_skills 过滤，需直接查角色固有技能
	var glory := _get_skill_by_name(player, "宇智波的荣耀")
	if glory != null and player.player_id != _sole_winner_id \
	and player.glory_unlocked and not player.glory_used_this_round and player.energy >= 4:
		return glory
	# 卫宫投影：自己回合可用，每回合一次（荣耀夺取后回合主已变更，原回合主不再满足）
	var all := player.get_all_skills()
	for i in range(all.size()):
		var skill: SkillData = all[i]
		if skill.skill_name == "投影":
			if player.player_id != _sole_winner_id:
				continue
			# 投影：每回合仅一次；本回合已使用则跳过
			if player.projected_used_this_round:
				continue
			# 气不足：本回合无法释放投影，视为不可用
			if player.energy < skill.energy_cost:
				continue
			return skill
	# 新止水·别天神（回溯）：自己回合准备阶段可用
	# 条件：上回合不是自己回合（且存在上回合）+ 存在上回合快照 + 气>=1
	if player.player_id == _sole_winner_id \
	and _prev_round_winner_id >= 0 \
	and player.player_id != _prev_round_winner_id \
	and not _prev_round_pre_snapshot.is_empty():
		var backtrack := _get_skill_by_name(player, "别天神")
		if backtrack != null and _is_new_shisui(player) and player.energy >= backtrack.energy_cost:
			return backtrack
	return null

## 获取准备阶段技能在技能列表中的索引
func _get_preparation_skill_index(player: PlayerState) -> int:
	# 荣耀直接返回-1（由 _begin_prep_player 用技能名识别，不依赖列表索引）
	var glory := _get_skill_by_name(player, "宇智波的荣耀")
	if glory != null and player.player_id != _sole_winner_id \
	and player.glory_unlocked and not player.glory_used_this_round and player.energy >= 4:
		return -1
	var all := player.get_all_skills()
	for i in range(all.size()):
		if all[i].skill_name == "投影":
			return i
	# 新止水·别天神（回溯）：若在 get_all_skills 中则返回索引（被动技会被过滤，此时返回-1由 _begin_prep_player fallback）
	if player.player_id == _sole_winner_id \
	and _prev_round_winner_id >= 0 \
	and player.player_id != _prev_round_winner_id \
	and not _prev_round_pre_snapshot.is_empty() \
	and _is_new_shisui(player):
		for i in range(all.size()):
			if all[i].skill_name == "别天神":
				return i
		# 回溯技能被过滤（被动技），返回-1让 _begin_prep_player 按技能名 fallback
		var backtrack := _get_skill_by_name(player, "别天神")
		if backtrack != null:
			return -1
	return -1

## 处理指定玩家的准备阶段：人类弹窗 / AI 自动决策
func _begin_prep_player(player: PlayerState) -> void:
	var all: Array[SkillData] = player.get_all_skills()
	var idx: int = _prep_current_skill_index
	# 荣耀/回溯：idx=-1（不依赖列表索引），直接识别技能名
	var skill: SkillData = null
	if idx >= 0 and idx < all.size():
		skill = all[idx]
	else:
		skill = _get_skill_by_name(player, "宇智波的荣耀")
		if skill == null:
			skill = _get_skill_by_name(player, "别天神")
	# ── 泉奈荣耀：在他回合准备阶段触发，目标为回合主 ──
	if skill != null and skill.skill_name == "宇智波的荣耀":
		var target := get_player(_sole_winner_id)
		if player.is_human:
			# 人类玩家：弹窗选择是否释放荣耀
			glory_required.emit(player.player_id, target.player_id)
			return
		# AI：自动释放
		_apply_glory_takeover(player, target)
		_process_prep_next()
		return
	# ── 新止水·别天神（回溯）：自己回合准备阶段触发 ──
	if skill != null and skill.skill_name == "别天神" and _is_new_shisui(player):
		if player.is_human:
			# 人类玩家：弹窗选择是否回溯
			_backtrack_pending = { "player_id": player.player_id }
			backtrack_required.emit(player.player_id)
			return
		# AI：自动回溯
		_apply_backtrack(player)
		_process_prep_next()
		return
	if skill == null or skill.skill_name != "投影":
		_process_prep_next()
		return
	if player.energy < skill.energy_cost:
		_process_prep_next()
		return
	if player.is_human:
		# 人类玩家：弹窗选择目标玩家与技能
		var target_ids: Array[int] = []
		for p in get_alive_players():
			if p.player_id != player.player_id:
				target_ids.append(p.player_id)
		project_skill_required.emit(player.player_id, target_ids)
	else:
		# AI：自动决策
		var target := _best_ai_projection_target(player)
		if target == null:
			_process_prep_next()
			return
		var skill_path: String = _pick_ai_projected_skill(target)
		if skill_path == "":
			_process_prep_next()
			return
		_apply_projection(player, target, skill_path)
		_process_prep_next()

## 推进准备阶段：处理下一位玩家，全部结束后进入行动阶段
func _process_prep_next() -> void:
	var current: PlayerState = get_player(_prep_current_player_id)
	_prep_current_player_id = -1
	_prep_current_skill_index = -1
	if current == null or not current.is_alive:
		_enter_phase(GamePhase.ACTION_INPUT)
		return
	# 找到当前玩家之后的下一个有准备技能的玩家（逆时针继续）
	var start_idx: int = current.player_id
	var n: int = _players.size()
	for i in range(1, n + 1):
		var pid: int = (start_idx + n - i) % n
		var p := get_player(pid)
		if p != null and p.is_alive and _get_preparation_skill(p) != null:
			_prep_current_player_id = p.player_id
			_prep_current_skill_index = _get_preparation_skill_index(p)
			_begin_prep_player(p)
			return
	# 全部结束，进入行动阶段
	_enter_phase(GamePhase.ACTION_INPUT)

## AI 投影目标选择：优先选择技能多的存活玩家
func _best_ai_projection_target(player: PlayerState) -> PlayerState:
	var best: PlayerState = null
	var best_count: int = -1
	for p in get_alive_players():
		if p.player_id == player.player_id:
			continue
		var cnt: int = p.get_all_skills().size()
		if cnt > best_count:
			best_count = cnt
			best = p
	return best

## AI 投影技能选择：从目标技能库中随机选一个可用的
func _pick_ai_projected_skill(target: PlayerState) -> String:
	var all := target.get_all_skills()
	if all.is_empty():
		return ""
	var chosen: SkillData = all[randi() % all.size()]
	return chosen.resource_path

## 执行投影：将目标玩家的技能副本赋予施法者
func _apply_projection(player: PlayerState, target: PlayerState, skill_path: String) -> void:
	if player == null or target == null or skill_path == "":
		return
	var skill_res := load(skill_path) as SkillData
	if skill_res == null:
		return
	# 消耗投影能量（投影耗气1）
	var proj_skill := _get_skill_by_name(player, "投影")
	var cost: int = proj_skill.energy_cost if proj_skill != null else 1
	player.energy = max(0, player.energy - cost)
	player_charged.emit(player.player_id, player.energy)
	player.projected_skill = skill_res
	# 本回合已使用投影（每技能每回合一次）
	player.projected_used_this_round = true
	projected_skill_gained.emit(player.player_id, skill_res.skill_name)

## ── 无限剑制：开启结界 ──────────────────────────────────────────────
## 释放瞬间：下次猜拳必赢（force_win_next_round）+ 锁定距离1以内的敌人 + 结界持续5全局回合
## 结界内敌人的技能（含被动技）以原耗气、可重复使用出现在卫宫技能列表中
func _start_binding_field(caster: PlayerState) -> void:
	if caster == null:
		return
	caster.binding_field_turns = 6  # 释放回合+之后5回合=共6回合生效
	caster.binding_field_force_win = true
	# 下次猜拳必赢：复用跺脚机制
	caster.force_win_next_round = true
# 锁定释放瞬间距离1以内的敌人（动态范围不追踪，按释放瞬间锁定）
	var locked: Array[int] = []
	for p in _players:
		if not p.is_alive or p.player_id == caster.player_id:
			continue
		var dist: int = _distance_system.get_distance(caster.player_id, p.player_id)
		if dist <= 1:
			locked.append(p.player_id)
	caster.binding_field_targets = locked
	# 收集结界内敌人的技能（含被动技）副本到卫宫技能列表
	# 规则：遍历角色全部技能（含被动），排除招架（含COUNTER_STANCE效果）与"投影"（避免套娃复制投影）
	caster.binding_field_skills.clear()
	for pid in locked:
		var p := get_player(pid)
		if p == null:
			continue
		for s in p.character.skills:
			if _is_prep_excluded_skill(s):
				continue
			caster.binding_field_skills.append(s)
		# 运行时解锁技能（如秽土柱间升级获得的技能）也纳入结界
		for s in p.unlocked_skills:
			if _is_prep_excluded_skill(s):
				continue
			caster.binding_field_skills.append(s)
	binding_field_started.emit(caster.player_id, 6, locked)

## 判断技能是否不适合被投影/结界复制：招架（含COUNTER_STANCE效果）与"投影"自身
func _is_prep_excluded_skill(skill: SkillData) -> bool:
	if skill.skill_name == "投影":
		return true
	for effect in skill.effects:
		if effect.effect_type == SkillEffect.EffectType.COUNTER_STANCE:
			return true
	return false

## 投影技能选择回调（UI/网络提交后执行）
func _on_project_skill_made(player_id: int, target_id: int, skill_path: String) -> void:
	if _current_phase != GamePhase.PREPARATION:
		return
	var player := get_player(player_id)
	if player == null:
		_process_prep_next()
		return
	# 无论投影还是跳过，本回合投影已处理（每技能每回合一次）
	player.projected_used_this_round = true
	if target_id < 0 or skill_path == "":
		# 跳过投影
		_process_prep_next()
		return
	var target := get_player(target_id)
	if target == null:
		_process_prep_next()
		return
	_apply_projection(player, target, skill_path)
	_process_prep_next()

## 人类玩家投影决策提交入口（由UI/网络主机调用）
## target_id < 0 或 skill_path 为空表示跳过投影
func submit_project_skill(player_id: int, target_id: int, skill_path: String) -> void:
	project_skill_made.emit(player_id, target_id, skill_path)

## 启动行动选择阶段：人类玩家显示UI，AI自动决策
func _start_action_input() -> void:
	var winner := get_player(_sole_winner_id)
	print("[GameManager] _start_action_input _sole_winner_id=%d winner=%s is_human=%s" % [_sole_winner_id, winner.player_name if winner else "null", winner.is_human if winner else "N/A"])
	if winner == null or not winner.is_alive:
		print("[GameManager] _start_action_input: winner dead/null, skipping to APPLYING")
		_enter_phase(GamePhase.APPLYING)
		return

	# 防反状态：触发后已在结算时取消；此处清理未触发而残留到下回合开始的防反
	if winner.counter_stance:
		winner.counter_stance = false
		counter_stance_ended.emit(winner.player_id)
	# 宇智波流招架状态：与防反一致，自己的下个回合开始时清除
	if winner.uchiha_stance:
		winner.uchiha_stance = false

	# 连续回合追踪：如果本回合胜者与上回合相同则+1，否则重置为1
	if _sole_winner_id == _prev_winner_id:
		winner.consecutive_rounds += 1
	else:
		winner.consecutive_rounds = 1
	_prev_winner_id = _sole_winner_id

	# 慈悲尖塔 buff：回生 — 自己回合开始时回复 regen_per_round 点 HP
	_process_tower_regen(winner)

	# 鬼才（司马懿）：连续获得两回合时，额外获得一个回合（下回合强制判胜）
	_process_genius(winner)

	action_required.emit(_sole_winner_id)

	if not winner.is_human:
		var decision := _ai_controller.decide_action(winner, get_alive_players(), _distance_system)
		print("[GameManager] _start_action_input: AI winner auto-decides action=%d skill=%d target=%d" % [decision["action"], decision["skill_index"], decision["target_id"]])
		submit_action(_sole_winner_id, decision["action"], decision["skill_index"], decision["target_id"])

## 慈悲尖塔 buff：回生 — 行动权拥有者自己回合开始时回复 regen_per_round 点 HP
func _process_tower_regen(player: PlayerState) -> void:
	if player == null or not player.is_alive or player.regen_per_round <= 0 or player.hp <= 0:
		return
	var heal: float = min(player.regen_per_round, player.get_max_hp() - player.hp)
	if heal > 0:
		player.hp += heal
		burn_damage_triggered.emit(player.player_id, -heal, player.hp, "回生")

## 执行胜者行动：CHARGE充能（含影分身加成）或 USE_SKILL释放技能
func _apply_actions() -> void:
	var winner := get_player(_sole_winner_id)
	if winner == null or not winner.is_alive:
		_enter_phase(GamePhase.ELIMINATION)
		return

	# 击飞状态：强制只能聚气（覆盖玩家/AI提交的行动）
	if winner.knockdown_turns > 0:
		winner.pending_action = PlayerState.ActionType.CHARGE
		winner.pending_skill_index = -1
		winner.skill_target_id = -1
		winner.knockdown_consumed_this_round = true

	match winner.pending_action:
		PlayerState.ActionType.CHARGE:
			# 影分身存在时聚气加成 +2，否则 +1
			var gain: int = 1 + winner.clone_count
			# 仙人之力（仙人鸣人）：聚气额外+1
			# 注意：不能用"仙人之力"技能名判断——秽土柱间也有同名被动（跺脚+气上限6），会误判给柱间加聚气
			if _tower_has_skill(winner, "蛙组手"):
				gain += 1
			# ── 慈悲尖塔 buff：蓄锐每回合额外聚气 ──
			gain += winner.charge_bonus
			winner.add_energy(gain)
			player_charged.emit(_sole_winner_id, winner.energy)
			var cs: PlayerMatchStats = _match_record.player_stats.get(_sole_winner_id)
			if cs:
				cs.charge_count += 1
			# 八门遁甲：聚气后自动开门
			_process_gate_open(winner)
			# 泉奈·荣耀解锁：聚气达到4时自动解锁（消耗4气；使用后需再次聚气4解锁）
			_process_glory_unlock(winner)
			# Record charge action in replay snapshot
			if _current_snapshot:
				var alog := ActionLog.new()
				alog.actor_id = winner.player_id
				alog.action_type = PlayerState.ActionType.CHARGE
				alog.skill_name = "聚气"
				_current_snapshot.actions.append(alog)

		PlayerState.ActionType.USE_SKILL:
			var all_skills := winner.get_all_skills()
			var skill_idx  := winner.pending_skill_index
			if skill_idx < 0 or skill_idx >= all_skills.size():
				_enter_phase(GamePhase.ELIMINATION)
				return
			var skill: SkillData = all_skills[skill_idx]

			# 血付机制：可血付技能气不足时，用HP补足气（在能量校验前执行）
			if skill.can_pay_with_hp and winner.pending_hp_payment > 0 \
			and winner.energy < skill.energy_cost:
				var hp_pay: float = winner.pending_hp_payment
				hp_pay = mini(hp_pay, winner.hp - 1.0)  # 不能血付致死
				hp_pay = mini(hp_pay, skill.energy_cost - winner.energy)  # 不能超过缺口
				if hp_pay > 0:
					winner.hp -= hp_pay
					winner.add_energy(int(hp_pay))  # 血付部分补足气
					hp_payment_made.emit(winner.player_id, hp_pay)
				winner.pending_hp_payment = 0

			if winner.energy < skill.energy_cost or winner.bell_count < skill.bell_cost:
				_enter_phase(GamePhase.ELIMINATION)
				return

			# 明神门：限定技获得2气（在技能效果前执行，因为效果里有禁锢需要射程）
			if skill.skill_name == "明神门":
				winner.add_energy(2)
				player_charged.emit(_sole_winner_id, winner.energy)

			# ── 迈特凯技能特殊处理 ──────────────────────────────────
			# 夜凯→双龙戏珠：有分身时自动替换为双龙戏珠
			if skill.skill_name == "夜凯" and winner.clone_count > 0:
				skill = _get_skill_by_name(winner, "双龙戏珠")
				if skill == null:
					skill = all_skills[skill_idx]  # fallback to original
			# 有分身时不能再放分身
			if skill.skill_name == "分身" and winner.clone_count > 0:
				_enter_phase(GamePhase.ELIMINATION)
				return
			# 夕象连续回合增伤：伤害 +（consecutive_rounds - 1）
			# 在技能效果的value上叠加增伤
			if skill.skill_name == "夕象":
				var bonus := winner.consecutive_rounds - 1
				if bonus > 0:
					skill = _copy_skill_with_bonus(skill, bonus)

			# ── 秽土柱间技能升级（气>=4时自动升级）──
			if skill.skill_name == "仙法·树界降诞" and winner.energy >= 4:
				var upgraded := _get_skill_by_name(winner, "仙法·花树界降临")
				if upgraded:
					skill = upgraded
			elif skill.skill_name == "木人之术" and winner.energy >= 4:
				var upgraded := _get_skill_by_name(winner, "木龙之术")
				if upgraded:
					skill = upgraded

			# ── 跺脚触发：普攻使用后激活跺脚（本回合+下回合受击触发）──
			if skill.skill_name == "普攻" and _is_edo_hashirama(winner):
				winner.stomp_active = 2

			# ── 新止水·幻影瞬身：普攻伤害加成（每个幻影+0.5）──
			# 通过技能副本叠加伤害，不修改原始资源
			if skill.skill_name == "普攻" and _is_new_shisui(winner) and winner.phantom_count > 0:
				var phantom_bonus: float = 0.5 * winner.phantom_count
				skill = _copy_skill_with_float_bonus(skill, phantom_bonus)

			var targets       := _build_skill_targets(winner, skill)
			var splash_targets := _build_splash_targets(winner, skill)

			# ── 宇智波止水技能特殊处理 ──────────────────────────────
			# 日晕舞：预选中断点（人类弹窗/AI自动），中断后衔接九十九
			# 斩/螺旋/九十九：多段伤害+无敌/封技/解锁，由 GameManager 直接结算
			if skill.skill_name == "宇智波流·日晕舞":
				# 消耗能量（与 apply_effects 一致）
				winner.energy -= skill.energy_cost
				player_charged.emit(winner.player_id, winner.energy)
				var main_target: PlayerState = targets[0] if targets.size() > 0 else null
				if main_target == null:
					_enter_phase(GamePhase.ELIMINATION)
					return
				# 保存上下文并请求中断点决策（人类弹窗 / AI自动）
				_hiano_pending = { "player_id": winner.player_id, "target_id": main_target.player_id, "skill": skill }
				_request_hiano_interrupt(winner, main_target)
				return
			elif skill.skill_name == "须佐能乎·斩":
				var slash_target: PlayerState = targets[0] if targets.size() > 0 else null
				if slash_target == null:
					_enter_phase(GamePhase.ELIMINATION)
					return
				# 本回合无敌 + 延迟2伤（回合结束结算）+ 解锁螺旋
				winner.energy -= skill.energy_cost
				player_charged.emit(winner.player_id, winner.energy)
				_process_susanoo_slash(winner, slash_target)
				_enter_phase(GamePhase.ELIMINATION)
				return
			elif skill.skill_name == "须佐能乎·螺旋":
				var s_target: PlayerState = targets[0] if targets.size() > 0 else null
				if s_target == null:
					_enter_phase(GamePhase.ELIMINATION)
					return
				winner.energy -= skill.energy_cost
				player_charged.emit(winner.player_id, winner.energy)
				_process_susanoo_spiral(winner, s_target)
				_enter_phase(GamePhase.ELIMINATION)
				return
			elif skill.skill_name == "须佐能乎·九十九":
				var n_target: PlayerState = targets[0] if targets.size() > 0 else null
				if n_target == null:
					_enter_phase(GamePhase.ELIMINATION)
					return
				winner.energy -= skill.energy_cost
				player_charged.emit(winner.player_id, winner.energy)
				_process_susanoo_ninety_nine(winner, n_target)
				_enter_phase(GamePhase.ELIMINATION)
				return
			# ── 新止水·日影舞：拥有3个幻影时消耗3气，分配4段斩击（每段2伤）──
			elif skill.skill_name == "日影舞":
				if winner.phantom_count < 3:
					_enter_phase(GamePhase.ELIMINATION)
					return
				winner.energy -= skill.energy_cost
				player_charged.emit(winner.player_id, winner.energy)
				# 每段独立指定目标（可重复），人类弹窗 / AI自动分配
				_hiroari_pending = { "player_id": winner.player_id, "skill": skill }
				_hiroari_target_ids = [-1, -1, -1, -1]
				_request_hiroari_targets(winner)
				return
			# ── 大黑塔·魔法：主目标2伤 + 所有【解】玩家1伤（含主目标）──
			elif skill.skill_name == "魔法":
				var magic_target: PlayerState = targets[0] if targets.size() > 0 else null
				if magic_target == null:
					_enter_phase(GamePhase.ELIMINATION)
					return
				winner.energy -= skill.energy_cost
				player_charged.emit(winner.player_id, winner.energy)
				var logs_m: Array[Dictionary] = []
				# 主目标 2 伤（解读增伤在吸收链内处理）
				var e_main := SkillEffect.new()
				e_main.effect_type = SkillEffect.EffectType.DAMAGE
				e_main.value = 2.0
				e_main.target = SkillEffect.EffectTarget.ENEMY_SINGLE
				var res_main := RoundResolver.apply_effect_standalone(e_main, winner, magic_target, _distance_system)
				logs_m.append({
					"attacker_id": winner.player_id,
					"target_id":   magic_target.player_id,
					"effect_type": SkillEffect.EffectType.DAMAGE,
					"value":       2.0,
					"result":      res_main,
				})
				# 解读标记处理（主目标受伤后可能刚获得【解】）
				_process_bigherta_effects(winner, logs_m)
				# AOE：所有【解】玩家各1伤（含主目标，此时主目标可能刚被标记）
				var aoe_logs_m: Array[Dictionary] = []
				for p in get_alive_players():
					if p.player_id == winner.player_id:
						continue
					if p.jiedu_by.is_empty():
						continue
					var e_aoe := SkillEffect.new()
					e_aoe.effect_type = SkillEffect.EffectType.DAMAGE
					e_aoe.value = 1.0
					e_aoe.target = SkillEffect.EffectTarget.ENEMY_SINGLE
					var res_aoe := RoundResolver.apply_effect_standalone(e_aoe, winner, p, _distance_system)
					aoe_logs_m.append({
						"attacker_id": winner.player_id,
						"target_id":   p.player_id,
						"effect_type": SkillEffect.EffectType.DAMAGE,
						"value":       1.0,
						"result":      res_aoe,
					})
				# AOE 伤害同样处理解读标记+格局打开（新标记的玩家被AOE打）
				_process_bigherta_effects(winner, aoe_logs_m)
				logs_m.append_array(aoe_logs_m)
				magic_used.emit(winner.player_id, magic_target.player_id)
				# 通用收尾：标记伤害/信号/记录
				_finalize_shisui_use(winner, skill, logs_m)
				_enter_phase(GamePhase.ELIMINATION)
				return
			# ── 蛙组手（仙人鸣人）：必中，2点真实伤害（跳过闪避/拦截）──
			elif skill.skill_name == "蛙组手":
				var frog_target: PlayerState = targets[0] if targets.size() > 0 else null
				if frog_target == null:
					_enter_phase(GamePhase.ELIMINATION)
					return
				winner.energy -= skill.energy_cost
				player_charged.emit(winner.player_id, winner.energy)
				# 必中真实伤害：TRUE_DAMAGE 走吸收链（受无敌/防反影响），但必中跳过闪避/拦截
				var e_frog := SkillEffect.new()
				e_frog.effect_type = SkillEffect.EffectType.TRUE_DAMAGE
				e_frog.value = 2.0
				e_frog.target = SkillEffect.EffectTarget.ENEMY_SINGLE
				var res_frog := RoundResolver.apply_effect_standalone(e_frog, winner, frog_target, _distance_system)
				var frog_logs: Array[Dictionary] = [{
					"attacker_id": winner.player_id,
					"target_id":   frog_target.player_id,
					"effect_type": SkillEffect.EffectType.TRUE_DAMAGE,
					"value":       2.0,
					"result":      res_frog,
				}]
				_finalize_shisui_use(winner, skill, frog_logs)
				_enter_phase(GamePhase.ELIMINATION)
				return

			# ── 飞雷神拦截检查 ──────────────────────────────────────
			# 检查目标中是否有波风水门且可触发换位/闪避
			var ftg_result := _check_ftg_intercept(winner, skill, targets)
			if ftg_result.has("pending"):
				# 需要等待水门玩家决策，暂存上下文，延迟执行 apply_effects
				_ftg_pending = {
					"winner": winner,
					"skill": skill,
					"targets": targets,
					"splash_targets": splash_targets,
				}
				return  # 等待 ftg_intercept_made 信号回调 _resume_ftg_action
			# 无需拦截或AI自动决策已完成，targets 可能已被修改
			if _ftg_pending.has("targets"):
				targets = _ftg_pending["targets"]
				_ftg_pending.clear()

			# ── 新止水·幻影瞬身闪避拦截检查 ────────────────────────
			# 目标中有可闪避的新止水时，暂存上下文，等待决策后恢复
			var phantom_dodge_result := _check_phantom_dodge_intercept(winner, skill, targets)
			if phantom_dodge_result.has("pending"):
				_phantom_dodge_pending = {
					"winner": winner,
					"skill": skill,
					"targets": targets,
					"splash_targets": splash_targets,
				}
				return  # 等待 phantom_dodge_made 信号回调 _resume_phantom_dodge_action
			# 无需拦截或AI自动决策已完成，targets 可能已被修改
			if _phantom_dodge_pending.has("targets"):
				targets = _phantom_dodge_pending["targets"]
				_phantom_dodge_pending.clear()

			# 黑塔：记录结算前HP快照（用于砖石50%阈值判定）
			var herta_hp_before: Dictionary = {}
			if _is_herta(winner):
				for p in _players:
					if p.is_alive:
						herta_hp_before[p.player_id] = p.hp
			# 破败王者之刃：记录普攻结算前目标HP（阶段1的50%伤害依据）
			var blade_hp_before: Dictionary = {}
			if skill.skill_name == "普攻" and _tower_has_skill(winner, "破败王者之刃"):
				for t in targets:
					blade_hp_before[t.player_id] = t.hp
			var logs := RoundResolver.apply_effects(winner, skill, targets, _distance_system, splash_targets)

			# ── 新止水·幻影瞬身：普攻命中后获得1幻影（至多3）──
			# 命中判定：普攻对目标造成了实际伤害（非无敌/护盾全挡/闪避）
			if skill.skill_name == "普攻" and _is_new_shisui(winner) and winner.phantom_count < 3:
				var phantom_hit := false
				for entry in logs:
					var res: Dictionary = entry.get("result", {})
					if res.get("damage_dealt", 0) > 0:
						phantom_hit = true
						break
				if phantom_hit:
					winner.phantom_count += 1
					phantom_changed.emit(winner.player_id, winner.phantom_count)

			# 双龙戏珠后效：分身消失 + 与夜凯共用限定技名额
			if skill.skill_name == "双龙戏珠":
				winner.clone_count = 0
				clone_destroyed.emit(winner.player_id)
				# 双龙戏珠与夜凯共用限定技名额
				if not "夜凯" in winner.limited_skills_used:
					winner.limited_skills_used.append("夜凯")

			# ── 波风水门·漂泊九尾处理 ──────────────────────────────
			if skill.skill_name == "漂泊九尾":
				_process_nine_tails_release(winner)

			# ── 秽土柱间·真数千手后效：本回合无敌 ─────────────────
			if skill.skill_name == "仙法·真数千手":
				winner.invincible_turns = 1
				player_invincible.emit(winner.player_id, 1)

			# ── 跺脚受击触发检查 ────────────────────────────────
			# 技能效果应用后，检查所有受击者是否有跺脚激活
			_process_stomp_trigger(winner, logs)

			# 标记造成伤害（用于钟获取）——消耗钟的技能（如砸钟）伤害不计入，防止砸钟回钟
			if skill.bell_cost <= 0:
				for entry in logs:
					if entry.get("effect_type", -1) == SkillEffect.EffectType.DAMAGE \
					or entry.get("effect_type", -1) == SkillEffect.EffectType.TRUE_DAMAGE \
					or entry.get("effect_type", -1) == SkillEffect.EffectType.FTG_MARK \
					or entry.get("effect_type", -1) == SkillEffect.EffectType.PIERCE_DAMAGE \
					or entry.get("effect_type", -1) == SkillEffect.EffectType.DEATH_SENTENCE:
						var res: Dictionary = entry.get("result", {})
						if res.get("damage_dealt", 0) > 0:
							winner.dealt_damage_this_round = true
							break
			for entry in logs:
				_emit_effect_signals(entry)
			skill_applied.emit(logs)
			player_charged.emit(_sole_winner_id, winner.energy)
			_record_action(winner, skill, logs)

			# ── 卫宫·投影技能使用后消失 ────────────────────────────
			# 投影技能是一次性的：使用后立即从技能列表中移除
			if winner.projected_skill != null and skill.skill_name == winner.projected_skill.skill_name:
				var lost_name: String = winner.projected_skill.skill_name
				winner.projected_skill = null
				winner.projected_used_this_round = false
				projected_skill_lost.emit(winner.player_id, lost_name)

			# ── 泉奈·荣耀使用 ─────────────────────────────────────
			# 荣耀在准备阶段触发（行动权转移），此处仅标记"本回合已使用"防止重复
			if skill.skill_name == "宇智波的荣耀":
				winner.glory_used_this_round = true

			# ── 卫宫·无限剑制开启 ──────────────────────────────────
			# 释放瞬间：下次猜拳必赢 + 锁定距离1以内的敌人 + 结界持续5全局回合
			if skill.skill_name == "无限剑制":
				_start_binding_field(winner)

			# ── 黑塔被动：genjutsu 距离-1 + 送你砖石 AOE（含连锁）──
			if _is_herta(winner):
				_process_herta_passives(winner, logs, herta_hp_before, [])

			# ── 大黑塔被动：解读标记 + 格局打开（任何来源受伤都检查）──
			_process_bigherta_effects(winner, logs)

			# ── 尖塔敌人普攻机制：破败王者之刃 + 反馈 ──
			if skill.skill_name == "普攻":
				var hit_target: PlayerState = null
				for entry in logs:
					if entry.get("effect_type", -1) == SkillEffect.EffectType.DAMAGE:
						var res: Dictionary = entry.get("result", {})
						if res.get("damage_dealt", 0) > 0:
							hit_target = get_player(entry.get("target_id", -1))
							break
				if hit_target != null and hit_target.is_alive:
					var bhp: float = float(blade_hp_before.get(hit_target.player_id, -1.0))
					_process_blade_of_the_fallen(winner, hit_target, bhp)
					_process_fury_burst(winner, hit_target)

	_enter_phase(GamePhase.ELIMINATION)

## 构建技能目标列表：ENEMY_ALL 取全部敌人，ENEMY_SINGLE 取指定目标
## 无法选择状态（untargetable_turns>0）的玩家不能被任何技能指定为目标
func _build_skill_targets(attacker: PlayerState, skill: SkillData) -> Array[PlayerState]:
	var has_enemy_all    := false
	var has_enemy_single := false
	for effect in skill.effects:
		if effect.target == SkillEffect.EffectTarget.ENEMY_ALL:
			has_enemy_all = true
		elif effect.target == SkillEffect.EffectTarget.ENEMY_SINGLE:
			has_enemy_single = true

	var targets: Array[PlayerState] = []
	if has_enemy_all:
		# ENEMY_ALL 默认包含所有其他存活玩家（含队友）
		# 真数千手用此机制打全场，施法者自身通过技能后效无敌免疫伤害
		# 注：友伤（队友被AOE波及）是游戏设定，不排除同队
		for p in _players:
			if p.is_alive and p.player_id != attacker.player_id:
				# 无法选择状态：不能被任何技能指定为目标（ENEMY_ALL 同样排除）
				if p.untargetable_turns > 0:
					continue
				targets.append(p)
	elif has_enemy_single:
		var tgt := get_player(attacker.skill_target_id)
		if tgt != null and tgt.is_alive:
			# 无法选择状态：技能无法指定该玩家为目标
			if tgt.untargetable_turns > 0:
				return targets
			targets.append(tgt)
	return targets

## 构建溅射目标列表：取主目标周围 splash_range 距离内的其他敌人
## 无法选择状态（untargetable_turns>0）的玩家不被溅射波及
func _build_splash_targets(attacker: PlayerState, skill: SkillData) -> Array[PlayerState]:
	var splash_range := 1
	var has_splash   := false
	for effect in skill.effects:
		if effect.target == SkillEffect.EffectTarget.ENEMY_SPLASH:
			has_splash   = true
			splash_range = effect.splash_range
			break
	if not has_splash:
		return []

	var main_target := get_player(attacker.skill_target_id)
	if main_target == null:
		return []

	var splash: Array[PlayerState] = []
	for p in _players:
		if not p.is_alive:
			continue
		if p.player_id == attacker.player_id or p.player_id == main_target.player_id:
			continue
		var dist: int = _distance_system.get_distance(main_target.player_id, p.player_id)
		if dist <= splash_range and p.untargetable_turns <= 0:
			splash.append(p)
	return splash

## 根据效果类型发射对应信号（护盾/麻痹/距离/影分身/解锁技能/失去技能/防反）
func _emit_effect_signals(entry: Dictionary) -> void:
	var res: Dictionary = entry.get("result", {})
	match entry.get("effect_type", -1):
		SkillEffect.EffectType.DAMAGE:
			if res.get("clone_destroyed", false):
				clone_destroyed.emit(entry["target_id"])
			if res.get("counter_stance_triggered", false):
				counter_stance_triggered.emit(entry["target_id"], entry.get("attacker_id", -1))
				counter_stance_ended.emit(entry["target_id"])  # 防反触发后取消招架状态
			if res.get("uchiha_counter_triggered", false):
				uchiha_counter_triggered.emit(entry["target_id"], entry.get("attacker_id", -1))
		SkillEffect.EffectType.SHIELD:
			player_shielded.emit(entry["target_id"], res.get("shield_value", 0))
		SkillEffect.EffectType.CLONE_SHIELD:
			# 影分身不发射 player_shielded（否则 UI 会把 shield 字段误设为 -1 全挡护盾）
			# 影分身的显示由 skill_applied 日志和 clone_count 徽章驱动
			pass
		SkillEffect.EffectType.PARALYZE:
			if not res.get("counter_immune", false):
				player_paralyzed.emit(entry["target_id"], res.get("turns", 0))
		SkillEffect.EffectType.KNOCKDOWN:
			if not res.get("counter_immune", false):
				player_knocked_down.emit(entry["target_id"], res.get("knockdown_turns", 0))
		SkillEffect.EffectType.CHANGE_DISTANCE:
			distance_changed.emit(
				entry.get("attacker_id", -1),
				entry["target_id"],
				res.get("new_distance", 0)
			)
		SkillEffect.EffectType.UNLOCK_SKILL:
			var sname: String = res.get("skill_name", "")
			if sname != "":
				skill_unlocked.emit(entry["target_id"], sname)
		SkillEffect.EffectType.DISABLE_SKILL:
			if not res.get("counter_immune", false):
				skill_disabled.emit(entry["target_id"], res.get("disabled_turns", 0))
		SkillEffect.EffectType.COUNTER_STANCE:
			counter_stance_entered.emit(entry["target_id"])
		SkillEffect.EffectType.TRUE_DAMAGE:
			# 真实伤害中防反触发后取消招架状态
			if res.get("counter_stance_triggered", false):
				counter_stance_triggered.emit(entry["target_id"], entry.get("attacker_id", -1))
				counter_stance_ended.emit(entry["target_id"])
			# 真实伤害日志已通过 skill_applied 信号传递，此处无需额外信号
			pass
		SkillEffect.EffectType.PIERCE_DAMAGE:
			# 穿透伤害日志通过 skill_applied 信号传递（含暴击信息）
			pass
		SkillEffect.EffectType.DEATH_SENTENCE:
			# 断罪死日志通过 skill_applied 信号传递（含7次猜拳结果）
			pass
		SkillEffect.EffectType.LOSE_SKILL:
			var lname: String = res.get("lost_skill", "")
			if lname != "":
				skill_lost.emit(entry["target_id"], lname)
		SkillEffect.EffectType.FTG_MARK:
			if res.get("ftg_marked", false):
				ftg_mark_applied.emit(entry["target_id"], entry.get("attacker_id", -1))
			if res.get("counter_stance_triggered", false):
				counter_stance_triggered.emit(entry["target_id"], entry.get("attacker_id", -1))
				counter_stance_ended.emit(entry["target_id"])
		SkillEffect.EffectType.FTG_CHARGE:
			ftg_marks_changed.emit(entry["target_id"], res.get("ftg_marks", 0))
		SkillEffect.EffectType.FTG_REMOVE:
			ftg_mark_removed.emit(entry["target_id"])
		SkillEffect.EffectType.NINE_TAILS:
			pass
		SkillEffect.EffectType.UNTARGETABLE:
			# 无法选择状态：由 UI 徽章驱动显示，此处无额外信号
			pass
		SkillEffect.EffectType.GLORY_TAKEOVER:
			# 荣耀夺取：行动权转移与效果由 GameManager 准备阶段特殊处理，日志经 skill_applied 传递
			pass
		SkillEffect.EffectType.UCHIHA_STANCE:
			# 宇智波流招架：进入独立招架状态
			uchiha_stance_entered.emit(entry["target_id"])


## ── 八门遁甲处理 ──────────────────────────────────────────────────────────────
## 聚气后自动开门：每次聚气+1门，本回合+下回合无敌
## 第八门触发后：回10血 + 解锁夜凯/夕象 + 燃烧 + 狂战士，然后失去八门遁甲
func _process_gate_open(player: PlayerState) -> void:
	# 检查角色是否拥有八门遁甲（通过技能名查找）
	var has_gate: bool = false
	for skill in player.character.skills:
		if skill.skill_name == "八门遁甲":
			has_gate = true
			break
	if not has_gate:
		return
	# 已失去八门遁甲则不再开门
	if "八门遁甲" in player.lost_skills:
		return

	player.gate_count += 1
	gate_changed.emit(player.player_id, player.gate_count)

	# 本回合+下回合无敌
	player.invincible_turns = 2
	player_invincible.emit(player.player_id, 2)

	if player.gate_count >= 8:
		# 第八门全开特效
		eighth_gate_opened.emit(player.player_id)
		# 回复10点生命
		player.hp = min(player.character.max_hp, player.hp + 10.0)
		# 获得燃烧和狂战士状态
		player.burning = true
		player_burning.emit(player.player_id)
		player.berserker = true
		player_berserker.emit(player.player_id)
		# 解锁夜凯/夕象/双龙戏珠（加载独立技能资源并加入解锁列表）
		var unlock_paths := [
			"res://resources/characters/skills/夜凯.tres",
			"res://resources/characters/skills/夕象.tres",
			"res://resources/characters/skills/双龙戏珠.tres",
		]
		for path in unlock_paths:
			var skill_res := load(path) as SkillData
			if skill_res and not player.unlocked_skills.has(skill_res):
				player.unlocked_skills.append(skill_res)
				skill_unlocked.emit(player.player_id, skill_res.skill_name)
		# 八门遁甲技能永久移除
		player.lost_skills.append("八门遁甲")
		skill_lost.emit(player.player_id, "八门遁甲")


## ── 宇智波泉奈：荣耀解锁 ─────────────────────────────────────────────────────
## 泉奈聚气达到4气时自动解锁荣耀（解锁不消耗气，解锁后需持有4气才能释放）
## 释放荣耀时消耗4气并清空解锁状态；需再次聚气4气重新解锁
func _process_glory_unlock(player: PlayerState) -> void:
	if player == null or not player.is_alive:
		return
	# 泉奈专属被动：只有角色技能包含"宇智波的荣耀"才处理
	if not _has_glory_skill(player):
		return
	# 已解锁则无需重复解锁
	if player.glory_unlocked:
		return
	# 达到4气：解锁荣耀（不消耗气）
	if player.energy >= 4:
		player.glory_unlocked = true
		glory_unlocked_changed.emit(player.player_id, true)
		skill_unlocked.emit(player.player_id, "宇智波的荣耀")

## 判断角色是否拥有荣耀技能（宇智波泉奈专属）
func _has_glory_skill(player: PlayerState) -> bool:
	for skill in player.character.skills:
		if skill.skill_name == "宇智波的荣耀":
			return true
	return false

## 荣耀夺取核心：在目标（回合主）的准备阶段触发
## 效果：目标本回合失去所有技能（即使其自身有无敌也生效，无敌不免疫封技）+ 对目标造成2点伤害
## 之后本回合行动权归泉奈
func _apply_glory_takeover(caster: PlayerState, target: PlayerState) -> void:
	if caster == null or target == null or not caster.is_alive or not target.is_alive:
		return
	# 荣耀消耗与解锁状态复位：使用后荣耀不再解锁（需重新聚气4解锁）
	caster.energy = max(0, caster.energy - 4)
	caster.glory_unlocked = false
	glory_unlocked_changed.emit(caster.player_id, false)
	# 消耗荣耀：标记本回合已使用（防同一回合重复触发）
	caster.glory_used_this_round = true

	# 效果1：目标本回合失去所有技能（封技1回合）——无视无敌/招架（通用状态）
	# 通用状态（无敌/无法选择等）依旧生效，但封技属于效果，独立于目标自身技能
	target.skill_disabled_turns = max(target.skill_disabled_turns, 1)
	skill_disabled.emit(target.player_id, target.skill_disabled_turns)
	# 目标招架状态解除（荣耀使其技能无效，招架作为技能效果不再生效）
	if target.counter_stance:
		target.counter_stance = false
		counter_stance_ended.emit(target.player_id)
	# 宇智波流招架同招架：荣耀夺取使目标本回合失去所有技能，招架不再生效
	target.uchiha_stance = false

	# 效果2：对目标造成2点伤害（正常伤害结算，可被护盾/分身/无敌等吸收）
	var dmg := 2.0
	var absorbed: float = 0.0
	var clone_broken: bool = false
	if target.clone_count > 0:
		target.clone_count -= 1
		absorbed = dmg
		dmg = 0
		clone_broken = true
	elif target.shield == -1:
		absorbed = dmg
		dmg = 0
		target.shield = 0
	elif target.shield > 0:
		absorbed = min(dmg, target.shield)
		dmg = max(0.0, dmg - target.shield)
		target.shield = max(0, target.shield - 2)
	# 无敌状态：完全免疫伤害（九尾无敌同）
	if target.invincible_turns > 0 or target.nine_tails_invincible:
		dmg = 0
		absorbed = 0
	target.hp = max(0.0, target.hp - dmg)
	if dmg > 0:
		target.took_damage_this_round = true
	# 造成伤害标记（钟获取）
	if dmg > 0:
		caster.dealt_damage_this_round = true
		# 伤害入账对局统计（结算界面"造成伤害"）
		var c_stats: PlayerMatchStats = _match_record.player_stats.get(caster.player_id)
		if c_stats:
			c_stats.total_damage_dealt += dmg
		var t_stats: PlayerMatchStats = _match_record.player_stats.get(target.player_id)
		if t_stats:
			t_stats.total_damage_taken += dmg

	# 回合主转移：本回合行动权归泉奈
	_sole_winner_id = caster.player_id
	# 目标本回合行动权被剥夺
	glory_takeover.emit(caster.player_id, target.player_id, dmg, absorbed, clone_broken)


## ── 宇智波止水（须佐能）专属核心机制 ─────────────────────────────────────
## 判断角色是否为旧止水（须佐能）：通过技能名"须佐能乎·斩"判断
## （不用"别天神"判断——新止水也有"别天神"技能但机制完全不同）
func _is_shisui(player: PlayerState) -> bool:
	if player == null:
		return false
	for skill in player.character.skills:
		if skill.skill_name == "须佐能乎·斩":
			return true
	return false

## 判断角色是否为新止水（天劫）：通过技能"日影舞"判断
## 旧止水的日晕舞技能名为"宇智波流·日晕舞"，新止水为"日影舞"，不会混淆
func _is_new_shisui(player: PlayerState) -> bool:
	if player == null:
		return false
	for skill in player.character.skills:
		if skill.skill_name == "日影舞":
			return true
	return false

## 判断角色是否获得过九十九（解锁/直接使用过均可，别天神触发条件）
func _has_kotoamatsukami(player: PlayerState) -> bool:
	if player == null:
		return false
	return player.has_kotoamatsukami_skill

## 获取止水角色技能资源（加载指定技能名对应的 .tres）
func _get_shisui_skill(skill_name: String) -> SkillData:
	var skill := load("res://resources/characters/skills/%s.tres" % skill_name) as SkillData
	return skill

## ── 日晕舞中断点决策：人类弹窗 / AI 自动选择 ──────────────────────────────
## 只有人类玩家需要弹窗选择中断点；AI 自动选择"不中断"或"按血线选择"
func _request_hiano_interrupt(player: PlayerState, target: PlayerState) -> void:
	if player == null or target == null:
		return
	if player.is_human:
		hiano_interrupt_required.emit(player.player_id, target.player_id, 2)
	else:
		# AI 策略：目标残血时提前中断（1段后），否则不中断
		var interrupt_at: int = 0
		if target.hp <= 1.5:
			interrupt_at = 1
		elif target.hp <= 2.5:
			interrupt_at = 2
		_on_hiano_interrupt_made(player.player_id, interrupt_at)

## 日晕舞中断点决策回调（UI/网络回传，或AI自动选择后直接调用）
## interrupt_at: 0=不中断 1=1段后中断 2=2段后中断
func _on_hiano_interrupt_made(player_id: int, interrupt_at: int) -> void:
	if _hiano_pending.is_empty():
		return
	if _current_phase != GamePhase.APPLYING:
		return
	var ctx: Dictionary = _hiano_pending
	_hiano_pending = {}
	var player := get_player(player_id)
	if player == null:
		_enter_phase(GamePhase.ELIMINATION)
		return
	var target := get_player(ctx.get("target_id", -1))
	if target == null or not target.is_alive:
		_enter_phase(GamePhase.ELIMINATION)
		return

	# 执行多段伤害（每段独立结算，目标死亡自动停止），break_after=预选中断点
	var logs := RoundResolver.apply_multi_hit_damage(player, target, 1.0, 3, _distance_system, interrupt_at)
	# 记录伤害来源（last_hit_by_id）已由 apply_multi_hit_damage 内部 DAMAGE 分支记录
	for entry in logs:
		_emit_effect_signals(entry)
	skill_applied.emit(logs)
	_record_action(player, ctx.get("skill", null) as SkillData, logs)

	# 中断后衔接：若中断（1段或2段后）且气足够，立即释放【须佐能乎·九十九】（消耗2气）
	# 设计确认：中断点后立即消耗2气释放九十九；气不足则仅中断不释放
	var did_break: bool = interrupt_at > 0
	if did_break and player.energy >= 2 and target.is_alive:
		player.energy -= 2
		player_charged.emit(player.player_id, player.energy)
		_process_susanoo_ninety_nine(player, target)

	_enter_phase(GamePhase.ELIMINATION)

## 通用日志封装：为技能使用后的日志发射信号、记录行动、刷新能量
func _finalize_skill_use(winner: PlayerState, skill: SkillData, logs: Array[Dictionary]) -> void:
	# 造成伤害标记（钟获取）——砸钟等 bell_cost>0 技能伤害不计入，防止砸钟回钟
	if skill.bell_cost <= 0:
		for entry in logs:
			if entry.get("effect_type", -1) == SkillEffect.EffectType.DAMAGE \
			or entry.get("effect_type", -1) == SkillEffect.EffectType.TRUE_DAMAGE \
			or entry.get("effect_type", -1) == SkillEffect.EffectType.PIERCE_DAMAGE:
				var res: Dictionary = entry.get("result", {})
				if res.get("damage_dealt", 0) > 0:
					winner.dealt_damage_this_round = true
					break
	for entry in logs:
		_emit_effect_signals(entry)
	skill_applied.emit(logs)
	player_charged.emit(_sole_winner_id, winner.energy)
	_record_action(winner, skill, logs)

## ── 须佐能乎·斩：本回合无敌 + 2点延迟伤害（目标回合结束阶段结算） ──────────────
func _process_susanoo_slash(winner: PlayerState, target: PlayerState) -> void:
	if winner == null or target == null:
		return
	# 本回合无敌（无敌持续到本回合结束，回合结束时递减）
	winner.invincible_turns = 1
	player_invincible.emit(winner.player_id, 1)
	# 解锁须佐能乎·螺旋（技能链永久解锁，跨回合可用）
	if not winner.susanoo_spiral_unlocked:
		winner.susanoo_spiral_unlocked = true
		var spiral := _get_shisui_skill("须佐能乎·螺旋")
		if spiral and not winner.unlocked_skills.has(spiral):
			winner.unlocked_skills.append(spiral)
			skill_unlocked.emit(winner.player_id, "须佐能乎·螺旋")
	# 2点伤害延迟到目标回合结束阶段结算（标准吸收链，duration=1：释放回合结束时触发）
	target.delayed_damages.append({ "damage": 2.0, "trigger_in": 1, "attacker_id": winner.player_id })
	susanoo_slash_used.emit(winner.player_id, 2.0)

## ── 须佐能乎·螺旋：3段1伤 + 本回合无敌 + 目标本回合封技 + 解锁九十九 ─────
func _process_susanoo_spiral(winner: PlayerState, target: PlayerState) -> void:
	if winner == null or target == null or not target.is_alive:
		return
	# 本回合无敌
	winner.invincible_turns = 1
	player_invincible.emit(winner.player_id, 1)
	# 目标本回合封技（回合结束就没了）
	target.skill_disabled_turns = max(target.skill_disabled_turns, 1)
	skill_disabled.emit(target.player_id, target.skill_disabled_turns)
	# 获得过九十九（别天神触发条件；日晕舞中断不满足此条件，只有螺旋/解锁链满足）
	if not winner.has_kotoamatsukami_skill:
		winner.has_kotoamatsukami_skill = true
	# 解锁须佐能乎·九十九（技能链永久解锁，跨回合可用）
	if not winner.unlocked_skills.has(_load_shisui_skill("须佐能乎·九十九")):
		var ninety_nine := _load_shisui_skill("须佐能乎·九十九")
		if ninety_nine:
			winner.unlocked_skills.append(ninety_nine)
			skill_unlocked.emit(winner.player_id, "须佐能乎·九十九")
	# 3段1伤害（每段独立走吸收链，目标死亡自动停止）
	var logs := RoundResolver.apply_multi_hit_damage(winner, target, 1.0, 3, _distance_system, 0)
	_finalize_shisui_use(winner, _load_shisui_skill("须佐能乎·螺旋"), logs)
	susanoo_spiral_used.emit(winner.player_id, target.player_id, logs.size())

## ── 须佐能乎·九十九：4段1 + 本回合无敌 ─────────────────────────────────
func _process_susanoo_ninety_nine(winner: PlayerState, target: PlayerState) -> void:
	if winner == null or target == null or not target.is_alive:
		return
	# 本回合无敌
	winner.invincible_turns = 1
	player_invincible.emit(winner.player_id, 1)
	# 4段1伤害
	var logs := RoundResolver.apply_multi_hit_damage(winner, target, 1.0, 4, _distance_system, 0)
	_finalize_shisui_use(winner, _load_shisui_skill("须佐能乎·九十九"), logs)
	susanoo_ninety_nine_used.emit(winner.player_id, target.player_id, logs.size())

## ── 别天神：击杀时自动触发（弹窗/自动夺舍） ──────────────────────────────
## 满足条件：止水获得过九十九（has_kotoamatsukami_skill）且未使用过别天神且未处于夺舍中
func _try_trigger_kotoamatsukami(killer: PlayerState, victim: PlayerState) -> void:
	if killer == null or victim == null:
		return
	if not killer.is_alive or victim.is_alive:
		return
	if not _is_shisui(killer):
		return
	if not _has_kotoamatsukami(killer):
		return
	if killer.kotoamatsukami_used:
		return
	if killer.takeover_active:
		return
	# 击杀者必须是止水自己（last_hit_by_id 已记录，含延迟/九尾等来源）
	if killer.player_id != victim.last_hit_by_id:
		return
	# 弹窗确认（人类）或自动夺舍（AI）
	killer.koto_awaiting_confirm = true
	if killer.is_human:
		kotoamatsukami_required.emit(killer.player_id, victim.player_id)
	else:
		_apply_kotoamatsukami_takeover(killer, victim)

## 执行别天神夺舍：保存快照 + 完全替换为被杀者角色 + 半血 + 继承气
func _apply_kotoamatsukami_takeover(killer: PlayerState, victim: PlayerState) -> void:
	if killer == null or victim == null:
		return
	# 保存夺舍前快照（用于夺舍体死亡后回退）
	killer.save_pre_takeover_snapshot()
	# 完全变成被杀者角色（技能替换）
	killer.character = victim.character
	# 血量 = 被杀者最大血量的一半（下限1，向上取整）
	var half_hp: float = max(1.0, ceilf(victim.character.max_hp * 0.5))
	killer.hp = half_hp
	# 继承其阵亡时的气
	killer.energy = victim.energy
	# 标记别天神已使用（被动限定技，一局一次）
	killer.kotoamatsukami_used = true
	# 标记夺舍状态（用于夺舍体死亡后回退）
	killer.takeover_active = true
	killer.koto_awaiting_confirm = false
	# 夺舍后清除自身状态（如无敌、结界等不继承）
	killer.invincible_turns = 0
	killer.shield = 0
	killer.paralyze_turns = 0
	killer.knockdown_turns = 0
	killer.clone_count = 0
	killer.skill_disabled_turns = 0
	killer.untargetable_turns = 0
	killer.counter_stance = false
	killer.uchiha_stance = false
	killer.ftg_marked_by.clear()
	killer.delayed_damages.clear()
	# 夺舍体继承被杀者的气（已设），重置回合数据
	killer.reset_round_data()
	# 发射信号
	kotoamatsukami_takeover.emit(killer.player_id, victim.player_id)
	# 记录击杀者造成伤害（夺舍不改变当前击杀统计）
	killer.dealt_damage_this_round = true

## 夺舍体死亡回退：夺舍体（当前为被杀者角色）死亡后，止水回到夺舍前状态
## 在淘汰检测循环中调用：若玩家处于 takeover_active 且 hp<=0，则回退并保持存活
func _revert_takeover_if_needed(player: PlayerState) -> bool:
	if player == null or not player.takeover_active:
		return false
	if player.hp > 0:
		return false
	# 夺舍体死亡：回退到夺舍前止水状态
	player.restore_pre_takeover_snapshot()
	takeover_reverted.emit(player.player_id)
	# 回退后血量>0（快照时为存活状态），保持存活
	return true

## ── 辅助：加载止水技能资源 ───────────────────────────────────────────────
func _load_shisui_skill(skill_name: String) -> SkillData:
	return load("res://resources/characters/skills/%s.tres" % skill_name) as SkillData

## ── 新止水·别天神回溯机制 ───────────────────────────────────────────────
## 拍摄当前回合（准备阶段前）的全体玩家状态快照
## 在猜拳唯一胜者确定后、进入 PREPARATION 前调用
## 同时记录上回合的回合主ID（用于回溯可用性判断）
func _capture_round_pre_snapshot() -> void:
	# 滚动快照：当前"当前回合开始前"快照 → "上回合开始前"快照（作为回溯恢复目标）
	_prev_round_pre_snapshot = _last_round_pre_snapshot
	# 记录上回合的玩家主：_sole_winner_id 已是当前回合胜者（在 _resolve_round/_resolve_tiebreak 中先更新）
	# 因此用 _prev_winner_id（上一回合胜者，在 _start_action_input 中维护）记录"上回合是谁"
	_prev_round_winner_id = _prev_winner_id
	var states: Dictionary = {}
	for p in _players:
		states[p.player_id] = p.capture_backtrack_snapshot()
	var dist_snap := {}
	if _distance_system:
		dist_snap = _distance_system.capture_snapshot()
	_last_round_pre_snapshot = {
		"winner_id": _sole_winner_id,
		"round": _current_round_number,
		"states": states,
		"distance": dist_snap,
	}

## 执行别天神回溯：将全体玩家状态恢复到 _prev_round_pre_snapshot（上回合开始前状态，即撤销上一回合）
## 条件：施法者为新止水，且上回合不是自己回合（在 _get_preparation_skill 已校验）
func _apply_backtrack(player: PlayerState) -> void:
	if player == null or not player.is_alive:
		return
	var snap := _prev_round_pre_snapshot
	if snap.is_empty():
		return
	# 恢复全体玩家状态（注意：必须在扣气之前，否则扣掉的气会被快照恢复覆盖）
	var states: Dictionary = snap.get("states", {})
	for p in _players:
		var p_snap: Dictionary = states.get(p.player_id, {})
		if not p_snap.is_empty():
			p.restore_from_backtrack_snapshot(p_snap)
	# 恢复距离系统（含座位表与距离偏移）
	var dist_snap: Dictionary = snap.get("distance", {})
	if _distance_system and not dist_snap.is_empty():
		_distance_system.restore_from_snapshot(dist_snap)
	# 将回溯后恢复为存活的玩家重新加入座位表（若快照时存活但现在不在表中）
	var snapshot_winner: int = snap.get("winner_id", -1)
	# 重新加入所有快照时存活的玩家
	for p in _players:
		if p.is_alive and not _distance_system_contains(p.player_id):
			_distance_system_re_add(p.player_id)
	# 消耗1气（别天神技能消耗）——放在快照恢复之后，作为回溯的施法代价
	var skill := _get_skill_by_name(player, "别天神")
	var cost: int = skill.energy_cost if skill != null else 1
	player.energy = max(0, player.energy - cost)
	player_charged.emit(player.player_id, player.energy)
	# 清除上回合快照（已用完）
	_prev_round_pre_snapshot = {}
	# 发射信号
	backtrack_performed.emit(player.player_id, snap.get("round", 0))

## 检查座位表是否包含指定玩家
func _distance_system_contains(player_id: int) -> bool:
	if _distance_system == null:
		return false
	var order: Array = _distance_system._seat_order
	return order.has(player_id)

## 将指定玩家重新加入座位表（追加到末尾，保持环形完整性）
func _distance_system_re_add(player_id: int) -> void:
	if _distance_system == null:
		return
	if not _distance_system_contains(player_id):
		_distance_system._seat_order.append(player_id)

## 别天神回溯确认回调（人类玩家 UI/网络回传，use_backtrack=true=回溯 false=跳过）
func _on_backtrack_made(player_id: int, use_backtrack: bool) -> void:
	if _backtrack_pending.is_empty():
		return
	if _current_phase != GamePhase.PREPARATION:
		return
	var ctx: Dictionary = _backtrack_pending
	_backtrack_pending = {}
	var player := get_player(player_id)
	if player == null:
		_process_prep_next()
		return
	if use_backtrack:
		_apply_backtrack(player)
	else:
		# 跳过：本次回溯机会已消耗，清空上回合快照，防止 _process_prep_next 轮询回自己时再次触发回溯弹窗
		_prev_round_pre_snapshot = {}
	# 无论回溯/跳过，继续推进准备阶段
	_process_prep_next()

## 人类玩家回溯决策提交入口（由UI/网络主机调用）
## use_backtrack=true=回溯 false=跳过
func submit_backtrack_decision(player_id: int, use_backtrack: bool) -> void:
	backtrack_made.emit(player_id, use_backtrack)

## ── 辅助：封装多段伤害日志的最终处理（标记伤害/信号/记录） ───────────────
func _finalize_shisui_use(winner: PlayerState, skill: SkillData, logs: Array[Dictionary]) -> void:
	for entry in logs:
		if entry.get("effect_type", -1) == SkillEffect.EffectType.DAMAGE \
		or entry.get("effect_type", -1) == SkillEffect.EffectType.TRUE_DAMAGE \
		or entry.get("effect_type", -1) == SkillEffect.EffectType.PIERCE_DAMAGE:
			var res: Dictionary = entry.get("result", {})
			if res.get("damage_dealt", 0) > 0:
				winner.dealt_damage_this_round = true
				break
	for entry in logs:
		_emit_effect_signals(entry)
	skill_applied.emit(logs)
	player_charged.emit(_sole_winner_id, winner.energy)
	_record_action(winner, skill, logs)

## ── 新止水·日影舞 ─────────────────────────────────────────────────────────────
## 请求日影舞4段目标选择：人类弹窗逐段选择 / AI 自动分配
func _request_hiroari_targets(player: PlayerState) -> void:
	if player == null:
		_enter_phase(GamePhase.ELIMINATION)
		return
	# 可指定目标：所有存活玩家（可重复，包含自己？默认其他玩家）
	var target_ids: Array[int] = []
	for p in get_alive_players():
		if p.player_id != player.player_id:
			target_ids.append(p.player_id)
	if player.is_human:
		# 人类玩家：弹窗逐段选择（4个目标ID，可重复）
		hiroari_targets_required.emit(player.player_id, target_ids)
	else:
		# AI：随机/按血线分配4段（优先低血量目标）
		var ai_targets: Array[int] = []
		var alive_others: Array[PlayerState] = []
		for p in get_alive_players():
			if p.player_id != player.player_id:
				alive_others.append(p)
		alive_others.sort_custom(func(a, b): return a.hp < b.hp)
		for i in range(4):
			if alive_others.size() > 0:
				ai_targets.append(alive_others[0].player_id)
		_on_hiroari_targets_made(player.player_id, ai_targets)

## 日影舞目标选择回调（UI/网络回传，targets 为4个目标ID数组）
func _on_hiroari_targets_made(player_id: int, targets: Array[int]) -> void:
	if _hiroari_pending.is_empty():
		return
	if _current_phase != GamePhase.APPLYING:
		return
	var ctx: Dictionary = _hiroari_pending
	_hiroari_pending = {}
	var player := get_player(player_id)
	if player == null:
		_enter_phase(GamePhase.ELIMINATION)
		return
	if player.phantom_count < 3:
		_enter_phase(GamePhase.ELIMINATION)
		return
	# 消耗3个幻影
	player.phantom_count = 0
	phantom_changed.emit(player.player_id, 0)
	# 逐段结算4段（每段2伤，每段独立指定目标，可重复；目标死亡顺延到下一存活玩家）
	var logs: Array[Dictionary] = []
	for i in range(4):
		var target_id: int = targets[i] if i < targets.size() else -1
		var target := get_player(target_id) if target_id >= 0 else null
		# 目标死亡/不存在：按逆时针顺延到下一存活玩家
		if target == null or not target.is_alive or target.hp <= 0:
			target = _next_alive_counterclockwise(player.player_id, target_id)
		if target == null:
			break
		var e := SkillEffect.new()
		e.effect_type = SkillEffect.EffectType.DAMAGE
		e.value = 2.0
		e.target = SkillEffect.EffectTarget.ENEMY_SINGLE
		var res := RoundResolver.apply_effect_standalone(e, player, target, _distance_system)
		logs.append({
			"attacker_id": player.player_id,
			"target_id":   target.player_id,
			"effect_type": SkillEffect.EffectType.DAMAGE,
			"value":       2.0,
			"result":      res,
		})
	hiroari_used.emit(player.player_id, targets)
	# 最终处理（标记伤害/信号/记录）
	_finalize_shisui_use(player, ctx.get("skill", null) as SkillData, logs)
	# 进入淘汰检测（日影舞为异步回调，需手动推进阶段）
	_enter_phase(GamePhase.ELIMINATION)

## 人类玩家日影舞目标选择提交入口（由UI/网络主机调用）
## targets 为4个目标ID数组（可重复选择，-1=跳过该段）
func submit_hiroari_targets(player_id: int, targets: Array[int]) -> void:
	hiroari_targets_made.emit(player_id, targets)

## 人类玩家日晕舞中断点提交入口（由UI/网络主机调用）
## interrupt_at: 0=不中断 1=1段后中断 2=2段后中断
func submit_hiano_interrupt(player_id: int, interrupt_at: int) -> void:
	hiano_interrupt_made.emit(player_id, interrupt_at)

## 逆时针取下一个存活玩家（从指定ID开始，用于日影舞死亡顺延）
func _next_alive_counterclockwise(from_id: int, skip_id: int = -1) -> PlayerState:
	var alive := get_alive_players()
	if alive.size() == 0:
		return null
	# 按座位顺序找到 from_id 之后的下一存活者
	var order: Array = _distance_system._seat_order if _distance_system else []
	if order.size() == 0:
		# 无座位表时按玩家ID顺序
		for p in alive:
			if p.player_id != skip_id:
				return p
		return alive[0]
	var start_idx := order.find(from_id)
	var n: int = order.size()
	for i in range(1, n + 1):
		var pid: int = order[(start_idx + n - i) % n]
		var p := get_player(pid)
		if p != null and p.is_alive and p.hp > 0 and p.player_id != skip_id:
			return p
	# 回退：任意存活玩家
	for p in alive:
		if p.player_id != skip_id:
			return p
	return null


## ── 燃烧/狂战士结算（END_PHASE中调用）──────────────────────────────────────────
## 燃烧：每回合结束失去1血（HP>1保护）
## 狂战士：本回合受过伤害则额外失去1血（可致死）
func _process_burn_and_berserker() -> void:
	for player in _players:
		if not player.is_alive:
			continue
		# 燃烧扣血（HP>1保护）
		if player.burning and player.hp > 1:
			player.hp -= 1.0
			burn_damage_triggered.emit(player.player_id, 1.0, player.hp, "燃烧")
		# 狂战士扣血（本回合受过伤害，可致死）
		if player.berserker and player.took_damage_this_round:
			player.hp = max(0.0, player.hp - 1.0)
			burn_damage_triggered.emit(player.player_id, 1.0, player.hp, "狂战士")


## ── 血付机制 ──────────────────────────────────────────────────────────────────
## 血付决策：人类玩家在 UI 弹窗选择，AI 在 ai_controller.decide_action 中直接设置
## pending_hp_payment；结算在 _apply_actions（能量校验前）统一处理

## 检测淘汰：HP<=0的玩家标记死亡、从距离系统移除、发射淘汰信号
## 别天神夺舍：止水击杀时若满足条件触发弹窗/自动夺舍；夺舍体死亡时回退到夺舍前状态
func _check_elimination() -> void:
	for player in _players:
		if player.is_alive and player.hp <= 0:
			# 夺舍体死亡：回退到夺舍前止水状态（不淘汰、不终止游戏）
			if _revert_takeover_if_needed(player):
				continue
			# 尝试触发止水别天神（击杀者自动夺舍）
			var killer := get_player(player.last_hit_by_id)
			if killer != null and killer.is_alive and _is_shisui(killer) \
			and _has_kotoamatsukami(killer) and not killer.kotoamatsukami_used \
			and not killer.takeover_active and not _koto_pending.has("player_id"):
				# 保存待确认上下文并进入夺舍流程
				_koto_pending = { "player_id": killer.player_id, "target_id": player.player_id }
				if killer.is_human:
					# 人类：弹窗确认，等待 _on_kotoamatsukami_made 回调后继续
					killer.koto_awaiting_confirm = true
					kotoamatsukami_required.emit(killer.player_id, player.player_id)
					# 保持玩家存活（等待夺舍确认，避免提前淘汰）
					player.is_alive = true
					# 停留在 ELIMINATION 阶段等待确认回调（回调中会继续 _check_elimination）
					return
				else:
					# AI：自动夺舍
					_apply_kotoamatsukami_takeover(killer, player)
					player.is_alive = false
					_distance_system.remove_player(player.player_id)
					player_eliminated.emit(player.player_id)
					var es: PlayerMatchStats = _match_record.player_stats.get(player.player_id)
					if es:
						es.elimination_round = _current_round_number
						es.elimination_reason = "HP归零"
					continue
			player.is_alive = false
			_distance_system.remove_player(player.player_id)
			player_eliminated.emit(player.player_id)
			var es: PlayerMatchStats = _match_record.player_stats.get(player.player_id)
			if es:
				es.elimination_round = _current_round_number
				es.elimination_reason = "HP归零"

	var alive := get_alive_players()
	if alive.size() <= 1:
		_enter_phase(GamePhase.GAME_OVER)
		return
	# 团队模式：所有存活者属于同一队则该队获胜
	if alive.any(func(p): return p.team_id != 0):
		var first_team: int = alive[0].team_id
		if alive.all(func(p): return p.team_id == first_team):
			_enter_phase(GamePhase.GAME_OVER)
			return
	# 保留原有"人类死亡则结束"逻辑（单机模式用；慈悲尖塔模式人类死亡不结束）
	if _is_human_dead() and not _is_network_game and not _is_tower_mode:
		_enter_phase(GamePhase.GAME_OVER)
		return
	_enter_phase(GamePhase.END_PHASE)

func _is_human_dead() -> bool:
	for player in _players:
		if player.is_human and not player.is_alive:
			return true
	return false

## 别天神夺舍确认回调（人类玩家 UI/网络回传，takeover=true=夺舍 false=放弃）
func _on_kotoamatsukami_made(player_id: int, takeover: bool) -> void:
	if _koto_pending.is_empty():
		return
	var ctx: Dictionary = _koto_pending
	_koto_pending = {}
	var killer := get_player(ctx.get("player_id", -1))
	var victim := get_player(ctx.get("target_id", -1))
	if killer == null or victim == null:
		return
	if killer.koto_awaiting_confirm:
		killer.koto_awaiting_confirm = false
	if takeover:
		_apply_kotoamatsukami_takeover(killer, victim)
	# 无论夺舍/放弃，受害者照常淘汰
	victim.is_alive = false
	_distance_system.remove_player(victim.player_id)
	player_eliminated.emit(victim.player_id)
	var es: PlayerMatchStats = _match_record.player_stats.get(victim.player_id)
	if es:
		es.elimination_round = _current_round_number
		es.elimination_reason = "HP归零"
	# 继续淘汰检测（可能因人类死亡结束游戏）
	_check_elimination()

## ── END_PHASE（钟结算+招架决策）─────────────────────────────────────────────────
## 回合结束前处理：1.造成伤害者获得钟 2.有钟玩家决定是否招架 3.燃烧/狂战士结算
func _process_end_phase() -> void:
	# 1. 本回合造成伤害的玩家获得钟
	for player in _players:
		if player.is_alive and player.dealt_damage_this_round and player.bell_count >= 0:
			# 只给有钟机制的角色（通过角色id或技能判断）
			if _has_bell_mechanic(player):
				player.bell_count += 1
				bell_gained.emit(player.player_id, player.bell_count)
	# 2. 燃烧/狂战士结算
	_process_burn_and_berserker()
	# 3. 有钟的存活玩家决定是否招架
	_process_bell_decisions()

## 检查角色是否拥有钟机制（有招架或砸钟技能）
func _has_bell_mechanic(player: PlayerState) -> bool:
	for skill in player.character.skills:
		if skill.bell_cost > 0:
			return true
	return false

## 处理招架决策：仅询问本回合行动权拥有者（_sole_winner_id）
## 招架是"赢得猜拳获得行动权"的玩家回合结束时的主动技能
func _process_bell_decisions() -> void:
	_bell_decision_players.clear()
	_bell_decision_index = 0
	var winner := get_player(_sole_winner_id)
	if winner == null or not winner.is_alive or winner.bell_count <= 0 or not _has_bell_mechanic(winner):
		_enter_phase(GamePhase.ROUND_END)
		return
	_bell_decision_players.append(winner)
	_process_next_bell_decision()

## 递归处理招架决策：处理队列中 index 位置的玩家，完成后推进到下一位
func _process_next_bell_decision() -> void:
	if _bell_decision_index >= _bell_decision_players.size():
		_enter_phase(GamePhase.ROUND_END)
		return
	var player := _bell_decision_players[_bell_decision_index]
	if not player.is_alive or player.bell_count <= 0:
		_bell_decision_index += 1
		_process_next_bell_decision()
		return
	if player.is_human:
		# 人类玩家：发射信号等待UI确认，提交后由 _on_bell_decision_made 推进
		end_phase_bell_decision_required.emit(player.player_id, player.bell_count)
	else:
		# AI决策
		var use_bell := _ai_controller.decide_bell_action(player, get_alive_players())
		if use_bell:
			player.bell_count -= 1
			player.counter_stance = true
			counter_stance_entered.emit(player.player_id)
		_bell_decision_index += 1
		_process_next_bell_decision()

## 招架决策回调：UI/网络提交后推进队列到下一位玩家
func _on_bell_decision_made(_player_id: int, _use_bell: bool) -> void:
	if _current_phase != GamePhase.END_PHASE:
		return
	_bell_decision_index += 1
	_process_next_bell_decision()

## 人类玩家招架决策回调（由UI调用）
func submit_bell_decision(player_id: int, use_bell: bool) -> void:
	if _current_phase != GamePhase.END_PHASE:
		return
	var player := get_player(player_id)
	if player == null or not player.is_alive:
		return
	if use_bell and player.bell_count > 0:
		player.bell_count -= 1
		player.counter_stance = true
		counter_stance_entered.emit(player.player_id)
	end_phase_bell_decision_made.emit(player_id, use_bell)

## 回合收尾：触发延迟伤害、九尾阶段推进、再次检测淘汰、减麻痹计数、重置回合数据
func _end_round() -> void:
	# 触发延迟伤害
	_process_delayed_damages()
	# 九尾阶段推进（阶段2/3在回合结束时触发）
	_process_nine_tails_progress()
	# 九尾伤害后检测淘汰
	for player in _players:
		if player.is_alive and player.hp <= 0:
			player.is_alive = false
			_distance_system.remove_player(player.player_id)
			player_eliminated.emit(player.player_id)
			var es3: PlayerMatchStats = _match_record.player_stats.get(player.player_id)
			if es3:
				es3.elimination_round = _current_round_number
				es3.elimination_reason = "九尾"
	# 延迟伤害后再次检测淘汰
	for player in _players:
		if player.is_alive and player.hp <= 0:
			player.is_alive = false
			_distance_system.remove_player(player.player_id)
			player_eliminated.emit(player.player_id)
			var es2: PlayerMatchStats = _match_record.player_stats.get(player.player_id)
			if es2:
				es2.elimination_round = _current_round_number
				es2.elimination_reason = "延迟伤害"
	var alive := get_alive_players()
	if alive.size() <= 1:
		for player in _players:
			player.reset_round_data()
		_enter_phase(GamePhase.GAME_OVER)
		return
	if alive.any(func(p): return p.team_id != 0):
		var first_team: int = alive[0].team_id
		if alive.all(func(p): return p.team_id == first_team):
			for player in _players:
				player.reset_round_data()
			_enter_phase(GamePhase.GAME_OVER)
			return
	if _is_human_dead() and not _is_network_game and not _is_tower_mode:
		for player in _players:
			player.reset_round_data()
		_enter_phase(GamePhase.GAME_OVER)
		return
	# 正常进入下一回合
	for player in _players:
		if player.paralyze_turns > 0 and player.current_gesture == PlayerState.Gesture.SKIP:
			player.paralyze_turns -= 1
			if player.paralyze_turns == 0:
				player_paralyzed.emit(player.player_id, 0)
		# 减少失去技能回合数
		if player.skill_disabled_turns > 0:
			player.skill_disabled_turns -= 1
			if player.skill_disabled_turns == 0:
				skill_disabled.emit(player.player_id, 0)
		# 减少击飞回合数（仅在击飞本回合实际生效——强制聚气——后才递减）
		if player.knockdown_turns > 0 and player.knockdown_consumed_this_round:
			player.knockdown_turns -= 1
			if player.knockdown_turns == 0:
				player_knocked_down.emit(player.player_id, 0)
		# 无敌回合递减
		if player.invincible_turns > 0:
			player.invincible_turns -= 1
		# 跺脚激活回合递减
		if player.stomp_active > 0:
			player.stomp_active -= 1
		# 卫宫·无限剑制结界回合递减（全局回合结束）
		if player.binding_field_turns > 0:
			player.binding_field_turns -= 1
			if player.binding_field_turns == 0:
				player.binding_field_targets.clear()
				player.binding_field_skills.clear()
				binding_field_ended.emit(player.player_id)
		player.reset_round_data()
	_enter_phase(GamePhase.GESTURE_INPUT)

## 处理延迟伤害队列：每回合结束时 tick 倒计时，触发的伤害执行吸收链
func _process_delayed_damages() -> void:
	for player in get_alive_players():
		var triggered: Array[Dictionary] = []
		for entry in player.delayed_damages:
			entry["trigger_in"] -= 1
			if entry["trigger_in"] <= 0:
				triggered.append(entry)
		for entry in triggered:
			player.delayed_damages.erase(entry)
			_apply_delayed_damage(player, entry["damage"], entry.get("attacker_id", -1))

## 应用单次延迟伤害：遵循无敌→防反→影分身→无限盾→数值盾→HP的吸收顺序
## 若来源为希耶尔，其被动（代行者/相位滑剑/暴击）同样生效
func _apply_delayed_damage(player: PlayerState, damage: float, attacker_id: int = -1) -> void:
	# 无敌状态：完全免疫延迟伤害
	if player.invincible_turns > 0:
		delayed_damage_triggered.emit(player.player_id, 0.0, player.hp)
		return
	var dmg: float = damage
	var clone_broken: bool = false
	# ── 希耶尔被动强化（仅来源为希耶尔时生效）──
	var xiye_attacker: PlayerState = null
	if attacker_id >= 0 and RoundResolver.is_xiye(get_player(attacker_id)):
		xiye_attacker = get_player(attacker_id)
		dmg += RoundResolver.agent_bonus(xiye_attacker, player)
		var ps := RoundResolver.phase_sword_pre_apply(xiye_attacker, dmg)
		dmg *= ps["multiplier"]
		var crit := RoundResolver.crit_check(xiye_attacker)
		dmg *= crit["multiplier"]
	# 防反拦截
	## 防反为持续状态：触发后保持到自身下回合开始（_start_action_input）才清除
	## 被控制（麻痹/封技）期间：招架状态保留但不触发（不减伤、不得气、不反击）
	if player.counter_stance and not RoundResolver.is_controlled(player):
		dmg = ceilf(dmg / 2.0)
		player.add_energy(1)
		# 反击1伤给来源（防反反击不触发钟获取）
		if attacker_id >= 0:
			var attacker := get_player(attacker_id)
			if attacker and attacker.is_alive:
				attacker.hp = max(0.0, attacker.hp - 1.0)
				# 防反反击1伤计入统计：防反者造成1伤害，来源者承受1伤害
				var c_stats: PlayerMatchStats = _match_record.player_stats.get(player.player_id)
				if c_stats:
					c_stats.total_damage_dealt += 1.0
				var a_stats: PlayerMatchStats = _match_record.player_stats.get(attacker_id)
				if a_stats:
					a_stats.total_damage_taken += 1.0
				counter_stance_triggered.emit(player.player_id, attacker_id)
		# 触发后取消招架状态
		player.counter_stance = false
		counter_stance_ended.emit(player.player_id)
	elif player.clone_count > 0:
		# 影分身吸收
		player.clone_count -= 1
		dmg = 0
		clone_broken = true
	elif player.shield == -1:
		dmg = 0
		player.shield = 0
	elif player.shield > 0:
		dmg = max(0.0, damage - player.shield)
		player.shield = max(0.0, player.shield - damage)
	player.hp = max(0.0, player.hp - dmg)
	if dmg > 0:
		player.took_damage_this_round = true
		if attacker_id >= 0:
			player.last_hit_by_id = attacker_id
	# 伤害致目标濒死 → 希耶尔置位可暴击
	if attacker_id >= 0 and dmg > 0 and player.hp <= 0:
		var x_att := get_player(attacker_id)
		if x_att and RoundResolver.is_xiye(x_att):
			x_att.can_crit_next = true
	if dmg > 0:
		if attacker_id >= 0:
			var a_stats: PlayerMatchStats = _match_record.player_stats.get(attacker_id)
			if a_stats:
				a_stats.total_damage_dealt += dmg
		var v_stats: PlayerMatchStats = _match_record.player_stats.get(player.player_id)
		if v_stats:
			v_stats.total_damage_taken += dmg
	if clone_broken:
		clone_destroyed.emit(player.player_id)
	delayed_damage_triggered.emit(player.player_id, dmg, player.hp)

## 结束游戏：填充 MatchRecord 最终数据，发射 game_over 信号
func _finish_game() -> void:
	var alive := get_alive_players()
	var winner_id := -1
	if alive.size() == 1:
		winner_id = alive[0].player_id
	_match_record.total_rounds = _current_round_number
	_match_record.winner_id = winner_id
	for p in _players:
		var stats: PlayerMatchStats = _match_record.player_stats.get(p.player_id)
		if stats:
			stats.final_hp = p.hp
			for s in p.unlocked_skills:
				stats.unlocked_skills.append(s.skill_name)
	game_over.emit(winner_id, _match_record)

## ── 数据收集 ──────────────────────────────────────────────────────────────────
## 初始化对局记录：为每位玩家创建空的 PlayerMatchStats
func _init_match_record() -> void:
	_match_record = MatchRecord.new()
	for p in _players:
		var stats := PlayerMatchStats.new()
		stats.player_id = p.player_id
		stats.player_name = p.player_name
		stats.character = p.character
		stats.is_human = p.is_human
		stats.max_hp = p.character.max_hp
		_match_record.player_stats[p.player_id] = stats

## 记录回合快照：新建 RoundSnapshot 并填充手势、胜负、玩家状态
func _record_round_snapshot(result: Dictionary) -> void:
	var snap := RoundSnapshot.new()
	snap.round_number = _current_round_number
	for player in _players:
		if player.is_alive:
			snap.gestures[player.player_id] = player.current_gesture
	snap.winners.assign(result.get("winners", []))
	if not result.get("is_draw", false):
		for id in snap.gestures:
			if not snap.winners.has(int(id)):
				snap.losers.append(int(id))
	snap.is_draw = result.get("is_draw", false)
	for player in _players:
		var ss := PlayerStateSnapshot.new()
		ss.player_id = player.player_id
		ss.hp = player.hp
		ss.energy = player.energy
		ss.has_shield = (player.shield != 0)
		ss.paralyze_turns = player.paralyze_turns
		ss.knockdown_turns = player.knockdown_turns
		ss.is_alive = player.is_alive
		ss.bell_count = player.bell_count
		ss.counter_stance = player.counter_stance
		ss.skill_disabled_turns = player.skill_disabled_turns
		ss.gate_count = player.gate_count
		ss.invincible_turns = player.invincible_turns
		ss.burning = player.burning
		ss.berserker = player.berserker
		ss.consecutive_rounds = player.consecutive_rounds
		ss.lost_skills = player.lost_skills.duplicate()
		ss.ftg_marks = player.ftg_marks
		ss.ftg_marked_by = player.ftg_marked_by.duplicate()
		ss.nine_tails_stage = player.nine_tails_stage
		ss.nine_tails_invincible = player.nine_tails_invincible
		ss.max_energy = player.max_energy
		ss.stomp_active = player.stomp_active
		ss.force_win_next_round = player.force_win_next_round
		ss.glory_unlocked = player.glory_unlocked
		ss.untargetable_turns = player.untargetable_turns
		snap.player_states_after.append(ss)
	_match_record.round_snapshots.append(snap)
	_current_snapshot = snap

## 记录行动：更新玩家统计、构建 ActionLog 和 SkillUseLog
func _record_action(winner: PlayerState, skill: SkillData, logs: Array[Dictionary]) -> void:
	var stats: PlayerMatchStats = _match_record.player_stats.get(winner.player_id)
	if stats == null:
		return
	stats.skill_use_count += 1
	for entry in logs:
		var etype: int = entry.get("effect_type", -1)
		var res: Dictionary = entry.get("result", {})
		# 防反反击伤害补记：无论哪种伤害效果触发防反，反击1伤由防反者(目标)造成、攻击者(winner)承受
		if res.get("counter_stance_triggered", false):
			var tid: int = entry.get("target_id", -1)
			var c_stats: PlayerMatchStats = _match_record.player_stats.get(tid)
			if c_stats:
				c_stats.total_damage_dealt += 1.0
			stats.total_damage_taken += 1.0
		match etype:
			SkillEffect.EffectType.DAMAGE:
				stats.total_damage_dealt += res.get("damage_dealt", 0)
				var tid: int = entry.get("target_id", -1)
				var t_stats: PlayerMatchStats = _match_record.player_stats.get(tid)
				if t_stats:
					t_stats.total_damage_taken += res.get("damage_dealt", 0)
			SkillEffect.EffectType.TRUE_DAMAGE:
				stats.total_damage_dealt += res.get("damage_dealt", 0)
				var tid: int = entry.get("target_id", -1)
				var t_stats: PlayerMatchStats = _match_record.player_stats.get(tid)
				if t_stats:
					t_stats.total_damage_taken += res.get("damage_dealt", 0)
			SkillEffect.EffectType.PIERCE_DAMAGE:
				stats.total_damage_dealt += res.get("damage_dealt", 0)
				var tid: int = entry.get("target_id", -1)
				var t_stats: PlayerMatchStats = _match_record.player_stats.get(tid)
				if t_stats:
					t_stats.total_damage_taken += res.get("damage_dealt", 0)
			SkillEffect.EffectType.DEATH_SENTENCE:
				stats.total_damage_dealt += res.get("damage_dealt", 0)
				stats.total_healing += res.get("total_heal", 0)
				var tid: int = entry.get("target_id", -1)
				var t_stats: PlayerMatchStats = _match_record.player_stats.get(tid)
				if t_stats:
					t_stats.total_damage_taken += res.get("damage_dealt", 0)
			SkillEffect.EffectType.HEAL:
				stats.total_healing += res.get("heal_amount", 0)
			SkillEffect.EffectType.PARALYZE:
				stats.paralyze_applied_count += 1
				var tid: int = entry.get("target_id", -1)
				var t_stats: PlayerMatchStats = _match_record.player_stats.get(tid)
				if t_stats:
					t_stats.paralyze_suffered_count += 1
			SkillEffect.EffectType.SHIELD:
				var tid: int = entry.get("target_id", -1)
				var t_stats: PlayerMatchStats = _match_record.player_stats.get(tid)
				if t_stats:
					t_stats.shield_blocked_count += 1
			SkillEffect.EffectType.FTG_MARK:
				stats.total_damage_dealt += res.get("damage_dealt", 0)
				var tid: int = entry.get("target_id", -1)
				var t_stats: PlayerMatchStats = _match_record.player_stats.get(tid)
				if t_stats:
					t_stats.total_damage_taken += res.get("damage_dealt", 0)
	# Build ActionLog for snapshot
	var alog := ActionLog.new()
	alog.actor_id = winner.player_id
	alog.action_type = PlayerState.ActionType.USE_SKILL
	alog.skill_name = skill.skill_name
	for entry in logs:
		var tid: int = entry.get("target_id", -1)
		alog.target_ids.append(tid)
		alog.effect_results.append(entry.get("result", {}))
	if _current_snapshot:
		_current_snapshot.actions.append(alog)

	# Build SkillUseLog
	var slog := SkillUseLog.new()
	slog.round_number = _current_round_number
	slog.actor_id = winner.player_id
	slog.actor_name = winner.player_name
	slog.skill_name = skill.skill_name
	for entry in logs:
		var tid: int = entry.get("target_id", -1)
		var tp := get_player(tid)
		if tp:
			slog.target_names.append(tp.player_name)
		var res: Dictionary = entry.get("result", {})
		slog.total_damage += res.get("damage_dealt", 0)
	# Build effects summary
	var parts: Array[String] = []
	for entry in logs:
		var etype: int = entry.get("effect_type", -1)
		var res: Dictionary = entry.get("result", {})
		match etype:
			SkillEffect.EffectType.DAMAGE:
				parts.append("%d伤害" % res.get("damage_dealt", 0))
				if res.get("paralyze_bonus", 0) > 0:
					parts.append("禁锢+1")
				if res.get("counter_stance_triggered", false):
					parts.append("防反")
			SkillEffect.EffectType.PARALYZE:
				if res.get("counter_immune", false):
					parts.append("免疫控制")
				else:
					parts.append("麻痹%d回合" % res.get("turns", 0))
			SkillEffect.EffectType.SHIELD:
				var sv: int = res.get("shield_value", 0)
				parts.append("全挡" if sv == -1 else "护盾%d" % sv)
			SkillEffect.EffectType.DELAYED_DAMAGE:
				parts.append("延迟%d伤" % res.get("damage", 0))
			SkillEffect.EffectType.HEAL:
				parts.append("回复%d" % res.get("heal_amount", 0))
			SkillEffect.EffectType.CLONE_SHIELD:
				parts.append("影分身")
			SkillEffect.EffectType.UNLOCK_SKILL:
				parts.append("解锁技能")
			SkillEffect.EffectType.DISABLE_SKILL:
				if res.get("counter_immune", false):
					parts.append("免疫封技")
				else:
					parts.append("封技%d回合" % res.get("disabled_turns", 0))
			SkillEffect.EffectType.COUNTER_STANCE:
				parts.append("防反")
			SkillEffect.EffectType.TRUE_DAMAGE:
				parts.append("真实%d伤" % res.get("damage_dealt", 0))
			SkillEffect.EffectType.PIERCE_DAMAGE:
				parts.append("穿透%d伤" % res.get("damage_dealt", 0))
				if res.get("crit", false):
					parts.append("暴击")
			SkillEffect.EffectType.DEATH_SENTENCE:
				if res.get("instant_kill", false):
					parts.append("即死")
				else:
					parts.append("断罪%d伤" % res.get("damage_dealt", 0))
				if res.get("total_heal", 0) > 0:
					parts.append("回复%d" % res.get("total_heal", 0))
			SkillEffect.EffectType.LOSE_SKILL:
				parts.append("失去技能")
			SkillEffect.EffectType.FTG_MARK:
				parts.append("飞雷神标记(%.1f伤)" % res.get("damage_dealt", 0))
			SkillEffect.EffectType.FTG_CHARGE:
				parts.append("飞雷神+1")
			SkillEffect.EffectType.FTG_REMOVE:
				parts.append("拔除飞雷神")
			SkillEffect.EffectType.NINE_TAILS:
				parts.append("漂泊九尾释放")
	slog.effects_summary = " + ".join(parts) if parts.size() > 0 else "-"
	_match_record.skill_use_logs.append(slog)

## ── 公开方法 ───────────────────────────────────────────────────────────────────
## 提交手势（由UI调用）：仅在 GESTURE_INPUT 阶段有效，全部提交后自动进入结算
# 立即处理所有待提交的 AI 手势（跳过 timer 延时）
func _flush_pending_ai_gestures() -> void:
	if _current_phase != GamePhase.GESTURE_INPUT:
		return
	for p in _players:
		if p.is_alive and not p.is_human and p.current_gesture == PlayerState.Gesture.NONE:
			var g := _ai_controller.decide_gesture(p)
			p.current_gesture = g
			gesture_submitted.emit(p.player_id, g)
	if _all_gestures_submitted():
		_enter_phase(GamePhase.RESOLVING)

func submit_gesture(player_id: int, gesture: PlayerState.Gesture) -> void:
	if _current_phase != GamePhase.GESTURE_INPUT:
		return
	var player := get_player(player_id)
	if player == null or not player.is_alive:
		return
	player.current_gesture = gesture
	gesture_submitted.emit(player_id, gesture)
	if _all_gestures_submitted():
		_enter_phase(GamePhase.RESOLVING)
	elif player.is_human:
		_flush_pending_ai_gestures()

## 提交加赛手势：仅在 TIEBREAK_INPUT 阶段有效，仅加赛候选玩家可提交
func _flush_pending_ai_tiebreak_gestures() -> void:
	if _current_phase != GamePhase.TIEBREAK_INPUT:
		return
	for tid in _tiebreak_candidates:
		var p := get_player(tid)
		if p != null and p.is_alive and not p.is_human and p.current_gesture == PlayerState.Gesture.NONE:
			var g := _ai_controller.decide_gesture(p)
			p.current_gesture = g
			gesture_submitted.emit(p.player_id, g)
	if _all_tiebreak_gestures_submitted():
		_enter_phase(GamePhase.TIEBREAK_RESOLVING)

func submit_tiebreak_gesture(player_id: int, gesture: PlayerState.Gesture) -> void:
	if _current_phase != GamePhase.TIEBREAK_INPUT:
		return
	if not _tiebreak_candidates.has(player_id):
		return
	var player := get_player(player_id)
	if player == null or not player.is_alive:
		return
	player.current_gesture = gesture
	gesture_submitted.emit(player_id, gesture)
	if _all_tiebreak_gestures_submitted():
		_enter_phase(GamePhase.TIEBREAK_RESOLVING)
	elif player.is_human:
		_flush_pending_ai_tiebreak_gestures()

## 提交荣耀释放决策（由UI调用）：人类泉奈在准备阶段选择是否释放荣耀
func submit_glory_decision(player_id: int, use_glory: bool) -> void:
	if _current_phase != GamePhase.PREPARATION:
		return
	var player := get_player(player_id)
	if player == null or not player.is_alive:
		return
	if use_glory:
		var target := get_player(_sole_winner_id)
		if target == null or not target.is_alive:
			_process_prep_next()
			return
		_apply_glory_takeover(player, target)
	_process_prep_next()

## 提交行动选择（由UI调用）：仅在 ACTION_INPUT 阶段有效，立即进入 APPLYING
func submit_action(player_id: int, action: PlayerState.ActionType, skill_index: int, target_id: int, hp_paid: int = 0) -> void:
	print("[GameManager] submit_action player_id=%d action=%d skill=%d target=%d hp_paid=%d phase=%d" % [player_id, action, skill_index, target_id, hp_paid, _current_phase])
	if _current_phase != GamePhase.ACTION_INPUT:
		print("[GameManager] submit_action REJECT: not in ACTION_INPUT")
		return
	var player := get_player(player_id)
	if player == null:
		print("[GameManager] submit_action REJECT: player not found")
		return
	player.pending_action      = action
	player.pending_skill_index = skill_index
	player.skill_target_id     = target_id
	player.pending_hp_payment  = hp_paid
	print("[GameManager] submit_action ACCEPT: entering APPLYING")
	_enter_phase(GamePhase.APPLYING)

## 获取所有存活玩家的数组
func get_alive_players() -> Array[PlayerState]:
	var result: Array[PlayerState] = []
	for player in _players:
		if player.is_alive:
			result.append(player)
	return result

## 根据ID获取玩家状态，不存在返回 null
func get_player(player_id: int) -> PlayerState:
	for player in _players:
		if player.player_id == player_id:
			return player
	return null

## 获取两玩家间的环形距离（委托给 DistanceSystem）
func get_distance(from_id: int, to_id: int) -> int:
	return _distance_system.get_distance(from_id, to_id)

## 在角色的所有技能（含解锁技能）中按名称查找
func _get_skill_by_name(player: PlayerState, skill_name: String) -> SkillData:
	for skill in player.character.skills:
		if skill.skill_name == skill_name:
			return skill
	for skill in player.unlocked_skills:
		if skill.skill_name == skill_name:
			return skill
	return null

## 创建技能副本，对第一个DAMAGE/TRUE_DAMAGE效果的value叠加bonus
## 用于夕象连续回合增伤（不修改原始资源）
func _copy_skill_with_bonus(skill: SkillData, bonus: int) -> SkillData:
	var copy := SkillData.new()
	copy.skill_name = skill.skill_name
	copy.description = skill.description
	copy.energy_cost = skill.energy_cost
	copy.min_range = skill.min_range
	copy.max_range = skill.max_range
	copy.bell_cost = skill.bell_cost
	copy.is_limited = skill.is_limited
	copy.bonus_if_paralyzed = skill.bonus_if_paralyzed
	copy.is_passive = skill.is_passive
	copy.can_pay_with_hp = skill.can_pay_with_hp
	copy.ftg_cost = skill.ftg_cost
	# 复制效果列表，第一个伤害类效果增加bonus
	var bonus_applied := false
	for effect in skill.effects:
		var ecopy := SkillEffect.new()
		ecopy.effect_type = effect.effect_type
		ecopy.value = effect.value
		ecopy.target = effect.target
		ecopy.duration = effect.duration
		ecopy.unlock_skill = effect.unlock_skill
		ecopy.splash_range = effect.splash_range
		ecopy.bonus_if_paralyzed = effect.bonus_if_paralyzed
		ecopy.lose_skill_name = effect.lose_skill_name
		if not bonus_applied and (effect.effect_type == SkillEffect.EffectType.DAMAGE or effect.effect_type == SkillEffect.EffectType.TRUE_DAMAGE):
			ecopy.value = effect.value + bonus
			bonus_applied = true
		copy.effects.append(ecopy)
	return copy

## 创建技能副本，对第一个DAMAGE/TRUE_DAMAGE效果的value叠加浮点bonus
## 用于新止水·幻影瞬身普攻增伤（每个幻影+0.5，不修改原始资源）
func _copy_skill_with_float_bonus(skill: SkillData, bonus: float) -> SkillData:
	var copy := SkillData.new()
	copy.skill_name = skill.skill_name
	copy.description = skill.description
	copy.energy_cost = skill.energy_cost
	copy.min_range = skill.min_range
	copy.max_range = skill.max_range
	copy.bell_cost = skill.bell_cost
	copy.is_limited = skill.is_limited
	copy.bonus_if_paralyzed = skill.bonus_if_paralyzed
	copy.is_passive = skill.is_passive
	copy.can_pay_with_hp = skill.can_pay_with_hp
	copy.ftg_cost = skill.ftg_cost
	# 复制效果列表，第一个伤害类效果增加浮点bonus
	var bonus_applied := false
	for effect in skill.effects:
		var ecopy := SkillEffect.new()
		ecopy.effect_type = effect.effect_type
		ecopy.value = effect.value
		ecopy.target = effect.target
		ecopy.duration = effect.duration
		ecopy.unlock_skill = effect.unlock_skill
		ecopy.splash_range = effect.splash_range
		ecopy.bonus_if_paralyzed = effect.bonus_if_paralyzed
		ecopy.lose_skill_name = effect.lose_skill_name
		if not bonus_applied and (effect.effect_type == SkillEffect.EffectType.DAMAGE or effect.effect_type == SkillEffect.EffectType.TRUE_DAMAGE):
			ecopy.value = effect.value + bonus
			bonus_applied = true
		copy.effects.append(ecopy)
	return copy

## ── 波风水门辅助方法 ──────────────────────────────────────────────────────────
## 检查角色是否为波风水门（通过技能名"飞雷神"判断）
func _is_minato(player: PlayerState) -> bool:
	for skill in player.character.skills:
		if skill.skill_name == "飞雷神":
			return true
	return false

## ── 秽土柱间辅助方法 ──────────────────────────────────────────────────────────
## 检查角色是否为秽土柱间（通过独有技能"仙法·树界降诞"判断）
## 注意：不能用"仙人之力"判断——仙人鸣人（仙人模式）也有同名被动技能（聚气+1），会误判
func _is_edo_hashirama(player: PlayerState) -> bool:
	if player == null or player.character == null:
		return false
	for skill in player.character.skills:
		if skill.skill_name == "仙法·树界降诞":
			return true
	return false

## 跺脚受击触发：检查技能日志中受击者是否有 stomp_active > 0
## 若受击者有跺脚激活，获得1气 + 设置 force_win_next_round
func _process_stomp_trigger(attacker: PlayerState, logs: Array[Dictionary]) -> void:
	for entry in logs:
		var res: Dictionary = entry.get("result", {})
		# 只对实际造成伤害的效果触发（DAMAGE/TRUE_DAMAGE/PIERCE_DAMAGE/FTG_MARK）
		var dmg_dealt: float = res.get("damage_dealt", 0)
		if dmg_dealt <= 0:
			continue
		var target_id: int = entry.get("target_id", -1)
		if target_id < 0:
			continue
		var target := get_player(target_id)
		if target == null or not target.is_alive:
			continue
		if target.stomp_active > 0:
			# 跺脚触发：获得1气 + 下回合强制判胜
			target.add_energy(1)
			target.force_win_next_round = true
			player_charged.emit(target_id, target.energy)

## ── 黑塔辅助方法与被动处理 ──────────────────────────────────────────────
## 检查角色是否为黑塔（通过技能名"送你砖石"判断）
func _is_herta(player: PlayerState) -> bool:
	if player == null or player.character == null:
		return false
	for skill in player.character.skills:
		if skill.skill_name == "送你砖石":
			return true
	return false

## 黑塔被动结算：在技能伤害应用后调用
## 1. genjutsu：对每个受到实际伤害的目标，黑塔对其距离-1（本结算链每玩家至多一次，可跨回合累积至最小1）
## 2. 送你砖石：目标血量从 ≥50% 跨到 <50% 时，对与黑塔距离≤1的所有其他玩家造成1点伤害
##    砖石AOE伤害本身也触发 genjutsu 与砖石（连锁触发），每玩家每结算链至多作为触发源一次（防无限循环）
## hp_before：本次伤害结算前各存活玩家的HP快照 {player_id: hp}
## triggered_ids：本结算链已作为砖石触发源的玩家ID（递归传递）
func _process_herta_passives(winner: PlayerState, logs: Array[Dictionary], hp_before: Dictionary, triggered_ids: Array[int]) -> void:
	if not _is_herta(winner):
		return
	var new_triggers: Array[int] = []
	var genjutsu_done: Array[int] = []
	for entry in logs:
		var res: Dictionary = entry.get("result", {})
		if res.get("damage_dealt", 0) <= 0:
			continue
		var target_id: int = entry.get("target_id", -1)
		if target_id < 0:
			continue
		var target := get_player(target_id)
		if target == null or not target.is_alive:
			continue
		# genjutsu：对受伤玩家距离-1
		if not genjutsu_done.has(target_id):
			genjutsu_done.append(target_id)
			_distance_system.modify_distance(winner.player_id, target_id, -1)
			distance_changed.emit(winner.player_id, target_id, _distance_system.get_distance(winner.player_id, target_id))
		# 送你砖石：血量跨过50%阈值（伤前≥50% 且 伤后<50%）
		var before: float = hp_before.get(target_id, target.hp)
		var half: float = target.character.max_hp * 0.5
		if before >= half and target.hp < half and not triggered_ids.has(target_id):
			triggered_ids.append(target_id)
			new_triggers.append(target_id)
	# 砖石 AOE：对黑塔距离≤1的所有其他玩家各造成1点伤害（正常吸收链）
	for trigger_id in new_triggers:
		var aoe_target_ids: Array[int] = []
		var aoe_logs: Array[Dictionary] = []
		var aoe_hp_before: Dictionary = {}
		for p in get_alive_players():
			if p.player_id == winner.player_id:
				continue
			if _distance_system.get_distance(winner.player_id, p.player_id) > 1:
				continue
			aoe_hp_before[p.player_id] = p.hp
			aoe_target_ids.append(p.player_id)
			var e := SkillEffect.new()
			e.effect_type = SkillEffect.EffectType.DAMAGE
			e.value = 1.0
			e.target = SkillEffect.EffectTarget.ENEMY_SINGLE
			var res := RoundResolver.apply_effect_standalone(e, winner, p, _distance_system)
			aoe_logs.append({
				"attacker_id": winner.player_id,
				"target_id":   p.player_id,
				"effect_type": SkillEffect.EffectType.DAMAGE,
				"value":       1.0,
				"result":      res,
			})
		if aoe_target_ids.size() > 0:
			herta_diamond_triggered.emit(winner.player_id, aoe_target_ids)
		# 连锁：AOE伤害继续触发 genjutsu + 砖石（每玩家每链至多一次）
		if not aoe_logs.is_empty():
			_process_herta_passives(winner, aoe_logs, aoe_hp_before, triggered_ids)
		# 黑塔砖石AOE伤害也触发大黑塔的格局打开（【解】玩家受伤回气）
		_process_bigherta_effects(winner, aoe_logs)

## ── 大黑塔被动处理：解读标记 + 格局打开 ──────────────────────────────
## 在任何伤害结算后调用（攻击者可为任何角色，格局打开对任何来源生效）
## 1. 解读：若攻击者是大黑塔，对每个实际受伤目标施加【解】标记（一次性）+ 距离-1
## 2. 格局打开：对每个受伤且带【解】的目标，仅该标记来源的大黑塔获得1气（每次伤害+1）
##    注：极端情况下多个大黑塔同时在场，回气只给标记该目标的那个大黑塔
func _process_bigherta_effects(attacker: PlayerState, logs: Array[Dictionary]) -> void:
	var is_herta_attack: bool = RoundResolver.is_big_herta(attacker)
	for entry in logs:
		var res: Dictionary = entry.get("result", {})
		if res.get("damage_dealt", 0) <= 0:
			continue
		var target_id: int = entry.get("target_id", -1)
		if target_id < 0:
			continue
		var target := get_player(target_id)
		if target == null or not target.is_alive:
			continue
		# 记录本次伤害前该目标已有的标记来源（格局打开只回气给既有标记者）
		var existing_markers: Array[int] = target.jiedu_by.duplicate()
		# 解读：大黑塔造成伤害 → 目标获得该大黑塔的【解】（按施法者区分，不覆盖他人标记）
		if is_herta_attack and not target.jiedu_by.has(attacker.player_id):
			target.jiedu_by.append(attacker.player_id)
			_distance_system.modify_distance(attacker.player_id, target_id, -1)
			distance_changed.emit(attacker.player_id, target_id, _distance_system.get_distance(attacker.player_id, target_id))
			jiedu_applied.emit(target_id, attacker.player_id)
		# 格局打开：【解】玩家受伤 → 每个既有标记者（伤害前已标记）各+1气
		# 本次伤害刚施加的新标记不参与本次回气（严格"【解】玩家受到伤害"语义）
		for mid in existing_markers:
			var mark_owner := get_player(mid)
			if mark_owner != null and mark_owner.is_alive:
				mark_owner.add_energy(1)
				player_charged.emit(mark_owner.player_id, mark_owner.energy)
				open_mind_triggered.emit(mark_owner.player_id)

## ── 慈悲尖塔敌人机制 ─────────────────────────────────────────────────
## 检查角色是否拥有指定技能（含解锁技能）
func _tower_has_skill(player: PlayerState, skill_name: String) -> bool:
	if player == null or player.character == null:
		return false
	for skill in player.character.skills:
		if skill.skill_name == skill_name:
			return true
	for skill in player.unlocked_skills:
		if skill.skill_name == skill_name:
			return true
	return false

## 尖塔祝福：开局获得2个气
func _has_tower_blessing(player: PlayerState) -> bool:
	return _tower_has_skill(player, "尖塔祝福")

## 破败王者之刃（锁定技）：普攻命中后按阶段触发
## 阶段1（第1次普攻）：附带目标现有生命值（普攻结算前）50%的伤害
## 阶段2（第2次普攻）：恢复自身一半生命值
## 阶段3（第3次普攻）：获得2个气
## 悲痛：血量低于一半时刷新阶段（重新从阶段1开始）
func _process_blade_of_the_fallen(attacker: PlayerState, target: PlayerState, hp_before: float = -1.0) -> void:
	if attacker == null or target == null:
		return
	if not _tower_has_skill(attacker, "破败王者之刃"):
		return
	# 悲痛：血量低于一半时刷新阶段
	if attacker.hp < attacker.character.max_hp * 0.5:
		attacker.blade_stage = 0
	if attacker.blade_stage >= 3:
		return  # 三次用完，等待悲痛刷新
	match attacker.blade_stage:
		0:
			# 附带目标现有生命值（普攻结算前）50%的伤害（走正常吸收链）
			var before_hp: float = hp_before if hp_before >= 0.0 else target.hp
			var extra := SkillEffect.new()
			extra.effect_type = SkillEffect.EffectType.DAMAGE
			extra.value = before_hp * 0.5
			extra.target = SkillEffect.EffectTarget.ENEMY_SINGLE
			RoundResolver.apply_effect_standalone(extra, attacker, target, _distance_system)
		1:
			# 恢复自身一半生命值（最大生命值的一半）
			var heal: float = attacker.character.max_hp * 0.5
			attacker.hp = min(attacker.character.max_hp, attacker.hp + heal)
		2:
			# 获得2个气
			attacker.add_energy(2)
			player_charged.emit(attacker.player_id, attacker.energy)
	attacker.blade_stage += 1

## 反馈（司马懿）：普攻命中后附加怒标记数的真实伤害，然后清空怒
func _process_fury_burst(attacker: PlayerState, target: PlayerState) -> void:
	if attacker == null or target == null:
		return
	if not _tower_has_skill(attacker, "反馈"):
		return
	if attacker.fury_marks <= 0:
		return
	var e := SkillEffect.new()
	e.effect_type = SkillEffect.EffectType.TRUE_DAMAGE
	e.value = float(attacker.fury_marks)
	e.target = SkillEffect.EffectTarget.ENEMY_SINGLE
	RoundResolver.apply_effect_standalone(e, attacker, target, _distance_system)
	attacker.fury_marks = 0

## 鬼才（司马懿）：连续获得两回合时，额外获得一个回合（复用强制判胜）
## 每连赢2回合触发一次（consecutive_rounds % 2 == 0），由 _start_action_input 调用
func _process_genius(winner: PlayerState) -> void:
	if winner == null or not winner.is_alive:
		return
	if not _tower_has_skill(winner, "鬼才"):
		return
	if winner.consecutive_rounds >= 2 and winner.consecutive_rounds % 2 == 0:
		winner.force_win_next_round = true

## ── 漂泊九尾释放处理 ──────────────────────────────────────────────────────────
## 释放时：进入无敌 + 咆哮（0.5x3伤害对所有其他玩家）
func _process_nine_tails_release(caster: PlayerState) -> void:
	caster.nine_tails_invincible = true
	nine_tails_invincible_started.emit(caster.player_id)
	caster.nine_tails_stage = 1
	nine_tails_stage_changed.emit(caster.player_id, 1)
	# 咆哮：对所有其他玩家造成0.5x3伤害
	var target_ids: Array[int] = []
	for p in get_alive_players():
		if p.player_id != caster.player_id:
			target_ids.append(p.player_id)
			# 3次0.5伤害
			for i in range(3):
				_apply_nine_tails_damage(p, 0.5, caster)
	nine_tails_attack.emit(caster.player_id, 1, 0.5, target_ids)

## 九尾阶段推进（在 _end_round 中调用）
func _process_nine_tails_progress() -> void:
	for player in get_alive_players():
		if player.nine_tails_stage == 0:
			continue
		if player.nine_tails_stage == 1:
			# 阶段2：大爪——对范围2内所有其他玩家造成1x2伤害
			player.nine_tails_stage = 2
			nine_tails_stage_changed.emit(player.player_id, 2)
			var target_ids: Array[int] = []
			for p in get_alive_players():
				if p.player_id != player.player_id:
					var dist: int = _distance_system.get_distance(player.player_id, p.player_id)
					if dist <= 2:
						target_ids.append(p.player_id)
						for i in range(2):
							_apply_nine_tails_damage(p, 1.0, player)
			nine_tails_attack.emit(player.player_id, 2, 1.0, target_ids)
		elif player.nine_tails_stage == 2:
			# 阶段3：尾兽玉——对所有其他玩家造成4伤害，然后退出无敌
			player.nine_tails_stage = 3
			nine_tails_stage_changed.emit(player.player_id, 3)
			var target_ids: Array[int] = []
			for p in get_alive_players():
				if p.player_id != player.player_id:
					target_ids.append(p.player_id)
					_apply_nine_tails_damage(p, 4.0, player)
			nine_tails_attack.emit(player.player_id, 3, 4.0, target_ids)
			# 退出无敌
			player.nine_tails_invincible = false
			player.nine_tails_stage = 0
			nine_tails_invincible_ended.emit(player.player_id)
			nine_tails_stage_changed.emit(player.player_id, 0)

## 九尾伤害应用：遵循无敌→防反→影分身→护盾→HP的吸收链
func _apply_nine_tails_damage(target: PlayerState, damage: float, caster: PlayerState) -> void:
	# 无敌状态（包括九尾无敌自身不受伤）
	if target.invincible_turns > 0 or target.nine_tails_invincible:
		return
	var dmg: float = damage
	# 防反拦截
	## 被控制（麻痹/封技）期间：招架状态保留但不触发
	## 触发后立即取消招架状态（一次性的防反）
	if target.counter_stance and not RoundResolver.is_controlled(target):
		dmg = ceilf(dmg / 2.0)
		target.add_energy(1)
		caster.hp = max(0.0, caster.hp - 1.0)
		# 防反反击1伤计入统计：防反者造成1伤害，来源者承受1伤害
		var c_stats: PlayerMatchStats = _match_record.player_stats.get(target.player_id)
		if c_stats:
			c_stats.total_damage_dealt += 1.0
		var a_stats: PlayerMatchStats = _match_record.player_stats.get(caster.player_id)
		if a_stats:
			a_stats.total_damage_taken += 1.0
		counter_stance_triggered.emit(target.player_id, caster.player_id)
		# 触发后取消招架状态
		target.counter_stance = false
		counter_stance_ended.emit(target.player_id)
	elif target.clone_count > 0:
		target.clone_count -= 1
		dmg = 0
		clone_destroyed.emit(target.player_id)
	elif target.shield == -1:
		dmg = 0
		target.shield = 0
	elif target.shield > 0:
		dmg = max(0.0, dmg - target.shield)
		target.shield = max(0, target.shield - damage)
	target.hp = max(0.0, target.hp - dmg)
	if dmg > 0:
		target.took_damage_this_round = true
		target.last_hit_by_id = caster.player_id
		# 统计记录
		var a_stats: PlayerMatchStats = _match_record.player_stats.get(caster.player_id)
		if a_stats:
			a_stats.total_damage_dealt += dmg
		var v_stats: PlayerMatchStats = _match_record.player_stats.get(target.player_id)
		if v_stats:
			v_stats.total_damage_taken += dmg


## ── 飞雷神换位/闪避拦截逻辑 ──────────────────────────────────────────────────

## 检查目标中是否有波风水门且可触发换位/闪避
## 返回 Dictionary: { "pending": bool } 如果需要等待人类玩家决策
## 如果不需要拦截或AI已自动决策，直接修改 targets 并返回 {}
func _check_ftg_intercept(attacker: PlayerState, skill: SkillData, targets: Array[PlayerState]) -> Dictionary:
	# 止水技能由 GameManager 特殊处理（多段/无敌/延迟），不参与飞雷神拦截
	if skill.skill_name in ["宇智波流·日晕舞", "须佐能乎·斩", "须佐能乎·螺旋", "须佐能乎·九十九"]:
		return {}
	# 只对有伤害类效果的技能触发拦截
	var has_damage_effect := false
	for effect in skill.effects:
		if effect.target == SkillEffect.EffectTarget.ENEMY_SINGLE or effect.target == SkillEffect.EffectTarget.ENEMY_ALL:
			if effect.effect_type == SkillEffect.EffectType.DAMAGE \
			or effect.effect_type == SkillEffect.EffectType.FTG_MARK \
			or effect.effect_type == SkillEffect.EffectType.TRUE_DAMAGE \
			or effect.effect_type == SkillEffect.EffectType.PARALYZE \
			or effect.effect_type == SkillEffect.EffectType.DISABLE_SKILL:
				has_damage_effect = true
				break
	if not has_damage_effect:
		return {}

	# 检查每个目标是否为波风水门
	for target in targets:
		if not _is_minato(target):
			continue
		if not target.is_alive:
			continue

		# 收集场上有水门标记的其他玩家
		var marked_players: Array[int] = []
		for p in _players:
			if p.is_alive and p.player_id != target.player_id and p.player_id != attacker.player_id:
				if p.ftg_marked_by.has(target.player_id):
					marked_players.append(p.player_id)

		# 检查攻击者是否被水门标记
		var attacker_is_marked: bool = attacker.ftg_marked_by.has(target.player_id)

		# 无可用选项则不拦截
		if marked_players.is_empty() and not attacker_is_marked:
			continue

		# 人类玩家：发射信号等待UI决策
		if target.is_human:
			ftg_intercept_required.emit(target.player_id, attacker.player_id, marked_players, attacker_is_marked)
			return { "pending": true }

		# AI自动决策
		var choice := _ai_decide_ftg_intercept(target, attacker, marked_players, attacker_is_marked)
		_apply_ftg_choice(target, attacker, choice, marked_players, targets)

	# 无需等待
	return {}

## ── 新止水·幻影瞬身闪避拦截逻辑 ───────────────────────────────────────────
## 检查目标中是否有新止水且可触发闪避（消耗1气+1幻影）
## 返回 Dictionary: { "pending": bool } 如果需要等待人类玩家决策
## 如果不需要拦截或AI已自动决策，直接修改 targets 并返回 {}
func _check_phantom_dodge_intercept(attacker: PlayerState, skill: SkillData, targets: Array[PlayerState]) -> Dictionary:
	# 止水技能由 GameManager 特殊处理，不参与幻影闪避拦截
	if skill.skill_name in ["宇智波流·日晕舞", "须佐能乎·斩", "须佐能乎·螺旋", "须佐能乎·九十九", "日影舞"]:
		return {}
	# 攻击者自己的幻影闪避无法拦截（不能闪避自己）
	# 只对有伤害类效果的技能触发拦截
	var has_damage_effect := false
	for effect in skill.effects:
		if effect.target == SkillEffect.EffectTarget.ENEMY_SINGLE or effect.target == SkillEffect.EffectTarget.ENEMY_ALL:
			if effect.effect_type == SkillEffect.EffectType.DAMAGE \
			or effect.effect_type == SkillEffect.EffectType.TRUE_DAMAGE \
			or effect.effect_type == SkillEffect.EffectType.PIERCE_DAMAGE:
				has_damage_effect = true
				break
	if not has_damage_effect:
		return {}

	# 检查每个目标是否为新止水且可闪避
	for target in targets:
		if target.player_id == attacker.player_id:
			continue
		if not _is_new_shisui(target):
			continue
		if not target.is_alive:
			continue
		# 闪避条件：气>=1 且 幻影>=1 且 未麻痹（麻痹状态不可使用任何技能）
		if target.energy < 1 or target.phantom_count < 1:
			continue
		if target.paralyze_turns > 0:
			continue

		# 人类玩家：发射信号等待UI决策
		if target.is_human:
			phantom_dodge_required.emit(target.player_id, attacker.player_id)
			return { "pending": true }

		# AI自动决策：闪避优先（保命）
		if _ai_decide_phantom_dodge(target, attacker):
			_apply_phantom_dodge(target, attacker, targets)

	# 无需等待
	return {}

## AI幻影闪避决策：残血时闪避，否则不闪避
func _ai_decide_phantom_dodge(target: PlayerState, attacker: PlayerState) -> bool:
	# 血量低于一半或即将死亡时闪避
	if target.hp <= target.character.max_hp * 0.5:
		return true
	# 对手是高威胁角色时闪避
	return false

## 应用幻影闪避：消耗1气+1幻影，从 targets 中移除该玩家
## 麻痹状态不可使用任何技能，直接忽略（防御性校验，正常路径已在 _check_phantom_dodge_intercept 拦截）
func _apply_phantom_dodge(target: PlayerState, attacker: PlayerState, targets: Array[PlayerState] = []) -> void:
	if target == null or target.paralyze_turns > 0:
		return
	target.energy = max(0, target.energy - 1)
	target.phantom_count = max(0, target.phantom_count - 1)
	phantom_changed.emit(target.player_id, target.phantom_count)
	phantom_dodge_triggered.emit(target.player_id, attacker.player_id)
	# 从 targets 中移除（闪避成功，本次伤害免疫）
	for i in range(targets.size() - 1, -1, -1):
		if targets[i].player_id == target.player_id:
			targets.remove_at(i)

## AI飞雷神拦截决策：闪避(优先)>换位>跳过
func _ai_decide_ftg_intercept(minato: PlayerState, attacker: PlayerState, marked_players: Array[int], attacker_is_marked: bool) -> int:
	# 闪避+螺旋丸反击（需2气）
	if attacker_is_marked and minato.energy >= 2:
		return FTGChoice.DODGE
	# 换位
	if not marked_players.is_empty():
		return FTGChoice.SWAP
	return FTGChoice.SKIP

## 应用飞雷神拦截选择
## targets 为当前攻击目标数组（引用传递，SWAP/DODGE 时会修改以移除/替换水门）
func _apply_ftg_choice(minato: PlayerState, attacker: PlayerState, choice: int, marked_players: Array[int], targets: Array[PlayerState] = []) -> int:
	match choice:
		FTGChoice.SWAP:
			# 换位：与第一个被标记玩家交换座位，该玩家替代水门成为目标
			if marked_players.is_empty():
				return FTGChoice.SKIP
			var swap_target_id: int = marked_players[0]
			var swap_target := get_player(swap_target_id)
			if swap_target == null or not swap_target.is_alive:
				return FTGChoice.SKIP
			# 交换座位
			_distance_system.swap_seats(minato.player_id, swap_target_id)
			# 移除被标记玩家的飞雷神标记
			swap_target.ftg_marked_by.erase(minato.player_id)
			ftg_swap_triggered.emit(minato.player_id, swap_target_id, minato.player_id)
			ftg_mark_removed.emit(swap_target_id)
			# 修改 targets 数组：将水门替换为被标记玩家
			_replace_minato_in_targets(targets, minato.player_id, swap_target)
			# 兼容 _ftg_pending 中暂存的 targets
			if _ftg_pending.has("targets"):
				var new_targets: Array[PlayerState] = []
				for t in _ftg_pending["targets"]:
					if t.player_id == minato.player_id:
						new_targets.append(swap_target)
					else:
						new_targets.append(t)
				_ftg_pending["targets"] = new_targets
			return FTGChoice.SWAP

		FTGChoice.DODGE:
			# 闪避：移除攻击者身上的标记，水门免疫本次技能
			attacker.ftg_marked_by.erase(minato.player_id)
			ftg_dodge_triggered.emit(minato.player_id, attacker.player_id)
			ftg_mark_removed.emit(attacker.player_id)
			# 从 targets 中移除水门（闪避成功）
			_remove_minato_from_targets(targets, minato.player_id)
			if _ftg_pending.has("targets"):
				var new_targets: Array[PlayerState] = []
				for t in _ftg_pending["targets"]:
					if t.player_id != minato.player_id:
						new_targets.append(t)
				_ftg_pending["targets"] = new_targets
			# 螺旋丸反击（二次确认）：人类玩家需先确认，AI 直接反击
			if minato.energy >= 2:
				if minato.is_human:
					_ftg_pending["awaiting_counter"] = true
					rasengan_counter_required.emit(minato.player_id, attacker.player_id, minato.energy)
				else:
					_perform_rasengan_counter(minato, attacker)
			return FTGChoice.DODGE

	return FTGChoice.SKIP

## 从 targets 数组中移除指定玩家（闪避）
func _remove_minato_from_targets(targets: Array[PlayerState], player_id: int) -> void:
	for i in range(targets.size() - 1, -1, -1):
		if targets[i].player_id == player_id:
			targets.remove_at(i)

## 将 targets 数组中的指定玩家替换为另一个（换位）
func _replace_minato_in_targets(targets: Array[PlayerState], player_id: int, replacement: PlayerState) -> void:
	for i in range(targets.size()):
		if targets[i].player_id == player_id:
			targets[i] = replacement

## 执行螺旋丸反击：对攻击者释放螺旋丸（消耗2气，造成3伤）
## energy 由 RoundResolver.apply_effects 自动扣除
func _perform_rasengan_counter(minato: PlayerState, attacker: PlayerState) -> void:
	if minato.energy < 2:
		return
	var rasengan := _get_skill_by_name(minato, "螺旋丸")
	if rasengan == null:
		rasengan = load("res://resources/characters/skills/螺旋丸.tres") as SkillData
	if rasengan:
		var counter_logs := RoundResolver.apply_effects(minato, rasengan, [attacker], _distance_system)
		for entry in counter_logs:
			_emit_effect_signals(entry)
		skill_applied.emit(counter_logs)

## 人类玩家闪避后反击决策回调（由UI/网络调用）
func submit_rasengan_counter(player_id: int, use_counter: bool) -> void:
	rasengan_counter_made.emit(player_id, use_counter)

## 闪避反击决策信号回调：继续被暂停的拦截流程
func _on_rasengan_counter_made(player_id: int, use_counter: bool) -> void:
	if _ftg_pending.is_empty():
		return
	if not _ftg_pending.get("awaiting_counter", false):
		return
	var minato := get_player(player_id)
	if minato == null:
		_resume_ftg_action()
		return
	var attacker: PlayerState = _ftg_pending.get("winner", null) as PlayerState
	if attacker == null:
		_resume_ftg_action()
		return
	_ftg_pending.erase("awaiting_counter")
	if use_counter:
		_perform_rasengan_counter(minato, attacker)
	_resume_ftg_action()

## 人类玩家飞雷神拦截决策回调（由UI调用）
func submit_ftg_intercept(player_id: int, choice: int, swap_target_id: int = -1) -> void:
	ftg_intercept_made.emit(player_id, choice, swap_target_id)

## 飞雷神拦截决策信号回调：执行选择并恢复被暂停的 apply_actions
func _on_ftg_intercept_made(player_id: int, choice: int, swap_target_id: int) -> void:
	if _ftg_pending.is_empty():
		return
	var minato := get_player(player_id)
	if minato == null:
		# 玩家不存在，直接恢复
		_resume_ftg_action()
		return

	# 获取拦截上下文中的攻击者
	var winner: PlayerState = _ftg_pending.get("winner", null) as PlayerState
	if winner == null:
		_resume_ftg_action()
		return

	# 如果选择换位但指定了目标，使用指定目标
	var marked_players: Array[int] = []
	if swap_target_id >= 0:
		marked_players = [swap_target_id]
	else:
		# 重新收集可换位玩家
		for p in _players:
			if p.is_alive and p.player_id != minato.player_id and p.player_id != winner.player_id:
				if p.ftg_marked_by.has(minato.player_id):
					marked_players.append(p.player_id)

	_apply_ftg_choice(minato, winner, choice, marked_players)
	# 若闪避后进入反击二次确认等待，则不继续，等待 rasengan_counter_made 回调
	if _ftg_pending.has("awaiting_counter"):
		return
	_resume_ftg_action()

## 恢复被飞雷神拦截暂停的 _apply_actions 后续执行
func _resume_ftg_action() -> void:
	if _ftg_pending.is_empty():
		return
	var winner: PlayerState = _ftg_pending["winner"]
	var skill: SkillData = _ftg_pending["skill"]
	var targets: Array[PlayerState] = _ftg_pending.get("targets", [])
	var splash_targets: Array[PlayerState] = _ftg_pending.get("splash_targets", [])
	_ftg_pending.clear()

	# 黑塔：记录结算前HP快照（用于砖石50%阈值判定）
	var herta_hp_before: Dictionary = {}
	if _is_herta(winner):
		for p in _players:
			if p.is_alive:
				herta_hp_before[p.player_id] = p.hp
	var logs := RoundResolver.apply_effects(winner, skill, targets, _distance_system, splash_targets)

	# 双龙戏珠后效
	if skill.skill_name == "双龙戏珠":
		winner.clone_count = 0
		clone_destroyed.emit(winner.player_id)
		if not "夜凯" in winner.limited_skills_used:
			winner.limited_skills_used.append("夜凯")

	# 漂泊九尾处理
	if skill.skill_name == "漂泊九尾":
		_process_nine_tails_release(winner)

	# 秽土柱间·真数千手后效
	if skill.skill_name == "仙法·真数千手":
		winner.invincible_turns = 1
		player_invincible.emit(winner.player_id, 1)

	# 跺脚受击触发检查
	_process_stomp_trigger(winner, logs)

	# 标记造成伤害——砸钟（bell_cost>0）伤害不计入钟获取
	if skill.bell_cost <= 0:
		for entry in logs:
			if entry.get("effect_type", -1) == SkillEffect.EffectType.DAMAGE \
			or entry.get("effect_type", -1) == SkillEffect.EffectType.TRUE_DAMAGE \
			or entry.get("effect_type", -1) == SkillEffect.EffectType.FTG_MARK:
				var res: Dictionary = entry.get("result", {})
				if res.get("damage_dealt", 0) > 0:
					winner.dealt_damage_this_round = true
					break
	for entry in logs:
		_emit_effect_signals(entry)
	skill_applied.emit(logs)
	player_charged.emit(_sole_winner_id, winner.energy)
	_record_action(winner, skill, logs)

	# ── 黑塔被动：genjutsu 距离-1 + 送你砖石 AOE（含连锁）──
	if _is_herta(winner):
		_process_herta_passives(winner, logs, herta_hp_before, [])

	# ── 大黑塔被动：解读标记 + 格局打开 ──
	_process_bigherta_effects(winner, logs)

	_enter_phase(GamePhase.ELIMINATION)

## 人类玩家幻影闪避决策提交入口（由UI/网络主机调用）
## dodge=true=闪避 false=不闪避
func submit_phantom_dodge(player_id: int, dodge: bool) -> void:
	phantom_dodge_made.emit(player_id, dodge)

## 幻影闪避决策信号回调：执行闪避并恢复被暂停的 apply_actions
func _on_phantom_dodge_made(player_id: int, dodge: bool) -> void:
	if _phantom_dodge_pending.is_empty():
		return
	var target := get_player(player_id)
	if target == null:
		_resume_phantom_dodge_action()
		return
	# 麻痹状态不可使用任何技能：即使已弹出闪避弹窗，点击闪避也无效（直接恢复行动）
	if target.paralyze_turns > 0:
		dodge = false
	# 若闪避，应用闪避（消耗1气+1幻影，从 targets 中移除）
	if dodge:
		var winner: PlayerState = _phantom_dodge_pending.get("winner", null) as PlayerState
		var targets: Array[PlayerState] = _phantom_dodge_pending.get("targets", [])
		_apply_phantom_dodge(target, winner, targets)
	_resume_phantom_dodge_action()

## 恢复被幻影闪避拦截暂停的 _apply_actions 后续执行
func _resume_phantom_dodge_action() -> void:
	if _phantom_dodge_pending.is_empty():
		return
	var winner: PlayerState = _phantom_dodge_pending["winner"]
	var skill: SkillData = _phantom_dodge_pending["skill"]
	var targets: Array[PlayerState] = _phantom_dodge_pending.get("targets", [])
	var splash_targets: Array[PlayerState] = _phantom_dodge_pending.get("splash_targets", [])
	_phantom_dodge_pending.clear()

	# 黑塔：记录结算前HP快照（用于砖石50%阈值判定）
	var herta_hp_before: Dictionary = {}
	if _is_herta(winner):
		for p in _players:
			if p.is_alive:
				herta_hp_before[p.player_id] = p.hp
	var logs := RoundResolver.apply_effects(winner, skill, targets, _distance_system, splash_targets)

	# ── 新止水·幻影瞬身：普攻命中后获得1幻影（至多3）──
	if skill.skill_name == "普攻" and _is_new_shisui(winner) and winner.phantom_count < 3:
		var phantom_hit := false
		for entry in logs:
			var res: Dictionary = entry.get("result", {})
			if res.get("damage_dealt", 0) > 0:
				phantom_hit = true
				break
		if phantom_hit:
			winner.phantom_count += 1
			phantom_changed.emit(winner.player_id, winner.phantom_count)

	# 双龙戏珠后效
	if skill.skill_name == "双龙戏珠":
		winner.clone_count = 0
		clone_destroyed.emit(winner.player_id)
		if not "夜凯" in winner.limited_skills_used:
			winner.limited_skills_used.append("夜凯")

	# 漂泊九尾处理
	if skill.skill_name == "漂泊九尾":
		_process_nine_tails_release(winner)

	# 秽土柱间·真数千手后效
	if skill.skill_name == "仙法·真数千手":
		winner.invincible_turns = 1
		player_invincible.emit(winner.player_id, 1)

	# 跺脚受击触发检查
	_process_stomp_trigger(winner, logs)

	# 标记造成伤害
	if skill.bell_cost <= 0:
		for entry in logs:
			if entry.get("effect_type", -1) == SkillEffect.EffectType.DAMAGE \
			or entry.get("effect_type", -1) == SkillEffect.EffectType.TRUE_DAMAGE \
			or entry.get("effect_type", -1) == SkillEffect.EffectType.FTG_MARK \
			or entry.get("effect_type", -1) == SkillEffect.EffectType.PIERCE_DAMAGE \
			or entry.get("effect_type", -1) == SkillEffect.EffectType.DEATH_SENTENCE:
				var res: Dictionary = entry.get("result", {})
				if res.get("damage_dealt", 0) > 0:
					winner.dealt_damage_this_round = true
					break
	for entry in logs:
		_emit_effect_signals(entry)
	skill_applied.emit(logs)
	player_charged.emit(_sole_winner_id, winner.energy)
	_record_action(winner, skill, logs)

	# ── 黑塔被动：genjutsu 距离-1 + 送你砖石 AOE（含连锁）──
	if _is_herta(winner):
		_process_herta_passives(winner, logs, herta_hp_before, [])

	# ── 大黑塔被动：解读标记 + 格局打开 ──
	_process_bigherta_effects(winner, logs)

	_enter_phase(GamePhase.ELIMINATION)

## 玩家运行时状态 — 存储单个玩家在一局游戏中的完整状态
## 包含生命值、能量、手势、行动决策以及所有跨回合持续的 buff/debuff
class_name PlayerState
extends RefCounted

## 猜拳手势枚举
enum Gesture { NONE, ROCK, SCISSORS, PAPER, SKIP }
## 行动类型枚举
enum ActionType { NONE, CHARGE, USE_SKILL }

var player_id: int                    ## 玩家唯一ID
var player_name: String               ## 玩家名称
var character: CharacterData          ## 使用的角色数据
var hp: float                          ## 当前生命值
var energy: int                       ## 当前能量值
var shield: int = 0                   ## 护盾值：-1=一次性全挡, 0=无护盾, >0=数值护盾
var paralyze_turns: int = 0           ## 剩余麻痹回合数（自动跳过出拳）
## 剩余击飞回合数（可正常猜拳获得回合，但行动阶段强制只能聚气）
var knockdown_turns: int = 0
## 本回合击飞是否已生效（强制聚气），用于_end_round判断是否递减
var knockdown_consumed_this_round: bool = false
## 本回合是否新施加了击飞（施加回合不递减，下回合结束才递减）
var knockdown_applied_this_round: bool = false
var is_alive: bool                    ## 是否存活
var is_human: bool                    ## 是否人类玩家

## 团队 ID：0 = FFA（无队伍），1/2 = 团队编号
var team_id: int = 0
## 是否当前由 AI 托管（断线替补）
var is_ai_controlled: bool = false
## ── 持续状态字段（跨回合保留）─────────────────────────────────────────────────
## 延迟伤害队列 [{damage, trigger_in(剩余回合), attacker_id}]
var delayed_damages: Array[Dictionary] = []
## 影分身数量（每个抵挡一次伤害，同时增加充能收益）
var clone_count: int = 0
## 运行时动态解锁的技能（如麒麟），跨回合持续
var unlocked_skills: Array[SkillData] = []
## ── 千手柱间专属字段 ───────────────────────────────────────────────
## 钟（专属可叠加标记），造成伤害的回合结束阶段+1
var bell_count: int = 0
## 防反状态（招架消耗钟进入），持续到下回合开始
var counter_stance: bool = false
## 失去技能剩余回合数（禁锢并失去技能时设置）
var skill_disabled_turns: int = 0
## 已使用的限定技技能名列表（一局游戏只能用一次）
var limited_skills_used: Array[String] = []
## 本回合是否造成过伤害（回合结束重置，用于钟获取判定）
var dealt_damage_this_round: bool = false

## ── 迈特凯专属字段 ───────────────────────────────────────────────
## 八门计数（0-8），聚气时自动+1，到8触发特效后失去八门遁甲
var gate_count: int = 0
## 无敌回合数（本回合+下回合无敌，无视所有伤害和控制效果）
var invincible_turns: int = 0
## 燃烧状态（每回合结束失去1血，HP>1保护）
var burning: bool = false
## 狂战士特性（受伤回合结束额外失去1血，可致死）
var berserker: bool = false
## 连续赢得猜拳次数（用于夕象增伤）
var consecutive_rounds: int = 0
## 已永久失去的技能名列表（八门遁甲用完后移除）
var lost_skills: Array[String] = []
## 血付待定：使用技能时用血代替气的数量（临时字段，行动提交时设置）
var pending_hp_payment: float = 0.0
## 本回合是否受到过伤害（回合结束重置，用于狂战士判定）
var took_damage_this_round: bool = false

## ── 波风水门专属字段 ───────────────────────────────────────────────
## 飞雷神标记数量（自身拥有的标记资源，开局获得3个）
var ftg_marks: int = 0
## 被哪些玩家标记了飞雷神（player_id列表）
var ftg_marked_by: Array[int] = []
## 漂泊九尾阶段（0=未释放, 1=咆哮已释放, 2=大爪已释放, 3=尾兽玉已释放）
var nine_tails_stage: int = 0
## 九尾无敌状态（持续到尾兽玉释放后解除）
var nine_tails_invincible: bool = false

## ── 希耶尔专属字段 ───────────────────────────────────────────────
## 可暴击状态：触发相位滑剑"伤害致濒死"后置位，下一次造成伤害时50%概率暴击(x2)
var can_crit_next: bool = false
## 本回合是否触发过暴击猜拳（用于防重复，回合结束重置）
var crit_checked_this_round: bool = false

## ── 秽土柱间专属字段 ───────────────────────────────────────────────
## 气上限（仙人之力：6，其他角色默认999）
var max_energy: int = 999
## 跺脚激活回合数（普攻后设为2，每回合结束-1，>0时受击触发得气+判胜）
var stomp_active: int = 0
## 下回合强制判胜（跺脚受击触发，下回合猜拳直接判为唯一赢家）
var force_win_next_round: bool = false

## ── 卫宫（射手）专属字段 ─────────────────────────────────────────────
## 投影获得的技能副本（用一次后消失，null=无投影技能）
var projected_skill: SkillData = null
## 投影获得的技能是否已在本回合使用过（准备阶段每技能每回合一次）
var projected_used_this_round: bool = false
## 无限剑制结界剩余全局回合数（0=无结界）
var binding_field_turns: int = 0
## 结界锁定的玩家ID列表（释放瞬间距离1以内的敌人，动态范围不追踪）
var binding_field_targets: Array[int] = []
## 无限剑制是否已释放（驱动"下次猜拳必赢"，复用 force_win_next_round 机制）
var binding_field_force_win: bool = false
## 结界内敌人技能副本列表（含被动技；以原耗气、可重复使用出现在卫宫技能列表中）
var binding_field_skills: Array[SkillData] = []

## ── 宇智波泉奈专属字段 ─────────────────────────────────────────────
## 荣耀已解锁标记（聚4个气自动解锁，使用后清空需重新聚气解锁）
var glory_unlocked: bool = false
## 无法选择剩余回合数（>0时其他玩家任何技能无法指定该玩家为目标）
var untargetable_turns: int = 0
## 荣耀是否已在本回合使用过（每回合至多一次，准备阶段结算）
var glory_used_this_round: bool = false
## 宇智波流招架状态（泉奈专属）：受击时伤害减半+进入无法选择+反击封技
var uchiha_stance: bool = false

## ── 宇智波止水专属字段 ─────────────────────────────────────────────
## 须佐能乎·螺旋是否已解锁（斩→螺旋→九十九技能链，永久解锁）
var susanoo_spiral_unlocked: bool = false
## 须佐能乎·九十九是否已解锁/获得过（别天神触发条件：获得过九十九即可）
var has_kotoamatsukami_skill: bool = false
## 别天神是否已使用（被动限定技，一局只能用一次）
var kotoamatsukami_used: bool = false
## 别天神夺舍前快照（用于夺舍体死亡后回退到夺舍前止水状态）
var pre_takeover_snapshot: Dictionary = {}
## 是否处于夺舍状态（true=当前是夺舍体）
var takeover_active: bool = false
## 别天神弹窗等待中标记（防止重复弹窗）
var koto_awaiting_confirm: bool = false
## 最近一次实际扣血的伤害来源玩家ID（-1=无，用于别天神击杀判定）
var last_hit_by_id: int = -1

## ── 新止水（宇智波止水·天劫）专属字段 ─────────────────────────────
## 幻影数量（0-3）：普攻命中后+1；每个幻影使普攻伤害+0.5；被攻击时可消耗1气+1幻影闪避
var phantom_count: int = 0
## 回溯快照（全体玩家）：在上一行动玩家回合开始前拍摄，别天神回溯时恢复
## 存储格式：{ "round": int, "winner_id": int, "states": {player_id: Dictionary} }
var backtrack_snapshot: Dictionary = {}

## ── 大黑塔专属字段 ───────────────────────────────────────────────
## 【解】标记：被大黑塔伤害过的玩家获得；效果=与标记者距离-1、受标记者伤害+1
## 按施法者区分：jiedu_by 记录标记来源大黑塔的player_id列表（类似飞雷神 ftg_marked_by）
## 同一玩家可被多个大黑塔分别标记，各自独立生效、互不通用；永久存在（无自然消失机制）
var jiedu_by: Array[int] = []

## ── 慈悲尖塔敌人专属字段 ─────────────────────────────────────────
## 破败王者之刃阶段计数（0=第1次普攻，1=第2次，2=第3次；3+=技能耗尽等待悲痛刷新）
var blade_stage: int = 0
## 反馈怒标记数（司马懿，0-4）
var fury_marks: int = 0

## ── 宙斯Boss专属字段 ─────────────────────────────────────────
## 当前回合剩余行动权（神权：一阶段2点/二阶段3点）
var action_points: int = 0
## 神怒获气标记：宙斯专属被动，无法自己聚气，其他玩家聚气或造成伤害时宙斯+1气
var is_zeus: bool = false
## 宙斯二阶段标记（true=当前为二阶段宙斯）
var is_zeus_phase2: bool = false
## 宙斯Boss标记（true=一阶段或二阶段宙斯，用于阶段切换判定）
var is_zeus_boss: bool = false
## 神大罚是否已使用（限定技，一局一次）
var zeus_judgement_used: bool = false

## ── 慈悲尖塔玩家 buff 字段（层间奖励，每层注入）──────────────────
## 普攻固定增伤（锋刃之力：+1）
var damage_bonus_basic: float = 0.0
## 每回合额外聚气（蓄锐：+1）
var charge_bonus: int = 0
## 固定减伤（坚壁：-0.5）
var damage_reduction: float = 0.0
## 每回合回血（回生：自己回合开始时+1）
var regen_per_round: float = 0.0
## 生命上限加成（生机/龙血：+N，注入时加到 max_hp 并同步补血）
var max_hp_bonus: float = 0.0
## 开局额外气量（起势/疾风：+N，注入时加到 energy）
var start_energy_bonus: int = 0
## 吸血（嗜血祝福：造成伤害时恢复 N 点生命值，不超过上限）
var lifesteal_per_hit: float = 0.0
## 免死金牌（一次性被动：免疫一次致命伤害，触发后标记消费）
var immortal_medal: bool = false
## 破军（普攻可暴击，50%概率双倍伤害）
var pojun_active: bool = false
## 霸体（免疫一切控制效果：麻痹/击飞/封技/无法选择）
var bati_active: bool = false
## 涅槃（一次性被动：死亡时以半血重生，触发后标记消费）
var niepan_active: bool = false

## 有效最大生命值 = 角色基础 + 慈悲尖塔 buff 加成（不污染共享 CharacterData 资源）
func get_max_hp() -> float:
	return character.max_hp + max_hp_bonus

## ── 回合临时数据（每回合开始时重置）───────────────────────────────────────────
var current_gesture: Gesture           ## 本回合出的手势
var pending_action: ActionType         ## 待执行的行动类型
var skill_target_id: int               ## 技能目标ID
var pending_skill_index: int           ## 待使用技能在技能列表中的索引

func _init(id: int, p_name: String, char_data: CharacterData, human: bool) -> void:
	player_id           = id
	player_name         = p_name
	character           = char_data
	hp                  = char_data.max_hp
	energy              = 0
	shield              = 0
	paralyze_turns      = 0
	knockdown_turns     = 0
	clone_count         = 0
	delayed_damages     = []
	unlocked_skills     = []
	is_alive            = true
	is_human            = human
	current_gesture     = Gesture.NONE
	pending_action      = ActionType.NONE
	skill_target_id     = -1
	pending_skill_index = -1
	# 慈悲尖塔 buff 字段默认值（每层注入前为 0）
	damage_bonus_basic  = 0.0
	charge_bonus        = 0
	damage_reduction    = 0.0
	regen_per_round     = 0.0
	max_hp_bonus        = 0.0
	start_energy_bonus  = 0
	lifesteal_per_hit   = 0.0
	immortal_medal      = false
	pojun_active        = false
	bati_active         = false
	niepan_active       = false
	pending_skill_index = -1
	# 秽土柱间·仙人之力：气上限6
	# 注意：不能用"仙人之力"判断——仙人鸣人（仙人模式）也有同名被动技能（聚气+1），会误判
	for skill in char_data.skills:
		if skill.skill_name == "仙法·树界降诞":
			max_energy = 6
			break

## 保存止水夺舍前快照（深拷贝关键字段，用于夺舍体死亡后回退）
func save_pre_takeover_snapshot() -> void:
	pre_takeover_snapshot = {
		"character": character,
		"hp": hp,
		"energy": energy,
		"shield": shield,
		"paralyze_turns": paralyze_turns,
		"knockdown_turns": knockdown_turns,
		"clone_count": clone_count,
		"invincible_turns": invincible_turns,
		"skill_disabled_turns": skill_disabled_turns,
		"counter_stance": counter_stance,
		"uchiha_stance": uchiha_stance,
		"untargetable_turns": untargetable_turns,
		"ftg_marks": ftg_marks,
		"bell_count": bell_count,
"unlocked_skills": unlocked_skills.duplicate(),
	"lost_skills": lost_skills.duplicate(),
	"delayed_damages": delayed_damages.duplicate(),
		"binding_field_turns": binding_field_turns,
		"binding_field_targets": binding_field_targets.duplicate(),
		"binding_field_skills": binding_field_skills.duplicate(),
		"projected_skill": projected_skill,
		"projected_used_this_round": projected_used_this_round,
		"nine_tails_stage": nine_tails_stage,
		"nine_tails_invincible": nine_tails_invincible,
		"gate_count": gate_count,
		"burning": burning,
		"berserker": berserker,
		"consecutive_rounds": consecutive_rounds,
		"stomp_active": stomp_active,
		"force_win_next_round": force_win_next_round,
		"max_energy": max_energy,
		"can_crit_next": can_crit_next,
		"glory_unlocked": glory_unlocked,
		"susanoo_spiral_unlocked": susanoo_spiral_unlocked,
		"has_kotoamatsukami_skill": has_kotoamatsukami_skill,
	}

## 从快照恢复（夺舍体死亡后回退到夺舍前止水状态）
func restore_pre_takeover_snapshot() -> void:
	if pre_takeover_snapshot.is_empty():
		return
	character             = pre_takeover_snapshot.get("character", character)
	hp                    = pre_takeover_snapshot.get("hp", hp)
	energy                = pre_takeover_snapshot.get("energy", energy)
	shield                = pre_takeover_snapshot.get("shield", shield)
	paralyze_turns        = pre_takeover_snapshot.get("paralyze_turns", paralyze_turns)
	knockdown_turns       = pre_takeover_snapshot.get("knockdown_turns", knockdown_turns)
	clone_count           = pre_takeover_snapshot.get("clone_count", clone_count)
	invincible_turns      = pre_takeover_snapshot.get("invincible_turns", invincible_turns)
	skill_disabled_turns  = pre_takeover_snapshot.get("skill_disabled_turns", skill_disabled_turns)
	counter_stance        = pre_takeover_snapshot.get("counter_stance", counter_stance)
	uchiha_stance         = pre_takeover_snapshot.get("uchiha_stance", uchiha_stance)
	untargetable_turns    = pre_takeover_snapshot.get("untargetable_turns", untargetable_turns)
	ftg_marks             = pre_takeover_snapshot.get("ftg_marks", ftg_marks)
	bell_count            = pre_takeover_snapshot.get("bell_count", bell_count)
	unlocked_skills       = pre_takeover_snapshot.get("unlocked_skills", []).duplicate()
	lost_skills           = pre_takeover_snapshot.get("lost_skills", []).duplicate() if pre_takeover_snapshot.has("lost_skills") else lost_skills
	delayed_damages       = pre_takeover_snapshot.get("delayed_damages", []).duplicate()
	binding_field_turns   = pre_takeover_snapshot.get("binding_field_turns", binding_field_turns)
	binding_field_targets = pre_takeover_snapshot.get("binding_field_targets", []).duplicate()
	binding_field_skills  = pre_takeover_snapshot.get("binding_field_skills", []).duplicate()
	projected_skill       = pre_takeover_snapshot.get("projected_skill", projected_skill)
	projected_used_this_round = pre_takeover_snapshot.get("projected_used_this_round", projected_used_this_round)
	nine_tails_stage      = pre_takeover_snapshot.get("nine_tails_stage", nine_tails_stage)
	nine_tails_invincible = pre_takeover_snapshot.get("nine_tails_invincible", nine_tails_invincible)
	gate_count            = pre_takeover_snapshot.get("gate_count", gate_count)
	burning               = pre_takeover_snapshot.get("burning", burning)
	berserker             = pre_takeover_snapshot.get("berserker", berserker)
	consecutive_rounds    = pre_takeover_snapshot.get("consecutive_rounds", consecutive_rounds)
	stomp_active          = pre_takeover_snapshot.get("stomp_active", stomp_active)
	force_win_next_round  = pre_takeover_snapshot.get("force_win_next_round", force_win_next_round)
	max_energy            = pre_takeover_snapshot.get("max_energy", max_energy)
	can_crit_next         = pre_takeover_snapshot.get("can_crit_next", can_crit_next)
	glory_unlocked        = pre_takeover_snapshot.get("glory_unlocked", glory_unlocked)
	susanoo_spiral_unlocked = pre_takeover_snapshot.get("susanoo_spiral_unlocked", susanoo_spiral_unlocked)
	has_kotoamatsukami_skill = pre_takeover_snapshot.get("has_kotoamatsukami_skill", has_kotoamatsukami_skill)
	# 夺舍回退后清除夺舍状态
	takeover_active = false
	koto_awaiting_confirm = false
	pre_takeover_snapshot = {}

## 拍摄回溯快照：保存自身完整运行时状态（用于新止水·别天神回溯）
## 与 pre_takeover_snapshot 不同：此快照用于全体玩家回滚，需覆盖全部可回溯字段
func capture_backtrack_snapshot() -> Dictionary:
	return {
		"character": character,
		"hp": hp,
		"energy": energy,
		"shield": shield,
		"paralyze_turns": paralyze_turns,
		"knockdown_turns": knockdown_turns,
		"knockdown_consumed_this_round": knockdown_consumed_this_round,
		"knockdown_applied_this_round": knockdown_applied_this_round,
		"is_alive": is_alive,
		"clone_count": clone_count,
		"unlocked_skills": unlocked_skills.duplicate(),
		"bell_count": bell_count,
		"counter_stance": counter_stance,
		"skill_disabled_turns": skill_disabled_turns,
		"limited_skills_used": limited_skills_used.duplicate(),
		"dealt_damage_this_round": dealt_damage_this_round,
		"gate_count": gate_count,
		"invincible_turns": invincible_turns,
		"burning": burning,
		"berserker": berserker,
		"consecutive_rounds": consecutive_rounds,
		"lost_skills": lost_skills.duplicate(),
		"pending_hp_payment": pending_hp_payment,
		"took_damage_this_round": took_damage_this_round,
		"ftg_marks": ftg_marks,
		"ftg_marked_by": ftg_marked_by.duplicate(),
		"nine_tails_stage": nine_tails_stage,
		"nine_tails_invincible": nine_tails_invincible,
		"can_crit_next": can_crit_next,
		"crit_checked_this_round": crit_checked_this_round,
		"max_energy": max_energy,
		"stomp_active": stomp_active,
		"force_win_next_round": force_win_next_round,
		"projected_skill": projected_skill,
		"projected_used_this_round": projected_used_this_round,
		"binding_field_turns": binding_field_turns,
		"binding_field_targets": binding_field_targets.duplicate(),
		"binding_field_skills": binding_field_skills.duplicate(),
		"binding_field_force_win": binding_field_force_win,
		"glory_unlocked": glory_unlocked,
		"untargetable_turns": untargetable_turns,
		"glory_used_this_round": glory_used_this_round,
		"uchiha_stance": uchiha_stance,
		"susanoo_spiral_unlocked": susanoo_spiral_unlocked,
		"has_kotoamatsukami_skill": has_kotoamatsukami_skill,
		"kotoamatsukami_used": kotoamatsukami_used,
		"takeover_active": takeover_active,
		"koto_awaiting_confirm": koto_awaiting_confirm,
		"last_hit_by_id": last_hit_by_id,
		"phantom_count": phantom_count,
		"delayed_damages": delayed_damages.duplicate(),
		"jiedu_by": jiedu_by.duplicate(),
		"damage_bonus_basic": damage_bonus_basic,
		"charge_bonus": charge_bonus,
		"damage_reduction": damage_reduction,
		"regen_per_round": regen_per_round,
		"max_hp_bonus": max_hp_bonus,
		"start_energy_bonus": start_energy_bonus,
		"lifesteal_per_hit": lifesteal_per_hit,
		"immortal_medal": immortal_medal,
		"pojun_active": pojun_active,
		"bati_active": bati_active,
		"niepan_active": niepan_active,
		"blade_stage": blade_stage,
		"fury_marks": fury_marks,
		"action_points": action_points,
		"is_zeus": is_zeus,
		"is_zeus_phase2": is_zeus_phase2,
		"is_zeus_boss": is_zeus_boss,
		"zeus_judgement_used": zeus_judgement_used,
	}

## 从回溯快照恢复自身状态（全部字段）
## 注意：is_alive 恢复为存活时，由 GameManager 负责将其重新加入距离系统
func restore_from_backtrack_snapshot(snap: Dictionary) -> void:
	if snap.is_empty():
		return
	character                = snap.get("character", character)
	hp                       = snap.get("hp", hp)
	energy                   = snap.get("energy", energy)
	shield                   = snap.get("shield", shield)
	paralyze_turns           = snap.get("paralyze_turns", paralyze_turns)
	knockdown_turns          = snap.get("knockdown_turns", knockdown_turns)
	knockdown_consumed_this_round = snap.get("knockdown_consumed_this_round", knockdown_consumed_this_round)
	knockdown_applied_this_round = snap.get("knockdown_applied_this_round", knockdown_applied_this_round)
	is_alive                 = snap.get("is_alive", is_alive)
	clone_count              = snap.get("clone_count", clone_count)
	unlocked_skills          = snap.get("unlocked_skills", []).duplicate()
	bell_count               = snap.get("bell_count", bell_count)
	counter_stance           = snap.get("counter_stance", counter_stance)
	skill_disabled_turns     = snap.get("skill_disabled_turns", skill_disabled_turns)
	limited_skills_used      = snap.get("limited_skills_used", []).duplicate()
	dealt_damage_this_round  = snap.get("dealt_damage_this_round", dealt_damage_this_round)
	gate_count               = snap.get("gate_count", gate_count)
	invincible_turns         = snap.get("invincible_turns", invincible_turns)
	burning                  = snap.get("burning", burning)
	berserker                = snap.get("berserker", berserker)
	consecutive_rounds       = snap.get("consecutive_rounds", consecutive_rounds)
	lost_skills              = snap.get("lost_skills", []).duplicate()
	pending_hp_payment       = snap.get("pending_hp_payment", pending_hp_payment)
	took_damage_this_round   = snap.get("took_damage_this_round", took_damage_this_round)
	ftg_marks                = snap.get("ftg_marks", ftg_marks)
	ftg_marked_by            = snap.get("ftg_marked_by", []).duplicate()
	nine_tails_stage         = snap.get("nine_tails_stage", nine_tails_stage)
	nine_tails_invincible    = snap.get("nine_tails_invincible", nine_tails_invincible)
	can_crit_next            = snap.get("can_crit_next", can_crit_next)
	crit_checked_this_round  = snap.get("crit_checked_this_round", crit_checked_this_round)
	max_energy               = snap.get("max_energy", max_energy)
	stomp_active             = snap.get("stomp_active", stomp_active)
	force_win_next_round     = snap.get("force_win_next_round", force_win_next_round)
	projected_skill          = snap.get("projected_skill", projected_skill)
	projected_used_this_round = snap.get("projected_used_this_round", projected_used_this_round)
	binding_field_turns      = snap.get("binding_field_turns", binding_field_turns)
	binding_field_targets    = snap.get("binding_field_targets", []).duplicate()
	binding_field_skills     = snap.get("binding_field_skills", []).duplicate()
	binding_field_force_win  = snap.get("binding_field_force_win", binding_field_force_win)
	glory_unlocked           = snap.get("glory_unlocked", glory_unlocked)
	untargetable_turns       = snap.get("untargetable_turns", untargetable_turns)
	glory_used_this_round    = snap.get("glory_used_this_round", glory_used_this_round)
	uchiha_stance            = snap.get("uchiha_stance", uchiha_stance)
	susanoo_spiral_unlocked  = snap.get("susanoo_spiral_unlocked", susanoo_spiral_unlocked)
	has_kotoamatsukami_skill = snap.get("has_kotoamatsukami_skill", has_kotoamatsukami_skill)
	kotoamatsukami_used      = snap.get("kotoamatsukami_used", kotoamatsukami_used)
	takeover_active          = snap.get("takeover_active", takeover_active)
	koto_awaiting_confirm    = snap.get("koto_awaiting_confirm", koto_awaiting_confirm)
	last_hit_by_id           = snap.get("last_hit_by_id", last_hit_by_id)
	phantom_count            = snap.get("phantom_count", phantom_count)
	delayed_damages          = (snap.get("delayed_damages", []) as Array).duplicate(true)
	jiedu_by                 = (snap.get("jiedu_by", []) as Array).duplicate()
	damage_bonus_basic       = snap.get("damage_bonus_basic", damage_bonus_basic)
	charge_bonus             = snap.get("charge_bonus", charge_bonus)
	damage_reduction         = snap.get("damage_reduction", damage_reduction)
	regen_per_round          = snap.get("regen_per_round", regen_per_round)
	max_hp_bonus             = snap.get("max_hp_bonus", max_hp_bonus)
	start_energy_bonus       = snap.get("start_energy_bonus", start_energy_bonus)
	lifesteal_per_hit        = snap.get("lifesteal_per_hit", lifesteal_per_hit)
	immortal_medal           = snap.get("immortal_medal", immortal_medal)
	pojun_active             = snap.get("pojun_active", pojun_active)
	bati_active              = snap.get("bati_active", bati_active)
	niepan_active            = snap.get("niepan_active", niepan_active)
	blade_stage              = snap.get("blade_stage", blade_stage)
	fury_marks               = snap.get("fury_marks", fury_marks)
	action_points            = snap.get("action_points", action_points)
	is_zeus                  = snap.get("is_zeus", is_zeus)
	is_zeus_phase2           = snap.get("is_zeus_phase2", is_zeus_phase2)
	is_zeus_boss             = snap.get("is_zeus_boss", is_zeus_boss)
	zeus_judgement_used      = snap.get("zeus_judgement_used", zeus_judgement_used)

## 重置回合临时数据（每回合开始时调用），持续状态字段不在此重置
## 防反（counter_stance）为持续状态：进入后持续到自己的下个回合行动开始（_start_action_input）时清除
func reset_round_data() -> void:
	current_gesture     = Gesture.NONE
	pending_action      = ActionType.NONE
	skill_target_id     = -1
	pending_skill_index = -1
	dealt_damage_this_round = false
	took_damage_this_round = false
	# 暴击猜拳标记每回合重置（可暴击状态 can_crit_next 持续保留直到触发）
	crit_checked_this_round = false
	# 卫宫投影：每回合重置"投影技能已使用"标记（投影技能本身跨回合保留至用掉为止）
	projected_used_this_round = false
	# 泉奈荣耀：每回合重置"本回合已使用"标记
	glory_used_this_round = false
	# 击飞递减标记每回合重置
	knockdown_consumed_this_round = false
	knockdown_applied_this_round = false
	# 无法选择回合递减（与麻痹/无敌等状态一致，回合结束时递减）
	if untargetable_turns > 0:
		untargetable_turns -= 1

## 返回角色固有技能 + 运行时解锁技能的合并列表
## 过滤掉：1.被禁用的技能 2.已使用的限定技 3.招架（END_PHASE主动技能）4.被动技 5.已失去的技能
func get_all_skills() -> Array[SkillData]:
	var all: Array[SkillData] = []
	for skill in character.skills:
		if skill_disabled_turns > 0 and skill.skill_name != "普攻":
			continue  # 失去技能时仅保留普攻
		if skill.is_limited and skill.skill_name in limited_skills_used:
			continue  # 限定技已使用过
		if _is_end_phase_only_skill(skill):
			continue  # 招架仅END_PHASE阶段触发
		if skill.is_passive:
			continue  # 被动技/锁定技不在操作阶段显示
		if skill.skill_name in lost_skills:
			continue  # 已永久失去的技能
		if skill.skill_name == "宇智波的荣耀":
			continue  # 荣耀：仅准备阶段触发，不进入常规技能列表
		all.append(skill)
	for skill in unlocked_skills:
		if skill_disabled_turns > 0:
			continue  # 失去技能时解锁技能也被禁用
		if skill.is_limited and skill.skill_name in limited_skills_used:
			continue
		if _is_end_phase_only_skill(skill):
			continue
		if skill.is_passive:
			continue
		if skill.skill_name in lost_skills:
			continue
		if skill.skill_name == "宇智波的荣耀":
			continue  # 荣耀：仅准备阶段触发，不进入常规技能列表
		all.append(skill)
	# 飞雷神拔除：任何被飞雷神标记的玩家都可消耗行动权拔除标记
	# 波风水门自身不会标记自己，且水门的技能列表已含该技能（UI 过滤逻辑会跳过重复）
	if ftg_marked_by.size() > 0 and not _has_skill(all, "飞雷神拔除"):
		var ftg_remove: SkillData = load("res://resources/characters/skills/飞雷神拔除.tres")
		if ftg_remove != null:
			all.append(ftg_remove)
	# 卫宫·投影技能：投影获得的技能副本（用一次后消失），追加到技能列表末尾
	if projected_skill != null and not _has_skill(all, projected_skill.skill_name):
		all.append(projected_skill)
	# 卫宫·无限剑制结界内技能：结界内敌人的技能（含被动技）以原耗气、可重复使用
	for bs in binding_field_skills:
		if not _has_skill(all, bs.skill_name):
			all.append(bs)
	return all

## 判断技能列表中是否已包含指定技能名（用于动态追加去重）
func _has_skill(skills: Array[SkillData], skill_name: String) -> bool:
	for s in skills:
		if s.skill_name == skill_name:
			return true
	return false

## 判断技能是否只在END_PHASE阶段生效（当前仅招架：含COUNTER_STANCE效果）
func _is_end_phase_only_skill(skill: SkillData) -> bool:
	for effect in skill.effects:
		if effect.effect_type == SkillEffect.EffectType.COUNTER_STANCE:
			return true
	return false

## 加气（自动clamp到max_energy上限）
func add_energy(amount: int) -> void:
	energy += amount
	energy = min(energy, max_energy)

## 设置气（自动clamp到max_energy上限）
func set_energy(value: int) -> void:
	energy = min(value, max_energy)

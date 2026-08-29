class_name NetworkProtocol
extends RefCounted

const PROTOCOL_VERSION := 1

# ── 服务器 → 客户端 OpCode ────────────────────────────────────
enum SrvOp {
	PHASE_ENTER          = 10,  # 进入新阶段，附带阶段数据
	GESTURES_REVEALED    = 11,  # 所有手势揭示（RESOLVING阶段）
	ACTION_RESULT        = 12,  # 技能/充能结果
	FULL_STATE_SYNC      = 13,  # 完整状态快照（断线重连用）
	GESTURE_DECIDED      = 14,  # 某玩家已决定手势
	PLAYER_DISCONNECTED  = 21,  # 某玩家断线，AI接管
	PLAYER_RECONNECTED   = 22,  # 某玩家重连
	HIGH_LATENCY         = 23,  # 某玩家高延迟警告
	PONG                 = 30,  # 响应Ping
	GAME_OVER_RESULT     = 40,
	CHAT_MESSAGE         = 41,
	STATE_HASH           = 50,  # 回合结束状态哈希，用于去同步检测
	END_PHASE_BELL       = 51,  # END_PHASE钟决策请求
	END_PHASE_RESULT     = 52,  # END_PHASE钟决策结果
	FTG_INTERCEPT        = 53,  # 飞雷神拦截决策请求
	FTG_COUNTER_CONFIRM  = 54,  # 闪避后螺旋丸反击二次确认请求
	PROJECT_SKILL_REQUIRED = 55,  # 投影决策请求（准备阶段，人类玩家弹窗）
	PHANTOM_DODGE_REQUIRED = 56,  # 幻影闪避决策请求（新止水受击弹窗）
	BACKTRACK_REQUIRED   = 57,  # 别天神回溯决策请求（新止水准备阶段弹窗）
	HIROARI_REQUIRED     = 58,  # 日影舞目标选择请求（新止水行动阶段弹窗）
	DREAM_END_REQUIRED   = 59,  # 梦之终结目标选择请求（奥伯龙结束阶段弹窗）
	LAKE_BLESSING_REQUIRED = 60,  # 湖之加护目标选择请求（卡斯特结束阶段弹窗）
	SWORD_FORGE_REQUIRED = 61,  # 圣剑锻造技能+目标选择请求（卡斯特→被锻造目标弹窗）
	TOWER_FLOOR_START    = 62,  # 塔模式：开始新楼层 {floor, enemy_name, seed, enemy_buffs}
	TOWER_FLOOR_CLEARED  = 66,  # 塔模式：层胜利（触发客户端退场对话）{floor}
	TOWER_REWARD_OFFER   = 63,  # 塔模式：向指定真人发祝福三选一 {player_index, char_name, choices}
	TOWER_REWARD_PICKED  = 64,  # 塔模式：某成员祝福已定（含AI自动选）{player_index, buff}
	TOWER_RUN_ENDED      = 65,  # 塔模式：整局结束 {victory, floor}
	TOWER_RUN_SYNC       = 67,  # 塔模式：断线重连的塔元状态快照 {floor, seed, enemy_name, buffs_per_player}
}

# ── 客户端 → 服务器 OpCode ────────────────────────────────────
enum CliOp {
	SUBMIT_GESTURE  = 1,   # {gesture: int}
	SUBMIT_ACTION   = 2,   # {action: int, skill_index: int, target_id: int}
	RECONNECT_REQ   = 3,   # {room_id: String, token: String}
	PING            = 10,  # {ts: float}
	SPECTATE_JOIN   = 20,  # {}
	BELL_DECISION   = 30,  # {player_id: int, use_bell: bool}
	REWARD_PICK     = 40,  # {player_index: int, buff: Dictionary} 塔模式祝福选择
}

# 序列化：Dictionary → PackedByteArray（JSON）
static func encode(op: int, payload: Dictionary) -> PackedByteArray:
	var msg = {"v": PROTOCOL_VERSION, "op": op, "d": payload}
	return JSON.stringify(msg).to_utf8_buffer()

# 反序列化：PackedByteArray → {op, payload}
static func decode(data: PackedByteArray) -> Dictionary:
	var text = data.get_string_from_utf8()
	var parsed = JSON.parse_string(text)
	if parsed == null:
		return {}
	var v: int = parsed.get("v", 0)
	if v != PROTOCOL_VERSION:
		push_warning("Protocol version mismatch: got %d, expected %d" % [v, PROTOCOL_VERSION])
	return {"op": int(parsed["op"]), "d": parsed.get("d", {})}

# 将 PlayerState 序列化为可网络传输的 Dictionary
static func serialize_player_state(p: PlayerState) -> Dictionary:
	return {
		"id":             p.player_id,
		"name":           p.player_name,
		"team":           p.team_id,
		"hp":             p.hp,
		"energy":         p.energy,
		"shield":         p.shield,
		"paralyze":       p.paralyze_turns,
		"knockdown":      p.knockdown_turns,
		"clone":          p.clone_count,
		"alive":          p.is_alive,
		"char_id":        p.character.resource_path,
		"delayed_dmg":    p.delayed_damages,
		"is_human":       p.is_human,
		"unlocked_skills": p.unlocked_skills.map(func(s: SkillData): return s.resource_path),
		"bell_count":      p.bell_count,
		"counter_stance":  p.counter_stance,
		"skill_disabled":  p.skill_disabled_turns,
		"limited_used":    p.limited_skills_used,
		"gate_count":      p.gate_count,
		"invincible_turns": p.invincible_turns,
		"burning":         p.burning,
		"berserker":       p.berserker,
		"consecutive_rounds": p.consecutive_rounds,
		"lost_skills":     p.lost_skills,
		"ftg_marks":      p.ftg_marks,
		"ftg_marked_by":   p.ftg_marked_by,
		"nine_tails_stage": p.nine_tails_stage,
		"nine_tails_invincible": p.nine_tails_invincible,
		"max_energy":       p.max_energy,
		"stomp_active":     p.stomp_active,
		"phantom_count":    p.phantom_count,
		"force_win_next_round": 1 if p.force_win_next_round else 0,
		"projected_skill_path": p.projected_skill.resource_path if p.projected_skill != null else "",
		"projected_used_this_round": 1 if p.projected_used_this_round else 0,
		"binding_field_turns": p.binding_field_turns,
		"binding_field_targets": p.binding_field_targets,
		"binding_field_force_win": 1 if p.binding_field_force_win else 0,
		"binding_field_skills_path": p.binding_field_skills.map(func(s: SkillData): return s.resource_path),
	}

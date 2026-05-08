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
}

# ── 客户端 → 服务器 OpCode ────────────────────────────────────
enum CliOp {
	SUBMIT_GESTURE  = 1,   # {gesture: int}
	SUBMIT_ACTION   = 2,   # {action: int, skill_index: int, target_id: int}
	RECONNECT_REQ   = 3,   # {room_id: String, token: String}
	PING            = 10,  # {ts: float}
	SPECTATE_JOIN   = 20,  # {}
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
		"clone":          p.clone_count,
		"alive":          p.is_alive,
		"char_id":        p.character.resource_path,
		"delayed_dmg":    p.delayed_damages,
		"is_human":       p.is_human,
		"unlocked_skills": p.unlocked_skills.map(func(s: SkillData): return s.resource_path),
	}

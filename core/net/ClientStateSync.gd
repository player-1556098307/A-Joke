## ClientStateSync — 将服务器广播数据包应用到 GameManager 状态缓存
## 仅由 game_ui 的联机信号处理函数调用（_on_action_result / _on_full_state_sync）
## 主机端状态由 RoundResolver 直接修改，不走此处
class_name ClientStateSync
extends RefCounted

## 将 ACTION_RESULT 数据包写入 GameManager 玩家状态
static func apply_action_result(data: Dictionary) -> void:
	match data.get("type", ""):
		"skill":
			_apply_skill_logs(data.get("logs", []))
		"charge":
			var p := GameManager.get_player(data.get("player_id", -1))
			if p:
				p.energy = data.get("energy", p.energy)
		"paralyze":
			var p := GameManager.get_player(data.get("player_id", -1))
			if p:
				p.paralyze_turns = data.get("turns", p.paralyze_turns)
		"knockdown":
			var p := GameManager.get_player(data.get("player_id", -1))
			if p:
				p.knockdown_turns = data.get("turns", p.knockdown_turns)
		"shield":
			var p := GameManager.get_player(data.get("player_id", -1))
			if p:
				p.shield = data.get("value", p.shield)
		"clone_destroyed":
			var p := GameManager.get_player(data.get("player_id", -1))
			if p and p.clone_count > 0:
				p.clone_count -= 1
		"delayed_damage":
			var p := GameManager.get_player(data.get("player_id", -1))
			if p:
				p.hp = data.get("hp", p.hp)
				# 移除已触发的延迟伤害条目（trigger_in 经 tick 后 <= 0）
				var dmg: float = data.get("damage", 0.0)
				for i in range(p.delayed_damages.size()):
					var entry: Dictionary = p.delayed_damages[i]
					if entry.get("trigger_in", 1) <= 0 and entry.get("damage", 0) == dmg:
						p.delayed_damages.remove_at(i)
						break
		"bell_gained":
			var p := GameManager.get_player(data.get("player_id", -1))
			if p:
				p.bell_count = data.get("bell_count", p.bell_count)
		"counter_stance":
			var p := GameManager.get_player(data.get("player_id", -1))
			if p:
				p.counter_stance = true
		"counter_ended":
			var p := GameManager.get_player(data.get("player_id", -1))
			if p:
				p.counter_stance = false
		"counter_triggered":
			var target := GameManager.get_player(data.get("target_id", -1))
			if target:
				target.energy += 1
			var attacker := GameManager.get_player(data.get("attacker_id", -1))
			if attacker:
				attacker.hp = max(0.0, attacker.hp - 1.0)
		"skill_disabled":
			var p := GameManager.get_player(data.get("player_id", -1))
			if p:
				p.skill_disabled_turns = data.get("turns", p.skill_disabled_turns)
		"invincible":
			var p := GameManager.get_player(data.get("player_id", -1))
			if p:
				p.invincible_turns = data.get("turns", p.invincible_turns)
		"burning":
			var p := GameManager.get_player(data.get("player_id", -1))
			if p:
				p.burning = true
		"berserker":
			var p := GameManager.get_player(data.get("player_id", -1))
			if p:
				p.berserker = true
		"gate_changed":
			var p := GameManager.get_player(data.get("player_id", -1))
			if p:
				p.gate_count = data.get("gate_count", p.gate_count)
		"eighth_gate":
			var p := GameManager.get_player(data.get("player_id", -1))
			if p:
				p.hp = min(p.character.max_hp, p.hp + 10.0)
				p.burning = true
				p.berserker = true
				p.lost_skills.append("八门遁甲")
		"skill_lost":
			var p := GameManager.get_player(data.get("player_id", -1))
			if p:
				var sname: String = data.get("skill_name", "")
				if sname != "" and not p.lost_skills.has(sname):
					p.lost_skills.append(sname)
		"burn_damage":
			var p := GameManager.get_player(data.get("player_id", -1))
			if p:
				p.hp = data.get("hp", p.hp)
		"hp_payment":
			var p := GameManager.get_player(data.get("player_id", -1))
			if p:
				p.hp = data.get("hp", p.hp)
				p.energy = data.get("energy", p.energy)
		"ftg_marks_changed":
			var p := GameManager.get_player(data.get("player_id", -1))
			if p:
				p.ftg_marks = data.get("marks", p.ftg_marks)
		"ftg_mark_applied":
			var target := GameManager.get_player(data.get("target_id", -1))
			if target:
				var aid: int = data.get("attacker_id", -1)
				if not target.ftg_marked_by.has(aid):
					target.ftg_marked_by.append(aid)
		"ftg_mark_removed":
			var p := GameManager.get_player(data.get("player_id", -1))
			if p:
				p.ftg_marked_by.clear()
		"ftg_swap":
			pass  # UI-only signal, no state change needed
		"ftg_dodge":
			pass  # UI-only signal, no state change needed
		"nine_tails_stage_changed":
			var p := GameManager.get_player(data.get("player_id", -1))
			if p:
				p.nine_tails_stage = data.get("stage", p.nine_tails_stage)
		"nine_tails_invincible_started":
			var p := GameManager.get_player(data.get("player_id", -1))
			if p:
				p.nine_tails_invincible = true
		"nine_tails_invincible_ended":
			var p := GameManager.get_player(data.get("player_id", -1))
			if p:
				p.nine_tails_invincible = false
		"nine_tails_attack":
			var hp_updates: Dictionary = data.get("hp_updates", {})
			for tid_str in hp_updates:
				var tid: int = int(tid_str)
				var tp := GameManager.get_player(tid)
				if tp:
					tp.hp = hp_updates[tid_str]
		"phantom_changed":
			var p := GameManager.get_player(data.get("player_id", -1))
			if p:
				p.phantom_count = data.get("count", p.phantom_count)
		"hiroari_used":
			pass  # UI-only signal, no state change needed
		"backtrack_performed":
			pass  # 回溯状态恢复由 FULL_STATE_SYNC 处理

## 将 FULL_STATE_SYNC 数据写入已存在的 GameManager._players（断线重连/再同步）
static func apply_full_sync(players: Array) -> void:
	for ps_data in players:
		var gm := GameManager.get_player(ps_data["id"])
		if gm == null:
			continue
		gm.hp              = ps_data["hp"]
		gm.energy          = ps_data["energy"]
		gm.shield          = ps_data["shield"]
		gm.paralyze_turns  = ps_data["paralyze"]
		gm.knockdown_turns = ps_data.get("knockdown", 0)
		gm.clone_count     = ps_data["clone"]
		gm.is_alive        = ps_data["alive"]
		gm.delayed_damages = ps_data.get("delayed_dmg", [])
		gm.bell_count      = ps_data.get("bell_count", 0)
		gm.counter_stance  = ps_data.get("counter_stance", false)
		gm.skill_disabled_turns = ps_data.get("skill_disabled", 0)
		gm.limited_skills_used = ps_data.get("limited_used", [])
		gm.gate_count = ps_data.get("gate_count", 0)
		gm.invincible_turns = ps_data.get("invincible_turns", 0)
		gm.burning = ps_data.get("burning", false)
		gm.berserker = ps_data.get("berserker", false)
		gm.consecutive_rounds = ps_data.get("consecutive_rounds", 0)
		gm.lost_skills = ps_data.get("lost_skills", [])
		gm.ftg_marks = ps_data.get("ftg_marks", 0)
		gm.ftg_marked_by = ps_data.get("ftg_marked_by", [])
		gm.nine_tails_stage = ps_data.get("nine_tails_stage", 0)
		gm.nine_tails_invincible = ps_data.get("nine_tails_invincible", false)
		gm.max_energy = ps_data.get("max_energy", 999)
		gm.stomp_active = ps_data.get("stomp_active", 0)
		gm.force_win_next_round = ps_data.get("force_win_next_round", 0) > 0
		gm.phantom_count = ps_data.get("phantom_count", 0)
		# 卫宫：投影/结界字段
		var proj_path: String = ps_data.get("projected_skill_path", "")
		gm.projected_skill = load(proj_path) as SkillData if proj_path != "" else null
		gm.projected_used_this_round = ps_data.get("projected_used_this_round", 0) > 0
		gm.binding_field_turns = ps_data.get("binding_field_turns", 0)
		gm.binding_field_targets = ps_data.get("binding_field_targets", [])
		gm.binding_field_force_win = ps_data.get("binding_field_force_win", 0) > 0
		gm.binding_field_skills.clear()
		for bf_path in ps_data.get("binding_field_skills_path", []):
			var bf_res := load(bf_path) as SkillData
			if bf_res:
				gm.binding_field_skills.append(bf_res)
		for path in ps_data.get("unlocked_skills", []):
			var skill_res := load(path) as SkillData
			if skill_res and not gm.unlocked_skills.has(skill_res):
				gm.unlocked_skills.append(skill_res)

## 每个 ROUND_END 阶段递减所有存活玩家的延迟伤害倒计时
## 使客户端徽章显示的剩余回合数与服务器保持同步
static func tick_delayed_damages() -> void:
	for player in GameManager._players:
		if not player.is_alive:
			continue
		for entry in player.delayed_damages:
			entry["trigger_in"] -= 1

## 将技能日志数组逐条写入 GameManager 玩家状态
static func _apply_skill_logs(logs: Array) -> void:
	for entry in logs:
		var target := GameManager.get_player(entry["target_id"])
		if target == null:
			continue
		var res: Dictionary = entry.get("result", {})
		match entry.get("effect_type", -1):
			SkillEffect.EffectType.DAMAGE:
				if res.get("clone_destroyed", false) and target.clone_count > 0:
					target.clone_count -= 1
				if res.get("counter_stance_triggered", false):
					target.energy += 1
					var attacker := GameManager.get_player(entry.get("attacker_id", -1))
					if attacker and attacker.is_alive:
						attacker.hp = max(0.0, attacker.hp - 1.0)
				target.hp = res.get("remaining_hp", target.hp)
				if res.get("damage_dealt", 0) > 0:
					target.took_damage_this_round = true
			SkillEffect.EffectType.TRUE_DAMAGE:
				target.hp = res.get("remaining_hp", target.hp)
				if res.get("damage_dealt", 0) > 0:
					target.took_damage_this_round = true
			SkillEffect.EffectType.SHIELD:
				target.shield = res.get("shield_value", target.shield)
			SkillEffect.EffectType.CLONE_SHIELD:
				target.clone_count = res.get("clone_count", target.clone_count + 1)
			SkillEffect.EffectType.PARALYZE:
				target.paralyze_turns = res.get("turns", target.paralyze_turns)
			SkillEffect.EffectType.KNOCKDOWN:
				target.knockdown_turns = res.get("knockdown_turns", target.knockdown_turns)
			SkillEffect.EffectType.HEAL:
				target.hp = res.get("remaining_hp", target.hp)
			SkillEffect.EffectType.DELAYED_DAMAGE:
				target.delayed_damages.append({
					"damage":      res.get("damage", 0),
					"trigger_in":  res.get("delay", 1),
					"attacker_id": entry.get("attacker_id", -1)
				})
			SkillEffect.EffectType.CHANGE_DISTANCE:
				if GameManager._distance_system:
					GameManager._distance_system.modify_distance(
						entry.get("attacker_id", -1),
						entry["target_id"],
						res.get("delta", 0)
					)
			SkillEffect.EffectType.UNLOCK_SKILL:
				var actor := GameManager.get_player(entry["target_id"])
				if actor:
					var path: String = res.get("skill_path", "")
					if path != "":
						var skill_res := load(path) as SkillData
						if skill_res and not actor.unlocked_skills.has(skill_res):
							actor.unlocked_skills.append(skill_res)
			SkillEffect.EffectType.DISABLE_SKILL:
				target.skill_disabled_turns = res.get("disabled_turns", target.skill_disabled_turns)
			SkillEffect.EffectType.COUNTER_STANCE:
				target.counter_stance = true
			SkillEffect.EffectType.LOSE_SKILL:
				var lname: String = res.get("lost_skill", "")
				if lname != "" and not target.lost_skills.has(lname):
					target.lost_skills.append(lname)
			SkillEffect.EffectType.FTG_MARK:
				target.hp = res.get("remaining_hp", target.hp)
				if res.get("damage_dealt", 0) > 0:
					target.took_damage_this_round = true
				var aid: int = entry.get("attacker_id", -1)
				if aid >= 0 and not target.ftg_marked_by.has(aid):
					target.ftg_marked_by.append(aid)
			SkillEffect.EffectType.FTG_CHARGE:
				pass  # ftg_marks updated via separate signal
			SkillEffect.EffectType.FTG_REMOVE:
				target.ftg_marked_by.clear()
			SkillEffect.EffectType.NINE_TAILS:
				pass  # handled via nine_tails signals

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
				var dmg: int = data.get("damage", 0)
				for i in range(p.delayed_damages.size()):
					var entry: Dictionary = p.delayed_damages[i]
					if entry.get("trigger_in", 1) <= 0 and entry.get("damage", 0) == dmg:
						p.delayed_damages.remove_at(i)
						break

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
		gm.clone_count     = ps_data["clone"]
		gm.is_alive        = ps_data["alive"]
		gm.delayed_damages = ps_data.get("delayed_dmg", [])
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
				target.hp = res.get("remaining_hp", target.hp)
			SkillEffect.EffectType.SHIELD:
				target.shield = res.get("shield_value", target.shield)
			SkillEffect.EffectType.CLONE_SHIELD:
				target.clone_count = res.get("clone_count", target.clone_count + 1)
			SkillEffect.EffectType.PARALYZE:
				target.paralyze_turns = res.get("turns", target.paralyze_turns)
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

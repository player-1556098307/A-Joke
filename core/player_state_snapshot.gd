## 玩家状态快照 — 用于战斗回放，记录某一时刻玩家的关键状态
class_name PlayerStateSnapshot
extends RefCounted

var player_id: int            ## 玩家ID
var hp: int                   ## 当前生命值
var energy: int               ## 当前能量
var has_shield: bool          ## 是否有护盾
var paralyze_turns: int       ## 剩余麻痹回合数
var is_alive: bool            ## 是否存活

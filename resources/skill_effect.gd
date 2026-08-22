## 技能效果 — 定义一个技能中的单个效果，含类型、数值、目标、持续等参数
class_name SkillEffect
extends Resource

## 效果类型枚举
enum EffectType {
	## 直接伤害：value=伤害量
	DAMAGE,
	## 护盾：value=-1为全挡, value>0为数值护盾
	SHIELD,
	## 麻痹：value=回合数，目标跳过出拳
	PARALYZE,
	## 改变距离：value=偏移量，可为负数
	CHANGE_DISTANCE,
	## 治疗：value=回复量，不超过最大HP
	HEAL,
	## 延迟伤害：挂buff，duration回合结束时触发
	DELAYED_DAMAGE,
	## 永久解锁技能到施法者列表
	UNLOCK_SKILL,
	## 影分身：一次性全挡伤害 + 充能加成
	CLONE_SHIELD,
	## 失去技能：value=回合数，目标无法使用技能（仅保留普攻）
	DISABLE_SKILL,
	## 防反姿态：进入counter_stance状态
	COUNTER_STANCE,
	## 真实伤害：无视护盾/分身/防反/无敌，直接扣HP
	TRUE_DAMAGE,
	## 失去技能：从角色技能列表中永久移除指定技能
	LOSE_SKILL,
	## 飞雷神标记：value=伤害量(0.5)，对目标造成伤害并标记飞雷神
	FTG_MARK,
	## 飞雷神聚气：自身+1飞雷神标记（消耗行动权，0气）
	FTG_CHARGE,
	## 飞雷神拔除：拔除自身飞雷神标记（消耗行动权，0气）
	FTG_REMOVE,
	## 漂泊九尾：三段延迟攻击（咆哮/大爪/尾兽玉），GameManager特殊处理
	NINE_TAILS,
	## 穿透伤害（断头台）：无视护盾(数值/全挡)、无敌、圣盾(全挡护盾)，直接扣HP
	PIERCE_DAMAGE,
	## 断罪死（第七圣典）：与目标进行7次猜拳，赢1次造成1伤，输1次回1血，赢≥4则即死
	DEATH_SENTENCE,
	## 投影（卫宫）：选择任意玩家，获得其一个技能的副本（用一次后消失）
	PROJECT_SKILL,
	## 无限剑制（卫宫）：下次猜拳必赢 + 结界持续5全局回合，结界内玩家的技能进入卫宫技能列表
	BINDING_FIELD,
	## 无法选择：value=回合数，目标无法被任何技能指定（不可选定状态）
	UNTARGETABLE,
	## 荣耀夺取（泉奈）：在目标回合的准备阶段触发，使其本回合失去所有技能并夺取本回合行动权
	GLORY_TAKEOVER,
	## 宇智波流招架（泉奈）：进入独立的招架状态，受击时伤害减半+进入无法选择+反击封技
	UCHIHA_STANCE,
	## 宇智波流·日晕舞（止水）：对一名玩家依次造成多段伤害，最后一段出伤前可预选中断点
	## value=单段伤害, duration=段数；中断与后续由 GameManager 处理
	HIANO_KAGEROHI,
	## 须佐能乎·斩（止水）：本回合无敌 + 2点伤害延迟到回合结束阶段结算（标准吸收链）
	## 伤害延迟由 GameManager 在 _end_round 处理，此处仅标记
	SUSANOO_SLASH,
	## 须佐能乎·螺旋（止水）：多段伤害（3段x1）+ 本回合无敌 + 目标本回合封技 + 解锁九十九
	## 每段单独走吸收链，由 GameManager 循环处理
	SUSANOO_SPIRAL,
	## 须佐能乎·九十九（止水）：多段伤害（4段x1）+ 本回合无敌，由 GameManager 循环处理
	SUSANOO_NINETY_NINE,
	## 别天神（止水，被动限定技）：获得过九十九即满足条件；击杀时自动弹窗确认夺舍
	## 夺舍：完全变成被杀者角色（技能替换）、血量回复至被杀者最大血量一半、继承其阵亡时气
	KOTOAMATSUKAMI,
	## 击飞：value=回合数，目标可正常猜拳获得回合，但行动阶段强制只能聚气
	KNOCKDOWN,
	## 天劫·回溯（新止水）：准备阶段消耗1气，全体玩家状态回滚到上一行动玩家回合开始前
	## 由 GameManager 在准备阶段特殊处理（快照拍摄+恢复）
	BACKTRACK,
	## 日影舞（新止水）：拥有3个幻影时消耗3气，对任意玩家分配4段斩击（每段2伤），每段独立结算
	## 由 GameManager 特殊处理（跨目标多段结算）
	HIROARI,
	## 幻影瞬身（新止水，被动标记）：普攻命中获得1幻影（至多3）；受击时可消耗1气+1幻影闪避
	## 被动生效，GameManager 处理获得/增伤/闪避，此处仅标记
	PHANTOM_BODY,
	## 送你砖石（黑塔，被动标记）：技能使目标血量跨过50%阈值时，立即对与黑塔范围为1的所有其他玩家造成1点伤害
	## 由 GameManager 在伤害结算后处理（含连锁触发，每玩家每结算链至多触发一次）
	GIFT_DIAMOND,
	## genjutsu（黑塔，被动标记）：黑塔对一名玩家造成伤害后，对其范围计算-1（可累积，距离最小1）
	## 由 GameManager 在伤害结算后处理
	GENJUTSU,
	## 解读（大黑塔，被动标记）：大黑塔造成伤害后目标获得【解】（距离-1、受大黑塔伤害+1）
	## 由 GameManager 在伤害结算后处理
	JIEDU,
	## 格局打开（大黑塔，被动标记）：【解】玩家受到任何来源伤害后大黑塔获得1气
	## 由 GameManager 在伤害结算后处理
	OPEN_MIND,
	## 魔法（大黑塔，主动）：3气，主目标2伤 + 所有【解】玩家1伤（含主目标）
	## 由 GameManager 特殊处理
	MAGIC,
	## ── 慈悲尖塔敌人专属 ──────────────────────────────────────────
	## 尖塔祝福（塔敌通用被动）：开局获得2个气
	TOWER_BLESSING,
	## 破败王者之刃（破败王者锁定技）：普攻3阶段强化（50%生命伤害/回半血/得2气），由GameManager处理
	BLADE_OF_THE_FALLEN,
	## 悲痛（破败王者被动）：血量低于一半时刷新破败王者之刃阶段
	HEARTBREAK,
	## 仙人之力（仙人鸣人被动）：聚气+1（聚气获得的气+1）
	SAGE_STRENGTH,
	## 蛙组手（仙人鸣人主动）：2耗，必中，2点真实伤害（跳过闪避/拦截）
	FROG_KATA,
	## 反馈（司马懿被动）：猜拳未获得回合时获得1怒（至多4），普攻附加怒数真实伤害后清空
	FURY,
	## 鬼才（司马懿被动）：连续获得两回合时额外获得一个回合
	GENIUS,
	## 谋略（司马懿被动）：免疫判定效果（麻痹/封技/击飞/无法选择等控制）
	STRATEGY,
	## 百分比伤害（慈悲尖塔一次性技能祝福：斩魂）：value=百分比（0.5=50%），
	## 按目标当前生命值结算，走标准减免链（无敌/护盾/分身/防反/坚壁）
	PERCENT_DAMAGE,
}

## 效果目标枚举
enum EffectTarget {
	ENEMY_SINGLE,  ## 单一敌人
	ENEMY_ALL,     ## 所有敌人
	SELF,          ## 自身
	ENEMY_SPLASH,  ## 主目标周围 splash_range 内的其他敌人
}

@export var effect_type: EffectType             ## 效果类型
@export var value: float                        ## 效果数值（含义因类型而异）
@export var target: EffectTarget                ## 目标类型
@export var duration: int = 1                   ## DELAYED_DAMAGE：延迟回合数
@export var unlock_skill: SkillData = null      ## UNLOCK_SKILL：要解锁的技能资源
@export var splash_range: int = 1               ## ENEMY_SPLASH：溅射半径
@export var bonus_if_paralyzed: int = 0         ## DAMAGE：目标被禁锢时额外伤害
@export var lose_skill_name: String = ""        ## LOSE_SKILL：要移除的技能名

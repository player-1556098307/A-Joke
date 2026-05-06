## 角色数据 — 定义可玩角色的基础属性、头像、技能和标签
## 作为 .tres 资源文件存储在 resources/characters/ 中，可在 Godot 编辑器中编辑
class_name CharacterData
extends Resource

@export var character_name: String      ## 角色名称
@export var max_hp: int                 ## 最大生命值
@export var basic_attack_cost: int = 1  ## 普攻能量消耗
@export var portrait: Texture2D         ## 角色头像
@export var avatar_emoji: String = ""   ## 头像框内显示的emoji（无头像时使用）
@export var skills: Array[SkillData]    ## 技能列表
@export var tags: Array[String] = []    ## 角色标签：战士/法师/坦克/刺客（可多个）

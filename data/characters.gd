## Characters — 角色数据表（Autoload）
extends Node

const LIST: Array[Dictionary] = [
	{
		"id": "naruto",
		"name": "漩涡鸣人",
		"sub": "NARUTO",
		"hp": 6,
		"role": "战士",
		"skills": "螺旋丸 · 影分身",
		"tags": ["近战", "机动性强"],
		"color": "#c8860a",
		"bg_color": "#fdf6e8",
		"res_path": "res://resources/characters/漩涡鸣人.tres",
	},
	{
		"id": "sasuke",
		"name": "宇智波佐助",
		"sub": "SASUKE",
		"hp": 6,
		"role": "法师",
		"skills": "豪火球 · 千鸟",
		"tags": ["远程", "爆发"],
		"color": "#2a6ab0",
		"bg_color": "#eef4fb",
		"res_path": "res://resources/characters/宇智波佐助.tres",
	},
	{
		"id": "sasuke2",
		"name": "宇智波佐助（疾风传）",
		"sub": "SASUKE II",
		"hp": 6,
		"role": "刺客",
		"skills": "火遁 · 铁锤",
		"tags": ["近战", "范围技"],
		"color": "#0f6e56",
		"bg_color": "#edf8f4",
		"res_path": "res://resources/characters/宇智波佐助（疾风传）.tres",
	},
	{
		"id": "sakura",
		"name": "春野樱",
		"sub": "SAKURA",
		"hp": 8,
		"role": "坦克",
		"skills": "蓄力拳 · 治疗",
		"tags": ["坦克", "治疗"],
		"color": "#993556",
		"bg_color": "#fbeff4",
		"res_path": "res://resources/characters/春野樱.tres",
	},
]

static func get_by_id(char_id: String) -> Dictionary:
	for data in LIST:
		if data.get("id") == char_id:
			return data
	return {}

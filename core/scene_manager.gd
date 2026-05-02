extends Node

## 跨场景传递游戏结果，game_ui.gd 写入，game_over.gd 读取
var pending_game_result: Dictionary = {}
## 记录最近一次游戏配置，支持再来一局
var last_game_config: Dictionary = {}

func go_to(path: String) -> void:
	get_tree().change_scene_to_file(path)

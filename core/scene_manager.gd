## SceneManager（自动加载）— 跨场景数据传递与场景导航
extends Node

## 游戏结果，由 game_ui.gd 写入，game_over.gd 读取
var pending_game_result: Dictionary = {}
## 最近一次游戏配置，支持"再来一局"功能
var last_game_config: Dictionary = {}
## HGW 模式最后一次配置（由角色选择场景写入，battle 场景读取）
var last_hgw_config: Dictionary = {}

## 切换场景到指定文件路径
func go_to(path: String) -> void:
	get_tree().change_scene_to_file(path)

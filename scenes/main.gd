extends Node

func _ready() -> void:
	if not SceneManager.last_game_config.is_empty():
		# 从 character_select 或 game_over 重玩时，config 已就绪
		GameManager.setup_game(SceneManager.last_game_config)
	elif GameManager.get_alive_players().is_empty():
		# 直接运行 main.tscn 时的调试回退配置
		var config := {
			"players": [
				{ "name": "佐助",        "is_human": true,  "character": preload("res://resources/characters/宇智波佐助.tres") },
				{ "name": "AI-疾风佐助", "is_human": false, "character": preload("res://resources/characters/宇智波佐助（疾风传）.tres") },
				{ "name": "AI-佐助",     "is_human": false, "character": preload("res://resources/characters/宇智波佐助.tres") },
			]
		}
		GameManager.setup_game(config)
	# setup_players 在 setup_game 延迟触发第一阶段之前执行，确保 UI 就绪
	$GameUI.setup_players(GameManager.get_alive_players())

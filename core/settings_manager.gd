## SettingsManager（自动加载）— 游戏设置持久化管理
## 使用 ConfigFile 存储到 user://settings.cfg，在 _ready 时加载并应用
extends Node

## 默认手势超时（秒）
const DEFAULT_GESTURE_TIMEOUT: int = 60
## 默认AI决策速度
const DEFAULT_AI_SPEED: String = "fast"
## 默认动画速度倍率
const DEFAULT_ANIM_SPEED: float = 1.0
## 默认全屏状态
const DEFAULT_FULLSCREEN: bool = false

## 手势输入超时时间（秒），0 表示无限制
var gesture_timeout: int = DEFAULT_GESTURE_TIMEOUT
## AI决策速度：fast=0.3s / medium=1.0s / slow=2.0s
var ai_speed: String = DEFAULT_AI_SPEED
## 动画播放速度倍率（通过 Engine.time_scale 实现）
var anim_speed: float = DEFAULT_ANIM_SPEED
## 是否全屏
var fullscreen: bool = DEFAULT_FULLSCREEN

const SAVE_PATH = "user://settings.cfg"

func _ready() -> void:
	load_settings()
	apply_fullscreen()
	Engine.time_scale = anim_speed

## 保存当前设置到文件
func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("gameplay", "gesture_timeout", gesture_timeout)
	cfg.set_value("gameplay", "ai_speed", ai_speed)
	cfg.set_value("gameplay", "anim_speed", anim_speed)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.save(SAVE_PATH)

## 从文件加载设置，文件不存在时使用默认值
func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	gesture_timeout = cfg.get_value("gameplay", "gesture_timeout", DEFAULT_GESTURE_TIMEOUT)
	ai_speed        = cfg.get_value("gameplay", "ai_speed",        DEFAULT_AI_SPEED)
	anim_speed      = cfg.get_value("gameplay", "anim_speed",      DEFAULT_ANIM_SPEED)
	fullscreen      = cfg.get_value("display",  "fullscreen",      DEFAULT_FULLSCREEN)

## 根据设置切换全屏/窗口模式
func apply_fullscreen() -> void:
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

## 返回AI决策延时（秒）：fast=0.3, medium=1.0, slow=2.0
func get_ai_delay() -> float:
	match ai_speed:
		"fast":   return 0.3
		"medium": return 1.0
		"slow":   return 2.0
	return 0.3

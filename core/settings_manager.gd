extends Node

const DEFAULT_GESTURE_TIMEOUT: int = 60
const DEFAULT_AI_SPEED: String = "fast"
const DEFAULT_ANIM_SPEED: float = 1.0
const DEFAULT_FULLSCREEN: bool = false

var gesture_timeout: int = DEFAULT_GESTURE_TIMEOUT
var ai_speed: String = DEFAULT_AI_SPEED
var anim_speed: float = DEFAULT_ANIM_SPEED
var fullscreen: bool = DEFAULT_FULLSCREEN

const SAVE_PATH = "user://settings.cfg"

func _ready() -> void:
	load_settings()
	apply_fullscreen()
	Engine.time_scale = anim_speed

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("gameplay", "gesture_timeout", gesture_timeout)
	cfg.set_value("gameplay", "ai_speed", ai_speed)
	cfg.set_value("gameplay", "anim_speed", anim_speed)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.save(SAVE_PATH)

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	gesture_timeout = cfg.get_value("gameplay", "gesture_timeout", DEFAULT_GESTURE_TIMEOUT)
	ai_speed        = cfg.get_value("gameplay", "ai_speed",        DEFAULT_AI_SPEED)
	anim_speed      = cfg.get_value("gameplay", "anim_speed",      DEFAULT_ANIM_SPEED)
	fullscreen      = cfg.get_value("display",  "fullscreen",      DEFAULT_FULLSCREEN)

func apply_fullscreen() -> void:
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func get_ai_delay() -> float:
	match ai_speed:
		"fast":   return 0.3
		"medium": return 1.0
		"slow":   return 2.0
	return 0.3

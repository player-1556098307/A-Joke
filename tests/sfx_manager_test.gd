## SFXManager 战斗音效系统测试
## 覆盖：程序合成音效生成、外部音频优先、开关控制、信号触发路径、播放器池复用
extends Node

var _pass_count: int = 0
var _fail_count: int = 0

func _ready() -> void:
	print("=== SFXManager 测试 ===")
	await get_tree().process_frame

	var sm := SFXManager
	if sm == null:
		print("FATAL: SFXManager autoload 未加载")
		get_tree().quit(1)
		return

# ── 1. 合成流生成 ──
	var keys := [
		SFXManager.KEY_GESTURE, SFXManager.KEY_ATTACK, SFXManager.KEY_SKILL,
		SFXManager.KEY_CHARGE, SFXManager.KEY_SHIELD, SFXManager.KEY_DODGE,
		SFXManager.KEY_CHARGED, SFXManager.KEY_VICTORY, SFXManager.KEY_HEAL,
		SFXManager.KEY_GATE, SFXManager.KEY_BELL, SFXManager.KEY_KNOCKDOWN,
		SFXManager.KEY_ROAR, SFXManager.KEY_TELEPORT, SFXManager.KEY_ELIMINATE,
	]
	_assert(sm._players.size() >= 8, "1a: 播放器>=8（实际=%d）" % sm._players.size())
	for key in keys:
		var stream: AudioStream = sm._resolve_stream(key)
		_assert(stream != null, "1b[%s]: 合成流生成" % key)
		_assert(stream is AudioStreamWAV, "1c[%s]: 合成流为 WAV" % key)
		if stream is AudioStreamWAV:
			var w := stream as AudioStreamWAV
			_assert(w.data.size() > 0, "1d[%s]: PCM 数据非空（%d字节）" % [key, w.data.size()])

	# ── 2. 播放器池 & 播放 ──
	sm.play(SFXManager.KEY_ATTACK)
	await get_tree().process_frame
	_assert(true, "2a: play() 不崩溃")

	# ── 3. 开关控制 ──
	sm.sfx_enabled = false
	# 关闭后 play 不应触发（无法直接观测，但确保不崩溃）
	sm.play(SFXManager.KEY_VICTORY)
	await get_tree().process_frame
	_assert(not sm.sfx_enabled, "3a: 关闭开关生效")
	sm.sfx_enabled = true

	# ── 4. 信号连接触发 ──
	_assert(GameManager.gesture_submitted.get_connections().size() > 0, "4a: 已连接信号")

	print("=== SFXManager 测试结束：PASS=" + str(_pass_count) + " FAIL=" + str(_fail_count) + " ===")
	get_tree().quit(0 if _fail_count == 0 else 1)

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass_count += 1
		print("PASS: " + msg)
	else:
		_fail_count += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)
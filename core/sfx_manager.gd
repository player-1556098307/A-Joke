## SFXManager（自动加载）— 战斗音效系统
##
## 职责：
##   1. 监听 GameManager 的 40+ 信号，自动触发对应战斗音效（UI 零侵入）
##   2. 音效来源优先级：外部音频文件（assets/audio/sfx/*.wav|*.ogg|*.mp3） > 程序合成短音效
##   3. 提供 play() API 供代码按需播放指定音效
##
## 外部音频替换规则（用户可自行放文件，无需改代码）：
##   - 文件名（不含扩展名）需与下列音效 KEY 同名，例如 hit.wav、charge.ogg
##   - 支持的 KEY：gesture, attack, skill, charge, shield, dodge, charged,
##                victory, heal, gate, bell, knockdown, roar, teleport, eliminate
##   - 加载后优先使用外部文件；缺失的 KEY 回退到程序合成音
##
## 程序合成音使用 AudioStreamWAV 直接构建 16-bit PCM 短波形，
## 无需任何外部素材文件，版权无忧；将来可直接用真实音频文件替换。

extends Node

## ── 音效 KEY 常量 ─────────────────────────────────────────────────────────
const KEY_GESTURE   := "gesture"
const KEY_ATTACK    := "attack"
const KEY_SKILL     := "skill"
const KEY_CHARGE    := "charge"
const KEY_SHIELD    := "shield"
const KEY_DODGE     := "dodge"
const KEY_CHARGED   := "charged"
const KEY_VICTORY   := "victory"
const KEY_HEAL      := "heal"
const KEY_GATE      := "gate"
const KEY_BELL      := "bell"
const KEY_KNOCKDOWN := "knockdown"
const KEY_ROAR      := "roar"
const KEY_TELEPORT  := "teleport"
const KEY_ELIMINATE := "eliminate"

## 外部音频搜索目录
const _SFX_DIR := "res://assets/audio/sfx/"

## 采样率
const _MIX_RATE := 22050

## 已加载的外部音效：key -> AudioStream
var _external: Dictionary = {}

## 音效总开关（持久化到 SettingsManager，默认开）
var sfx_enabled: bool = true

## 播放器池
var _players: Array[AudioStreamPlayer] = []

## 各音效音量倍率
const _VOLUMES := {
	KEY_GESTURE: 0.55, KEY_ATTACK: 0.8, KEY_SKILL: 0.8, KEY_CHARGE: 0.5,
	KEY_SHIELD: 0.7, KEY_DODGE: 0.7, KEY_CHARGED: 0.9, KEY_VICTORY: 0.9,
	KEY_HEAL: 0.7, KEY_GATE: 0.9, KEY_BELL: 0.85, KEY_KNOCKDOWN: 0.8,
	KEY_ROAR: 0.9, KEY_TELEPORT: 0.7, KEY_ELIMINATE: 0.85,
}

func _ready() -> void:
	_load_external_sfx()
	for i in range(10):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	if GameManager:
		_connect_signals()

## ── 信号连接 ───────────────────────────────────────────────────────────────
func _connect_signals() -> void:
	var gm := GameManager
	gm.gesture_submitted.connect(func(_p: int, _g: int): _play(KEY_GESTURE))
	gm.player_charged.connect(func(_p: int, _e: int): _play(KEY_CHARGE))
	gm.player_shielded.connect(func(_p: int, _s: float): _play(KEY_SHIELD))
	gm.player_eliminated.connect(func(_p: int): _play(KEY_ELIMINATE))
	gm.game_over.connect(_on_game_over)
	gm.bell_gained.connect(func(_p: int, _c: int): _play(KEY_BELL))
	gm.player_invincible.connect(func(_p: int, _t: int): _play(KEY_GATE))
	gm.eighth_gate_opened.connect(func(_p: int): _play(KEY_GATE))
	gm.player_burning.connect(func(_p: int): _play(KEY_ROAR))
	gm.player_berserker.connect(func(_p: int): _play(KEY_ROAR))
	gm.player_knocked_down.connect(func(_p: int, _t: int): _play(KEY_KNOCKDOWN))
	gm.ftg_swap_triggered.connect(func(_a: int, _b: int, _c: int): _play(KEY_TELEPORT))
	gm.ftg_dodge_triggered.connect(func(_p: int, _a: int): _play(KEY_DODGE))
	gm.phantom_dodge_triggered.connect(func(_p: int, _a: int): _play(KEY_DODGE))
	gm.counter_stance_triggered.connect(func(_t: int, _a: int): _play(KEY_SHIELD))
	gm.skill_applied.connect(_on_skill_applied)

## 技能命中音效：普攻 vs 技能区分
func _on_skill_applied(logs: Array) -> void:
	if logs.is_empty():
		return
	var first: Dictionary = logs[0]
	var skill_name: String = first.get("skill_name", "")
	if skill_name == "" or skill_name == "普攻":
		_play(KEY_ATTACK)
	else:
		_play(KEY_SKILL)

func _on_game_over(_winner_id: int, _record) -> void:
	_play(KEY_VICTORY)

## ── 对外 API ───────────────────────────────────────────────────────────────
func play(key: String, volume_scale: float = 1.0) -> void:
	_play(key, volume_scale)

func set_enabled(on: bool) -> void:
	sfx_enabled = on

func _play(key: String, volume_scale: float = 1.0) -> void:
	if not sfx_enabled:
		return
	var stream := _resolve_stream(key)
	if stream == null:
		return
	var p := _get_free_player()
	if p == null:
		return
	p.stream = stream
	p.volume_db = linear_to_db(_VOLUMES.get(key, 0.8) * volume_scale)
	p.play()

## 选择播放流：外部文件优先，缺失则程序合成
func _resolve_stream(key: String) -> AudioStream:
	if _external.has(key):
		return _external[key]
	return _synth_stream(key)

## ── 外部音频加载 ───────────────────────────────────────────────────────────
func _load_external_sfx() -> void:
	if not DirAccess.dir_exists_absolute(_SFX_DIR):
		return
	var dir := DirAccess.open(_SFX_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			var key := _filename_to_key(fname)
			if key != "":
				var stream: AudioStream = load(_SFX_DIR + fname)
				if stream != null:
					_external[key] = stream
		fname = dir.get_next()
	dir.list_dir_end()

## 文件名 -> KEY：去扩展名，统一小写
func _filename_to_key(fname: String) -> String:
	var dot := fname.rfind(".")
	if dot == -1:
		return ""
	var base := fname.substr(0, dot).to_lower()
	if base in _VOLUMES:
		return base
	return ""

## ── 程序合成音效 ───────────────────────────────────────────────────────────
## 用 AudioStreamWAV 构建 16-bit PCM 短波形
func _synth_stream(key: String) -> AudioStream:
	var mix_rate := _MIX_RATE
	var samples := _build_samples(key, mix_rate)
	if samples.is_empty():
		return null
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = mix_rate
	wav.stereo = false
	wav.data = _samples_to_pcm(samples)
	return wav

## 生成样本（范围 -1..1），返回 float 数组
func _build_samples(key: String, rate: int) -> Array[float]:
	match key:
		KEY_GESTURE:  return _tone(rate, 0.09, 880.0, 620.0, "sine", 0.6)
		KEY_ATTACK:   return _noise_hit(rate, 0.12, 0.8, 1500.0)
		KEY_SKILL:    return _tone(rate, 0.22, 320.0, 900.0, "saw", 0.7)
		KEY_CHARGE:   return _tone(rate, 0.12, 300.0, 600.0, "triangle", 0.6)
		KEY_SHIELD:   return _tone(rate, 0.18, 700.0, 350.0, "sine", 0.6)
		KEY_DODGE:    return _slide(rate, 0.15, 1200.0, 400.0, "sine", 0.55)
		KEY_CHARGED:  return _tone(rate, 0.22, 523.0, 1046.0, "triangle", 0.8)
		KEY_VICTORY:  return _arpeggio(rate, 0.8, [523.0, 659.0, 784.0, 1046.0], "triangle", 0.8)
		KEY_HEAL:     return _tone(rate, 0.25, 660.0, 990.0, "sine", 0.6)
		KEY_GATE:     return _tone(rate, 0.4, 120.0, 240.0, "saw", 0.8)
		KEY_BELL:     return _bell(rate, 0.5, 1200.0, 0.6)
		KEY_KNOCKDOWN:return _noise_hit(rate, 0.2, 0.7, 300.0)
		KEY_ROAR:     return _tone(rate, 0.3, 80.0, 160.0, "saw", 0.9)
		KEY_TELEPORT: return _slide(rate, 0.2, 300.0, 1800.0, "sine", 0.55)
		KEY_ELIMINATE:return _tone(rate, 0.35, 400.0, 100.0, "saw", 0.85)
	return []

## 单音（频率可选从 f0 滑到 f1），带指数衰减包络
func _tone(rate: int, dur: float, f0: float, f1: float, wave: String, amp: float) -> Array[float]:
	var n := int(dur * rate)
	var out: Array[float] = []
	out.resize(n)
	var phase := 0.0
	for i in range(n):
		var t := float(i) / n
		var f := f0 + (f1 - f0) * t
		phase += 2.0 * PI * f / float(rate)
		var v := _osc(phase, wave)
		var env := exp(-4.0 * t) # 指数衰减
		out[i] = v * env * amp
	return out

## 滑音（从 f0 到 f1，二次曲线，带回声感包络）
func _slide(rate: int, dur: float, f0: float, f1: float, wave: String, amp: float) -> Array[float]:
	var n := int(dur * rate)
	var out: Array[float] = []
	out.resize(n)
	var phase := 0.0
	for i in range(n):
		var t := float(i) / n
		var f := f0 + (f1 - f0) * (t * t)
		phase += 2.0 * PI * f / float(rate)
		var v := _osc(phase, wave)
		var env := sin(PI * t)  # 两端渐入渐出
		out[i] = v * env * amp
	return out

## 短促噪音撞击（打击感）
func _noise_hit(rate: int, dur: float, amp: float, lp: float) -> Array[float]:
	var n := int(dur * rate)
	var out: Array[float] = []
	out.resize(n)
	var lp_prev := 0.0
	for i in range(n):
		var t := float(i) / n
		var white := randf_range(-1.0, 1.0)
		# 简单一阶低通，模拟闷响
		lp_prev = lp_prev + lp * 0.003 * (white - lp_prev)
		var v := lp_prev
		var env := exp(-5.0 * t)
		out[i] = v * env * amp
	return out

## 钟声：主频 + 泛音，长衰减
func _bell(rate: int, dur: float, f0: float, amp: float) -> Array[float]:
	var n := int(dur * rate)
	var out: Array[float] = []
	out.resize(n)
	var phase := 0.0
	for i in range(n):
		var t := float(i) / n
		phase += 2.0 * PI * f0 / float(rate)
		# 主频 + 1.5倍泛音（非整数倍更接近金属感）
		var v := sin(phase) + 0.4 * sin(phase * 2.7)
		var env := exp(-6.0 * t)
		out[i] = v * env * amp
	return out

## 上行琶音（胜利）
func _arpeggio(rate: int, dur: float, freqs: Array, wave: String, amp: float) -> Array[float]:
	var out: Array[float] = []
	var per := dur / freqs.size()
	for f in freqs:
		var seg := _tone(rate, per, f, f, wave, amp)
		out.append_array(seg)
	return out

## 波形振荡器
func _osc(phase: float, wave: String) -> float:
	match wave:
		"sine":
			return sin(phase)
		"saw":
			var ph := fmod(phase, 2.0 * PI) / (2.0 * PI)
			return 2.0 * ph - 1.0
		"triangle":
			var ph := fmod(phase, 2.0 * PI) / (2.0 * PI)
			return 4.0 * abs(ph - 0.5) - 1.0
		"square":
			return 1.0 if fmod(phase, 2.0 * PI) < PI else -1.0
	return 0.0

## 样本数组 -> 16-bit PCM 字节
func _samples_to_pcm(samples: Array[float]) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in range(samples.size()):
		var v: float = clampf(samples[i], -1.0, 1.0)
		var s := int(v * 32767.0)
		var b := s & 0xFF
		bytes[i * 2] = b
		bytes[i * 2 + 1] = (s >> 8) & 0xFF
	return bytes

## ── 播放器池 ───────────────────────────────────────────────────────────────
func _get_free_player() -> AudioStreamPlayer:
	for p in _players:
		if not p.playing:
			return p
	return _players[0] if not _players.is_empty() else null
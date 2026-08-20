## TowerGate — 慈悲尖塔塔门对话场景（神官·梅塔特隆）
## 使用通用 DialogueBox 组件，支持打字机效果、分支选项、多阶段死亡对话
extends Control

## ---- 配色 ----
const C_BG       := Color("#12100D")
const C_PANEL_BG := Color("#1C1915")
const C_BORDER   := Color("#3A342A")
const C_GOLD     := Color("#FAC775")
const C_TEXT     := Color("#E8E2D5")
const C_TEXT_DIM := Color("#9A9182")

var _dialogue_box: DialogueBox
var _enter_btn: Button
var _back_btn: Button

const _CN_DIGITS := ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]

## 阿拉伯数字 → 中文数字（支持 0-99）
func _cn_num(n: int) -> String:
	if n <= 0:
		return "零"
	if n < 10:
		return _CN_DIGITS[n]
	if n < 20:
		return "十" + ("" if n == 10 else _CN_DIGITS[n % 10])
	if n < 100:
		var s: String = _CN_DIGITS[n / 10] + "十"
		if n % 10 > 0:
			s += _CN_DIGITS[n % 10]
		return s
	return str(n)

func _ready() -> void:
	_build_ui()
	_start_dialogue()

func _build_ui() -> void:
	# 全屏暗色背景
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.show_behind_parent = true
	add_child(bg)

	# 返回按钮（左上角）
	_back_btn = Button.new()
	_back_btn.text = "← 返回"
	_back_btn.focus_mode = Control.FOCUS_NONE
	_back_btn.custom_minimum_size = Vector2(90, 30)
	_back_btn.anchor_left = 0.0; _back_btn.anchor_top = 0.0
	_back_btn.offset_left = 16.0; _back_btn.offset_top = 14.0
	_back_btn.offset_right = 106.0; _back_btn.offset_bottom = 44.0
	_back_btn.z_index = 100
	_back_btn.add_theme_stylebox_override("normal", _make_flat(Color("#2A2A28"), Color("#3A342A"), 1, 6))
	_back_btn.add_theme_stylebox_override("hover", _make_flat(Color("#3A342A"), Color("#5A4E38"), 1, 6))
	_back_btn.add_theme_color_override("font_color", Color("#C9A84C"))
	_back_btn.add_theme_font_size_override("font_size", 11)
	_back_btn.pressed.connect(func(): SceneManager.go_to("res://scenes/tower/tower_select.tscn"))
	add_child(_back_btn)

	# 进入尖塔按钮（对话结束后显示）
	_enter_btn = Button.new()
	_enter_btn.text = "进入尖塔"
	_enter_btn.visible = false
	_enter_btn.focus_mode = Control.FOCUS_NONE
	_enter_btn.custom_minimum_size = Vector2(150, 36)
	_enter_btn.add_theme_font_size_override("font_size", 14)
	_enter_btn.anchor_left = 0.5; _enter_btn.anchor_top = 0.0; _enter_btn.anchor_right = 0.5
	_enter_btn.offset_left = -75.0; _enter_btn.offset_right = 75.0
	_enter_btn.offset_top = 474.0; _enter_btn.offset_bottom = 510.0
	_enter_btn.add_theme_stylebox_override("normal", _make_flat(Color("#2A5A3A"), Color("#2C2C2A"), 3, 8))
	_enter_btn.add_theme_stylebox_override("hover", _make_flat(Color("#3B6D11"), Color("#2C2C2A"), 3, 8))
	_enter_btn.pressed.connect(_on_enter)
	add_child(_enter_btn)

	# DialogueBox 组件
	_dialogue_box = DialogueBox.new()
	add_child(_dialogue_box)
	_dialogue_box.dialogue_finished.connect(_on_dialogue_finished)

func _start_dialogue() -> void:
	var data := _build_dialogue_data()
	_dialogue_box.start(data)

func _build_dialogue_data() -> Dictionary:
	var is_death: bool = SceneManager.tower_death_count > 0
	var death_count: int = SceneManager.tower_death_count
	var failed_floor: int = SceneManager.last_tower_config.get("failed_floor", 0)

	if is_death:
		return _build_death_dialogue(death_count, failed_floor)
	else:
		return _build_opening_dialogue()

## ---- 开场白 ----
func _build_opening_dialogue() -> Dictionary:
	return {
		"speaker": "神官 · 梅塔特隆",
		"lines": [
			{ "text": "（神官夹着圣典，眼皮都没抬）\n\n停。" },
			{ "text": "我是梅塔特隆，天书记官。塔里葬过一百零六个人，现在要葬第一百零七个。" },
			{ "text": "规矩只说一遍：死了就重来，直到你死够为止。\n你信慈悲？塔顶那点光，是钓饵。天堂从不怜惜走进去的人——它只怜惜走出来的。" },
			{ "text": "话已至此。你要进，我不拦。" },
			{ "text": "……但我劝你别回来自取其辱。" },
		]
	}

## ---- 多阶段死亡对话 ----
func _build_death_dialogue(count: int, failed_floor: int) -> Dictionary:
	var cn := _cn_num(count)
	var floor_cn := _cn_num(failed_floor) if failed_floor > 0 else "未知"

	# 根据死亡次数选择不同态度
	if count <= 2:
		return _death_cold(cn, floor_cn, count, failed_floor)
	elif count <= 5:
		return _death_impatient(cn, floor_cn, count, failed_floor)
	elif count <= 9:
		return _death_eerie(cn, floor_cn, count, failed_floor)
	else:
		return _death_exception(cn, floor_cn, count, failed_floor)

## 第1-2次死亡：冷漠记录
func _death_cold(cn: String, floor_cn: String, count: int, failed_floor: int) -> Dictionary:
	return {
		"speaker": "神官 · 梅塔特隆",
		"lines": [
			{ "text": "（梅塔特隆的笔停顿了一瞬，随即继续书写）\n\n回来了。第%s次。" % cn },
			{ "text": "天书这一页记得很清楚：某年某日，一名无名旅人，死于塔内第%s层，被自己的影子所杀。笔触潦草，不值得我多看。" % floor_cn },
			{ "text": "你总说下次能行。每个死人都这么说。" },
			{ "text": "……这次，往上爬的时候，别再回头看。塔会记住你怕什么。你越怕，它越往下长。" },
			{ "text": "去吧。你欠这塔的次数，还没还清。" },
		]
	}

## 第3-5次死亡：微微不耐
func _death_impatient(cn: String, floor_cn: String, count: int, failed_floor: int) -> Dictionary:
	return {
		"speaker": "神官 · 梅塔特隆",
		"lines": [
			{ "text": "（梅塔特隆甚至没有抬头）又来了。第%s次。" % cn },
			{ "text": "天书上你的那一页，墨迹都快透了。第%s层，还是老样子——你连自己的影子都打不过。" % floor_cn },
			{ "text": "你还真是有毅力——或者蠢。这两样东西在塔里没什么区别。" },
			{ "text": "知道吗？第一百零六个人也像你一样，来来回回走了十趟。后来他在塔里住下了，不走了。你猜他现在在哪？" },
			{ "text": "……算我没问。走吧，别让我把你的名字写进死人堆。" },
		]
	}

## 第6-9次死亡：诡异关怀
func _death_eerie(cn: String, floor_cn: String, count: int, failed_floor: int) -> Dictionary:
	return {
		"speaker": "神官 · 梅塔特隆",
		"lines": [
			{ "text": "（梅塔特隆合上圣典，第一次直视你的眼睛）\n\n第%s次。" % cn },
			{ "text": "……你变了。你有没有注意到？你的影子上长了东西。" },
			{ "text": "塔开始记住你了。每一次你倒下去，它就多记住你一点。你以为你在爬塔——其实塔也在爬你。" },
			{ "text": "天书上你的名字已经不是墨水写的了。是刻上去的。刻得很深。" },
			{ "text": "去吧。但下次回来的时候……如果还记得自己是谁，告诉我。我好奇。" },
		]
	}

## 第10+次死亡：破例
func _death_exception(cn: String, floor_cn: String, count: int, failed_floor: int) -> Dictionary:
	return {
		"speaker": "神官 · 梅塔特隆",
		"lines": [
			{ "text": "……" },
			{ "text": "（梅塔特隆缓缓撕下天书的一页，捏碎，灰烬从指缝间落下）" },
			{ "text": "你知道我从来不删记录。一百零六个人，每个人我都记得清清楚楚。" },
			{ "text": "但你……你已经不算是记录了。你是一种……循环。" },
			{ "text": "……我把天书这一页撕了。出去，就当从未来过。" },
			{ "text": "（停顿很久）\n\n但如果你非要再进来——门永远开着。" },
		]
	}

func _on_dialogue_finished() -> void:
	_enter_btn.visible = true

func _on_enter() -> void:
	SceneManager.go_to("res://scenes/tower/tower_battle.tscn")

func _make_flat(bg: Color, bdr: Color, bw: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg; s.border_color = bdr
	s.set_border_width_all(bw); s.set_corner_radius_all(radius)
	return s

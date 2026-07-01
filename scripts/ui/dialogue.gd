extends Node2D
# 面谈场景 · v4 · 双模式（summon 有预设 / active 只自输）

signal dialogue_finished(country: String, verdict: String)

var country: String = ""
var event_text: String = ""
var mode: String = "summon"   # "summon" | "active"
var _submitted: bool = false
var _preset_a: String = ""
var _preset_b: String = ""
var _preset_c: String = ""
var _presets_ready: bool = false

@onready var top_label: Label = $UILayer/TopLabel
@onready var name_label: Label = $UILayer/NameLabel
@onready var monarch_speech: Label = $UILayer/MonarchSpeechPanel/MonarchSpeech
@onready var briefing_label: Label = $UILayer/BriefingPanel/BriefingVBox/BriefingLabel
@onready var input_box: TextEdit = $UILayer/InputBox
@onready var submit_btn: Button = $UILayer/SubmitButton
@onready var result_label: Label = $UILayer/ResultLabel
@onready var portrait: Sprite2D = $Portrait

var _preset_a_btn: Button
var _preset_b_btn: Button
var _preset_c_btn: Button
var _others_btn: Button

func _ready() -> void:
	submit_btn.pressed.connect(_on_submit)
	_build_preset_buttons()

func _build_preset_buttons() -> void:
	# 动态在 result_label 上方创建 4 个按钮（仅 summon 模式显示）
	var ui = $UILayer
	_preset_a_btn = _mk_preset_btn("A. 加载中…", 240)
	_preset_b_btn = _mk_preset_btn("B. 加载中…", 292)
	_preset_c_btn = _mk_preset_btn("C. 加载中…", 344)
	_others_btn = _mk_preset_btn("others 自己说", 396)
	ui.add_child(_preset_a_btn)
	ui.add_child(_preset_b_btn)
	ui.add_child(_preset_c_btn)
	ui.add_child(_others_btn)
	_preset_a_btn.pressed.connect(func(): _on_preset(_preset_a))
	_preset_b_btn.pressed.connect(func(): _on_preset(_preset_b))
	_preset_c_btn.pressed.connect(func(): _on_preset(_preset_c))
	_others_btn.pressed.connect(_on_others)
	for b in [_preset_a_btn, _preset_b_btn, _preset_c_btn, _others_btn]:
		b.disabled = true
		b.visible = false

func _mk_preset_btn(txt: String, top: float) -> Button:
	var b := Button.new()
	b.set_anchors_preset(Control.PRESET_TOP_LEFT)
	b.anchor_left = 0.5
	b.anchor_right = 0.5
	b.offset_left = -420
	b.offset_right = 420
	b.offset_top = top
	b.offset_bottom = top + 44
	b.text = txt
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_font_size_override("font_size", 14)
	return b

func setup(c: String, ev_text: String, m: String = "summon") -> void:
	country = c
	event_text = ev_text
	mode = m
	var disp: String = _country_name(c)
	top_label.text = ("召见 · " if mode == "summon" else "求见 · ") + disp
	var mock: Dictionary = State.monarch_mock.get(c, {})
	name_label.text = String(mock.get("name", disp + "君"))
	var portrait_path: String = "res://assets/sprites/monarch_%s_portrait.png" % c
	var tex: Texture2D = load(portrait_path)
	if tex != null:
		portrait.texture = tex
	var am = get_node_or_null("/root/AgentManager")
	if am != null and am.has_method("get_audience_briefing"):
		briefing_label.text = am.get_audience_briefing()
	else:
		briefing_label.text = ""

	if mode == "summon":
		monarch_speech.text = "君主思忖片刻，望向你，缓缓开口……"
		# 隐藏输入框，显示预设按钮
		input_box.visible = false
		submit_btn.visible = false
		for b in [_preset_a_btn, _preset_b_btn, _preset_c_btn, _others_btn]:
			b.visible = true
		_request_summon_openings()
	else:
		var lines: Array = mock.get("audience", [])
		var speech: String = ""
		if lines.size() > 0:
			speech = String(lines[randi() % lines.size()])
		if event_text != "":
			speech = event_text + "\n" + speech
		monarch_speech.text = speech
		input_box.visible = true
		submit_btn.visible = true
		for b in [_preset_a_btn, _preset_b_btn, _preset_c_btn, _others_btn]:
			b.visible = false

# === 召见模式：问 LLM 要问句 + 3 预设 ===
func _request_summon_openings() -> void:
	var llm = get_node_or_null("/root/LLMClient")
	if llm == null or not llm.is_ready():
		_use_fallback_openings()
		return
	var prompt: String = _build_summon_opening_prompt()
	llm.request(prompt, {"model": "deepseek-v4-flash", "timeout_sec": 15.0, "temperature": 0.8, "response_json": true},
		func(parsed: Variant, err: String):
			if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
				_use_fallback_openings()
				return
			var q: String = String((parsed as Dictionary).get("question", ""))
			var opts: Variant = (parsed as Dictionary).get("options", null)
			if q == "" or typeof(opts) != TYPE_ARRAY or (opts as Array).size() < 3:
				_use_fallback_openings()
				return
			monarch_speech.text = q
			_preset_a = String((opts as Array)[0])
			_preset_b = String((opts as Array)[1])
			_preset_c = String((opts as Array)[2])
			_preset_a_btn.text = "A. " + _preset_a
			_preset_b_btn.text = "B. " + _preset_b
			_preset_c_btn.text = "C. " + _preset_c
			_presets_ready = true
			for b in [_preset_a_btn, _preset_b_btn, _preset_c_btn, _others_btn]:
				b.disabled = false
	)

func _use_fallback_openings() -> void:
	var mock: Dictionary = State.monarch_mock.get(country, {})
	var lines: Array = mock.get("audience", [])
	monarch_speech.text = String(lines[randi() % lines.size()]) if lines.size() > 0 else "先生请言。"
	_preset_a = "臣以为当合纵抗秦，以齐赵之力可拒之。"
	_preset_b = "此局关键在时机，臣请大王暂缓表态，静观其变。"
	_preset_c = "秦势不可当，与其抗之，不如以利结之。"
	_preset_a_btn.text = "A. " + _preset_a
	_preset_b_btn.text = "B. " + _preset_b
	_preset_c_btn.text = "C. " + _preset_c
	_presets_ready = true
	for b in [_preset_a_btn, _preset_b_btn, _preset_c_btn, _others_btn]:
		b.disabled = false

func _build_summon_opening_prompt() -> String:
	var monarch_names = {"qin": "秦王嬴稷（雄猜多疑）", "zhao": "赵王赵何（犹疑谨慎）", "qi": "齐王田地（精明渔利）"}
	var attrs: Dictionary = State.country_attrs.get(country, {})
	var lines: Array = [
		"# 你是",
		String(monarch_names.get(country, country)),
		"你现在召见了纵横家，正准备向他抛出你眼下的困局。",
		"",
		"# 局势",
		"你的三维：国威%d 盟信%d 战心%d" % [int(attrs.get("guowei",0)), int(attrs.get("mengxin",0)), int(attrs.get("zhanxin",0))],
		"关键事件：%s" % event_text,
		"",
		"# 任务",
		"1. 用文言写一句 ≤ 60 字的问句 question：说出你眼下的困局，请纵横家给建议。",
		"2. 生成 3 个可能的回答选项 options，每条 ≤ 30 字，第一人称（\"臣以为...\"）。",
		"   - options[0]: 立场偏向合纵抗秦",
		"   - options[1]: 中立自保、观望权变",
		"   - options[2]: 立场偏向亲秦连横",
		"",
		"# 输出（严格 JSON）：",
		'{"question": "...", "options": ["...", "...", "..."]}'
	]
	return "\n".join(lines)

func _on_preset(text: String) -> void:
	if _submitted or not _presets_ready:
		return
	_submitted = true
	for b in [_preset_a_btn, _preset_b_btn, _preset_c_btn, _others_btn]:
		b.disabled = true
	input_box.text = text
	input_box.visible = true
	submit_btn.visible = true
	submit_btn.disabled = true
	_send_to_verdict(text)

func _on_others() -> void:
	if _submitted:
		return
	# 打开自输：隐藏预设，展示输入框
	for b in [_preset_a_btn, _preset_b_btn, _preset_c_btn, _others_btn]:
		b.visible = false
	input_box.visible = true
	submit_btn.visible = true
	input_box.grab_focus()

func _on_submit() -> void:
	if _submitted:
		return
	_submitted = true
	submit_btn.disabled = true
	_send_to_verdict(input_box.text)

func _send_to_verdict(text: String) -> void:
	result_label.text = "君主思忖中…"
	result_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.5))
	var llm = get_node_or_null("/root/LLMClient")
	if llm != null and llm.is_ready():
		result_label.text = "君主思忖中…（最长 30 秒）"
		var prompt: String = _build_dialogue_prompt(text)
		llm.request(prompt, {"model": "deepseek-v4-pro", "timeout_sec": 30.0, "temperature": 0.6, "response_json": true},
			func(parsed: Variant, err: String):
				if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
					_apply_verdict_from_arbiter(text, "LLM 失败(%s) 走关键词兜底" % err)
					return
				_apply_verdict_from_llm(parsed as Dictionary)
		)
	else:
		var reason: String = "无 LLM 客户端" if llm == null else "config.cfg 无 api_key"
		_apply_verdict_from_arbiter(text, "%s 走关键词兜底" % reason)

func _build_dialogue_prompt(player_text: String) -> String:
	var monarch_persona = {
		"qin": "秦王嬴稷。雄猜多疑，霸道果决。你欲东出灭六国，最惧合纵。",
		"zhao": "赵王赵何。犹疑谨慎，欲联齐抗秦又怕被拖累。",
		"qi": "齐王田地。精明渔利，喜观望，谁给的多倾向谁。"
	}
	var attrs: Dictionary = State.country_attrs.get(country, {})
	var lines: Array = [
		"# 你是谁", monarch_persona.get(country, "一位战国君主"),
		"",
		"# 当前局势",
		"你的三维：国威%d 盟信%d 战心%d" % [int(attrs.get("guowei",0)), int(attrs.get("mengxin",0)), int(attrs.get("zhanxin",0))],
		"关键事件：%s" % event_text,
		"",
		"# 一位纵横家在你面前，说：", "「%s」" % player_text,
		"",
		"# 你的评估任务",
		"从 3 个维度对纵横家的这段话打分（0-10）：",
		"- comprehension: 你是否理解他想表达什么",
		"- stance_match: 他的话是否与你的立场匹配（合你意的越高）",
		"- persuasion: 他的游说力度",
		"",
		"# 输出（严格 JSON）：",
		'{"comprehension": 0-10, "stance_match": 0-10, "persuasion": 0-10, "response": "≤80 字君主回话（文言）", "internal": "≤40 字内心独白"}'
	]
	return "\n".join(lines)

func _apply_verdict_from_llm(parsed: Dictionary) -> void:
	var comp: float = clampf(float(parsed.get("comprehension", 5)), 0.0, 10.0)
	var stance: float = clampf(float(parsed.get("stance_match", 5)), 0.0, 10.0)
	var pers: float = clampf(float(parsed.get("persuasion", 5)), 0.0, 10.0)
	var score: float = comp * 0.3 + stance * 0.4 + pers * 0.3
	var verdict: String = "accept" if score >= 6.0 else "reject"
	var response_text: String = String(parsed.get("response", ""))

	if verdict == "accept":
		State.apply_player_delta({"hezong": 8, "mingwang": 5, "xinji": 5})
		State.pending_intel.append("[情报] %s采纳：%s" % [_country_name(country), response_text if response_text != "" else "君主允诺。"])
		result_label.text = "采纳 · 综合分 %.1f · 三维均升\n君主：%s" % [score, response_text]
		result_label.add_theme_color_override("font_color", Color(0.6, 1, 0.6))
	else:
		State.apply_player_delta({"mingwang": -5})
		State.pending_intel.append("[情报] %s拒绝：%s" % [_country_name(country), response_text if response_text != "" else "君主未允。"])
		result_label.text = "拒绝 · 综合分 %.1f · 名望 -5\n君主：%s" % [score, response_text]
		result_label.add_theme_color_override("font_color", Color(1, 0.6, 0.6))
	_finish_after_delay(verdict)

func _apply_verdict_from_arbiter(text: String, note: String) -> void:
	var arb = get_node("/root/Arbiter")
	var res: Dictionary = arb.parse_dialogue(text, country, "")
	var verdict: String = String(res.get("verdict", "reject"))
	var score: float = float(res.get("score", 5.0))
	if verdict == "accept":
		State.apply_player_delta({"hezong": 8, "mingwang": 5, "xinji": 5})
		State.pending_intel.append("[情报] %s采纳。" % _country_name(country))
		result_label.text = "采纳 · %.1f · %s" % [score, note]
		result_label.add_theme_color_override("font_color", Color(0.6, 1, 0.6))
	else:
		State.apply_player_delta({"mingwang": -5})
		State.pending_intel.append("[情报] %s拒绝。" % _country_name(country))
		result_label.text = "拒绝 · %.1f · %s" % [score, note]
		result_label.add_theme_color_override("font_color", Color(1, 0.6, 0.6))
	_finish_after_delay(verdict)

func _finish_after_delay(verdict: String) -> void:
	submit_btn.disabled = false
	submit_btn.visible = true
	submit_btn.text = "关闭"
	for con in submit_btn.pressed.get_connections():
		submit_btn.pressed.disconnect(con.callable)
	submit_btn.pressed.connect(func():
		emit_signal("dialogue_finished", country, verdict)
	)

static func _country_name(c: String) -> String:
	match c:
		"qin": return "秦"
		"zhao": return "赵"
		"qi": return "齐"
		_: return c

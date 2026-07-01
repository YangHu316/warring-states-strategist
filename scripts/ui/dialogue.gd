extends Node2D
# 面谈场景 · v5 · 双模式（summon 有预设 / active 只自输）· 布局用 VBox

signal dialogue_finished(country: String, verdict: String)

var country: String = ""
var event_text: String = ""
var mode: String = "summon"
var _submitted: bool = false
var _preset_a: String = ""
var _preset_b: String = ""
var _preset_c: String = ""
var _presets_ready: bool = false

@onready var top_label: Label = $UILayer/Root/VBox/TopLabel
@onready var name_label: Label = $UILayer/Root/VBox/NameLabel
@onready var briefing_label: Label = $UILayer/Root/VBox/BriefingPanel/BriefingVBox/BriefingLabel
@onready var monarch_speech: Label = $UILayer/Root/VBox/MonarchSpeechPanel/MonarchSpeech
@onready var preset_vbox: VBoxContainer = $UILayer/Root/VBox/PresetVBox
@onready var preset_a_btn: Button = $UILayer/Root/VBox/PresetVBox/PresetA
@onready var preset_b_btn: Button = $UILayer/Root/VBox/PresetVBox/PresetB
@onready var preset_c_btn: Button = $UILayer/Root/VBox/PresetVBox/PresetC
@onready var others_btn: Button = $UILayer/Root/VBox/PresetVBox/OthersBtn
@onready var input_box: TextEdit = $UILayer/Root/VBox/InputBox
@onready var submit_btn: Button = $UILayer/Root/VBox/SubmitButton
@onready var result_label: Label = $UILayer/Root/VBox/ResultLabel
@onready var portrait: Sprite2D = $Portrait

func _ready() -> void:
	submit_btn.pressed.connect(_on_submit)
	preset_a_btn.pressed.connect(func(): _on_preset(_preset_a))
	preset_b_btn.pressed.connect(func(): _on_preset(_preset_b))
	preset_c_btn.pressed.connect(func(): _on_preset(_preset_c))
	others_btn.pressed.connect(_on_others)
	preset_a_btn.disabled = true
	preset_b_btn.disabled = true
	preset_c_btn.disabled = true
	others_btn.disabled = true

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
		briefing_label.text = "（无博弈记录）"

	if mode == "summon":
		monarch_speech.text = "君主思忖片刻，望向你，缓缓开口……"
		preset_vbox.visible = true
		input_box.visible = false
		submit_btn.visible = false
		_request_summon_openings()
	else:
		var lines: Array = mock.get("audience", [])
		var speech: String = ""
		if lines.size() > 0:
			speech = String(lines[randi() % lines.size()])
		if event_text != "":
			speech = event_text + "\n" + speech
		monarch_speech.text = speech
		preset_vbox.visible = false
		input_box.visible = true
		submit_btn.visible = true

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
			preset_a_btn.text = "A. " + _preset_a
			preset_b_btn.text = "B. " + _preset_b
			preset_c_btn.text = "C. " + _preset_c
			_presets_ready = true
			preset_a_btn.disabled = false
			preset_b_btn.disabled = false
			preset_c_btn.disabled = false
			others_btn.disabled = false
	)

func _use_fallback_openings() -> void:
	var mock: Dictionary = State.monarch_mock.get(country, {})
	var lines: Array = mock.get("audience", [])
	monarch_speech.text = String(lines[randi() % lines.size()]) if lines.size() > 0 else "先生请言。"
	_preset_a = "臣以为当合纵抗秦，以齐赵之力可拒之。"
	_preset_b = "此局关键在时机，臣请大王暂缓表态，静观其变。"
	_preset_c = "秦势不可当，与其抗之，不如以利结之。"
	preset_a_btn.text = "A. " + _preset_a
	preset_b_btn.text = "B. " + _preset_b
	preset_c_btn.text = "C. " + _preset_c
	_presets_ready = true
	preset_a_btn.disabled = false
	preset_b_btn.disabled = false
	preset_c_btn.disabled = false
	others_btn.disabled = false

func _build_summon_opening_prompt() -> String:
	var monarch_names = {"qin": "秦王嬴稷（雄猜多疑）", "zhao": "赵王赵何（犹疑谨慎）", "qi": "齐王田地（精明渔利）"}
	var attrs: Dictionary = State.country_attrs.get(country, {})
	var lines: Array = [
		"# 世界铁律（不可违反）",
		"这个世界只有三个国家：秦、赵、齐。**不存在**韩、魏、楚、燕、宋、卫等任何其他国家。",
		"你的问句和 3 个选项**只能提及秦、赵、齐**。绝不允许出现其他国名或使者名（如张仪、平原君、廉颇、孟尝君可用，但苏秦、屈原等不许）。",
		"",
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
		"   - options[0]: 立场偏向合纵抗秦（秦赵齐三国框架内的合纵）",
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
	preset_a_btn.disabled = true
	preset_b_btn.disabled = true
	preset_c_btn.disabled = true
	others_btn.disabled = true
	input_box.text = text
	input_box.visible = true
	input_box.editable = false
	submit_btn.visible = false
	_send_to_verdict(text)

func _on_others() -> void:
	if _submitted:
		return
	preset_vbox.visible = false
	input_box.visible = true
	input_box.editable = true
	submit_btn.visible = true
	input_box.grab_focus()

func _on_submit() -> void:
	if _submitted:
		return
	_submitted = true
	submit_btn.disabled = true
	_send_to_verdict(input_box.text)

func _send_to_verdict(text: String) -> void:
	result_label.text = "君主思忖中…（最长 30 秒）"
	result_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.5))
	var llm = get_node_or_null("/root/LLMClient")
	if llm != null and llm.is_ready():
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
		"# 世界铁律",
		"这个世界只有三个国家：秦、赵、齐。**不存在**韩、魏、楚、燕、宋、卫等其他国家。你的回话只能提及秦赵齐（可提张仪/平原君/廉颇/孟尝君等本作出场人物）。",
		"",
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
		'{"comprehension": 0-10, "stance_match": 0-10, "persuasion": 0-10, "response": "≤80 字君主回话（文言，只提秦赵齐）", "internal": "≤40 字内心独白"}'
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
		result_label.text = "采纳 · 综合分 %.1f\n君主：%s" % [score, response_text]
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

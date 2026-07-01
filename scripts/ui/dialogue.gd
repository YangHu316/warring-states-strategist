extends Node2D
# 面谈场景 · v6 · 双模式 + 面谈后触发反应轮（群体智能）

signal dialogue_finished(country: String, verdict: String)
signal audience_settled(country: String, verdict: String, player_text: String, summary: String)

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
@onready var submit_hbox: HBoxContainer = $UILayer/Root/VBox/SubmitHBox
@onready var advisor_btn: Button = $UILayer/Root/VBox/SubmitHBox/AdvisorButton
@onready var submit_btn: Button = $UILayer/Root/VBox/SubmitHBox/SubmitButton
@onready var advisor_panel: PanelContainer = $UILayer/Root/VBox/AdvisorPreviewPanel
@onready var advisor_preview_label: Label = $UILayer/Root/VBox/AdvisorPreviewPanel/AdvisorPreviewVBox/AdvisorPreviewLabel
@onready var advisor_confirm_btn: Button = $UILayer/Root/VBox/AdvisorPreviewPanel/AdvisorPreviewVBox/AdvisorConfirmHBox/AdvisorConfirmBtn
@onready var advisor_reject_btn: Button = $UILayer/Root/VBox/AdvisorPreviewPanel/AdvisorPreviewVBox/AdvisorConfirmHBox/AdvisorRejectBtn
@onready var result_label: Label = $UILayer/Root/VBox/ResultLabel
@onready var portrait: Sprite2D = $Portrait

var _advisor_text: String = ""

func _ready() -> void:
	submit_btn.pressed.connect(_on_submit)
	advisor_btn.pressed.connect(_on_advisor_rewrite)
	advisor_confirm_btn.pressed.connect(_on_advisor_confirm)
	advisor_reject_btn.pressed.connect(_on_advisor_reject)
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
		submit_hbox.visible = false
		advisor_panel.visible = false
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
		submit_hbox.visible = true
		advisor_panel.visible = false

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
	var fb_by_country: Dictionary = {
		"qin": {
			"a": "臣以为当速速东出、以雷霆之势压赵，令其屈服。",
			"b": "臣以为宜先离间赵齐，瓦解合纵，再图东出。",
			"c": "臣以为当以利诱结齐、稳固后方，缓兵图之。"
		},
		"zhao": {
			"a": "臣以为当合纵联齐，以齐赵之力共拒秦。",
			"b": "臣以为宜暂缓表态，观秦齐动向后再决。",
			"c": "臣以为与其硬抗，不如通秦为好，以求偏安。"
		},
		"qi": {
			"a": "臣以为当押赵结盟，共抗秦以成合纵。",
			"b": "臣以为宜坐观秦赵之斗，待价而沽。",
			"c": "臣以为可接秦之利、坐享连横之益。"
		}
	}
	var fb: Dictionary = fb_by_country.get(country, fb_by_country["zhao"])
	_preset_a = String(fb["a"])
	_preset_b = String(fb["b"])
	_preset_c = String(fb["c"])
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
	var option_specs: Dictionary = {
		"qin": [
			"options[0] 激进：主张速速东出、军事施压赵，以雷霆之势压服",
			"options[1] 稳健：先离间赵齐、瓦解合纵，再图东出",
			"options[2] 怀柔：暂缓兵锋、以利诱结齐、稳固后方"
		],
		"zhao": [
			"options[0] 抗秦：坚定合纵联齐，以齐赵之力共拒秦",
			"options[1] 骑墙：暂缓表态、观望秦齐动向、伺机而动",
			"options[2] 亲秦：与其硬抗不如通秦为好、以求偏安"
		],
		"qi": [
			"options[0] 押赵：与赵结盟共抗秦、赌合纵能成",
			"options[1] 观望：坐山观秦赵之斗、待价而沽",
			"options[2] 押秦：接受秦之利诱、坐享连横之益"
		]
	}
	var opts: Array = option_specs.get(country, option_specs["zhao"])
	var lines: Array = [
		"# 世界铁律（不可违反）",
		"这个世界只有三个国家：秦、赵、齐。**不存在**韩、魏、楚、燕、宋、卫等任何其他国家。",
		"你的问句和 3 个选项**只能提及秦、赵、齐**。可用人物：张仪、魏冉、平原君、廉颇、孟尝君（不允许其他）。",
		"",
		"# 你是",
		String(monarch_names.get(country, country)),
		"你现在召见了纵横家，正准备向他抛出你眼下的困局。",
		"",
		"# 极其重要：选项的立场必须基于你（%s）的国家利益" % _country_name(country),
		"你**绝不会**问纵横家'如何抗击自己'——三个选项都必须是**辅佐你自己**的不同路线：",
		opts[0],
		opts[1],
		opts[2],
		"",
		"# 局势",
		"你的三维：国威%d 盟信%d 战心%d" % [int(attrs.get("guowei",0)), int(attrs.get("mengxin",0)), int(attrs.get("zhanxin",0))],
		"关键事件：%s" % event_text,
		"",
		"# 任务",
		"1. 用文言写一句 ≤ 60 字的问句 question：说出你眼下的困局，请纵横家给建议。",
		"2. 生成 3 个回答选项 options，每条 ≤ 30 字，第一人称（\"臣以为...\"），严格对应上面 3 条路线。",
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
	submit_hbox.visible = false
	_send_to_verdict(text)

func _on_others() -> void:
	if _submitted:
		return
	preset_vbox.visible = false
	input_box.visible = true
	input_box.editable = true
	submit_hbox.visible = true
	input_box.grab_focus()

func _on_advisor_rewrite() -> void:
	if _submitted:
		return
	var raw: String = input_box.text.strip_edges()
	if raw == "":
		result_label.text = "请先输入你的意图，谋士方能代拟。"
		result_label.add_theme_color_override("font_color", Color(1, 0.75, 0.4))
		return
	var llm = get_node_or_null("/root/LLMClient")
	if llm == null or not llm.is_ready():
		result_label.text = "谋士离席（LLM 未连接）—— 请直言。"
		result_label.add_theme_color_override("font_color", Color(1, 0.75, 0.4))
		return
	advisor_btn.disabled = true
	submit_btn.disabled = true
	result_label.text = "谋士润色中…"
	result_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.5))
	var prompt: String = _build_advisor_prompt(raw)
	llm.request(prompt, {"model": "deepseek-v4-flash", "timeout_sec": 15.0, "temperature": 0.7, "response_json": true},
		func(parsed: Variant, err: String):
			advisor_btn.disabled = false
			submit_btn.disabled = false
			if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
				result_label.text = "谋士辞穷（%s）—— 请直言。" % err
				result_label.add_theme_color_override("font_color", Color(1, 0.75, 0.4))
				return
			var polished: String = String((parsed as Dictionary).get("polished", ""))
			if polished == "":
				result_label.text = "谋士未能出言 —— 请直言。"
				return
			_advisor_text = polished
			advisor_preview_label.text = polished
			advisor_panel.visible = true
			result_label.text = ""
	)

func _build_advisor_prompt(raw: String) -> String:
	var monarch_names = {"qin": "秦王嬴稷", "zhao": "赵王赵何", "qi": "齐王田地"}
	var lines: Array = [
		"# 你是纵横家的私人谋士，负责将纵横家的白话意图润色为符合战国场合的说辞。",
		"# 世界铁律：世界只有秦、赵、齐三国。可提及张仪、魏冉、平原君、廉颇、孟尝君。",
		"",
		"# 场合",
		"纵横家正在面见 %s，欲进言。" % String(monarch_names.get(country, "一位君主")),
		"关键事件：%s" % event_text,
		"",
		"# 纵横家的意图（白话）",
		"「%s」" % raw,
		"",
		"# 你的任务",
		"将上文润色为一段 ≤ 100 字的文言进言，第一人称（\"臣\"），保留纵横家的核心目的与立场。",
		"要求：",
		"- 用文言，但不必生僻",
		"- 措辞讲究，符合面见君王的礼节",
		"- **不得改变原意的立场**（原意抗秦→润色也抗秦；原意亲秦→润色也亲秦）",
		"",
		"# 输出（严格 JSON）",
		'{"polished": "…润色后的文言…"}'
	]
	return "\n".join(lines)

func _on_advisor_confirm() -> void:
	if _submitted or _advisor_text == "":
		return
	_submitted = true
	input_box.text = _advisor_text
	input_box.editable = false
	advisor_panel.visible = false
	submit_hbox.visible = false
	_send_to_verdict(_advisor_text)

func _on_advisor_reject() -> void:
	advisor_panel.visible = false
	_advisor_text = ""
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
				_apply_verdict_from_llm(parsed as Dictionary, text)
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

func _apply_verdict_from_llm(parsed: Dictionary, player_text: String = "") -> void:
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
	_broadcast_audience(verdict, player_text)
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
	_broadcast_audience(verdict, text)
	_finish_after_delay(verdict)

func _broadcast_audience(verdict: String, player_text: String) -> void:
	# 简单摘要 = 玩家原文（≤ 60 字），若太长截断
	var summary: String = player_text.strip_edges()
	if summary.length() > 60:
		summary = summary.substr(0, 58) + "……"
	emit_signal("audience_settled", country, verdict, player_text, summary)

func _finish_after_delay(verdict: String) -> void:
	advisor_panel.visible = false
	advisor_btn.visible = false
	submit_hbox.visible = true
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

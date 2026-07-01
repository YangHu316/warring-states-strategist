extends Node2D
# 面谈场景 · v3 · LLM 二值裁决

signal dialogue_finished(country: String, verdict: String)

var country: String = ""
var event_text: String = ""
var _submitted: bool = false

@onready var top_label: Label = $UILayer/TopLabel
@onready var name_label: Label = $UILayer/NameLabel
@onready var monarch_speech: Label = $UILayer/MonarchSpeechPanel/MonarchSpeech
@onready var briefing_label: Label = $UILayer/BriefingPanel/BriefingVBox/BriefingLabel
@onready var input_box: TextEdit = $UILayer/InputBox
@onready var submit_btn: Button = $UILayer/SubmitButton
@onready var result_label: Label = $UILayer/ResultLabel
@onready var portrait: Sprite2D = $Portrait

func _ready() -> void:
	submit_btn.pressed.connect(_on_submit)

func setup(c: String, ev_text: String) -> void:
	country = c
	event_text = ev_text
	var disp: String = _country_name(c)
	top_label.text = "面谈 · %s" % disp
	var mock: Dictionary = State.monarch_mock.get(c, {})
	name_label.text = String(mock.get("name", disp + "君"))
	var lines: Array = mock.get("audience", [])
	var speech: String = ""
	if lines.size() > 0:
		speech = String(lines[randi() % lines.size()])
	if event_text != "":
		speech = event_text + "\n" + speech
	monarch_speech.text = speech
	var portrait_path: String = "res://assets/sprites/monarch_%s_portrait.png" % c
	var tex: Texture2D = load(portrait_path)
	if tex != null:
		portrait.texture = tex
	var am = get_node_or_null("/root/AgentManager")
	if am != null and am.has_method("get_audience_briefing"):
		briefing_label.text = am.get_audience_briefing()
	else:
		briefing_label.text = ""

func _on_submit() -> void:
	if _submitted:
		return
	_submitted = true
	var text: String = input_box.text
	submit_btn.disabled = true
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
		"# 你是谁",
		monarch_persona.get(country, "一位战国君主"),
		"",
		"# 当前局势",
		"你的三维：国威%d 盟信%d 战心%d" % [int(attrs.get("guowei",0)), int(attrs.get("mengxin",0)), int(attrs.get("zhanxin",0))],
		"关键事件：%s" % event_text,
		"",
		"# 一位纵横家在你面前，说：",
		"「%s」" % player_text,
		"",
		"# 你的评估任务",
		"从 3 个维度对纵横家的这段话打分（0-10）：",
		"- comprehension: 你是否理解他想表达什么",
		"- stance_match: 他的话是否与你的立场匹配（合你意的越高）",
		"- persuasion: 他的游说力度",
		"",
		"# 输出（严格 JSON，无多余文字）：",
		"{",
		'  "comprehension": 0-10,',
		'  "stance_match": 0-10,',
		'  "persuasion": 0-10,',
		'  "response": "≤80 字君主回话（用文言，符合你的性格）",',
		'  "internal": "≤40 字你的内心独白"',
		"}"
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
		var deltas: Dictionary = {"hezong": 8, "mingwang": 5, "xinji": 5}  # 打牌方向 1.5 倍近似
		State.apply_player_delta(deltas)
		State.intel_hand.append("[情报] %s采纳：%s" % [_country_name(country), response_text if response_text != "" else "君主允诺。"])
		result_label.text = "采纳 · 综合分 %.1f · 三维均升\n君主：%s" % [score, response_text]
		result_label.add_theme_color_override("font_color", Color(0.6, 1, 0.6))
	else:
		State.apply_player_delta({"mingwang": -5})
		State.intel_hand.append("[情报] %s拒绝：%s" % [_country_name(country), response_text if response_text != "" else "君主未允。"])
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
		State.intel_hand.append("[情报] %s采纳。" % _country_name(country))
		result_label.text = "采纳 · %.1f · %s" % [score, note]
		result_label.add_theme_color_override("font_color", Color(0.6, 1, 0.6))
	else:
		State.apply_player_delta({"mingwang": -5})
		State.intel_hand.append("[情报] %s拒绝。" % _country_name(country))
		result_label.text = "拒绝 · %.1f · %s" % [score, note]
		result_label.add_theme_color_override("font_color", Color(1, 0.6, 0.6))
	_finish_after_delay(verdict)

func _finish_after_delay(verdict: String) -> void:
	submit_btn.disabled = false
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

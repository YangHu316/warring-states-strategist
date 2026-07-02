extends Node2D
# 面谈场景 · v7.3.5 · 君主提议行动 · 玩家赞同/反对/中立 · 无成功率 · 影响国家三维

signal dialogue_finished(country: String, verdict: String)
signal audience_settled(country: String, verdict: String, player_text: String, summary: String)

var country: String = ""
var event_text: String = ""
var mode: String = "summon"
var _submitted: bool = false
var _proposed_action: String = ""
var _monarch_opening: String = ""
var _presets_ready: bool = false
var _stance_a: String = ""
var _stance_b: String = ""
var _stance_c: String = ""

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
	preset_a_btn.pressed.connect(func(): _on_preset("推合纵", _stance_a))
	preset_b_btn.pressed.connect(func(): _on_preset("中立", _stance_b))
	preset_c_btn.pressed.connect(func(): _on_preset("推亲秦", _stance_c))
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

	monarch_speech.text = "君主思忖片刻，望向你，缓缓开口……"
	preset_vbox.visible = true
	input_box.visible = false
	submit_hbox.visible = false
	advisor_panel.visible = false
	preset_a_btn.text = "A. 推合纵（加载中…）"
	preset_b_btn.text = "B. 中立"
	preset_c_btn.text = "C. 推亲秦"
	others_btn.text = "others 自己表态"
	_request_monarch_proposal()

# === 面谈开场：请君主提出一个行动意图 ===
func _request_monarch_proposal() -> void:
	var llm = get_node_or_null("/root/LLMClient")
	if llm == null or not llm.is_ready():
		_use_fallback_proposal()
		return
	var prompt: String = _build_proposal_prompt()
	llm.request(prompt, {"model": "deepseek-v4-flash", "timeout_sec": 15.0, "temperature": 0.8, "response_json": true},
		func(parsed: Variant, err: String):
			if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
				_use_fallback_proposal()
				return
			var opening: String = String((parsed as Dictionary).get("opening", ""))
			var proposed: String = String((parsed as Dictionary).get("proposed_action", ""))
			var opts_var: Variant = (parsed as Dictionary).get("stance_options", null)
			if opening == "" or proposed == "":
				_use_fallback_proposal()
				return
			_monarch_opening = opening
			_proposed_action = proposed
			monarch_speech.text = opening
			if typeof(opts_var) == TYPE_DICTIONARY:
				var opts: Dictionary = opts_var
				_stance_a = String(opts.get("hezong", ""))
				_stance_b = String(opts.get("neutral", ""))
				_stance_c = String(opts.get("qin", ""))
			if _stance_a == "":
				_stance_a = "臣以为当联齐赵以御秦，共举合纵之旗。"
			if _stance_b == "":
				_stance_b = "臣不敢妄决，请大王依己意而行。"
			if _stance_c == "":
				_stance_c = "臣以为当以秦为主，权变而行连横。"
			preset_a_btn.text = "A. 推合纵：" + _stance_a
			preset_b_btn.text = "B. 中立：" + _stance_b
			preset_c_btn.text = "C. 推亲秦：" + _stance_c
			_presets_ready = true
			preset_a_btn.disabled = false
			preset_b_btn.disabled = false
			preset_c_btn.disabled = false
			others_btn.disabled = false
	)

func _use_fallback_proposal() -> void:
	var default_actions: Dictionary = {
		"qin": {
			"opening": "赵齐动向不明，寡人有意备战蓄力，以待时变。足下以为何如？",
			"action": "prepare",
			"stance_a": "臣愚以为大王当缓东出之计，避六国之疑，方为长久之策。",
			"stance_b": "臣不敢妄决，请大王依己意而行，静观其变可也。",
			"stance_c": "臣以为大王备战正是时候，来日东出必成千秋伟业。"
		},
		"zhao": {
			"opening": "秦势逼人，孤欲联齐求盟以为犄角。先生以为可行否？",
			"action": "seek_alliance",
			"stance_a": "臣以为联齐乃赵之生路，大王当速遣使入齐，共举合纵。",
			"stance_b": "臣愚未敢妄断，请大王察齐之诚意再决不迟。",
			"stance_c": "臣以为齐不足恃，不如与秦交好，以求偏安一时。"
		},
		"qi": {
			"opening": "秦赵相持，寡人思观望渔利，先生以为妥当否？",
			"action": "observation",
			"stance_a": "臣以为齐当挺身联赵，共抗秦之东出，方为大义。",
			"stance_b": "臣以为大王待价而沽，坐观秦赵相争，最为稳妥。",
			"stance_c": "臣以为齐当受秦之利，倒向连横，可保富庶不失。"
		}
	}
	var fb: Dictionary = default_actions.get(country, default_actions["qin"])
	_monarch_opening = String(fb["opening"])
	_proposed_action = String(fb["action"])
	_stance_a = String(fb["stance_a"])
	_stance_b = String(fb["stance_b"])
	_stance_c = String(fb["stance_c"])
	monarch_speech.text = _monarch_opening
	preset_a_btn.text = "A. 推合纵：" + _stance_a
	preset_b_btn.text = "B. 中立：" + _stance_b
	preset_c_btn.text = "C. 推亲秦：" + _stance_c
	_presets_ready = true
	preset_a_btn.disabled = false
	preset_b_btn.disabled = false
	preset_c_btn.disabled = false
	others_btn.disabled = false

func _build_proposal_prompt() -> String:
	var monarch_names = {"qin": "秦王嬴稷（雄猜多疑）", "zhao": "赵王赵何（犹疑谨慎）", "qi": "齐王田地（精明渔利）"}
	var actions_defs = {
		"qin": "军事施压 pressure / 遣使离间 alienate / 连横利诱 lure / 备战蓄力 prepare",
		"zhao": "求盟联齐 seek_alliance / 备战固境 prepare / 遣使试探 probe / 骑墙观望 observation",
		"qi": "观望渔利 observation / 待价而沽 wait_price / 趁火打劫 hijack / 闭门自保 self_protect"
	}
	var attrs: Dictionary = State.country_attrs.get(country, {})
	var stance_hints: Dictionary = {
		"qin": {
			"hezong": "在秦王面前提合纵——极其危险，但纵横家可婉言暗劝秦王缓东出、待时机（不能直接说抗秦）",
			"neutral": "劝秦王暂观其变，不做定论",
			"qin": "力主秦当东出，为秦王背书连横之计"
		},
		"zhao": {
			"hezong": "力主赵联齐抗秦，直言合纵为唯一出路",
			"neutral": "劝赵王暂缓表态，观秦齐之动",
			"qin": "劝赵王与秦交好，避免与秦为敌"
		},
		"qi": {
			"hezong": "劝齐王联赵抗秦，不宜观望渔利",
			"neutral": "支持齐王待价而沽、坐山观虎斗",
			"qin": "劝齐王倒向秦，接受连横之利"
		}
	}
	var sh: Dictionary = stance_hints.get(country, stance_hints["zhao"])
	var lines: Array = [
		"# 世界铁律",
		"这个世界只有秦、赵、齐三国。可提及张仪、魏冉、平原君、廉颇、孟尝君。",
		"",
		"# 你是",
		String(monarch_names.get(country, country)),
		"你现在召见了纵横家，抛出困局，征询他的天下立场（推合纵/中立/推亲秦）。",
		"",
		"# 局势",
		"你的三维：国威%d 盟信%d 战心%d" % [int(attrs.get("guowei",0)), int(attrs.get("mengxin",0)), int(attrs.get("zhanxin",0))],
		"关键事件：%s" % event_text,
		"",
		"# 你的可用行动",
		String(actions_defs.get(country, "")),
		"",
		"# 任务",
		"1. `proposed_action`：从上表选一个你倾向采取的行动（英文 id）。",
		"2. `opening`：≤ 80 字文言开场——简述博弈 + 提出行动意图 + 一句问句征询纵横家立场。",
		"3. `stance_options`：为纵横家生成 3 个**完整文言表态句**（每条 30-60 字，不是短标签），对应三种立场：",
		"   - `hezong`（推合纵）：%s" % String(sh["hezong"]),
		"   - `neutral`（中立）：%s" % String(sh["neutral"]),
		"   - `qin`（推亲秦）：%s" % String(sh["qin"]),
		"   **重要**：3 条表态必须**符合当前君主人设**、**符合当前局势**、用文言、以'臣'自称、有礼节。",
		"",
		"# 输出（严格 JSON，无多余文字）：",
		'{"opening": "...", "proposed_action": "...", "stance_options": {"hezong": "...", "neutral": "...", "qin": "..."}}'
	]
	return "\n".join(lines)

# === 玩家表态 ===
func _on_preset(_stance_label: String, stance_text: String) -> void:
	if _submitted or not _presets_ready:
		return
	_submitted = true
	preset_a_btn.disabled = true
	preset_b_btn.disabled = true
	preset_c_btn.disabled = true
	others_btn.disabled = true
	input_box.text = stance_text
	input_box.visible = true
	input_box.editable = false
	_send_to_verdict(stance_text)

func _on_others() -> void:
	if _submitted:
		return
	preset_vbox.visible = false
	input_box.visible = true
	input_box.editable = true
	submit_hbox.visible = true
	submit_btn.disabled = false
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
	var monarch_names = {"qin": "秦王嬴稷", "zhao": "赵王赵何", "qi": "齐王田地"}
	var lines: Array = [
		"# 你是纵横家的私人谋士，负责将纵横家的白话意图润色为符合战国场合的说辞。",
		"# 世界铁律：世界只有秦、赵、齐三国。可提及张仪、魏冉、平原君、廉颇、孟尝君。",
		"",
		"# 场合",
		"纵横家正在面见 %s，君主刚提议采取行动「%s」，" % [String(monarch_names.get(country, country)), _proposed_action],
		"纵横家欲对该提议表态。",
		"",
		"# 纵横家的意图（白话）",
		"「%s」" % raw,
		"",
		"# 你的任务",
		"将上文润色为一段 ≤ 100 字的文言表态，第一人称（\"臣\"），保留纵横家的核心目的与立场（赞同/反对/中立均可，看原意）。",
		"要求：",
		"- 用文言，但不必生僻",
		"- 措辞讲究，符合面见君王的礼节",
		"- **不得改变原意的立场**",
		"",
		"# 输出（严格 JSON）",
		'{"polished": "…润色后的文言…"}'
	]
	llm.request("\n".join(lines), {"model": "deepseek-v4-flash", "timeout_sec": 15.0, "temperature": 0.7, "response_json": true},
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
		var prompt: String = _build_verdict_prompt(text)
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

func _build_verdict_prompt(player_text: String) -> String:
	var monarch_persona = {
		"qin": "秦王嬴稷。雄猜多疑，霸道果决。",
		"zhao": "赵王赵何。犹疑谨慎，怕独战怕激秦。",
		"qi": "齐王田地。精明渔利，喜观望。"
	}
	var attrs: Dictionary = State.country_attrs.get(country, {})
	var lines: Array = [
		"# 世界铁律：只有秦、赵、齐三国。可提及张仪、魏冉、平原君、廉颇、孟尝君。",
		"",
		"# 你是", monarch_persona.get(country, "一位战国君主"),
		"",
		"# 你先前的开场（提议行动）",
		_monarch_opening,
		"（你想执行的行动：%s）" % _proposed_action,
		"",
		"# 局势",
		"你的三维：国威%d 盟信%d 战心%d" % [int(attrs.get("guowei",0)), int(attrs.get("mengxin",0)), int(attrs.get("zhanxin",0))],
		"关键事件：%s" % event_text,
		"",
		"# 纵横家的表态",
		"「%s」" % player_text,
		"",
		"# 你的判断任务",
		"判断纵横家的立场是**推合纵**（联齐赵抗秦）、**推亲秦**（与秦交好），还是**中立**（不明确表态）：",
		"- 推合纵 → 玩家为你背书 → resolved=true，你坚定执行 proposed_action",
		"- 推亲秦 → 玩家为你背书 → resolved=true，你坚定执行 proposed_action",
		"- 中立/模糊 → 你按自己的性格自决（默认执行）→ resolved=true",
		"",
		"# 输出（严格 JSON）：",
		'{"player_stance": "推合纵"|"中立"|"推亲秦", "response": "≤ 60 字君主回话（文言，只提秦赵齐）", "resolved": true|false}'
	]
	return "\n".join(lines)

func _apply_verdict_from_llm(parsed: Dictionary, player_text: String = "") -> void:
	var stance: String = String(parsed.get("player_stance", "中立"))
	var resolved: bool = bool(parsed.get("resolved", true))
	var response_text: String = String(parsed.get("response", ""))
	_apply_stance(stance, resolved, response_text, player_text)

func _apply_verdict_from_arbiter(text: String, note: String) -> void:
	# 关键词兜底判读 推合纵/中立/推亲秦
	var t: String = text.strip_edges()
	var hezong_kw: Array = ["合纵", "抗秦", "联齐", "联赵", "共抗", "唇齿"]
	var qin_kw: Array = ["亲秦", "连横", "从秦", "归秦", "投秦", "秦交", "顺秦"]
	var stance: String = "中立"
	for k in hezong_kw:
		if t.find(k) >= 0:
			stance = "推合纵"
			break
	if stance == "中立":
		for k in qin_kw:
			if t.find(k) >= 0:
				stance = "推亲秦"
				break
	# 中立/推合纵/推亲秦 都视为背书 → resolved=true
	_apply_stance(stance, true, "（%s）" % note, text)

func _apply_stance(stance: String, resolved: bool, response_text: String, player_text: String) -> void:
	var arb = get_node("/root/Arbiter")
	var deltas_note: String = ""
	if resolved and arb != null and arb.has_method("settle_proposed_action"):
		var res: Dictionary = arb.settle_proposed_action(country, _proposed_action, "")
		deltas_note = String(res.get("note", ""))
	# 面谈完成 → 送 1 张情报牌（面谈摘要）
	State.intel_hand.append("[情报·%s面谈] 提议:%s / 你:%s / 结果:%s" % [
		_country_name(country), _proposed_action, stance, ("生效" if resolved else "搁置")
	])
	var color: Color
	if stance == "推合纵":
		color = Color(0.3, 0.85, 0.3)
	elif stance == "推亲秦":
		color = Color(1, 0.55, 0.2)
	else:
		color = Color(1, 0.75, 0.15)
	result_label.text = "你: %s | 提议 %s → %s\n君主：%s\n%s" % [
		stance, _proposed_action, ("生效" if resolved else "搁置"), response_text, deltas_note
	]
	result_label.add_theme_color_override("font_color", color)
	_broadcast_audience(stance, resolved, player_text)
	_finish_after_delay(stance)

func _broadcast_audience(stance: String, resolved: bool, player_text: String) -> void:
	var summary: String = "%s提议'%s'——纵横家%s，%s" % [
		_country_name(country), _proposed_action, stance, ("生效" if resolved else "搁置")
	]
	emit_signal("audience_settled", country, stance, player_text, summary)

func _finish_after_delay(verdict: String) -> void:
	preset_vbox.visible = false
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

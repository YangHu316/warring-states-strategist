extends Node2D
# 面谈场景 · v7.3.9 · 君主提议行动 · 玩家选倾向 → 双方 agent 围绕立场
# 进行最多 3 轮文言辩论 → 出 verdict · 主流聊天界面（左对方/右我方）

signal dialogue_finished(country: String, verdict: String)
signal audience_settled(country: String, verdict: String, player_text: String, summary: String)

const PlayerAgentScript = preload("res://scripts/core/player_agent.gd")

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

# v7.3.9 辩论状态 — 不限轮数，由 agent 主动 [END] 或玩家主动结束
var _debate_round: int = 0
const MAX_DEBATE_ROUNDS: int = 10  # 代码硬控上限（prompt 软控 5 轮）
var _current_stance: String = ""
var _debate_history: Array = []  # [{side, name, text}]
var _player_agent = null
var _debate_player_locked: bool = false  # 防止重复启动
var _debate_user_aborted: bool = false  # 玩家主动按"结束辩论"

@onready var top_label: Label = $UILayer/TopLabel
@onready var name_label: Label = $UILayer/NameLabel
@onready var briefing_label: Label = $UILayer/Root/VBox/BriefingPanel/BriefingVBox/BriefingLabel
@onready var monarch_speech_panel: PanelContainer = $UILayer/Root/VBox/MonarchSpeechPanel
@onready var monarch_speech: Label = $UILayer/Root/VBox/MonarchSpeechPanel/MonarchSpeech
@onready var chat_box: PanelContainer = $UILayer/Root/VBox/ChatBox
@onready var chat_log: VBoxContainer = $UILayer/Root/VBox/ChatBox/ChatVBox/ChatScroll/ChatLog
@onready var status_label: Label = $UILayer/Root/VBox/ChatBox/ChatVBox/StatusBar/StatusLabel
@onready var intercept_panel: PanelContainer = $UILayer/InterceptPanel
@onready var intercept_draft_label: Label = $UILayer/InterceptPanel/InterceptVBox/InterceptDraftLabel
@onready var intercept_countdown_label: Label = $UILayer/InterceptPanel/InterceptVBox/InterceptCountdownLabel
@onready var intercept_ok_btn: Button = $UILayer/InterceptPanel/InterceptVBox/InterceptHBox/InterceptOkBtn
@onready var intercept_add_btn: Button = $UILayer/InterceptPanel/InterceptVBox/InterceptHBox/InterceptAddBtn
@onready var intercept_input_box: TextEdit = $UILayer/InterceptPanel/InterceptVBox/InterceptInputBox
@onready var intercept_regen_btn: Button = $UILayer/InterceptPanel/InterceptVBox/InterceptRegenBtn

var _intercept_draft: String = ""
var _intercept_ended: bool = false      # 玩家 agent 是否已 [END]
var _intercept_timer: Timer = null
var _intercept_countdown: int = 3
var _intercept_regenerating: bool = false
@onready var end_btn: Button = $UILayer/Root/VBox/ChatBox/ChatVBox/StatusBar/EndDebateBtn
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
@onready var portrait: Sprite2D = $UILayer/Portrait
@onready var bg: Sprite2D = $BG

var _advisor_text: String = ""

func _ready() -> void:
	_player_agent = PlayerAgentScript.make()
	submit_btn.pressed.connect(_on_submit)
	advisor_btn.pressed.connect(_on_advisor_rewrite)
	advisor_confirm_btn.pressed.connect(_on_advisor_confirm)
	advisor_reject_btn.pressed.connect(_on_advisor_reject)
	preset_a_btn.pressed.connect(func(): _on_preset("推合纵", _stance_a))
	preset_b_btn.pressed.connect(func(): _on_preset("中立", _stance_b))
	preset_c_btn.pressed.connect(func(): _on_preset("推亲秦", _stance_c))
	others_btn.pressed.connect(_on_others)
	end_btn.pressed.connect(_on_end_debate_pressed)
	preset_a_btn.disabled = true
	preset_b_btn.disabled = true
	preset_c_btn.disabled = true
	others_btn.disabled = true
	# 拦截 UI
	intercept_ok_btn.pressed.connect(_on_intercept_ok)
	intercept_add_btn.pressed.connect(_on_intercept_add)
	intercept_regen_btn.pressed.connect(_on_intercept_regen)
	_intercept_timer = Timer.new()
	_intercept_timer.wait_time = 1.0
	_intercept_timer.one_shot = false
	add_child(_intercept_timer)
	_intercept_timer.timeout.connect(_on_intercept_tick)

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
	# 大殿背景按国家切换（秦/赵/齐 三张 02 大殿美术，v7.3.7 美术迭代）
	# v7.3.10：动态计算 bg.scale 使背景铺满整个屏幕（cover 模式）
	# 三张原图分辨率不同，硬编码 scale 会导致显示大小不一致
	var bg_path: String = "res://assets/bg/dialogue_%s.png" % c
	var bg_tex: Texture2D = load(bg_path)
	if bg_tex != null:
		bg.texture = bg_tex
	else:
		push_warning("dialogue: 背景图缺失 %s（fallback = 秦国大殿）" % bg_path)
		var fb: Texture2D = load("res://assets/bg/dialogue_qin.png")
		if fb != null:
			bg.texture = fb
	# 动态计算 scale 让背景铺满屏幕（cover：取较大比例保证无黑边）
	if bg.texture != null:
		var vp_size: Vector2 = get_viewport_rect().size
		var tex_size: Vector2 = bg.texture.get_size()
		if tex_size.x > 0 and tex_size.y > 0:
			var sx: float = vp_size.x / tex_size.x
			var sy: float = vp_size.y / tex_size.y
			var s: float = maxf(sx, sy)
			bg.scale = Vector2(s, s)
			# 居中（Sprite2D 原点在纹理中心）
			bg.position = vp_size / 2.0
	var am = get_node_or_null("/root/AgentManager")
	if am != null and am.has_method("get_audience_briefing_async"):
		briefing_label.text = "（史官正为你总结局势……）"
		am.get_audience_briefing_async(func(text: String):
			if is_instance_valid(briefing_label):
				briefing_label.text = text
		)
	elif am != null and am.has_method("get_audience_briefing"):
		briefing_label.text = am.get_audience_briefing()
	else:
		briefing_label.text = "（无博弈记录）"

	monarch_speech.text = "君主思忖片刻，望向你，缓缓开口……"
	preset_vbox.visible = true
	input_box.visible = false
	submit_hbox.visible = false
	advisor_panel.visible = false
	chat_box.visible = false
	# 清空 ChatLog 历史
	for child in chat_log.get_children():
		child.queue_free()
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

# === 玩家选择预设立场 → 启动辩论 ===
func _on_preset(stance_label: String, stance_text: String) -> void:
	if _submitted or not _presets_ready:
		return
	_submitted = true
	preset_a_btn.disabled = true
	preset_b_btn.disabled = true
	preset_c_btn.disabled = true
	others_btn.disabled = true
	_start_debate(stance_text, stance_label)

# === others 模式：玩家自输入 → 启动辩论（首句 = 输入文本） ===
func _on_others() -> void:
	if _submitted:
		return
	preset_vbox.visible = false
	input_box.visible = true
	input_box.editable = true
	submit_hbox.visible = true
	submit_btn.disabled = false
	input_box.grab_focus()

# === 玩家提交自定义文本（others 模式）→ 启动辩论 ===
func _on_submit() -> void:
	if _submitted:
		return
	_submitted = true
	submit_btn.disabled = true
	var txt: String = input_box.text.strip_edges()
	if txt == "":
		result_label.text = "请输入表态。"
		result_label.add_theme_color_override("font_color", Color(1, 0.75, 0.4))
		_submitted = false
		submit_btn.disabled = false
		return
	_start_debate(txt, "自定义")

# === 谋士代拟稿确认 → 启动辩论（首句 = 润色后文言） ===
func _on_advisor_confirm() -> void:
	if _submitted or _advisor_text == "":
		return
	_start_debate(_advisor_text, "自定义")
	# _start_debate 内部会 _submitted=true；这里不再单独标记

# === 启动辩论：把首条 player_msg 加进去 → 进入循环 ===
func _start_debate(player_first_msg: String, stance: String) -> void:
	_debate_player_locked = true
	_debate_user_aborted = false
	_current_stance = stance
	_debate_round = 0
	_debate_history = []
	_submitted = true
	# UI 切换
	preset_vbox.visible = false
	input_box.visible = false
	submit_hbox.visible = false
	advisor_panel.visible = false
	advisor_btn.visible = false
	monarch_speech_panel.visible = false
	chat_box.visible = true
	end_btn.disabled = false
	end_btn.visible = true
	for child in chat_log.get_children():
		child.queue_free()
	# 第 0 步：君主开场（pre-debate）作为 left msg
	_add_chat_msg("left", _country_name(country) + "王", _monarch_opening)
	_debate_history.append({"side": "left", "name": _country_name(country) + "王", "text": _monarch_opening})
	# 第 1 步：玩家 first_msg 作为 right msg
	_add_chat_msg("right", "你", player_first_msg)
	_debate_history.append({"side": "right", "name": "你", "text": player_first_msg})
	# 状态行
	_set_status("君主正在斟酌…")
	# 君主立即回复（这是 round 1 的君主回复）
	_debate_step_monarch()

# === 君主 agent 回应玩家最近一句 → 然后进入玩家下一步 ===
func _debate_step_monarch() -> void:
	if _debate_user_aborted:
		_end_debate()
		return
	if _debate_round >= MAX_DEBATE_ROUNDS:
		_end_debate()
		return
	_debate_round += 1
	var last_player_msg: String = _last_msg_text("right")
	var ai = _get_monarch_ai()
	if ai == null:
		# 兜底：直接结束
		_end_debate()
		return
	_set_status("君主正在斟酌…（已 %d 轮）" % _debate_round)
	var ctx: Dictionary = {
		"player_stance": _current_stance,
		"round": _debate_round,
		"last_player_msg": last_player_msg,
		"chat_history": _debate_history.duplicate()
	}
	ai.debate_respond_async(ctx, func(text: String):
		if _debate_user_aborted:
			_end_debate()
			return
		var ended: bool = text.begins_with("[END]")
		var disp: String = text.substr(5) if ended else text
		if disp == "":
			_end_debate()
			return
		_add_chat_msg("left", _country_name(country) + "王", disp)
		_debate_history.append({"side": "left", "name": _country_name(country) + "王", "text": disp})
		if ended:
			_end_debate()
			return
		# 君主没结束 → 玩家 agent 拟稿
		_debate_step_player()
	)

# === 玩家 agent 拟稿 → 君主 agent 回应 ===
func _debate_step_player() -> void:
	if _debate_user_aborted:
		_end_debate()
		return
	if _debate_round >= MAX_DEBATE_ROUNDS:
		_end_debate()
		return
	_debate_round += 1
	_generate_and_intercept("", "")

# 生成一次玩家 agent 发言（含指令 + 上一版拟稿），拟好后弹 3s 拦截
func _generate_and_intercept(player_instruction: String, previous_draft: String) -> void:
	if _debate_user_aborted:
		_end_debate()
		return
	var last_monarch_msg: String = _last_msg_text("left")
	if _intercept_regenerating:
		_set_status("谋士按你的指令重拟中……")
	else:
		_set_status("你正在斟酌…（已 %d 轮）" % _debate_round)
	var ctx: Dictionary = {
		"player_stance": _current_stance,
		"round": _debate_round,
		"last_monarch_msg": last_monarch_msg,
		"chat_history": _debate_history.duplicate(),
		"country": country,
		"player_instruction": player_instruction,
		"previous_draft": previous_draft
	}
	if _player_agent == null:
		_player_agent = PlayerAgentScript.make()
	_player_agent.respond_async(ctx, func(text: String):
		if _debate_user_aborted:
			_end_debate()
			return
		var ended: bool = text.begins_with("[END]")
		var disp: String = text.substr(5) if ended else text
		if disp == "":
			_end_debate()
			return
		# 弹拦截 UI 而不是直接送辩论
		_show_intercept(disp, ended)
	)

# 3s 拦截窗口 —— 玩家可确认 / 补充指令 / 或超时自动送
func _show_intercept(draft: String, ended: bool) -> void:
	_intercept_draft = draft
	_intercept_ended = ended
	_intercept_regenerating = false
	intercept_draft_label.text = draft + ("  [谋士判定：达成共识]" if ended else "")
	intercept_input_box.text = ""
	intercept_input_box.visible = false
	intercept_regen_btn.visible = false
	intercept_regen_btn.disabled = false
	intercept_ok_btn.disabled = false
	intercept_add_btn.disabled = false
	intercept_panel.visible = true
	_intercept_countdown = 10
	intercept_countdown_label.text = "%d" % _intercept_countdown
	_intercept_timer.start()

func _on_intercept_tick() -> void:
	_intercept_countdown -= 1
	if _intercept_countdown <= 0:
		_intercept_timer.stop()
		_finalize_intercept_ok()
		return
	intercept_countdown_label.text = "%d" % _intercept_countdown

func _on_intercept_ok() -> void:
	if _intercept_regenerating:
		return
	_intercept_timer.stop()
	_finalize_intercept_ok()

func _finalize_intercept_ok() -> void:
	# 玩家确认或倒计时到 → 送这条进言进辩论
	intercept_panel.visible = false
	var text: String = _intercept_draft
	var ended: bool = _intercept_ended
	_intercept_draft = ""
	_add_chat_msg("right", "你", text)
	_debate_history.append({"side": "right", "name": "你", "text": text})
	if ended:
		_end_debate()
		return
	# 玩家没结束 → 君主回应
	_debate_step_monarch()

func _on_intercept_add() -> void:
	# 玩家点【有补充】→ 停倒计时，展开输入框
	_intercept_timer.stop()
	intercept_countdown_label.text = "已暂停 · 请给谋士下指令"
	intercept_ok_btn.disabled = true
	intercept_add_btn.disabled = true
	intercept_input_box.visible = true
	intercept_regen_btn.visible = true
	intercept_input_box.grab_focus()

func _on_intercept_regen() -> void:
	if _intercept_regenerating:
		return
	var instruction: String = intercept_input_box.text.strip_edges()
	if instruction == "":
		intercept_countdown_label.text = "请先输入指令"
		return
	_intercept_regenerating = true
	intercept_regen_btn.disabled = true
	intercept_countdown_label.text = "谋士重拟中……"
	var previous_draft: String = _intercept_draft
	# 重生成（不+_debate_round，还是这一轮）
	_generate_and_intercept(instruction, previous_draft)

# === 玩家主动按"结束辩论"：禁用按钮 + 设标志，等当前 LLM callback 回来就终止 ===
func _on_end_debate_pressed() -> void:
	if not _debate_player_locked:
		return
	_debate_user_aborted = true
	end_btn.disabled = true
	_set_status("正在收束辩论…（等待 agent 收尾）")

# === 设置 ChatBox 状态行（常驻） ===
func _set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text

# === 辩论结束 → 直接结算（v7.3.10 快速路径，跳过第二次 LLM 仲裁） ===
# 原 _send_to_verdict 会调 deepseek-v4-pro 慢模型再仲裁一次（最长 30s）
# 玩家反馈：第一次辩论里君主 [END] 已表达态度，不需要再等 30s
# 快速路径：直接用玩家开场选的立场 + 君主最后一句作为 response → 走 _apply_stance
func _end_debate() -> void:
	if not chat_box.visible:
		# 已结束（避免 verdict 后再被 callback 重复触发）
		return
	# 用最后一条 player message 作为 player_text
	var player_text: String = _last_msg_text("right")
	end_btn.disabled = true
	chat_box.visible = false
	# 显示君主 speech 面板
	monarch_speech_panel.visible = true
	# 快速路径：直接取君主最后一条发言作为 response
	var response_text: String = _last_msg_text("left")
	if response_text == "":
		response_text = "寡人已决。"
	# stance 用玩家开场选的（推合纵/中立/推亲秦）—— 这是第一次"仲裁"的输入
	var stance: String = _current_stance
	if stance == "":
		stance = "中立"
	# 直接走结算流程，跳过 _send_to_verdict 的第二次 LLM 仲裁
	_apply_stance(stance, true, response_text, player_text)

# === 动态添加一条聊天行 ===
func _add_chat_msg(side: String, name: String, text: String) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)

	if side == "left":
		# 君主发言：左对齐（暗色气泡）
		var vb := VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var name_lbl := Label.new()
		name_lbl.text = name
		name_lbl.add_theme_color_override("font_color", Color(0.95, 0.6, 0.4))
		name_lbl.add_theme_font_size_override("font_size", 11)
		var bubble := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.15, 0.1, 0.2, 0.85)
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_right = 8
		style.corner_radius_bottom_left = 8
		style.content_margin_left = 12
		style.content_margin_right = 12
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		bubble.add_theme_stylebox_override("panel", style)
		var lbl := Label.new()
		lbl.text = text
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.custom_minimum_size = Vector2(320, 0)
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
		bubble.add_child(lbl)
		vb.add_child(name_lbl)
		vb.add_child(bubble)
		row.add_child(vb)
		# 撑满右侧
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
	else:
		# 玩家发言：右对齐（蓝色气泡）
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
		var vb := VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_SHRINK_END
		var name_lbl := Label.new()
		name_lbl.text = name
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		name_lbl.add_theme_color_override("font_color", Color(0.5, 0.85, 1))
		name_lbl.add_theme_font_size_override("font_size", 11)
		var bubble := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.1, 0.2, 0.4, 0.85)
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_right = 8
		style.corner_radius_bottom_left = 8
		style.content_margin_left = 12
		style.content_margin_right = 12
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		bubble.add_theme_stylebox_override("panel", style)
		var lbl := Label.new()
		lbl.text = text
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.custom_minimum_size = Vector2(320, 0)
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", Color(0.92, 0.96, 1))
		bubble.add_child(lbl)
		vb.add_child(name_lbl)
		vb.add_child(bubble)
		row.add_child(vb)
	chat_log.add_child(row)
	# 滚动到底
	await get_tree().process_frame
	var scroll: ScrollContainer = chat_log.get_parent() as ScrollContainer
	if scroll != null:
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)

# === 取最近一条指定侧的消息文字 ===
func _last_msg_text(side: String) -> String:
	for i in range(_debate_history.size() - 1, -1, -1):
		var m: Dictionary = _debate_history[i]
		if String(m.get("side", "")) == side:
			return String(m.get("text", ""))
	return ""

# === 从 AgentManager 拿君主 AI（RefCounted MonarchAI）===
func _get_monarch_ai():
	var am = get_node_or_null("/root/AgentManager")
	if am == null:
		return null
	if not am.has_method("get"):
		return null
	# AgentManager.ais 是 Dictionary country -> MonarchAI 实例
	var ai = am.ais.get(country, null) if am.ais != null else null
	return ai

# === 顾问润色：保持原逻辑，仅在辩论未启动时调用 ===
func _on_advisor_rewrite() -> void:
	if _submitted or _debate_player_locked:
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

func _on_advisor_reject() -> void:
	advisor_panel.visible = false
	_advisor_text = ""
	input_box.grab_focus()

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
	# 把辩论历史拼进 prompt（最后 6 条）
	var hist_str: String = "（无辩论历史）"
	if _debate_history.size() > 0:
		var hlines: Array = []
		var start: int = max(0, _debate_history.size() - 6)
		for i in range(start, _debate_history.size()):
			var m: Dictionary = _debate_history[i]
			hlines.append("[%s] %s：%s" % [String(m.get("side", "")), String(m.get("name", "")), String(m.get("text", ""))])
		hist_str = "\n".join(hlines)
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
		"# 辩论过程",
		hist_str,
		"",
		"# 纵横家最后一句",
		"「%s」" % player_text,
		"",
		"# 你的判断任务",
		"根据整场辩论，判断纵横家的立场是**推合纵**（联齐赵抗秦）、**推亲秦**（与秦交好），还是**中立**（不明确表态）：",
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
	# 关键词兜底判读 推合纵/中立/推亲秦（对齐 C13 v7.3.7）
	var t: String = text.strip_edges()
	# v7.3.7 P0-10：投降类词优先判为中立，不判为亲秦
	var neutral_kw: Array = ["降", "投降", "乞降", "请降", "归降",
		"中立", "自保", "自守", "观望", "看情况", "再说", "且慢",
		"依君", "听凭", "由你", "由王", "由君", "全凭",
		"不敢妄言", "臣不知", "难以作答"]
	var hezong_kw: Array = ["合", "纵", "盟", "抗秦", "联六国", "联抗", "六国合",
		"抗", "援助", "结盟", "联赵", "联齐", "联韩", "联魏", "联楚",
		"义兵", "义师", "义战", "共存", "守望相助", "互保", "公义", "唇齿"]
	# 亲秦：v7.3.7 移除 "降/投降"
	var qin_kw: Array = ["连横", "亲秦", "和秦", "归秦", "归顺", "事秦", "奉秦",
		"献", "三城", "河外", "河西", "议和", "和约",
		"聘", "质子", "朝贡", "岁贡", "纳贡", "通好"]
	var stance: String = "中立"
	# 优先匹配中立（含投降词）
	for k in neutral_kw:
		if t.find(k) >= 0:
			stance = "中立"
			# 若已含投降类，直接锁定中立
			if k in ["降", "投降", "乞降", "请降", "归降"]:
				_apply_stance(stance, true, "（%s · 投降→中立）" % note, text)
				return
			break
	# 无投降词 → 检查合纵
	for k in hezong_kw:
		if t.find(k) >= 0:
			stance = "推合纵"
			break
	if stance == "中立":
		for k in qin_kw:
			if t.find(k) >= 0:
				stance = "推亲秦"
				break
	_apply_stance(stance, true, "（%s）" % note, text)

func _apply_stance(stance: String, resolved: bool, response_text: String, player_text: String) -> void:
	var arb = get_node("/root/Arbiter")
	var deltas_note: String = ""
	if resolved and arb != null:
		# v7.3.7 RFC-002：立场三分支结算国家三维
		if arb.has_method("settle_proposed_action_with_stance"):
			var res: Dictionary = arb.settle_proposed_action_with_stance(country, _proposed_action, stance, "")
			deltas_note = String(res.get("note", ""))
		elif arb.has_method("settle_proposed_action"):
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

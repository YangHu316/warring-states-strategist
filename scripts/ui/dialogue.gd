extends Node2D
# 面谈场景 · v7.3.9 · 君主提议行动 · 玩家选倾向 → 双方 agent 围绕立场
# 进行最多 3 轮文言辩论 → 出 verdict · 主流聊天界面（左对方/右我方）

signal dialogue_finished(country: String, verdict: String)
signal audience_settled(country: String, verdict: String, player_text: String, summary: String)

const PlayerAgentScript = preload("res://scripts/core/player_agent.gd")

# fallback 常量：LLM 不可用时的结算动作 / 开场池 / 表态池（每次随机，避免每轮一模一样）
const _DEFAULT_ACTION: Dictionary = {"qin": "prepare", "zhao": "seek_alliance", "qi": "observation"}

const _FALLBACK_OPENINGS: Dictionary = {
	"qin": [
		"赵齐动向不明，寡人有意备战蓄力，以待时变。足下以为何如？",
		"六国之盟若隐若现，寡人欲先发制人。足下以为当先图何处？",
		"张仪言连横可不战而屈人，魏冉言当以兵威慑之——先生为寡人断之。"
	],
	"zhao": [
		"秦势逼人，孤欲联齐求盟以为犄角。先生以为可行否？",
		"廉颇请战，平原君主盟——两策相左，先生为孤断之。",
		"齐使迟迟不至，秦兵日近一日。孤当再遣使，还是自固邯郸？"
	],
	"qi": [
		"秦赵相持，寡人思观望渔利，先生以为妥当否？",
		"秦使赵使皆候于临淄——寡人先见谁？抑或都不见？",
		"孟尝君劝孤勿趟浑水，然坐视秦并赵，齐能独全乎？先生教我。"
	]
}

const _STANCE_POOLS: Dictionary = {
	"qin": {
		"hezong": [
			"臣愚以为大王当缓东出之计，避六国之疑，方为长久之策。",
			"臣闻强弩之末不穿鲁缟——愿大王暂敛兵锋，徐图后计。",
			"六国怨秦久矣，此时东出恐激其同仇。臣愿大王先施仁义、缓其戒心。"
		],
		"neutral": [
			"臣不敢妄决，请大王依己意而行，静观其变可也。",
			"此事关军国大计，臣愿大王召廷议而后定，毋轻动。",
			"两可之间，臣不敢代大王决。愿大王权衡利害，自断之。"
		],
		"qin": [
			"臣以为天命在秦，正当乘势而进，成千秋伟业。",
			"臣愿为大王画连横之策——六国之盟，散之不难。",
			"六国貌合神离，正是各个击破之时。臣请为大王先说最弱一环。"
		]
	},
	"zhao": {
		"hezong": [
			"臣以为联齐乃赵之生路，大王当速遣使入齐，共举合纵。",
			"赵齐唇齿也。臣请奉国书使齐，约同进退，共拒强秦。",
			"独木难支大厦。臣愿亲赴临淄为大王说齐王，成合纵之约。"
		],
		"neutral": [
			"臣愚未敢妄断，请大王察齐之诚意再决不迟。",
			"两难之局，臣以为不妨先固边备而缓表态，观数月再定。",
			"齐意未明之际，轻动皆险。臣愿大王静守，待变而动。"
		],
		"qin": [
			"臣以为齐不足恃，不如与秦交好，以求偏安一时。",
			"秦势方张，逆之必碎。臣请大王遣使入咸阳，先通其好。",
			"与其待秦兵临城下，不如先结其欢——和亲纳好，可换十年之安。"
		]
	},
	"qi": {
		"hezong": [
			"臣以为齐当挺身联赵，共抗秦之东出，方为大义。",
			"皮之不存，毛将焉附？赵若亡，齐岂能独全——愿大王速盟赵。",
			"秦之志在天下，非独在赵。臣愿大王早备唇亡齿寒之局。"
		],
		"neutral": [
			"臣以为大王待价而沽，坐观秦赵相争，最为稳妥。",
			"两强相争，齐居其间——臣以为且慢表态，价高者得。",
			"临淄富庶甲于天下，何必蹚浑水？臣愿大王坐收渔利。"
		],
		"qin": [
			"臣以为齐当受秦之利，倒向连横，可保富庶不失。",
			"秦之所许，实利也；合纵之义，虚名也。臣愿大王取实利。",
			"合纵成则赵强，连横成则齐安。为齐计，臣愿大王亲秦。"
		]
	}
}

# v7.3.10：action_id → 中文动词（用于记叙文本）
const _ACTION_CN_VERB: Dictionary = {
	"pressure": "施压", "alienate": "离间", "lure": "利诱", "prepare": "备战",
	"seek_alliance": "求盟", "probe": "试探", "observation": "观望",
	"wait_price": "待价", "hijack": "打劫", "self_protect": "自保",
	"declare_war": "兴兵", "war_attacker": "进军", "war_defender": "守御", "war_third": "观势"
}

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
const MAX_DEBATE_ROUNDS: int = 7  # 代码硬控上限（prompt 软控 7 轮，agent [END] 可提前结束）
var _current_stance: String = ""
var _debate_history: Array = []  # [{side, name, text}]
var _player_agent = null
var _debate_player_locked: bool = false  # 防止重复启动
var _debate_user_aborted: bool = false  # 玩家主动按"结束辩论"

# v7.4.1 心证：君主对进言的实时态度（−6..+6）。收场三档（采纳/自决/拒绝）由它决定，
# 收场白按已定结果生成 —— 台词、结果、数值结算三者同源
var _attitude: int = 0
var _last_shift: int = 0
const ATTITUDE_ACCEPT: int = 4
const ATTITUDE_REJECT: int = -4
const _INIT_ATTITUDE: Dictionary = {
	"qin":  {"推合纵": -2, "中立": 0, "推亲秦": 2},
	"zhao": {"推合纵": 2, "中立": 0, "推亲秦": -2},
	"qi":   {"推合纵": 0, "中立": 1, "推亲秦": 1}
}

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
var _intercept_draft_gloss: String = ""   # v7.3.10：拦截期拟稿的白话译文
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
	var prefix: String = "召见 · "
	if mode == "war":
		prefix = "军情 · "
	elif mode != "summon":
		prefix = "求见 · "
	top_label.text = prefix + disp
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

	monarch_speech.text = "君主正在思考，随后开口……"
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
	# v7.3.10：优先用君主 R2 决策时预生成的 proposed_action（召见前就想好的问题）
	# 若 AgentManager 缓存了，直接用；否则 fallback 调 LLM 想（原流程）
	# am 变量在 L132 已声明（用于 briefing），这里复用
	var pre_proposed: String = ""
	if am != null and am.has_method("get_country_proposed_action"):
		pre_proposed = am.get_country_proposed_action(country)
	# 战时优先：任何国家的面谈都围绕当前战事（RFC-004 §4.1.1）
	if WarManager.has_war():
		_use_war_proposal(WarManager.war_role(country))
	elif pre_proposed != "":
		_use_pre_proposed_action(pre_proposed)
	else:
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
			_apply_stance_options(opts_var if typeof(opts_var) == TYPE_DICTIONARY else {})
	)

func _use_fallback_proposal() -> void:
	var openings: Array = _FALLBACK_OPENINGS.get(country, _FALLBACK_OPENINGS["zhao"])
	_monarch_opening = String(openings[randi() % openings.size()])
	_proposed_action = String(_DEFAULT_ACTION.get(country, "observation"))
	monarch_speech.text = _monarch_opening
	_apply_stance_options({})

# v7.3.10：用君主 R2 预生成的 proposed_action（召见前就想好的问题）
# opening 用 proposed_action 本身（君主开场就直接抛出问题）
func _use_pre_proposed_action(pre_proposed: String) -> void:
	_monarch_opening = pre_proposed  # 君主开场 = 预生成的问题
	# v7.4.1：结算的动作必须是君主 R2 真实想做的事，不能用 fallback 顶替
	var actual: String = ""
	var am2 = get_node_or_null("/root/AgentManager")
	if am2 != null and am2.has_method("get_country_last_action_type"):
		actual = am2.get_country_last_action_type(country)
	_proposed_action = actual if actual != "" else String(_DEFAULT_ACTION.get(country, "observation"))
	monarch_speech.text = _monarch_opening
	# 表态选项：LLM 可用则按困局+史实现场定制，否则从池中随机
	var llm = get_node_or_null("/root/LLMClient")
	if llm != null and llm.is_ready():
		_request_stance_options()
	else:
		_apply_stance_options({})

# 战时面谈：开场与三表态围绕当前战事（攻方=劝和/缓兵/怂恿；守方=搬救兵/求和/屈从；第三方=驰援/静观/不援）
func _use_war_proposal(role: String) -> void:
	var brief: Dictionary = WarManager.war_brief()
	var att: String = _country_name(String(brief.get("attacker", "")))
	var def: String = _country_name(String(brief.get("defender", "")))
	var wp_name: String = String(brief.get("waypoint_name", ""))
	var price: String = WarManager.peace_price_text()
	_proposed_action = "war_" + role
	var openings: Dictionary = {
		"attacker": [
			"寡人大军已发，%s——先生此来，是劝寡人罢兵，还是助寡人破%s？" % [wp_name, def],
			"兵已出，%s。先生若有高见，此刻便讲；若是来求情的，且开个价。" % wp_name
		],
		"defender": [
			"%s军压境，%s！社稷危如累卵——先生教我：搬救兵？求和（其索价：%s）？还是死战？" % [att, wp_name, price],
			"敌军%s，城中人心惶惶。先生远来，可有解围之策？（闻%s军肯以%s罢兵）" % [wp_name, att, price]
		],
		"third": [
			"%s%s相攻，战火将蔓。孤当出手援%s，还是坐山观虎斗？先生试言之。" % [att, def, def],
			"%s军已%s。有人劝孤驰援%s，有人劝孤坐收渔利——先生以为如何？" % [att, wp_name, def]
		]
	}
	var arr: Array = openings.get(role, openings["third"])
	_monarch_opening = String(arr[randi() % arr.size()])
	monarch_speech.text = _monarch_opening
	var opts: Dictionary = {}
	match role:
		"attacker":
			opts = {
				"hezong": "臣以为此战不可久——六国侧目，胜亦失势。愿大王见好即收，罢兵还师。",
				"neutral": "臣以为宜缓进而观其变——围而不打，坐待城中自乱。",
				"qin": "兵贵神速！迟则生变，愿大王挥军疾进，一鼓而下！"
			}
		"defender":
			opts = {
				"hezong": "臣请为大王星夜出使，说邻国之君合兵驰援——盟成之日，敌自退。",
				"neutral": "存人失地，人地皆得。臣以为可纳%s求和，留元气以图后计。" % price,
				"qin": "强弱之势明矣。臣以为不如屈意事之，献%s换其罢兵，徐图自强。" % price
			}
		_:
			opts = {
				"hezong": "唇亡齿寒！臣愿大王即刻歃血为盟，发兵驰援——此天下之枢机。",
				"neutral": "臣以为且按兵不动，静观胜负，再定行止。",
				"qin": "臣以为大王当明言不预此战——莫为他人火中取栗。"
			}
	_apply_stance_options(opts)

# 应用表态选项；空/缺字段一律从池中随机补齐（避免每轮一模一样）
func _apply_stance_options(opts: Dictionary) -> void:
	var pool: Dictionary = _STANCE_POOLS.get(country, _STANCE_POOLS["zhao"])
	var pick = func(key: String) -> String:
		var arr: Array = pool.get(key, [])
		return String(arr[randi() % arr.size()]) if arr.size() > 0 else ""
	_stance_a = String(opts.get("hezong", ""))
	if _stance_a == "":
		_stance_a = pick.call("hezong")
	_stance_b = String(opts.get("neutral", ""))
	if _stance_b == "":
		_stance_b = pick.call("neutral")
	_stance_c = String(opts.get("qin", ""))
	if _stance_c == "":
		_stance_c = pick.call("qin")
	preset_a_btn.text = "A. 推合纵：" + _stance_a
	preset_b_btn.text = "B. 中立：" + _stance_b
	preset_c_btn.text = "C. 推亲秦：" + _stance_c
	_presets_ready = true
	preset_a_btn.disabled = false
	preset_b_btn.disabled = false
	preset_c_btn.disabled = false
	others_btn.disabled = false

# 为君主已抛出的问题定制三条表态（引账本史实）；失败回退池
func _request_stance_options() -> void:
	preset_a_btn.text = "A. 推合纵（谋士拟稿中…）"
	preset_b_btn.text = "B. 中立（谋士拟稿中…）"
	preset_c_btn.text = "C. 推亲秦（谋士拟稿中…）"
	var llm = get_node_or_null("/root/LLMClient")
	if llm == null or not llm.is_ready():
		_apply_stance_options({})
		return
	var monarch_names = {"qin": "秦王嬴稷", "zhao": "赵王赵何", "qi": "齐王田地"}
	var ledger_lines: Array = State.ledger_lines_for(country)
	var lines: Array = [
		"# 世界铁律：只有秦、赵、齐三国。可提及张仪、魏冉、平原君、廉颇、孟尝君。",
		"",
		"# 场合",
		"你是纵横家的私人谋士。%s召见纵横家，问：「%s」" % [String(monarch_names.get(country, country)), _monarch_opening],
		"",
		"# 既往盟约与恩怨（可为论据）",
		("\n".join(ledger_lines) if ledger_lines.size() > 0 else "（尚无）"),
		"",
		"# 任务",
		"为纵横家拟 3 条候选表态（每条 30-60 字文言，以'臣'自称，须直接回应君主之问，可引上述史实）：",
		"- hezong：推合纵（联齐赵抗秦）方向",
		"- neutral：中立/请君自决方向",
		"- qin：推亲秦（连横）方向",
		"",
		"# 输出（严格 JSON）：",
		'{"hezong": "...", "neutral": "...", "qin": "..."}'
	]
	llm.request("\n".join(lines), {"model": "deepseek-v4-flash", "timeout_sec": 8.0, "temperature": 0.85, "response_json": true},
		func(parsed: Variant, err: String):
			if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
				_apply_stance_options({})
				return
			_apply_stance_options(parsed as Dictionary)
	)

func _build_proposal_prompt() -> String:
	var monarch_names = {"qin": "秦王嬴稷（雄猜多疑）", "zhao": "赵王赵何（犹疑谨慎）", "qi": "齐王田地（精明渔利）"}
	var actions_defs = {
		"qin": "军事施压 pressure / 遣使离间 alienate / 连横利诱 lure / 备战蓄力 prepare",
		"zhao": "求盟联齐 seek_alliance / 备战固境 prepare / 遣使试探 probe / 骑墙观望 observation",
		"qi": "观望渔利 observation / 待价而沽 wait_price / 趁火打劫 hijack / 闭门自保 self_protect"
	}
	var wa: Dictionary = State.world_attrs
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
		"天下大势：秦之霸业%d 六国之盟%d 天下纷乱%d" % [int(wa.get("qin_baye",0)), int(wa.get("liu_guo_meng",0)), int(wa.get("tian_xia_fenluan",0))],
		"关键事件：%s" % event_text,
		"",
		"# 既往盟约与恩怨（跨回合史实，你亲历之事）",
		("\n".join(State.ledger_lines_for(country)) if State.ledger_lines_for(country).size() > 0 else "（尚无）"),
		"你的开场困局应与上述史实衔接（如已受某国之诺，可问'某国之诺可信否'）。",
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
	_attitude = int((_INIT_ATTITUDE.get(country, {}) as Dictionary).get(stance, 0))
	# 恩怨记忆：上次纳你之谏 +1 / 上次拒你或衔恨在心 −1（君主的信任是 Agent 的记忆）
	if String(State.last_audience.get(country, "")) == "采纳":
		_attitude += 1
	elif String(State.last_audience.get(country, "")) == "拒绝":
		_attitude -= 1
	if State.has_grudge(country):
		_attitude -= 1
	# 既有盟约影响初始心证：与秦有约者亲秦之说顺耳、合纵之说逆耳；赵齐有盟则反之
	if country != "qin" and State.has_pact(country, "qin"):
		if stance == "推亲秦":
			_attitude += 1
		elif stance == "推合纵":
			_attitude -= 1
	if State.has_pact("zhao", "qi"):
		if country == "qin":
			if stance == "推合纵":
				_attitude -= 1
		else:
			if stance == "推合纵":
				_attitude += 1
			elif stance == "推亲秦":
				_attitude -= 1
	# 兵祸及身的守方听得进救亡之言（合纵/搬援于他是生路，不是立场之争）
	if WarManager.has_war() and String(WarManager.war_brief().get("defender", "")) == country \
			and stance == "推合纵":
		_attitude += 2
	# 下限 −2：旧怨可以垫高门槛，但不许把话堵死（−2 起步 4 句好话仍可翻盘）
	_attitude = clampi(_attitude, -2, 3)
	_last_shift = 0
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
	_set_status("君主正在思考…")
	# 君主立即回复（这是 round 1 的君主回复）
	_debate_step_monarch()

# === 君主 agent 回应玩家最近一句 → 累计心证 → 然后进入玩家下一步 ===
func _debate_step_monarch() -> void:
	if _debate_user_aborted:
		_conclude_debate()
		return
	if _debate_round >= MAX_DEBATE_ROUNDS:
		_conclude_debate()
		return
	_debate_round += 1
	var last_player_msg: String = _last_msg_text("right")
	var ai = _get_monarch_ai()
	if ai == null:
		# 兜底：直接结束
		_conclude_debate()
		return
	_set_status("君主正在思考…（第 %d 轮）" % _debate_round)
	var ctx: Dictionary = {
		"player_stance": _current_stance,
		"round": _debate_round,
		"attitude": _attitude,
		"proposed_action": _proposed_action,
		"key_event_text": event_text,
		"last_player_msg": last_player_msg,
		"chat_history": _debate_history.duplicate(),
		"ledger_lines": State.ledger_lines_for(country),
		"territory_line": State.territory_line()
	}
	ai.debate_respond_async(ctx, func(msg: Dictionary):
		if _debate_user_aborted:
			_conclude_debate()
			return
		var text: String = String(msg.get("text", ""))
		var gloss: String = String(msg.get("gloss", ""))
		var ended: bool = bool(msg.get("ended", false))
		if text.begins_with("[END]"):
			text = text.substr(5)
			ended = true
		if text == "":
			_conclude_debate()
			return
		_last_shift = clampi(int(msg.get("shift", 0)), -2, 2)
		_attitude = clampi(_attitude + _last_shift, -6, 6)
		if _last_shift <= -2:
			State.apply_mingwang(-1)  # 当廷失言，传为笑谈
		_add_chat_msg("left", _country_name(country) + "王", text, gloss)
		_debate_history.append({"side": "left", "name": _country_name(country) + "王", "text": text, "gloss": gloss})
		_set_status("第 %d 轮 · %s%s" % [_debate_round, _attitude_desc(), _shift_arrow()])
		if ended or _attitude >= ATTITUDE_ACCEPT or _attitude <= ATTITUDE_REJECT:
			_conclude_debate()
			return
		# 君主没结束 → 玩家 agent 拟稿
		_debate_step_player()
	)

func _attitude_desc() -> String:
	if _attitude >= ATTITUDE_ACCEPT:
		return "君心已动，欲纳其言"
	if _attitude <= ATTITUDE_REJECT:
		return "君主怒意已生"
	if _attitude >= 2:
		return "君主意动"
	if _attitude <= -2:
		return "君主面有愠色"
	return "君主犹疑未决"

func _shift_arrow() -> String:
	if _last_shift > 0:
		return "（↑你的话起了作用）"
	if _last_shift < 0:
		return "（↓此言失策）"
	return ""

# === 玩家 agent 拟稿 → 君主 agent 回应 ===
func _debate_step_player() -> void:
	if _debate_user_aborted:
		_conclude_debate()
		return
	if _debate_round >= MAX_DEBATE_ROUNDS:
		_conclude_debate()
		return
	_debate_round += 1
	_generate_and_intercept("", "")

# 生成一次玩家 agent 发言（含指令 + 上一版拟稿），拟好后弹 3s 拦截
func _generate_and_intercept(player_instruction: String, previous_draft: String) -> void:
	if _debate_user_aborted:
		_conclude_debate()
		return
	var last_monarch_msg: String = _last_msg_text("left")
	if _intercept_regenerating:
		_set_status("谋士按你的指令重拟中……")
	else:
		_set_status("谋士正在拟稿…（已 %d 轮）" % _debate_round)
	var ctx: Dictionary = {
		"player_stance": _current_stance,
		"round": _debate_round,
		"last_monarch_msg": last_monarch_msg,
		"chat_history": _debate_history.duplicate(),
		"country": country,
		"player_instruction": player_instruction,
		"previous_draft": previous_draft,
		"ledger_lines": State.ledger_lines_for(country)
	}
	if _player_agent == null:
		_player_agent = PlayerAgentScript.make()
	_player_agent.respond_async(ctx, func(msg: Dictionary):
		if _debate_user_aborted:
			_conclude_debate()
			return
		var text: String = String(msg.get("text", ""))
		var gloss: String = String(msg.get("gloss", ""))
		var ended: bool = bool(msg.get("ended", false))
		var ended_prefix: bool = text.begins_with("[END]")
		var disp: String = text.substr(5) if ended_prefix else text
		if disp == "":
			_conclude_debate()
			return
		# 弹拦截 UI 而不是直接送辩论
		_show_intercept(disp, gloss, ended or ended_prefix)
	)

# 3s 拦截窗口 —— 玩家可确认 / 补充指令 / 或超时自动送
func _show_intercept(draft: String, gloss: String, ended: bool) -> void:
	_intercept_draft = draft
	_intercept_draft_gloss = gloss
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
	var gloss: String = _intercept_draft_gloss
	var ended: bool = _intercept_ended
	_intercept_draft = ""
	_intercept_draft_gloss = ""
	_add_chat_msg("right", "你", text, gloss)
	_debate_history.append({"side": "right", "name": "你", "text": text, "gloss": gloss})
	if ended:
		_conclude_debate()
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
	_set_status("正在结束辩论…（等待 agent 完成最后一句）")

# === 设置 ChatBox 状态行（常驻） ===
func _set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text

# === 辩论收束（v7.4.1 心证裁决） ===
# 结果三档由心证值决定，收场白按已定结果生成——台词、结果、数值结算三者同源：
#   心证 ≥ +2 → 采纳（按玩家立场分支结算）
#   心证 ≤ −2 → 拒绝（君主坚定执行原动作，全额）
#   其余      → 自决（中立分支，半幅）
func _conclude_debate() -> void:
	if not chat_box.visible:
		# 已结束（避免收场后再被 callback 重复触发）
		return
	end_btn.disabled = true
	chat_box.visible = false
	monarch_speech_panel.visible = true
	var outcome: String
	if _attitude >= 2:
		outcome = "采纳"
	elif _attitude <= -2:
		outcome = "拒绝"
	else:
		outcome = "自决"
	# 自定义表态 → 从玩家全部发言里判读立场（采纳分支需要）
	var stance: String = _current_stance
	if not (stance in ["推合纵", "中立", "推亲秦"]):
		stance = _stance_from_keywords(_all_player_text())
	var player_text: String = _last_msg_text("right")
	monarch_speech.text = "君主沉吟……"
	_set_status("")
	var ai = _get_monarch_ai()
	if ai != null and ai.has_method("debate_close_async"):
		var ctx: Dictionary = {
			"player_stance": stance,
			"outcome": outcome,
			"proposed_action": _proposed_action,
			"chat_history": _debate_history.duplicate()
		}
		ai.debate_close_async(ctx, func(msg: Dictionary):
			_apply_outcome(stance, outcome, String(msg.get("text", "")), String(msg.get("gloss", "")), player_text)
		)
	else:
		_apply_outcome(stance, outcome, "", "", player_text)

func _all_player_text() -> String:
	var parts: Array = []
	for m in _debate_history:
		if String(m.get("side", "")) == "right":
			parts.append(String(m.get("text", "")))
	return "。".join(parts)

# 自定义表态的立场判读（关键词兜底，无需 LLM）
func _stance_from_keywords(t: String) -> String:
	for k in ["降", "投降", "乞降", "请降", "归降"]:
		if t.find(k) >= 0:
			return "中立"
	var hezong_kw: Array = ["合", "纵", "盟", "抗秦", "联六国", "联抗", "六国合",
		"抗", "援助", "结盟", "联赵", "联齐",
		"义兵", "义师", "义战", "共存", "守望相助", "互保", "公义", "唇齿"]
	for k in hezong_kw:
		if t.find(k) >= 0:
			return "推合纵"
	var qin_kw: Array = ["连横", "亲秦", "和秦", "归秦", "归顺", "事秦", "奉秦",
		"献", "三城", "河外", "河西", "议和", "和约",
		"聘", "质子", "朝贡", "岁贡", "纳贡", "通好"]
	for k in qin_kw:
		if t.find(k) >= 0:
			return "推亲秦"
	return "中立"

# === 动态添加一条聊天行 ===
# v7.3.10：气泡内文言 + 白话同一 Label，\n 换行（同字体大小颜色）
# gloss 由 LLM/mock 与 text 同步返回，无加载等待
func _add_chat_msg(side: String, name: String, text: String, gloss: String = "") -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)

	# v7.3.10：文言 + 白话合并成单条文本，\n 分隔（如「汝以为如何？\n（你觉得怎样？）」）
	var full_text: String = text
	if gloss != "" and gloss != text:
		full_text = text + "\n（" + gloss + "）"

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
		lbl.text = full_text
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
		lbl.text = full_text
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

func _apply_outcome(stance: String, outcome: String, close_text: String, close_gloss: String, player_text: String) -> void:
	var arb = get_node("/root/Arbiter")
	var deltas_note: String = ""
	# 名望结算（RFC-004 §5.2，r10 减半）：采纳 +4 / 自决 +1 / 拒绝 −3
	match outcome:
		"采纳":
			State.apply_mingwang(4)
		"自决":
			State.apply_mingwang(1)
		"拒绝":
			State.apply_mingwang(-3)
	State.last_audience[country] = outcome
	# 纳谏进大殿：立场信号影响君主本回合后续决策，谏言入其跨回合记忆
	if outcome == "采纳":
		var stance_sig: Dictionary = {"推合纵": "hezong", "推亲秦": "qin", "中立": "neutral"}
		if stance_sig.has(stance):
			AgentManager.player_stance = String(stance_sig[stance])
		var mem_ai = AgentManager.ais.get(country, null)
		if mem_ai != null:
			mem_ai.memory.push_back({
				"round": State.current_round,
				"action": "纳纵横家之言（%s）" % stance,
				"target": "player",
				"player_stance": String(stance_sig.get(stance, ""))
			})
			if mem_ai.memory.size() > mem_ai.MEMORY_MAX:
				mem_ai.memory.pop_front()
	# 战时面谈优先按行军指令结算（收兵/减缓/疾进/求和/结盟驰援）
	var war_was_active: bool = WarManager.has_war()
	var war_res: Dictionary = WarManager.settle_audience(country, stance, outcome)
	if bool(war_res.get("handled", false)):
		deltas_note = String(war_res.get("note", ""))
		# 化解战争（劝退/促和/驰援劝退）→ 弭兵之名天下知
		if war_was_active and not WarManager.has_war() and outcome == "采纳" and stance != "推亲秦":
			State.apply_mingwang(8)
			deltas_note += "（弭兵之功，名望大涨）"
	elif arb != null:
		match outcome:
			"采纳":
				var res: Dictionary = arb.settle_proposed_action_with_stance(country, _proposed_action, stance, "")
				deltas_note = String(res.get("note", ""))
				# 合纵之谏的实体出口：说动赵/齐 → 赵齐军事同盟立成（纵横家两头奔走缔约）；
				# 说动秦王 → 息兵之诺（本回合不兴兵）
				if stance == "推合纵":
					if country in ["zhao", "qi"] and not State.has_alliance("zhao", "qi"):
						var ally_note: String = WarManager.form_alliance("zhao", "qi")
						if ally_note != "":
							deltas_note = (deltas_note + "；" + ally_note) if deltas_note != "" else ally_note
					elif country == "qin":
						WarManager.impose_truce("qin", 1)
						deltas_note = (deltas_note + "；" if deltas_note != "" else "") + "秦王允诺暂息兵戈（本回合不兴兵）"
			"自决":
				var res2: Dictionary = arb.settle_proposed_action_with_stance(country, _proposed_action, "中立", "")
				deltas_note = String(res2.get("note", ""))
			"拒绝":
				# 谏言被拒 → 君主坚定执行原动作（全额）
				var action_id: String = String(arb.PROPOSED_ACTION_MAP.get(_proposed_action, _proposed_action))
				var target: String = "zhao" if country == "qin" else "qin"
				var res3: Dictionary = arb.settle_agent_action({
					"actor": country,
					"target_country": target,
					"action_type": action_id
				})
				deltas_note = String(res3.get("note", ""))
	# 面谈完成 → 送 1 张情报牌（面谈摘要）
	var action_cn: String = String(_ACTION_CN_VERB.get(_proposed_action, _proposed_action))
	State.intel_hand.append("[情报·%s面谈] 议题:%s / 你:%s / 君主:%s" % [
		_country_name(country), action_cn, stance, outcome
	])
	# 君主收场白展示（文言 + 白话）
	if close_text != "":
		var disp: String = close_text
		if close_gloss != "" and close_gloss != close_text:
			disp += "\n（" + close_gloss + "）"
		monarch_speech.text = disp
	else:
		monarch_speech.text = "……"
	var color: Color
	match outcome:
		"采纳":
			color = Color(0.3, 0.85, 0.3)
		"拒绝":
			color = Color(1, 0.45, 0.3)
		_:
			color = Color(1, 0.75, 0.15)
	var stance_verb: String = "进言"
	if stance == "推合纵":
		stance_verb = "力主合纵之议"
	elif stance == "推亲秦":
		stance_verb = "力主连横之议"
	elif stance == "中立":
		stance_verb = "陈述中立之见"
	var king_name: String = _country_name(country) + "王"
	var outcome_verb: String
	match outcome:
		"采纳":
			outcome_verb = "纳其言"
		"拒绝":
			outcome_verb = "拂袖不纳，决意行「%s」之计" % action_cn
		_:
			outcome_verb = "沉吟未决，仍依己意而行"
	var narrative: String = "纵横家面见%s，%s。%s听罢，终%s。%s" % [
		king_name, stance_verb, king_name, outcome_verb, close_text
	]
	if deltas_note != "":
		narrative += "\n" + deltas_note
	# 面谈结果入承诺账本（跨回合，各国后续决策可引述）
	var ledger_line: String
	match outcome:
		"采纳":
			ledger_line = "%s纳纵横家之谏（%s）" % [king_name, stance_verb]
		"拒绝":
			ledger_line = "%s拒纵横家之谏，行「%s」" % [king_name, action_cn]
		_:
			ledger_line = "%s闻谏而自决（%s）" % [king_name, action_cn]
	State.add_ledger("audience", country, "", ledger_line)
	result_label.text = narrative
	result_label.add_theme_color_override("font_color", color)
	_broadcast_audience(stance, outcome, player_text, narrative)
	_finish_after_delay(outcome)

func _broadcast_audience(stance: String, outcome: String, player_text: String, narrative: String = "") -> void:
	var king_name: String = _country_name(country) + "王"
	var stance_short: String = "进言"
	if stance == "推合纵":
		stance_short = "力主合纵"
	elif stance == "推亲秦":
		stance_short = "力主连横"
	elif stance == "中立":
		stance_short = "陈述中立"
	var outcome_short: String = "纳其言"
	if outcome == "拒绝":
		outcome_short = "不纳"
	elif outcome == "自决":
		outcome_short = "自决之"
	var summary: String = "纵横家面见%s，%s，%s%s。" % [king_name, stance_short, king_name, outcome_short]
	if narrative != "":
		summary = narrative  # 若传入完整叙事则用叙事
	emit_signal("audience_settled", country, outcome, player_text, summary)

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

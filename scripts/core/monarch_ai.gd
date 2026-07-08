extends RefCounted
class_name MonarchAI
# V3 君主 AI — 状态感知的 mock 决策 + LLM 接入 hook
#
# 设计对齐 v7.3 §04-Agent架构 §11b-角色设计稿-程序：
#  - 每位君主独立评估世界状态、选择目标+动作
#  - 决策输入：本国三维、他国三维、关键事件、玩家立场信号、上一轮记忆
#  - 输出：{target_country, action, reason, confidence, expected_settle}
#
# LLM 接入点：pick_action_async(ctx, callback) 预留（当前直接同步 mock）。

var country: String = ""
var persona: Dictionary = {}
var advisor_weights: Dictionary = {}
var memory: Array = []  # 跨回合保留（换局才清）
const MEMORY_MAX: int = 8
var _alliance_refusals: int = 0  # 拒盟次数（跨回合，换局才清）：越拒越硬

# 性格偏离追踪：连续 2 轮 LLM 输出偏离性格 → 本回合改用 mock
var _persona_drift_count: int = 0
var _force_mock_this_run: bool = false

static func make(country_id: String) -> MonarchAI:
	var ai := MonarchAI.new()
	ai.country = country_id
	match country_id:
		"qin":
			ai.persona = {
				"actions": ["pressure", "alienate", "lure", "prepare", "declare_war"],
				"base": {"pressure": 1.0, "alienate": 1.0, "lure": 1.0, "prepare": 0.6, "declare_war": 0.3}
			}
			# 张仪·连横推手 + 魏冉·主战
			ai.advisor_weights = {"lure": 1.5, "prepare": 0.6, "pressure": 1.4, "declare_war": 1.2}
		"zhao":
			ai.persona = {
				"actions": ["seek_alliance", "prepare", "probe", "observation"],
				"base": {"seek_alliance": 1.4, "prepare": 1.0, "probe": 0.8, "observation": 0.6}
			}
			# 平原君·主合纵 + 廉颇·主战
			ai.advisor_weights = {"seek_alliance": 1.4, "observation": 0.5, "prepare": 1.3}
		"qi":
			ai.persona = {
				"actions": ["observation", "wait_price", "hijack", "self_protect", "seek_alliance"],
				"base": {"observation": 1.5, "wait_price": 1.0, "hijack": 0.5, "self_protect": 0.8, "seek_alliance": 0.4}
			}
			# 孟尝君·谨慎渔利
			ai.advisor_weights = {"observation": 1.3, "hijack": 0.5, "wait_price": 0.8}
		_:
			ai.persona = {"actions": ["observation"], "base": {"observation": 1.0}}
	return ai

# 主决策入口。ctx 包含全部上下文：
#   ctx = {
#     round: int,                        # 1 或 2
#     key_event_tag: String,
#     world_attrs: Dictionary,           # 世界三维 {qin_baye, liu_guo_meng, tian_xia_fenluan}
#     player_stance: String,             # "hezong"/"qin"/"neutral"/""——玩家最近打牌方向
#     opponents_history: Array,          # 上一轮各君主动作
#     me_last_action: Dictionary
#   }
func pick_action(ctx: Dictionary) -> Dictionary:
	# 1. 计算每个可用动作的分数
	var scores: Dictionary = _score_actions(ctx)
	# 2. 挑最高分作为动作类型
	var action: String = _argmax(scores)
	# 3. 挑目标国（按 country）
	var target: String = _pick_target(action, ctx)
	# 4. 判断本轮是否为最终轮 → settle_hint
	var round_num: int = int(ctx.get("round", 1))
	var settle_hint: String = ""
	if round_num >= 2:
		settle_hint = _decide_settle(action, ctx)
	# v7.3.10：R2 summon 时预生成 proposed_action（君主召见时开场问题）
	var proposed_action: String = ""
	if round_num >= 2 and settle_hint == "summon":
		proposed_action = _gen_proposed_action(action, target, ctx)
	# 5. 记录到记忆
	var out := {
		"actor": country,
		"target_country": target,
		"action_type": action,
		"round": round_num,
		"reason": _gen_reason(action, target, ctx),
		"narrative": _gen_narrative(action, target),
		"expected_settle": settle_hint,
		"proposed_action": proposed_action,
		"confidence": _confidence(action, scores)
	}
	memory.push_back({
		"round": round_num,
		"action": action,
		"target": target,
		"player_stance": String(ctx.get("player_stance", ""))
	})
	if memory.size() > MEMORY_MAX:
		memory.pop_front()
	return out

# v7.3.5 反应轮：面谈后其他君主的性格化响应（群体智能）
func pick_reaction_async(ctx: Dictionary, callback: Callable) -> void:
	var llm = Engine.get_main_loop().root.get_node_or_null("LLMClient")
	if llm == null or not llm.is_ready():
		if callback.is_valid():
			var mock_out = pick_action(ctx)
			mock_out["source"] = "mock:no_llm"
			callback.call(mock_out)
		return
	var prompt: String = _build_reaction_prompt(ctx)
	llm.request(prompt, {"model": "deepseek-v4-flash", "timeout_sec": 10.0, "temperature": 0.85, "response_json": true},
		func(parsed: Variant, err: String):
			if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
				if callback.is_valid():
					var mock_out = pick_action(ctx)
					mock_out["source"] = "mock:%s" % err
					callback.call(mock_out)
				return
			var out = _validate_llm_action(parsed, ctx)
			if out.is_empty():
				if callback.is_valid():
					var mock_out = pick_action(ctx)
					mock_out["source"] = "mock:invalid_schema"
					callback.call(mock_out)
				return
			out["source"] = "llm-react"
			memory.push_back({
				"round": int(ctx.get("round", 3)),
				"action": String(out.get("action_type", "")),
				"target": String(out.get("target_country", "")),
				"player_stance": String(ctx.get("player_stance", "")),
				"is_reaction": true
			})
			if memory.size() > MEMORY_MAX:
				memory.pop_front()
			if callback.is_valid():
				callback.call(out)
	)

func _build_reaction_prompt(ctx: Dictionary) -> String:
	var wa: Dictionary = ctx.get("world_attrs", {})
	var rc: Dictionary = ctx.get("reaction_context", {})
	var audience_country: String = String(rc.get("audience_country", ""))
	var verdict: String = String(rc.get("verdict", ""))
	var player_summary: String = String(rc.get("player_summary", ""))

	var role_defs = {
		"qin": "秦王嬴稷，雄猜之主。核心恐惧=六国合纵。",
		"zhao": "赵王赵何，犹疑之主。怕独战怕激秦。",
		"qi": "齐王田地，渔利之主。谁给的多帮谁。"
	}
	var actions_defs = {
		"qin": "pressure|alienate|lure|prepare",
		"zhao": "seek_alliance|prepare|probe|observation",
		"qi": "observation|wait_price|hijack|self_protect"
	}
	var recent_lines: Array = []
	var hist: Array = ctx.get("opponents_history", [])
	for i in range(max(0, hist.size() - 5), hist.size()):
		var h: Dictionary = hist[i]
		var actor_c: String = String(h.get("actor", ""))
		if actor_c == country or actor_c == "":
			continue
		recent_lines.append("- %s：%s" % [_country_name(actor_c), String(h.get("narrative", ""))])

	var lines: Array = [
		"# 世界铁律：只有秦、赵、齐三国。target_country 只能是 qin/zhao/qi。",
		"",
		"# 你是",
		role_defs.get(country, ""),
		"",
		"# 刚发生的事",
		"纵横家面见%s，表态：%s（%s）" % [_country_name(audience_country), player_summary, verdict],
		"你听说了这件事。",
		"",
		"# 最近他人动向",
		("\n".join(recent_lines) if recent_lines.size() > 0 else "（暂无）"),
		"",
		"# 既往盟约与恩怨（跨回合）",
		("\n".join(ctx.get("ledger_lines", [])) if (ctx.get("ledger_lines", []) as Array).size() > 0 else "（尚无）"),
		"",
		"# 当前天下大势",
		_world_line(wa),
		"",
		"# 你可用的动作",
		actions_defs.get(country, ""),
		"",
		"# 决策规则",
		"基于你的性格，对刚发生的面谈事件做出**一个**回应动作。reason 必须以\"基于我...\"开头。",
		"",
		"# 输出（严格 JSON）",
		"{",
		'  "target_country": "qin"|"zhao"|"qi",',
		'  "action_type": <上表 action id>,',
		'  "reason": "≤ 40 字，以「基于我...」开头",',
		'  "narrative": "≤ 40 字第三人称描述",',
		'  "settle_hint": "summon"|"decided",',
		'  "confidence": 1-10',
		"}"
	]
	return "\n".join(lines)

# LLM 接入点：async 调用 DeepSeek，失败/超时/性格偏离回退 mock
func pick_action_async(ctx: Dictionary, callback: Callable) -> void:
	var llm = Engine.get_main_loop().root.get_node_or_null("LLMClient")
	if llm == null or not llm.is_ready() or _force_mock_this_run:
		if callback.is_valid():
			var mock_out = pick_action(ctx)
			mock_out["source"] = "mock:persona_drift" if _force_mock_this_run else "mock:no_llm"
			callback.call(mock_out)
		return
	var prompt: String = _build_prompt(ctx)
	llm.request(prompt, {"model": "deepseek-v4-flash", "timeout_sec": 5.0, "temperature": 0.8, "response_json": true},
		func(parsed: Variant, err: String):
			if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
				if callback.is_valid():
					var mock_out = pick_action(ctx)
					mock_out["source"] = "mock:%s" % err
					callback.call(mock_out)
				return
			var out = _validate_llm_action(parsed, ctx)
			if out.is_empty():
				if callback.is_valid():
					var mock_out = pick_action(ctx)
					mock_out["source"] = "mock:invalid_schema"
					callback.call(mock_out)
				return
			if _is_persona_drift(out, ctx):
				_persona_drift_count += 1
				if _persona_drift_count >= 2:
					_force_mock_this_run = true
				if callback.is_valid():
					var mock_out = pick_action(ctx)
					mock_out["source"] = "mock:drift(%d)" % _persona_drift_count
					callback.call(mock_out)
				return
			_persona_drift_count = 0
			out["source"] = "llm"
			memory.push_back({
				"round": int(ctx.get("round", 1)),
				"action": String(out.get("action_type", "")),
				"target": String(out.get("target_country", "")),
				"player_stance": String(ctx.get("player_stance", ""))
			})
			if memory.size() > MEMORY_MAX:
				memory.pop_front()
			if callback.is_valid():
				callback.call(out)
	)

# 回合间重置：只清性格偏离计数，记忆跨回合保留
func reset_round_state() -> void:
	_persona_drift_count = 0
	_force_mock_this_run = false

# 整局重置：连记忆一起清
func reset_run_state() -> void:
	reset_round_state()
	memory.clear()
	_alliance_refusals = 0

# 性格偏离检测：LLM 输出的动作是否符合该君主的性格底线
func _is_persona_drift(out: Dictionary, ctx: Dictionary) -> bool:
	var action: String = String(out.get("action_type", ""))
	var wa: Dictionary = ctx.get("world_attrs", {})
	var meng: int = int(wa.get("liu_guo_meng", 0))
	var luan: int = int(wa.get("tian_xia_fenluan", 0))
	match country:
		"qin":
			# 合纵成势（六国之盟 ≥ 60）时秦若不出手破局 → 偏离
			if meng >= 60 and not (action in ["alienate", "pressure", "lure"]):
				return true
		"zhao":
			# 赵不该主动施压/离间（不在 zhao actions 里，validate 已挡；此处保守）
			pass
		"qi":
			# 天下未乱（天下纷乱 < 50）时第 1 轮就趁火打劫 → 偏离
			var round_num: int = int(ctx.get("round", 1))
			if round_num == 1 and action == "hijack" and luan < 50:
				return true
	return false

# === LLM prompt 构建（对齐 v7.3 §11b 8 模块结构，紧凑版）===
func _build_prompt(ctx: Dictionary) -> String:
	var wa: Dictionary = ctx.get("world_attrs", {})
	var round_num: int = int(ctx.get("round", 1))
	var stance: String = String(ctx.get("player_stance", ""))
	var event_text: String = String(ctx.get("key_event_text", ""))

	var role_defs = {
		"qin": "秦王嬴稷，雄猜之主：果决多疑霸道。核心恐惧=六国合纵。行为铁律：一旦察觉合纵成势（六国之盟 ≥ 55），你必须优先破之（遣使离间 alienate）；决策 confidence 常 ≥ 7；面对犹豫方优先施压。兵锋不拘于赵——赵齐皆东出之障，弱者先取；对观望的齐亦须常施威慑（施压/威胁），使其不敢轻言援赵。",
		"zhao": "赵王赵何，犹疑之主：谨慎易被说服，怕独战怕激秦。行为铁律：**以当前战况自断**——你若为守方立刻 seek_alliance 搬援；秦攻齐时掂量唇亡齿寒（齐亡则赵独面秦锋），勿只顾观望；默认动作偏 seek_alliance/observation；第 1 轮多试探/求盟；第 2 轮若仍无定见→ settle_hint=summon（等纵横家给指路）；confidence 常 ≤ 6。",
		"qi": "齐王田地，渔利之主：精明观望，谁给的多帮谁——但存亡高于渔利。行为铁律：**以当前战况国力自断，不守死套路**——你若为战争守方 → 立刻 seek_alliance 搬援，勿再观望待价；秦攻他国时掂量唇亡齿寒；太平时默认 observation，案头有实利出价才 wait_price；天下大乱（天下纷乱 ≥ 55）才 hijack；第 2 轮多 settle_hint=decided（齐王自决），唯战危难决时 summon。"
	}
	var actions_defs = {
		"qin": "pressure(军事施压 舆论造势)|alienate(遣使离间 拆盟)|lure(连横利诱=真交易：许城2座，易对方立中立之约)|prepare(募兵整训 兵+6万)|declare_war(兴兵伐国 需兵力显著占优且目标无军事同盟；三点位行军，中途可被斡旋)",
		"zhao": "seek_alliance(请结军事同盟=真谈判，对方应允即歃血为盟并驰援；战时求盟可解围)|prepare(募兵整训 兵+6万)|probe(遣使试探)|observation(骑墙观望)",
		"qi": "observation(观望渔利)|wait_price(待价而沽=应下案头实利出价，真收城并立约；太平时空口盟约不受)|hijack(趁火打劫=对兵力<40万之弱国真宣战，需己兵≥50万)|self_protect(闭门自保)|seek_alliance(请结军事同盟=真谈判，兵祸及身时的救亡之策，对方应允即歃血为盟并驰援)"
	}
	var advisor_defs = {
		"qin": "近臣：张仪（连横推手，选 lure 时他说'齐王贪利，许以三城可定'——加 confidence）；魏冉（主战，选 pressure 时说'战机稍纵即逝'——加 confidence）",
		"zhao": "近臣：平原君（主合纵，选 seek_alliance 时说'合纵抗秦是赵国唯一出路'）；廉颇（主战不信秦，选 prepare 时说'廉颇老矣尚能一战'）",
		"qi": "近臣：孟尝君（谨慎渔利，动手时低声说'动则必败，观望方为上策'——observation 加 confidence）"
	}

	var stance_hint = "无明显立场"
	match stance:
		"hezong": stance_hint = "推合纵抗秦（此立场对秦是威胁——秦应警觉；对赵是鼓舞——赵应求盟；对齐是压力——齐应观望自保）"
		"qin": stance_hint = "推亲秦连横（此立场对秦是助力——秦可加码利诱；对赵是恐惧——赵应备战；对齐是诱因——齐可待价）"
		"neutral": stance_hint = "中立传信（不偏帮任何一方）"

	var mem_lines: Array = []
	for i in range(max(0, memory.size() - 2), memory.size()):
		var m: Dictionary = memory[i]
		mem_lines.append("- 你曾：%s → %s（当时玩家立场=%s）" % [
			String(m.get("action", "")), String(m.get("target", "")), String(m.get("player_stance", ""))
		])
	var mem_str: String = "\n".join(mem_lines) if mem_lines.size() > 0 else "（无既往动作）"

	# 他国最近动向（来自本回合博弈记录，不含自己；朝议另有专段，此处滤掉）
	var opp_lines: Array = []
	var hist: Array = ctx.get("opponents_history", [])
	for h in hist:
		var hd: Dictionary = h
		var actor_c: String = String(hd.get("actor", ""))
		if actor_c == country or actor_c == "":
			continue
		if String(hd.get("action_type", "")) == "chat":
			continue
		var nar: String = String(hd.get("narrative", ""))
		if nar == "":
			continue
		opp_lines.append("- %s：%s" % [_country_name(actor_c), nar])
	if opp_lines.size() > 4:
		opp_lines = opp_lines.slice(opp_lines.size() - 4)
	var opp_str: String = "\n".join(opp_lines) if opp_lines.size() > 0 else "（尚无他国动向）"

	var chat_lines: Array = ctx.get("chat_lines", [])
	var chat_str: String = "\n".join(chat_lines) if chat_lines.size() > 0 else "（尚无朝议）"
	var ledger_lines: Array = ctx.get("ledger_lines", [])
	var ledger_str: String = "\n".join(ledger_lines) if ledger_lines.size() > 0 else "（尚无盟约恩怨）"

	var event_line: String = event_text if event_text != "" else "（本回合无关键事件描述）"
	var implication: String = _event_implication(event_text, ctx)

	var lines: Array = [
		"# 世界铁律（不可违反）",
		"这个世界只有三个国家：秦、赵、齐。**不存在**韩、魏、楚、燕等其他国家。target_country 只能是 qin/zhao/qi，narrative/reason 中不许提及其他国名。",
		"打不赢的仗不打：宣战前先比兵力与盟约；正被攻打时优先求盟自固。",
		"**领土铁案**：下方'列国国力'即领土实录——已割/已占之地不可否认，不得声称未得已得之地、未失已失之地。**出处不可颠倒**：'受X割让'=对方主动所予（当念其惠），'夺X地'=兵锋所得，二者不可混称。",
		"**割地岁限**：每国每回合至多割 3 城，勿许空头支票。",
		"",
		"# 你是谁",
		role_defs.get(country, ""),
		"",
		"# 本回合关键事件",
		event_line,
		"# 该事件对你的暗示",
		implication,
		"你的本轮决策必须围绕此事件展开——不要选与此事件无关的动作。",
		"",
		"# 当前天下大势（第 %d 轮）" % round_num,
		_world_line(wa),
		"# 列国国力（城池/兵力）",
		_national_line(ctx),
		"# 当前战事",
		_war_line(ctx),
		"纵横家立场：%s" % stance_hint,
		"",
		"# 他国最近动向",
		opp_str,
		"",
		"# 朝议近闻（你可见的）",
		chat_str,
		"",
		"# 既往盟约与恩怨（跨回合）",
		ledger_str,
		"",
		"# 你自己的既往动作",
		mem_str,
		"",
		"# 你可用的动作",
		actions_defs.get(country, ""),
		advisor_defs.get(country, ""),
		"",
		"# 决策规则",
		"- 严格遵循性格铁律。第 1 轮：探/求盟/观望；第 2 轮：做终局决策。",
		"- **回应而非自说自话**：你的 reason 应引用他国动向/朝议/盟约中的至少一条事实（如'赵齐已成约''秦刚离间我'）。",
		"- 你既往若已用某动作而局势未变，换目标或换手段，勿原样重复。",
		"- 若第 2 轮仍犹豫（需纵横家建议）→ settle_hint=summon；否则 decided。",
		"- **v7.3.10**：第 2 轮若 settle_hint=summon，必须同时给出 proposed_action（你想问纵横家的问题/提议，≤ 40 字文言，第一人称\"寡人/孤\"）。这是召见时君主开场就提出的问题，玩家来了直接听到。",
		"- reason 必须以'基于我 [性格]……'开头，明确引用你的性格特征。",
		"",
		"# 输出（严格 JSON，无多余文字）：",
		"{",
		'  "target_country": "qin"|"zhao"|"qi",  // 你要针对的对手（不能是你自己）',
		'  "action_type": <上表 action id>,',
		'  "reason": "≤ 40 字内心独白，必须以「基于我...」开头",',
		'  "narrative": "≤ 40 字第三人称描述（用于事件流）",',
		'  "settle_hint": "summon"|"decided",  // 仅第 2 轮有意义',
		'  "proposed_action": "≤40字文言问题/提议（仅第 2 轮 settle_hint=summon 时必填，否则留空）",',
		'  "confidence": 1-10',
		"}"
	]
	return "\n".join(lines)

func _event_implication(event_text: String, ctx: Dictionary) -> String:
	var wa: Dictionary = ctx.get("world_attrs", {})
	var meng: int = int(wa.get("liu_guo_meng", 0))
	var baye: int = int(wa.get("qin_baye", 0))
	if event_text.find("合纵") >= 0 and event_text.find("签字") >= 0:
		return "六国签字合纵——若你是秦，必须离间/施压破局；若你是赵，此时最需求盟固盟；若你是齐，此时是待价而沽的最佳时机。"
	if event_text.find("秦拔宜阳") >= 0 or event_text.find("秦军推进") >= 0 or event_text.find("秦军压境") >= 0:
		return "秦军已动——此时局面对秦最有利。若你是秦，宜乘胜施压；若你是赵，宜求援备战；若你是齐，宜自保或待价。"
	if event_text.find("张仪") >= 0 or event_text.find("连横") >= 0:
		return "秦在利诱他国——若你是秦，此计当推进；若你是赵，警觉齐被拉拢；若你是齐，此时秦价高，可待价。"
	if event_text.find("函谷关") >= 0 or event_text.find("决战") >= 0:
		return "决战时刻——各方立场应最为鲜明。犹豫和观望的成本最高。"
	if meng >= 55:
		return "六国之盟已成气候（%d），合纵迹象明显——若你是秦，必须优先破之。" % meng
	if baye >= 70:
		return "秦之霸业已盛（%d）——若你是赵齐，压力空前；若你是秦，可持续施压。" % baye
	return "此事件为回合背景，你的决策应契合当前性格与局势。"

func _round_to_month(rn: int) -> int:
	return clampi(rn * 2 - 1, 1, 12)

# 校验 LLM 输出的 action 字段合法
func _validate_llm_action(parsed: Dictionary, ctx: Dictionary) -> Dictionary:
	# 用 str() 而非 String() —— LLM 可能返回非标量类型（StringName/null/Dictionary），
	# String() 构造器对部分 Variant 类型会触发 "Invalid call 'String' constructor"
	var target: String = str(parsed.get("target_country", ""))
	var atype: String = str(parsed.get("action_type", ""))
	var valid_actions: Array = persona.get("actions", [])
	if not (target in ["qin", "zhao", "qi"]) or target == country:
		return {}
	if not (atype in valid_actions):
		return {}
	var round_num: int = int(ctx.get("round", 1))
	var settle_hint: String = str(parsed.get("settle_hint", "summon"))
	if not (settle_hint in ["summon", "decided"]):
		settle_hint = "summon"
	return {
		"actor": country,
		"target_country": target,
		"action_type": atype,
		"round": round_num,
		"reason": str(parsed.get("reason", "")),
		"narrative": str(parsed.get("narrative", _gen_narrative(atype, target))),
		"expected_settle": settle_hint if round_num >= 2 else "",
		"proposed_action": str(parsed.get("proposed_action", "")),  # v7.3.10：召见时预生成的问题
		"confidence": clampi(int(parsed.get("confidence", 5)), 1, 10)
	}

# === 打分核心 ===
func _score_actions(ctx: Dictionary) -> Dictionary:
	var scores: Dictionary = {}
	var base: Dictionary = persona.get("base", {})
	for a in persona.get("actions", []):
		var s: float = float(base.get(a, 1.0))
		s *= float(advisor_weights.get(a, 1.0))
		s += _situational_bonus(a, ctx)
		s = max(s, 0.05)
		scores[a] = s
	return scores

# 情境加成——各君主对世界大势的差异化反应
func _situational_bonus(action: String, ctx: Dictionary) -> float:
	var wa: Dictionary = ctx.get("world_attrs", {})
	var meng: int = int(wa.get("liu_guo_meng", 0))
	var baye: int = int(wa.get("qin_baye", 0))
	var luan: int = int(wa.get("tian_xia_fenluan", 0))
	var stance: String = String(ctx.get("player_stance", ""))
	var round_num: int = int(ctx.get("round", 1))
	var pacts: Dictionary = ctx.get("pacts", {})
	var war: Dictionary = ctx.get("war", {})
	var nat: Dictionary = ctx.get("national", {})

	# 战时通用偏置：守方全力求援自固，攻方稳住后方，第三方视秦锋自断
	if not war.is_empty():
		var role_def: bool = country == String(war.get("defender", ""))
		var role_att: bool = country == String(war.get("attacker", ""))
		if role_def and action == "seek_alliance":
			return 1.8
		if role_def and action == "prepare":
			return 0.8
		if role_att and action == "prepare":
			return 0.6
		# 唇亡齿寒：秦兵既动，旁观的第三方也该掂量抱团（不等玩家来劝）
		if not role_def and not role_att and action == "seek_alliance" \
				and String(war.get("attacker", "")) == "qin":
			return 0.9

	match country:
		"qin":
			# 秦：兵力优势 + 敌无强援 → 兴兵
			if action == "declare_war":
				if not war.is_empty():
					return -2.0
				if bool(ctx.get("mil_alliance_zhao_qi", false)):
					return -1.0
				var myt: int = int((nat.get("qin", {}) as Dictionary).get("troops", 0))
				var weakest_t: int = 999
				for cc in ["zhao", "qi"]:
					weakest_t = mini(weakest_t, int((nat.get(cc, {}) as Dictionary).get("troops", 100)))
				if myt >= int(weakest_t * 1.6):
					return 2.4 if round_num >= 2 else 0.8  # 压倒之势，鲸吞之机
				if myt >= int(weakest_t * 1.25):
					return 1.6 if round_num >= 2 else 0.5
				return -1.0
			# 秦：警觉合纵 → 优先离间
			if action == "alienate":
				if bool(pacts.get("zhao_qi", false)):
					return 1.6  # 赵齐已成约 → 必破其盟
				if meng >= 60:
					return 1.5  # 合纵成势 → 必破
				if meng >= 50:
					return 0.8
			if action == "lure":
				# 真交易：要有城可许（城≥22），且提议槽空闲
				if int((nat.get("qin", {}) as Dictionary).get("cities", 0)) < 22:
					return -1.5
				if bool(ctx.get("pending_busy", false)):
					return -0.6
				if luan >= 45:
					return 0.8
				if stance == "qin":
					return 0.6  # 玩家推亲秦时秦更愿花钱
			if action == "pressure":
				# 玩家推合纵或霸业已盛 → 直接压
				if stance == "hezong":
					return 0.6
				if baye >= 65:
					return 0.5
			if action == "prepare":
				# 玩家推合纵 + 秦第一轮 → 更倾向蓄力
				if round_num == 1 and stance == "hezong":
					return 0.3
		"zhao":
			# 赵：秦势大 + 独战 → 求盟或备战
			if action == "seek_alliance":
				if bool(ctx.get("mil_alliance_zhao_qi", false)):
					return -0.8  # 已有同盟，勿重复求
				if bool(ctx.get("pending_busy", false)):
					return -0.4
				if baye >= 60:
					return 0.8
				if stance == "hezong":
					return 0.6
			if action == "prepare":
				if bool(pacts.get("qin_qi", false)):
					return 0.8  # 齐已倒向秦 → 赵只能自固
				if baye >= 70:
					return 0.8
			if action == "observation":
				if stance == "qin":
					return 0.4  # 玩家推亲秦 → 赵不敢乱动
			if action == "probe":
				if round_num == 1:
					return 0.4  # 第一轮偏向试探
		"qi":
			# 齐：默认观望，被利诱转 wait_price
			var _lured_by_qin: bool = false
			for m in ctx.get("opponents_history", []):
				var md: Dictionary = m
				if String(md.get("actor", "")) == "qin" and String(md.get("action_type", "")) == "lure" and String(md.get("target_country", "")) == "qi":
					_lured_by_qin = true
					break
			if action == "wait_price":
				if bool(ctx.get("pending_to_me", false)):
					return 2.0  # 有价挂在案头 → 立刻应价
				if _lured_by_qin:
					return 1.8  # 强信号：秦刚出价，齐应待价
				if bool(pacts.get("qin_qi", false)):
					return 0.6  # 与秦有约在先 → 继续抬价
			if action == "observation":
				if _lured_by_qin:
					return -1.2  # 有出价方 → 观望反被动
			if action == "hijack":
				# 真宣战门槛：己兵 ≥50 且 有兵<40 之弱国
				var myt2: int = int((nat.get("qi", {}) as Dictionary).get("troops", 0))
				var weak: bool = false
				for cc in ["qin", "zhao"]:
					if int((nat.get(cc, {}) as Dictionary).get("troops", 100)) < 40:
						weak = true
				if myt2 >= 50 and weak and war.is_empty():
					return 1.5
				return -1.0
			if action == "self_protect":
				if baye >= 70:
					return 0.5
	return 0.0

func _argmax(d: Dictionary) -> String:
	var best_key: String = ""
	var best_val: float = -INF
	for k in d.keys():
		var v: float = float(d[k])
		if v > best_val:
			best_val = v
			best_key = String(k)
	return best_key

func _pick_target(action: String, ctx: Dictionary) -> String:
	var others: Array = []
	for c in ["qin", "zhao", "qi"]:
		if c != country:
			others.append(c)
	if others.is_empty():
		return ""
	match action:
		"declare_war":
			# 兴兵挑最弱者（兵力最少的非己方国）——各线路战争均可能发生
			var nat_w: Dictionary = ctx.get("national", {})
			var weakest: String = String(others[0])
			var wt: int = 999
			for c in others:
				var t: int = int((nat_w.get(c, {}) as Dictionary).get("troops", 999))
				if t < wt:
					wt = t
					weakest = String(c)
			return weakest
		"pressure":
			# 秦兵威两面摇：六成压赵、四成慑齐（齐须始终感到函谷之师的存在）
			if country == "qin" and "zhao" in others and "qi" in others:
				return "zhao" if randf() < 0.6 else "qi"
			return "zhao" if "zhao" in others else String(others[0])
		"alienate":
			# 离间赵齐之盟：随机挑一国下手
			return String(others[randi() % others.size()])
		"lure":
			# 张仪之策：战时利诱第三方使其中立（稳住后方，远交近攻）；平时利诱观望的齐
			var wb2: Dictionary = ctx.get("war", {})
			if not wb2.is_empty() and String(wb2.get("attacker", "")) == country:
				var def_c: String = String(wb2.get("defender", ""))
				for c2 in others:
					if String(c2) != def_c:
						return String(c2)
			return "qi" if "qi" in others else String(others[0])
		"seek_alliance":
			# 求盟对象＝赵齐互指（抗秦轴线）
			if country == "qi":
				return "zhao" if "zhao" in others else String(others[0])
			return "qi" if "qi" in others else String(others[0])
		"probe":
			# 赵试探：秦（威胁最大）
			return "qin" if "qin" in others else String(others[0])
		"wait_price":
			# 齐待价：跟出价方（谁最近对齐 lure 过）；无信号则秦
			for m in ctx.get("opponents_history", []):
				var md: Dictionary = m
				if String(md.get("action_type", "")) == "lure" and String(md.get("target_country", "")) == country:
					return String(md.get("actor", ""))
			return "qin" if "qin" in others else String(others[0])
		"hijack":
			# 趁火打劫：挑被秦消耗的赵
			return "zhao" if "zhao" in others else String(others[0])
		_:
			# prepare/observation/self_protect: 目标 = 感知威胁最大的国
			if country == "qin":
				return "zhao" if "zhao" in others else String(others[0])
			return "qin" if "qin" in others else String(others[0])

# 判断第 2 轮结束后进入 summon 还是 decided
func _decide_settle(action: String, ctx: Dictionary) -> String:
	# 犹豫型动作 → summon（等纵横家给建议）
	# 明确行动型 → decided
	var summon_actions := ["probe", "observation", "seek_alliance"]
	var decided_actions := ["pressure", "alienate", "lure", "prepare", "hijack", "self_protect", "wait_price", "declare_war"]
	if action in summon_actions:
		return "summon"
	if action in decided_actions:
		# 例外：齐 wait_price 在玩家推合纵时改为 summon（"给孤指条路"）
		var stance: String = String(ctx.get("player_stance", ""))
		if country == "qi" and action == "wait_price" and stance == "hezong":
			return "summon"
		return "decided"
	return "summon"

func _confidence(action: String, scores: Dictionary) -> int:
	var s: float = float(scores.get(action, 1.0))
	return clampi(int(round(s * 3.0)), 1, 10)

# === 台词生成 ===
# v7.3.10：mock 路径预生成 proposed_action（君主召见时开场问题）
# R2 settle_hint=summon 时调用，存到 action.proposed_action
# dialogue.gd setup 优先读此字段，若为空才自己调 LLM 想
func _gen_proposed_action(action: String, target: String, _ctx: Dictionary) -> String:
	var tname: String = _country_name(target)
	var pools: Dictionary = {
		"pressure": [
			"寡人欲兴兵伐%s，足下以为可否？",
			"兵临%s境，胜负几何？先生教我。",
			"寡人欲以武力慑%s，当先图何处？"
		],
		"alienate": [
			"寡人欲遣使离间%s之盟，先生有何良策？",
			"%s与盟邦信甚坚，寡人欲破之，何以施之？",
			"离间之计已成竹在胸，先生以为可乎？"
		],
		"lure": [
			"寡人欲以利诱%s归附，许以何物为当？",
			"连横之议，先生以为%s可受否？",
			"寡人欲许%s以地，足下以为可行否？"
		],
		"prepare": [
			"寡人欲闭关备战，蓄势待发，先生以为何如？",
			"备战之道，当以何为先？先生教寡人。",
			"寡人欲秣马厉兵，足下有何高见？"
		],
		"seek_alliance": [
			"寡人欲联%s为盟，共抗强秦，先生以为可行否？",
			"求盟于%s，先生以为辞当何如？",
			"寡人欲遣使赴%s，先生以为可否？"
		],
		"probe": [
			"寡人欲遣使探%s虚实，先生以为可否？",
			"%s之虚实未明，寡人欲遣间，何如？",
			"寡人欲知%s之谋，先生有何良策？"
		],
		"observation": [
			"天下纷扰，寡人欲静观其变，先生以为何如？",
			"寡人欲按兵不动，先生以为可否？",
			"观望之策，先生以为当守至何时？"
		],
		"wait_price": [
			"秦赵皆求寡人，寡人欲待价而沽，先生以为何如？",
			"寡人欲观秦赵之争而后动，先生以为可否？",
			"待价之策，先生以为当取何方？"
		],
		"hijack": [
			"%s近衰，寡人欲趁火打劫，先生以为可否？",
			"寡人欲取%s之地以自强，先生以为何如？",
			"%s之衰，寡人欲乘之，先生有何良策？"
		],
		"self_protect": [
			"寡人欲闭门自保，不预外事，先生以为何如？",
			"自保之策，先生以为当以何为重？",
			"寡人欲谢绝外使，先生以为可否？"
		]
	}
	var arr: Array = pools.get(action, ["寡人欲问先生，天下大势当如何处之？"])
	var picked: String = String(arr[randi() % arr.size()])
	# 只对含 %s 的句子格式化（self_protect/prepare/observation 等不含 %s）
	if picked.find("%s") >= 0:
		return picked % tname
	return picked

# 多句池：每个 action 4 句，按 country 自适应（秦/赵/齐 措辞不同）
# 随机选一句，避免三国在不同轮次重复同一句叙事
func _gen_narrative(action: String, target: String) -> String:
	var name: String = _country_name(country)
	var tname: String = _country_name(target)
	var pools: Dictionary = {
		"declare_war": [
			"%s王升殿点将，大军拔营——兵锋直指%s！" % [name, tname],
			"%s下令兴师伐%s，粮秣辎重络绎于道，战端已开。" % [name, tname],
			"%s誓师出征，剑指%s城下——列国为之屏息。" % [name, tname],
		],
		"pressure": [
			"%s边境突燃烽燧，铁骑滚滚压向%s，函谷关外战鼓频催。" % [name, tname],
			"%s遣白起之流整军东出，%s边吏告急，求援之书日夜不绝。" % [name, tname],
			"%s陈兵十万于河西，旌旗蔽日，%s朝堂为之震悚。" % [name, tname],
			"%s使人扬言伐%s，大军未发而威已至，邯郸城中彻夜不眠。" % [name, tname],
		],
		"alienate": [
			"%s遣纵横之士潜入%s，以黄金珠玉赂其近臣，欲拆其盟约。" % [name, tname],
			"%s使反间于%s，散布流言，称其将与秦私盟，致同盟离心。" % [name, tname],
			"%s密使持重金游说%s重臣，许以封邑，欲令其君臣相疑。" % [name, tname],
			"%s遣人于%s朝堂散布谗言，称其相国暗通敌国，朝议为之纷乱。" % [name, tname],
		],
		"lure": [
			"%s使人赍连横之书入%s，许以河西之地三百里，欲使其背合纵之约。" % [name, tname],
			"%s遣使遗%s璧玉十双、黄金千镒，言：与秦结好，世享其利。" % [name, tname],
			"%s以商於之地六百里相诱，邀%s会盟，实欲离其与赵齐之交。" % [name, tname],
			"%s许%s以太子为质，约结婚姻，欲以恩结而分其合纵之势。" % [name, tname],
		],
		"prepare": [
			"%s闭关息民，广积粟帛，命大将治兵于上党，修车乘、缮甲胄。" % name,
			"%s下令征发丁壮，凿太行险道，储粮于仓廪，以为持久之计。" % name,
			"%s使工师督造强弩万张、战车千乘，士卒日操夜练，军容甚整。" % name,
			"%s遣人入山采铁，冶铸兵刃，又募游士习击刺，以待天下有变。" % name,
		],
		"seek_alliance": [
			"%s遣使奉束帛加璧入%s，泣诉强秦之逼，愿结唇齿之好，共御西邻。" % [name, tname],
			"%s使平原君之属入%s，约以婚姻，歃血为盟，誓同进退，共抗暴秦。" % [name, tname],
			"%s遣使持国书入%s，言：秦虎狼也，独力难支，愿修合纵之好。" % [name, tname],
			"%s使人致书%s，愿割边城以盟，约同出兵救难，永为兄弟之邦。" % [name, tname],
		],
		"probe": [
			"%s遣舌辩之士入%s，假以商贾之名，密探其国虚实与朝议动向。" % [name, tname],
			"%s使细作潜入%s市井，收买门客，刺其君之喜怒与将帅之名。" % [name, tname],
			"%s遣使入%s称贺，实观其仓廪士卒，归而具陈虚实，以定后图。" % [name, tname],
			"%s使人于%s边境佯作游猎，徐察其烽燧守备与民情向背。" % [name, tname],
		],
		"observation": [
			"%s按甲不出，筑台以望四方，曰：天下纷扰，且观孰为先犯者。" % name,
			"%s令边吏谨守疆界，勿妄动，朝议以为：两虎相斗，姑待其毙。" % name,
			"%s闭门谢客，唯日览边报，群臣莫测其意，皆以为持重之策。" % name,
			"%s按兵不动，命人日录列国动静，藏于密室，以待可乘之机。" % name,
		],
		"wait_price": [
			"%s端坐朝堂，笑谓群臣：秦赵相争，吾且观其价，价高者得齐助。" % name,
			"%s使人数秦赵之使往来，皆待以礼而不许，曰：未至其时也。" % name,
			"%s令边吏稳守，暗使人于秦赵之间通好意，两受其赂而不结其约。" % name,
			"%s佯作不知天下之事，实阴使人周旋于秦赵，待价而沽于两强之间。" % name,
		],
		"hijack": [
			"%s见%s新败于秦，国力凋敝，遂发兵袭其边境，夺城数座而归。" % [name, tname],
			"%s乘%s主力在外，遣轻骑袭其后方，掠其牛马子女以万计。" % [name, tname],
			"%s闻%s国内有乱，即刻举兵伐之，取边邑三城，以张其势。" % [name, tname],
			"%s趁%s与第三国鏖战之际，突入其境，割其膏腴之地以为己有。" % [name, tname],
		],
		"self_protect": [
			"%s下令闭关绝使，严守边境，凡外来客旅皆验符盘查，朝议唯求自安。" % name,
			"%s筑长城于北疆，修关塞于要冲，谢绝列国之使，唯务保境安民。" % name,
			"%s遣使告于四方：本邦无争霸之心，唯守先王之土，愿各安其境。" % name,
			"%s令边吏坚壁清野，禁民与外商往来，国中唯以休养生息为务。" % name,
		],
	}
	var arr: Array = pools.get(action, ["%s未有动作。" % name])
	if arr.is_empty():
		arr = ["%s未有动作。" % name]
	return String(arr[randi() % arr.size()])

func _gen_reason(action: String, target: String, ctx: Dictionary) -> String:
	var stance: String = String(ctx.get("player_stance", ""))
	var stance_hint: String = ""
	if stance == "hezong":
		stance_hint = "（察觉纵横家推合纵）"
	elif stance == "qin":
		stance_hint = "（察觉纵横家推亲秦）"
	match action:
		"declare_war": return "兵力占优而%s无援，此天赐战机%s" % [_country_name(target), stance_hint]
		"alienate": return "合纵迹象已显，先破%s之盟%s" % [_country_name(target), stance_hint]
		"lure": return "%s可以利诱，胜过刀兵%s" % [_country_name(target), stance_hint]
		"pressure": return "%s可欺，正当施压%s" % [_country_name(target), stance_hint]
		"seek_alliance": return "独抗秦必败，联%s可保%s" % [_country_name(target), stance_hint]
		"prepare": return "外无援则内自强%s" % stance_hint
		"observation": return "静观其变，不为他人做嫁衣%s" % stance_hint
		"wait_price": return "两方求我，不妨再待其价%s" % stance_hint
		_: return "此时此势，宜如此%s" % stance_hint

static func _country_name(c: String) -> String:
	match c:
		"qin": return "秦"
		"zhao": return "赵"
		"qi": return "齐"
		_: return c

static func _world_line(wa: Dictionary) -> String:
	return "秦之霸业 %d / 六国之盟 %d / 天下纷乱 %d" % [
		int(wa.get("qin_baye", 0)), int(wa.get("liu_guo_meng", 0)), int(wa.get("tian_xia_fenluan", 0))
	]

static func _national_line(ctx: Dictionary) -> String:
	# 优先领土实录（含占领构成，铁案）；无则由 national 兜底拼装
	var out: String = String(ctx.get("territory_line", ""))
	if out == "":
		var nat: Dictionary = ctx.get("national", {})
		if nat.is_empty():
			return "（未知）"
		var parts: Array = []
		for c in ["qin", "zhao", "qi"]:
			var n: Dictionary = nat.get(c, {})
			parts.append("%s 城%d 兵%d万" % [_country_name(c), int(n.get("cities", 0)), int(n.get("troops", 0))])
		out = " ｜ ".join(parts)
	if bool(ctx.get("mil_alliance_zhao_qi", false)):
		out += "（赵齐有军事同盟）"
	return out

static func _war_line(ctx: Dictionary) -> String:
	var war: Dictionary = ctx.get("war", {})
	if war.is_empty():
		return "（无战事）"
	return "%s军伐%s——%s（点位%d/3，可斡旋）" % [
		_country_name(String(war.get("attacker", ""))), _country_name(String(war.get("defender", ""))),
		String(war.get("waypoint_name", "")), int(war.get("waypoint", 0))
	]

# === 三国朝议聊天室（v7.3.8；v7.4.2 意图机制） ===
# ctx = {key_event_tag, key_event_text, world_attrs, player_stance, chat_history,
#        recent_actions, ledger_lines, pending_proposal({from,to,text} 若有待你回应的提议), my_last_chat}
# callback(msg: Dictionary { target: String, text: String, intent: String })
# intent ∈ 提议|应允|拒绝|威胁|试探|陈情 —— "应允"将立约（改世界数值），"威胁"生乱
func chat_speak_async(ctx: Dictionary, callback: Callable) -> void:
	var llm = Engine.get_main_loop().root.get_node_or_null("LLMClient")
	if llm == null or not llm.is_ready():
		if callback.is_valid():
			callback.call(_mock_chat(ctx))
		return
	var prompt: String = _build_chat_prompt(ctx)
	llm.request(prompt, {"model": "deepseek-v4-flash", "timeout_sec": 8.0, "temperature": 0.9, "response_json": true},
		func(parsed: Variant, err: String):
			if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
				if callback.is_valid():
					callback.call(_mock_chat(ctx))
				return
			var target: String = String((parsed as Dictionary).get("target", ""))
			var text: String = String((parsed as Dictionary).get("text", ""))
			var intent: String = String((parsed as Dictionary).get("intent", "陈情"))
			var cede: int = clampi(int((parsed as Dictionary).get("cede_cities", 0)), 0, 3)
			if not (target in ["qin", "zhao", "qi", "all", ""]):
				target = ""
			if text == "":
				callback.call(_mock_chat(ctx))
				return
			if callback.is_valid():
				callback.call({"target": target, "text": text, "intent": intent, "cede_cities": cede})
	)

func _build_chat_prompt(ctx: Dictionary) -> String:
	var role_defs = {
		"qin": "秦王嬴稷（雄猜多疑，欲东出灭六国）",
		"zhao": "赵王赵何（犹疑谨慎，欲联齐抗秦又怕拖累）",
		"qi": "齐王田地（精明渔利，喜观望，谁给的多帮谁）"
	}
	var wa: Dictionary = ctx.get("world_attrs", {})

	var chat_lines: Array = []
	var hist: Array = ctx.get("chat_history", [])
	for i in range(max(0, hist.size() - 5), hist.size()):
		var h: Dictionary = hist[i]
		var actor_c: String = String(h.get("country", ""))
		var target_c: String = String(h.get("target", ""))
		var text: String = String(h.get("text", ""))
		var it: String = String(h.get("intent", ""))
		var to_str: String = ""
		if target_c != "" and target_c != "all":
			to_str = " → " + _country_name(target_c)
		var it_str: String = (" [%s]" % it) if it != "" else ""
		chat_lines.append("%s%s%s：%s" % [_country_name(actor_c), to_str, it_str, text])

	var pending: Dictionary = ctx.get("pending_proposal", {})
	var pending_block: String = ""
	if not pending.is_empty():
		var terms: Array = []
		if int(pending.get("cede", 0)) > 0:
			terms.append("对方许割%d城（应允即真交割）" % int(pending.get("cede", 0)))
		var kind: String = String(pending.get("kind", ""))
		if kind == "lure":
			terms.append("性质：利诱——应允即立中立之约，约内结军事同盟=毁约失信")
		elif kind == "alliance":
			terms.append("性质：军事同盟——应允即歃血为盟；若战事正酣，须即刻划拨半数兵力驰援")
			terms.append("结盟以利害自断，勿按套路：你若正被攻伐，救亡高于价码，当速应；秦兵虽未及你身而其锋已动，唇亡齿寒亦当掂量；太平无事时，无质无利不轻允")
		pending_block = "%s向你提议：「%s」%s\n**你必须回应此提议**：应允（intent=应允，条款即刻兑现）/ 拒绝（intent=拒绝）/ 讨价还价（intent=提议，提出你的条件）。" % [
			_country_name(String(pending.get("from", ""))), String(pending.get("text", "")),
			("\n（" + "；".join(terms) + "）") if terms.size() > 0 else ""
		]
		if bool(ctx.get("i_am_neutral_bound", false)) and kind == "alliance":
			pending_block += "\n**警示：你有中立之约在身——此时应允结盟即当众毁约，天下侧目，信誉扫地。**"
		if bool(ctx.get("proposer_breach", false)):
			pending_block += "\n（对方有毁约前科，其言未必可信。）"
		if int(ctx.get("proposer_ceded_to_me", 0)) > 0:
			pending_block += "\n（你曾受对方割让共%d城之惠——受人之地，负人之义。）" % int(ctx.get("proposer_ceded_to_me", 0))
	var my_last: String = String(ctx.get("my_last_chat", ""))

	var lines: Array = [
		"# 世界铁律：只有秦、赵、齐三国。你只能提及秦赵齐 + 张仪魏冉平原君廉颇孟尝君。",
		"",
		"# 你是",
		String(role_defs.get(country, country)),
		"你正在与另外两位君主进行朝议（远程通信/使者往来）。朝议不是空谈：提议可成约，威胁有回响，说出的话都会记入列国史册。",
		"",
		"# 局势",
		"天下大势：%s" % _world_line(wa),
		"列国国力：%s" % _national_line(ctx),
		"当前战事：%s" % _war_line(ctx),
		"关键事件：%s" % String(ctx.get("key_event_text", "")),
		"纵横家立场：%s" % String(ctx.get("player_stance", "")),
		"",
		"# 既往盟约与恩怨（跨回合）",
		("\n".join(ctx.get("ledger_lines", [])) if (ctx.get("ledger_lines", []) as Array).size() > 0 else "（尚无）"),
		"",
		"# 最近朝议记录",
		("\n".join(chat_lines) if chat_lines.size() > 0 else "（尚无发言）"),
		("" if my_last == "" else "\n# 你自己的上一条发言\n「%s」\n**不得重复其论点或句式**——要么推进（给出具体条件/回应对方），要么转向他国。" % my_last),
		("" if pending_block == "" else "\n# 待你回应的提议\n" + pending_block),
		"",
		"# 任务",
		"用文言写一句 ≤ 40 字的**朝议发言**，并给出意图 intent：",
		"- 提议：向某国提出具体盟约/交易（含条件，如'割三城''共击秦'）→ 对方下条会回应",
		"- 应允：接受对方挂起的提议（将立约、改天下大势；**若提议含割城，成约即真割地、载入领土实录**）",
		"- 拒绝：回绝对方的提议",
		"- 威胁：向某国施压放话（天下纷乱会+1）",
		"- 试探 / 陈情：探对方口风 / 表明态度",
		"要求：严格符合你的性格（雄猜/犹疑/渔利）；target ∈ {qin, zhao, qi, all}（提议/应允/拒绝/威胁必须指定具体国家）。",
		"cede_cities：若你的提议含**己方割城**条款，填城数（1-3）；否则填 0。割出的城会真的从你的领土实录中划走——勿轻许。",
		"**割地岁限**：每国每回合至多割 3 城。你本回合割地余额：%d 城——超出余额的许诺无法兑现，勿开空头支票。" % int(ctx.get("cede_allowance", 3)),
		"**地之出处不可颠倒**：实录中'受X割让'=对方主动所予（当念其惠），'夺X地'=兵锋所得。受让之地不得称攻占，更不得否认已受。",
		"**交兵之国无中立之约可言**：不得向正与你交战之国递利诱/中立之议——与交战国该谈的只有战与和。战时利诱当指向第三方（远交近攻），求援当指向未参战者。",
		"",
		"# 输出（严格 JSON）：",
		'{"target": "qin"|"zhao"|"qi"|"all", "text": "≤40 字文言发言", "intent": "提议"|"应允"|"拒绝"|"威胁"|"试探"|"陈情", "cede_cities": 0}'
	]
	return "\n".join(lines)

# 结盟利害评估（不写死）：由当前战况/国力对比/条款/恩怨实时算出应盟意愿
func _alliance_utility(ctx: Dictionary, pending: Dictionary) -> float:
	var war: Dictionary = ctx.get("war", {})
	var nat: Dictionary = ctx.get("national", {})
	var my_t: float = float((nat.get(country, {}) as Dictionary).get("troops", 50))
	var qin_t: float = float((nat.get("qin", {}) as Dictionary).get("troops", 80))
	var u: float = 0.15  # 平时基准：结盟兹事体大，无由不轻允
	if country == "zhao":
		u = 0.55  # 赵地处秦锋，素来急盟
	if String(war.get("defender", "")) == country:
		u += 0.6  # 兵祸及身：救亡高于渔利与价码
	elif not war.is_empty() and String(war.get("attacker", "")) == "qin":
		u += 0.2  # 唇亡齿寒：秦兵既动，下一个未必不是自己
	if country != "qin" and qin_t >= my_t * 1.5:
		u += 0.1  # 强邻压顶
	if int(pending.get("cede", 0)) > 0:
		u += 0.2  # 对方纳质之诚
	if int(ctx.get("proposer_ceded_to_me", 0)) > 0:
		u += 0.2  # 受人之地，负人之义
	if bool(ctx.get("proposer_breach", false)):
		u -= 0.3  # 毁约之国，其言难信
	# 平时拒过的盟越拒越硬；存亡之际不讲面子
	if String(war.get("defender", "")) != country:
		u -= 0.08 * float(_alliance_refusals)
	return clampf(u, 0.05, 0.95)

func _mock_chat(ctx: Dictionary) -> Dictionary:
	# 有待回应的提议 → 按性格/条款/约束/对方信誉决定应允与否
	var pending: Dictionary = ctx.get("pending_proposal", {})
	if not pending.is_empty():
		var from_c: String = String(pending.get("from", ""))
		var kind: String = String(pending.get("kind", ""))
		var accept_prob: float = 0.5
		if country == "qi":
			accept_prob = 0.65
		elif country == "qin":
			accept_prob = 0.35
		if kind == "lure":
			accept_prob += 0.15  # 有实利在手
		if kind == "alliance":
			# 结盟不按性格写死——由当前战况/国力/恩怨实时评估利害
			accept_prob = _alliance_utility(ctx, pending)
			if bool(ctx.get("i_am_neutral_bound", false)):
				# 中立之约在身：结盟即毁约——平时极不情愿；兵祸及身则顾不得脸面
				var refuse_p: float = 0.9
				if String((ctx.get("war", {}) as Dictionary).get("defender", "")) == country:
					refuse_p = 0.35
				if randf() < refuse_p:
					return {"target": from_c, "text": "孤有中立之约在身，此时结盟，失信于天下——未便从命。", "intent": "拒绝", "cede_cities": 0}
		else:
			if bool(ctx.get("proposer_breach", false)):
				accept_prob -= 0.3  # 毁约之国，其言难信
			if int(ctx.get("proposer_ceded_to_me", 0)) > 0:
				accept_prob += 0.15  # 受人之地，负人之义
			if kind == "lure" and String((ctx.get("war", {}) as Dictionary).get("attacker", "")) == from_c:
				accept_prob -= 0.25  # 其兵正伐邻邦，此饵近于与虎谋皮
		if randf() < accept_prob:
			var accepts: Dictionary = {
				"qin": "可。寡人便允此议——然若有诈，函谷之师即出。",
				"zhao": "善，孤应此议。愿两邦守约，共度时艰。",
				"qi": "此议有利，孤便应了。约成之日，勿忘齐之所得。"
			}
			return {"target": from_c, "text": String(accepts.get(country, "可，便依此议。")), "intent": "应允", "cede_cities": 0}
		else:
			if kind == "alliance" and country == "qi":
				_alliance_refusals += 1
			var refuses: Dictionary = {
				"qin": "此议于秦无利，寡人不取。",
				"zhao": "兹事体大，孤未敢遽从，容再计议。",
				"qi": "价码不足，孤不应。加利再来。"
			}
			return {"target": from_c, "text": String(refuses.get(country, "此议不妥，孤未敢从。")), "intent": "拒绝", "cede_cities": 0}
	var pool: Dictionary = {
		"qin": [
			{"target": "zhao", "text": "赵若不识时务，寡人铁骑将至邯郸城下。", "intent": "威胁", "cede_cities": 0},
			{"target": "qi", "text": "齐王勿谓言之不预——寡人之师取赵不过旬月，转锋东向临淄亦不过旬日。", "intent": "威胁", "cede_cities": 0},
			{"target": "qi", "text": "齐王若守中立，寡人愿以三城相赠——此约可立。", "intent": "提议", "cede_cities": 3},
			{"target": "all", "text": "东出乃大势，六国合纵不过一纸空文。", "intent": "陈情", "cede_cities": 0}
		],
		"zhao": [
			{"target": "qi", "text": "齐王，赵齐唇齿相依——愿与齐歃血为盟，共拒强秦。", "intent": "提议", "cede_cities": 0},
			{"target": "qin", "text": "秦欲蚕食六国，孤宁独战，亦不奉秦。", "intent": "陈情", "cede_cities": 0},
			{"target": "qi", "text": "齐若坐视赵亡，秦兵旦暮及于临淄——齐王三思。", "intent": "试探", "cede_cities": 0}
		],
		"qi": [
			{"target": "all", "text": "孤只知渔利，秦赵之争与齐何干？", "intent": "陈情", "cede_cities": 0},
			{"target": "qin", "text": "秦王之礼，孤已收下。然三城何时交割？", "intent": "试探", "cede_cities": 0},
			{"target": "zhao", "text": "赵欲结盟，可先以河间一城为质——孤即刻应盟。", "intent": "提议", "cede_cities": 0}
		]
	}
	# 战局定向（不写死）：交战双方与旁观者的说辞按当前战况实时生成——
	# 攻方威胁交战国、利诱第三方；守方斥敌、向第三方求援；第三方观望要价
	var war_now: Dictionary = ctx.get("war", {})
	if not war_now.is_empty():
		var att_c: String = String(war_now.get("attacker", ""))
		var def_c: String = String(war_now.get("defender", ""))
		var third_c: String = ""
		for cc3 in ["qin", "zhao", "qi"]:
			if cc3 != att_c and cc3 != def_c:
				third_c = cc3
		if country == att_c:
			pool[country] = [
				{"target": def_c, "text": "%s城旦暮可下——城下之盟，胜于城破，%s王自度之。" % [_country_name(def_c), _country_name(def_c)], "intent": "威胁", "cede_cities": 0},
				{"target": third_c, "text": "此战与%s无涉——%s王若安坐不动，寡人愿以三城相谢。" % [_country_name(third_c), _country_name(third_c)], "intent": "提议", "cede_cities": 3},
				{"target": "all", "text": "大军既出，不下坚城不还——列国自量，毋撄兵锋。", "intent": "陈情", "cede_cities": 0}
			]
		elif country == def_c:
			pool[country] = [
				{"target": third_c, "text": "唇亡则齿寒——%s若亡，%s将独面虎狼。愿君侯速断。" % [_country_name(def_c), _country_name(third_c)], "intent": "试探", "cede_cities": 0},
				{"target": att_c, "text": "城池尚固，士卒尚饱——%s欲战，孤奉陪到底！" % _country_name(att_c), "intent": "陈情", "cede_cities": 0},
				{"target": third_c, "text": "%s王，孤愿与君歃血为盟，共退强敌——事成必有厚报。" % _country_name(third_c), "intent": "提议", "cede_cities": 0}
			]
		else:
			pool[country] = [
				{"target": def_c, "text": "%s之难，孤已尽知——然兵者国之大事，容孤权衡。" % _country_name(def_c), "intent": "陈情", "cede_cities": 0},
				{"target": att_c, "text": "%s王兵锋既利，可曾虑及列国侧目？" % _country_name(att_c), "intent": "试探", "cede_cities": 0},
				{"target": def_c, "text": "欲孤发兵相援，须示之以诚——纳质与盟，孤即可议。", "intent": "试探", "cede_cities": 0}
			]
	var arr: Array = pool.get(country, [{"target": "all", "text": "……", "intent": "陈情", "cede_cities": 0}])
	return arr[randi() % arr.size()]

# === v7.4.1 面谈辩论 — 心证驱动的君主回应 ===
# ctx = {
#   player_stance: String ("推合纵" | "推亲秦" | "中立" | "自定义"),
#   round: int,                  # 第几轮 (1..7)
#   attitude: int,               # 当前心证 −6..+6（>0 趋纳，<0 趋拒；由 dialogue 累计）
#   proposed_action: String,     # 君主召见时欲行之事（英文 id）
#   key_event_text: String,
#   last_player_msg: String,     # 玩家最新一句
#   chat_history: Array,         # [{side, name, text}] 全部历史
# }
# callback(msg: Dictionary) — {text, gloss, shift: −2..+2, ended: bool}
# shift = 玩家最新一句对君主心证的推动，由君主判定、dialogue 累计成 attitude
const _DEBATE_ACTION_CN: Dictionary = {
	"pressure": "军事施压", "alienate": "遣使离间", "lure": "连横利诱", "prepare": "备战",
	"seek_alliance": "求盟联齐", "probe": "遣使试探", "observation": "观望",
	"wait_price": "待价而沽", "hijack": "趁火打劫", "self_protect": "闭门自保",
	"declare_war": "兴兵伐国", "war_attacker": "进军还是罢兵", "war_defender": "御敌之策", "war_third": "邻邦之战"
}

func debate_respond_async(ctx: Dictionary, callback: Callable) -> void:
	var llm = Engine.get_main_loop().root.get_node_or_null("LLMClient")
	if llm == null or not llm.is_ready():
		if callback.is_valid():
			callback.call(_mock_debate(ctx))
		return
	var prompt: String = _build_debate_prompt(ctx)
	llm.request(prompt, {"model": "deepseek-v4-flash", "timeout_sec": 10.0, "temperature": 0.85, "response_json": true},
		func(parsed: Variant, err: String):
			if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
				if callback.is_valid():
					callback.call(_mock_debate(ctx))
				return
			var d: Dictionary = parsed as Dictionary
			var text: String = String(d.get("text", ""))
			var gloss: String = String(d.get("gloss", ""))
			var shift: int = clampi(int(d.get("shift", 0)), -2, 2)
			var ended: bool = bool(d.get("end", false))
			if text == "":
				if callback.is_valid():
					callback.call(_mock_debate(ctx))
				return
			if gloss == "":
				gloss = text  # LLM 没返回 gloss 就用文言兜底（极少发生）
			if callback.is_valid():
				callback.call({"text": text, "gloss": gloss, "shift": shift, "ended": ended})
	)

func _build_debate_prompt(ctx: Dictionary) -> String:
	var stance: String = String(ctx.get("player_stance", ""))
	var round_num: int = int(ctx.get("round", 1))
	var attitude: int = int(ctx.get("attitude", 0))
	var action_cn: String = String(_DEBATE_ACTION_CN.get(String(ctx.get("proposed_action", "")), "既定之策"))
	var event_text: String = String(ctx.get("key_event_text", ""))
	var role_defs = {
		"qin": "秦王嬴稷，雄猜之主，霸道果决。核心恐惧=六国合纵。",
		"zhao": "赵王赵何，犹疑之主，怕独战怕激秦。",
		"qi": "齐王田地，渔利之主，谁给的多帮谁。"
	}
	var stakes = {
		"qin": "你在乎：破合纵、成霸业。能打动你的：助你离间赵齐、献可行的连横之策、指出合纵的破绽；触怒你的：劝你止步收兵、空谈仁义道德。",
		"zhao": "你在乎：不独自扛秦。能打动你的：齐国会出兵的凭据、具体的盟约安排、可行的守边之策；触怒你的：要你先动却无保障、劝你屈事秦国。",
		"qi": "你在乎：实利。能打动你的：城邑、市利、盟主之位等具体好处；触怒你的：空谈大义、要齐先出血。"
	}
	var stance_hint := "立场未明（自陈其见）"
	match stance:
		"推合纵": stance_hint = "推合纵（联手抗秦）"
		"推亲秦": stance_hint = "推亲秦（连横）"
		"中立": stance_hint = "中立"
	var mood: String
	if attitude <= -2:
		mood = "言辞抗拒，可讥讽可斥责"
	elif attitude >= 2:
		mood = "已有意动，转向索要具体落实"
	else:
		mood = "摇摆试探，追问细节"

	var hist_lines: Array = []
	for m in ctx.get("chat_history", []):
		var d: Dictionary = m
		hist_lines.append("[%s] %s" % [String(d.get("name", "")), String(d.get("text", ""))])
	var hist_str: String = "\n".join(hist_lines) if hist_lines.size() > 0 else "（尚无）"
	var ledger_lines: Array = ctx.get("ledger_lines", [])
	var ledger_str: String = "\n".join(ledger_lines) if ledger_lines.size() > 0 else "（尚无）"

	var territory: String = String(ctx.get("territory_line", ""))
	var lines: Array = [
		"# 世界铁律：只有秦、赵、齐三国。可提及张仪、魏冉、平原君、廉颇、孟尝君。",
		"",
		"# 你是",
		String(role_defs.get(country, "一位战国君主")),
		"你召见纵横家，正就「%s」一事征询其意见。纵横家的立场：%s。" % [action_cn, stance_hint],
		("当前关键事件：%s" % event_text) if event_text != "" else "",
		"",
		"# 列国领土实录（铁案，不可否认）",
		(territory if territory != "" else "（未知）"),
		"",
		"# 你的利害（判断说服力的准绳）",
		String(stakes.get(country, "")),
		"",
		"# 既往盟约与恩怨（跨回合史实，你亲历之事，不可遗忘）",
		ledger_str,
		"",
		"# 你的心证（外人不可见）",
		"当前心证 %d（−6=极抗拒，+6=倾心欲纳）。本轮语气必须与心证一致：%s。" % [attitude, mood],
		"",
		"# 历史对话",
		hist_str,
		"",
		"# 纵横家最新一句",
		String(ctx.get("last_player_msg", "")),
		"",
		"# 本轮任务（第 %d 轮）" % round_num,
		"1. shift：判断纵横家最新一句对你的说服力，取 -2/-1/0/1/2——给出新论据、具体承诺、切中你的利害 → 正；重复旧论点、空话、与你核心利益相悖 → 负；不痛不痒 → 0。",
		"1b. 立场相左≠必给负：只要对方给出实利（城/质/兵/约）或直击你的恐惧与欲求，仍应给正 shift——你是可以被说动的君主，不是石头。",
		"2. text：≤60 字文言回应（第一人称\"寡人/孤\"）；gloss：白话译文 ≤40 字。",
		"   - **不得重复你此前任何一句的论点或句式**。每轮必须推进——提出新质疑 / 索要具体承诺 / 有条件让步 / 亮出底线，四者择一。",
		"   - **史实一致**：盟约恩怨是你亲历之事，回应必须与之衔接——已受某国之诺，不可称'未见其利'，而应质问其兑现（如'秦许三城，何时交割'）；已与某国成约，不可佯装无约；纵横家所言与史实相悖时，当场戳穿。",
		"   - **领土铁案**：割地/占领以领土实录为准——已得之地不可称未得，已失之地不可称仍有；'受X割让'是对方主动所予（当念其惠），不得说成是你攻占的。",
		"3. end：你已被说动、或彻底失望、或话已说尽（第 5 轮起从速收束）→ true。",
		"",
		"# 输出（严格 JSON）：",
		'{"text": "≤60字文言", "gloss": "≤40字白话", "shift": 0, "end": false}'
	]
	return "\n".join(lines)

# mock 辩论：分阶段推进（质疑→索要→收束），shift 按性格×立场契合度给
func _mock_debate(ctx: Dictionary) -> Dictionary:
	var stance: String = String(ctx.get("player_stance", ""))
	var round_num: int = int(ctx.get("round", 1))
	var shift_map: Dictionary = {
		"qin":  {"推合纵": -1, "中立": 0, "推亲秦": 1},
		"zhao": {"推合纵": 1, "中立": 0, "推亲秦": -1},
		"qi":   {"推合纵": 0, "中立": 0, "推亲秦": 1}
	}
	var shift: int = int((shift_map.get(country, {}) as Dictionary).get(stance, 0))
	# 实词动君心：给出实利/凭据/兵约者，纵立场相左亦可被说动；空谈遭嫌
	var msg: String = String(ctx.get("last_player_msg", ""))
	var substance: int = 0
	for kw in ["城", "质", "盟", "约", "兵", "援", "利", "凭", "割", "破", "间"]:
		if msg.find(kw) >= 0:
			substance += 1
	if substance >= 3:
		shift += 2
	elif substance >= 2:
		shift += 1
	elif substance == 0 and round_num >= 2:
		shift -= 1
	shift = clampi(shift, -2, 2)
	var phase: String = "probe" if round_num <= 2 else ("demand" if round_num <= 4 else "close")
	var pools: Dictionary = {
		"qin": {
			"probe": [
				{"text": "空言无益。先生所言，于秦何利？", "gloss": "空话没用。你说的对秦国有什么好处？"},
				{"text": "先生远来，必有奇策。愿闻其详，毋泛泛而谈。", "gloss": "先生远道而来必有奇策，请讲细节，别泛泛而谈。"}
			],
			"demand": [
				{"text": "若欲寡人从之，须予寡人可握之实——地、城、或六国之隙。", "gloss": "要我听你的，得给我实在的——地、城，或六国的破绽。"},
				{"text": "赵齐之盟可破否？先生若有良策，寡人洗耳恭听。", "gloss": "赵齐联盟能不能破？你有办法我就听。"}
			],
			"close": [
				{"text": "寡人听之已久，意将决矣。先生还有何言？", "gloss": "我听得够久了，就要做决定了。你还有什么要说？"}
			]
		},
		"zhao": {
			"probe": [
				{"text": "齐王果肯出兵乎？孤若先动，秦兵旦暮即至邯郸。", "gloss": "齐王真肯出兵吗？我若先动，秦军很快就打到邯郸。"},
				{"text": "先生之言易，行之难。愿闻其可行处。", "gloss": "先生说来容易做来难，想听听怎么落实。"}
			],
			"demand": [
				{"text": "先生可能立约为凭？空口之诺，孤不敢以国相托。", "gloss": "你能立下凭据吗？空口承诺，我不敢把国家押上去。"},
				{"text": "若齐迁延不至，赵将奈何？先生须为孤谋退路。", "gloss": "如果齐国拖延不来，赵国怎么办？你得给我留退路。"}
			],
			"close": [
				{"text": "孤意渐定。先生一言，可为终言。", "gloss": "我的主意快定了。你再说一句，就是最后一句。"}
			]
		},
		"qi": {
			"probe": [
				{"text": "说得动听。然齐国何所得？先生试言之。", "gloss": "说得好听。但齐国能得到什么？你说说看。"},
				{"text": "秦赵之争，与齐何干？先生欲齐入局，须有说法。", "gloss": "秦赵之争与齐何干？要齐国入局，得有个说法。"}
			],
			"demand": [
				{"text": "城几何？利几何？盟主之位归谁？先生一一道来。", "gloss": "城多少？利多少？盟主之位归谁？你一一说清楚。"},
				{"text": "口惠而实不至者，孤见得多矣。凭据何在？", "gloss": "只给口头好处不兑现的，我见多了。凭据在哪？"}
			],
			"close": [
				{"text": "孤之算盘已拨定。先生还有加价否？", "gloss": "我的算盘已经打定。你还加价吗？"}
			]
		}
	}
	var c_pool: Dictionary = pools.get(country, pools["qin"])
	var arr: Array = c_pool.get(phase, c_pool["probe"])
	var picked: Dictionary = arr[randi() % arr.size()]
	return {
		"text": String(picked.get("text", "")),
		"gloss": String(picked.get("gloss", "")),
		"shift": shift,
		"ended": phase == "close"
	}

# === 辩论收场白：结果已由心证定死，君主说一句与之一致的收场文言 ===
# ctx = {player_stance, outcome ("采纳"|"拒绝"|"自决"), proposed_action, chat_history}
# callback(msg) — {text, gloss}
func debate_close_async(ctx: Dictionary, callback: Callable) -> void:
	var llm = Engine.get_main_loop().root.get_node_or_null("LLMClient")
	if llm == null or not llm.is_ready():
		if callback.is_valid():
			callback.call(_mock_close(ctx))
		return
	var prompt: String = _build_close_prompt(ctx)
	llm.request(prompt, {"model": "deepseek-v4-flash", "timeout_sec": 8.0, "temperature": 0.8, "response_json": true},
		func(parsed: Variant, err: String):
			if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
				if callback.is_valid():
					callback.call(_mock_close(ctx))
				return
			var d: Dictionary = parsed as Dictionary
			var text: String = String(d.get("text", ""))
			var gloss: String = String(d.get("gloss", ""))
			if text == "":
				if callback.is_valid():
					callback.call(_mock_close(ctx))
				return
			if gloss == "":
				gloss = text
			if callback.is_valid():
				callback.call({"text": text, "gloss": gloss})
	)

func _build_close_prompt(ctx: Dictionary) -> String:
	var outcome: String = String(ctx.get("outcome", "自决"))
	var action_cn: String = String(_DEBATE_ACTION_CN.get(String(ctx.get("proposed_action", "")), "既定之策"))
	var role_defs = {
		"qin": "秦王嬴稷，雄猜之主，霸道果决。",
		"zhao": "赵王赵何，犹疑之主，怕独战怕激秦。",
		"qi": "齐王田地，渔利之主，谁给的多帮谁。"
	}
	var outcome_hints = {
		"采纳": "你已决定**采纳**纵横家之言。语气：赞许、托付，可附一句期许或警告。",
		"拒绝": "你已决定**拒绝**纵横家之言，坚行「%s」。语气：拂袖、斥退，保持君王气度。" % action_cn,
		"自决": "你未被说服也未翻脸，决定仍按自己的盘算（%s）行事。语气：沉吟、保留。" % action_cn
	}
	var hist_lines: Array = []
	var hist: Array = ctx.get("chat_history", [])
	for i in range(max(0, hist.size() - 6), hist.size()):
		var d: Dictionary = hist[i]
		hist_lines.append("[%s] %s" % [String(d.get("name", "")), String(d.get("text", ""))])
	var lines: Array = [
		"# 世界铁律：只有秦、赵、齐三国。可提及张仪、魏冉、平原君、廉颇、孟尝君。",
		"",
		"# 你是",
		String(role_defs.get(country, "一位战国君主")),
		"",
		"# 辩论片段（最后几句）",
		"\n".join(hist_lines),
		"",
		"# 你的最终决定",
		String(outcome_hints.get(outcome, outcome_hints["自决"])),
		"",
		"# 任务",
		"说一句 ≤50 字的收场文言（第一人称\"寡人/孤\"）+ 白话译文 ≤40 字。**必须与最终决定一致，不得含糊。**",
		"",
		"# 输出（严格 JSON）：",
		'{"text": "≤50字文言", "gloss": "≤40字白话"}'
	]
	return "\n".join(lines)

func _mock_close(ctx: Dictionary) -> Dictionary:
	var outcome: String = String(ctx.get("outcome", "自决"))
	var pools: Dictionary = {
		"qin": {
			"采纳": {"text": "善。便依先生之策。若有差池，唯先生是问。", "gloss": "好，就按你说的办。出了差错，唯你是问。"},
			"拒绝": {"text": "先生之言，寡人不取。送客。", "gloss": "你的话我不采纳。送客。"},
			"自决": {"text": "先生之言，寡人记下了。然秦国之事，寡人自有分寸。", "gloss": "你的话我记下了，但秦国的事我自有分寸。"}
		},
		"zhao": {
			"采纳": {"text": "善！便依先生。愿先生助孤周旋至最后。", "gloss": "好！就按先生说的。愿先生帮我周旋到底。"},
			"拒绝": {"text": "先生请回。赵国之路，孤另有计较。", "gloss": "先生请回吧。赵国的路，我另有打算。"},
			"自决": {"text": "容孤再思。先生之言，孤未敢全信，亦未敢全废。", "gloss": "让我再想想。你的话我不敢全信，也不敢全不听。"}
		},
		"qi": {
			"采纳": {"text": "成交。齐国便押先生这一注。", "gloss": "成交。齐国就押你这一注。"},
			"拒绝": {"text": "价不够。先生请回，孤不奉陪。", "gloss": "出价不够。先生请回，我不奉陪。"},
			"自决": {"text": "孤且收下先生之言，静观其变，再作计较。", "gloss": "你的话我先收下，静观其变再说。"}
		}
	}
	var c_pool: Dictionary = pools.get(country, pools["qin"])
	var picked: Dictionary = c_pool.get(outcome, c_pool["自决"])
	return {"text": String(picked.get("text", "")), "gloss": String(picked.get("gloss", ""))}

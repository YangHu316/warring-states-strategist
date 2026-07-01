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
var memory: Array = []
const MEMORY_MAX: int = 4

# 性格偏离追踪：连续 2 轮 LLM 输出偏离性格 → 本回合改用 mock
var _persona_drift_count: int = 0
var _force_mock_this_run: bool = false

static func make(country_id: String) -> MonarchAI:
	var ai := MonarchAI.new()
	ai.country = country_id
	match country_id:
		"qin":
			ai.persona = {
				"actions": ["pressure", "alienate", "lure", "prepare"],
				"base": {"pressure": 1.0, "alienate": 1.0, "lure": 1.0, "prepare": 0.6}
			}
			# 张仪·连横推手 + 魏冉·主战
			ai.advisor_weights = {"lure": 1.5, "prepare": 0.6, "pressure": 1.4}
		"zhao":
			ai.persona = {
				"actions": ["seek_alliance", "prepare", "probe", "observation"],
				"base": {"seek_alliance": 1.4, "prepare": 1.0, "probe": 0.8, "observation": 0.6}
			}
			# 平原君·主合纵 + 廉颇·主战
			ai.advisor_weights = {"seek_alliance": 1.4, "observation": 0.5, "prepare": 1.3}
		"qi":
			ai.persona = {
				"actions": ["observation", "wait_price", "hijack", "self_protect"],
				"base": {"observation": 1.5, "wait_price": 1.0, "hijack": 0.5, "self_protect": 0.8}
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
#     country_attrs: Dictionary,         # 全部三国三维
#     player_attrs: Dictionary,          # 玩家三维（用于识别玩家倾向）
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
	# 5. 记录到记忆
	var out := {
		"actor": country,
		"target_country": target,
		"action_type": action,
		"round": round_num,
		"reason": _gen_reason(action, target, ctx),
		"narrative": _gen_narrative(action, target),
		"expected_settle": settle_hint,
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

# 反应轮：面谈后其他君主的性格化响应
func pick_reaction_async(ctx: Dictionary, callback: Callable) -> void:
	var llm = Engine.get_main_loop().root.get_node_or_null("LLMClient")
	if llm == null or not llm.is_ready():
		if callback.is_valid():
			var mock_out = _mock_reaction(ctx)
			mock_out["source"] = "mock:no_llm"
			callback.call(mock_out)
		return
	var prompt: String = _build_reaction_prompt(ctx)
	llm.request(prompt, {"model": "deepseek-v4-flash", "timeout_sec": 10.0, "temperature": 0.85, "response_json": true},
		func(parsed: Variant, err: String):
			if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
				if callback.is_valid():
					var mock_out = _mock_reaction(ctx)
					mock_out["source"] = "mock:%s" % err
					callback.call(mock_out)
				return
			var out = _validate_llm_action(parsed, ctx)
			if out.is_empty():
				if callback.is_valid():
					var mock_out = _mock_reaction(ctx)
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
	var attrs: Dictionary = ctx.get("country_attrs", {})
	var me: Dictionary = attrs.get(country, {})
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
	var others: Array = []
	for c in ["qin", "zhao", "qi"]:
		if c != country:
			var a = attrs.get(c, {})
			others.append("%s(国威%d/盟信%d/战心%d)" % [_country_name(c), int(a.get("guowei",0)), int(a.get("mengxin",0)), int(a.get("zhanxin",0))])

	# 最近 5 条 recent_actions 里非本人 action_type 的作为"最近他人动向"
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
		"纵横家在%s面前进言，%s：「%s」" % [_country_name(audience_country), ("被采纳" if verdict == "accept" else "被拒绝"), player_summary],
		"你听说了这件事。",
		"",
		"# 最近他人动向",
		("\n".join(recent_lines) if recent_lines.size() > 0 else "（暂无）"),
		"",
		"# 当前局势",
		"你的三维：国威%d 盟信%d 战心%d" % [int(me.get("guowei",0)), int(me.get("mengxin",0)), int(me.get("zhanxin",0))],
		"其他国：%s" % ", ".join(others),
		"",
		"# 你可用的动作",
		actions_defs.get(country, ""),
		"",
		"# 决策规则",
		"基于你的性格，对刚发生的面谈事件做出**一个**回应动作。",
		"- 如果面谈事件对你有利：稳住或扩大战果",
		"- 如果对你不利：破坏、离间、备战、观望，视性格而定",
		"- reason 必须以\"基于我...\"开头引用你的性格",
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

func _mock_reaction(ctx: Dictionary) -> Dictionary:
	# 反应轮 mock：直接调 pick_action，让它基于当前状态选一个
	var out = pick_action(ctx)
	out["is_reaction"] = true
	return out

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

func reset_run_state() -> void:
	_persona_drift_count = 0
	_force_mock_this_run = false
	memory.clear()

# 性格偏离检测：LLM 输出的动作是否符合该君主的性格底线
func _is_persona_drift(out: Dictionary, ctx: Dictionary) -> bool:
	var action: String = String(out.get("action_type", ""))
	var attrs: Dictionary = ctx.get("country_attrs", {})
	var zm: int = int(attrs.get("zhao", {}).get("mengxin", 0))
	var qim: int = int(attrs.get("qi", {}).get("mengxin", 0))
	match country:
		"qin":
			# 秦王察觉合纵迹象（赵齐盟信和 ≥ 90）时若不选 alienate/pressure/lure 之一 → 偏离
			if zm + qim >= 90 and not (action in ["alienate", "pressure", "lure"]):
				return true
		"zhao":
			# 赵不该主动施压/离间（不在 zhao actions 里，validate 已挡；此处保守）
			pass
		"qi":
			# 齐第 1 轮就 hijack/self_protect（激进）而无衰弱迹象 → 偏离
			var round_num: int = int(ctx.get("round", 1))
			if round_num == 1 and action == "hijack":
				var qgw: int = int(attrs.get("qin", {}).get("guowei", 100))
				var zgw: int = int(attrs.get("zhao", {}).get("guowei", 100))
				if qgw >= 50 and zgw >= 50:
					return true
	return false

# === LLM prompt 构建（对齐 v7.3 §11b 8 模块结构，紧凑版）===
func _build_prompt(ctx: Dictionary) -> String:
	var attrs: Dictionary = ctx.get("country_attrs", {})
	var me: Dictionary = attrs.get(country, {})
	var round_num: int = int(ctx.get("round", 1))
	var stance: String = String(ctx.get("player_stance", ""))
	var event_text: String = String(ctx.get("key_event_text", ""))

	var role_defs = {
		"qin": "秦王嬴稷，雄猜之主：果决多疑霸道。核心恐惧=六国合纵。行为铁律：一旦察觉合纵迹象（赵齐盟信和 ≥ 90），你必须优先破之（遣使离间 alienate）；决策 confidence 常 ≥ 7；面对犹豫方优先施压。",
		"zhao": "赵王赵何，犹疑之主：谨慎易被说服，怕独战怕激秦。行为铁律：默认动作偏 seek_alliance/observation；第 1 轮多试探/求盟；第 2 轮若仍无定见→ settle_hint=summon（等纵横家给指路）；confidence 常 ≤ 6。",
		"qi": "齐王田地，渔利之主：精明观望，谁给的多帮谁。行为铁律：默认 observation；只有秦已 lure 你（史录中）才转 wait_price；见某方衰弱才 hijack；第 2 轮多 settle_hint=decided（齐王自决）。"
	}
	var actions_defs = {
		"qin": "pressure(军事施压 目标国威-5)|alienate(遣使离间 目标国盟信-8)|lure(连横利诱 目标国盟信+5倒向秦)|prepare(备战蓄力 己国威+3)",
		"zhao": "seek_alliance(求盟联齐 双方盟信+5)|prepare(备战固境 己战心+5)|probe(遣使试探 无数值影响)|observation(骑墙观望 己战心-2)",
		"qi": "observation(观望渔利 己战心-2)|wait_price(待价而沽 与出价方盟信+5)|hijack(趁火打劫 对方国威-3)|self_protect(闭门自保 无变化)"
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

	var mem_str = "无历史（本回合首轮）"
	if memory.size() > 0:
		var last = memory[-1]
		mem_str = "上一轮你选择了：%s → %s（当时玩家立场=%s）" % [
			String(last.get("action", "")), String(last.get("target", "")), String(last.get("player_stance", ""))
		]

	var others: Array = []
	for c in ["qin", "zhao", "qi"]:
		if c != country:
			var a = attrs.get(c, {})
			others.append("%s(国威%d/盟信%d/战心%d)" % [_country_name(c), int(a.get("guowei",0)), int(a.get("mengxin",0)), int(a.get("zhanxin",0))])

	var event_line: String = event_text if event_text != "" else "（本回合无关键事件描述）"
	var implication: String = _event_implication(event_text, ctx)

	var lines: Array = [
		"# 世界铁律（不可违反）",
		"这个世界只有三个国家：秦、赵、齐。**不存在**韩、魏、楚、燕等其他国家。target_country 只能是 qin/zhao/qi，narrative/reason 中不许提及其他国名。",
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
		"# 当前局势（第 %d 轮）" % round_num,
		"你的三维：国威%d 盟信%d 战心%d" % [int(me.get("guowei",0)), int(me.get("mengxin",0)), int(me.get("zhanxin",0))],
		"其他国：%s" % ", ".join(others),
		"纵横家立场：%s" % stance_hint,
		mem_str,
		"",
		"# 你可用的动作",
		actions_defs.get(country, ""),
		advisor_defs.get(country, ""),
		"",
		"# 决策规则",
		"- 严格遵循性格铁律。第 1 轮：探/求盟/观望；第 2 轮：做终局决策。",
		"- 若第 2 轮仍犹豫（需纵横家建议）→ settle_hint=summon；否则 decided。",
		"- reason 必须以'基于我 [性格]……'开头，明确引用你的性格特征。",
		"",
		"# 输出（严格 JSON，无多余文字）：",
		"{",
		'  "target_country": "qin"|"zhao"|"qi",  // 你要针对的对手（不能是你自己）',
		'  "action_type": <上表 action id>,',
		'  "reason": "≤ 40 字内心独白，必须以「基于我...」开头",',
		'  "narrative": "≤ 40 字第三人称描述（用于事件流）",',
		'  "settle_hint": "summon"|"decided",  // 仅第 2 轮有意义',
		'  "confidence": 1-10',
		"}"
	]
	return "\n".join(lines)

func _event_implication(event_text: String, ctx: Dictionary) -> String:
	var attrs: Dictionary = ctx.get("country_attrs", {})
	var zm: int = int(attrs.get("zhao", {}).get("mengxin", 0))
	var qim: int = int(attrs.get("qi", {}).get("mengxin", 0))
	var qgw: int = int(attrs.get("qin", {}).get("guowei", 0))
	if event_text.find("合纵") >= 0 and event_text.find("签字") >= 0:
		return "六国签字合纵——若你是秦，必须离间/施压破局；若你是赵，此时最需求盟固盟；若你是齐，此时是待价而沽的最佳时机。"
	if event_text.find("秦拔宜阳") >= 0 or event_text.find("秦军推进") >= 0 or event_text.find("秦军压境") >= 0:
		return "秦军已动——此时局面对秦最有利。若你是秦，宜乘胜施压；若你是赵，宜求援备战；若你是齐，宜自保或待价。"
	if event_text.find("张仪") >= 0 or event_text.find("连横") >= 0:
		return "秦在利诱他国——若你是秦，此计当推进；若你是赵，警觉齐被拉拢；若你是齐，此时秦价高，可待价。"
	if event_text.find("函谷关") >= 0 or event_text.find("决战") >= 0:
		return "决战时刻——各方立场应最为鲜明。犹豫和观望的成本最高。"
	if zm + qim >= 90:
		return "赵齐盟信之和已高（%d），合纵迹象明显——若你是秦，必须优先破之。" % (zm + qim)
	if qgw >= 80:
		return "秦国威已强（%d）——若你是赵齐，压力空前；若你是秦，可持续施压。" % qgw
	return "此事件为回合背景，你的决策应契合当前性格与局势。"

func _round_to_month(rn: int) -> int:
	return clampi(rn * 2 - 1, 1, 12)

# 校验 LLM 输出的 action 字段合法
func _validate_llm_action(parsed: Dictionary, ctx: Dictionary) -> Dictionary:
	var target: String = String(parsed.get("target_country", ""))
	var atype: String = String(parsed.get("action_type", ""))
	var valid_actions: Array = persona.get("actions", [])
	if not (target in ["qin", "zhao", "qi"]) or target == country:
		return {}
	if not (atype in valid_actions):
		return {}
	var round_num: int = int(ctx.get("round", 1))
	var settle_hint: String = String(parsed.get("settle_hint", "summon"))
	if not (settle_hint in ["summon", "decided"]):
		settle_hint = "summon"
	return {
		"actor": country,
		"target_country": target,
		"action_type": atype,
		"round": round_num,
		"reason": String(parsed.get("reason", "")),
		"narrative": String(parsed.get("narrative", _gen_narrative(atype, target))),
		"expected_settle": settle_hint if round_num >= 2 else "",
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

# 情境加成——各君主对世界状态的差异化反应
func _situational_bonus(action: String, ctx: Dictionary) -> float:
	var attrs: Dictionary = ctx.get("country_attrs", {})
	var qin: Dictionary = attrs.get("qin", {})
	var zhao: Dictionary = attrs.get("zhao", {})
	var qi: Dictionary = attrs.get("qi", {})
	var stance: String = String(ctx.get("player_stance", ""))
	var event: String = String(ctx.get("key_event_tag", ""))
	var round_num: int = int(ctx.get("round", 1))

	match country:
		"qin":
			# 秦：警觉合纵 → 优先离间
			if action == "alienate":
				var alliance_signal: int = int(zhao.get("mengxin", 0)) + int(qi.get("mengxin", 0))
				if alliance_signal >= 90:
					return 1.5  # 强合纵迹象 → 必破
				if alliance_signal >= 70:
					return 0.8
			if action == "lure":
				# 齐观望时 → 利诱齐
				if int(qi.get("zhanxin", 0)) < 40:
					return 0.8
				if stance == "qin":
					return 0.6  # 玩家推亲秦时秦更愿花钱
			if action == "pressure":
				# 玩家推合纵或秦国威很高 → 直接压
				if stance == "hezong":
					return 0.6
				if int(qin.get("guowei", 0)) >= 80:
					return 0.5
			if action == "prepare":
				# 玩家推合纵 + 秦第一轮 → 更倾向蓄力
				if round_num == 1 and stance == "hezong":
					return 0.3
		"zhao":
			# 赵：秦压境 + 独战 → 求盟或备战
			if action == "seek_alliance":
				if int(qin.get("guowei", 0)) >= 75:
					return 0.8
				if stance == "hezong":
					return 0.6
			if action == "prepare":
				if int(qin.get("zhanxin", 0)) >= 70:
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
				if _lured_by_qin:
					return 1.8  # 强信号：秦刚出价，齐应待价
			if action == "observation":
				if _lured_by_qin:
					return -1.2  # 有出价方 → 观望反被动
			if action == "hijack":
				if int(zhao.get("guowei", 100)) <= 40:
					return 0.7
			if action == "self_protect":
				if int(qin.get("zhanxin", 0)) >= 80:
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
	var attrs: Dictionary = ctx.get("country_attrs", {})
	var others: Array = []
	for c in ["qin", "zhao", "qi"]:
		if c != country:
			others.append(c)
	if others.is_empty():
		return ""
	match action:
		"pressure":
			# 秦压最弱的
			var weakest: String = String(others[0])
			var min_gw: int = int(attrs.get(weakest, {}).get("guowei", 100))
			for c in others:
				var g: int = int(attrs.get(c, {}).get("guowei", 100))
				if g < min_gw:
					weakest = c
					min_gw = g
			return weakest
		"alienate":
			# 离间意味着"目标 = 一国，效果 = 该国与另一国的盟信"
			# 挑盟信最高的（最像盟友的）
			var strongest: String = String(others[0])
			var max_mx: int = int(attrs.get(strongest, {}).get("mengxin", 0))
			for c in others:
				var m: int = int(attrs.get(c, {}).get("mengxin", 0))
				if m > max_mx:
					strongest = c
					max_mx = m
			return strongest
		"lure":
			# 秦利诱：优先犹豫的（战心低）
			var best: String = String(others[0])
			var min_zx: int = int(attrs.get(best, {}).get("zhanxin", 100))
			for c in others:
				var z: int = int(attrs.get(c, {}).get("zhanxin", 100))
				if z < min_zx:
					best = c
					min_zx = z
			return best
		"seek_alliance":
			# 赵求盟：优先齐（设计中赵求盟对象=齐）
			return "qi" if "qi" in others else String(others[0])
		"probe":
			# 赵试探：秦（威胁最大）
			return "qin" if "qin" in others else String(others[0])
		"wait_price", "hijack":
			# 齐待价：跟出价方（谁最近对齐 lure 过）；无信号则秦
			for m in ctx.get("opponents_history", []):
				var md: Dictionary = m
				if String(md.get("action_type", "")) == "lure" and String(md.get("target_country", "")) == country:
					return String(md.get("actor", ""))
			return "qin" if "qin" in others else String(others[0])
		_:
			# prepare/observation/self_protect: 目标 = 感知威胁最大的国
			var threat: String = String(others[0])
			var max_zx: int = int(attrs.get(threat, {}).get("zhanxin", 0))
			for c in others:
				var z: int = int(attrs.get(c, {}).get("zhanxin", 0))
				if z > max_zx:
					threat = c
					max_zx = z
			return threat

# 判断第 2 轮结束后进入 summon 还是 decided
func _decide_settle(action: String, ctx: Dictionary) -> String:
	# 犹豫型动作 → summon（等纵横家给建议）
	# 明确行动型 → decided
	var summon_actions := ["probe", "observation", "seek_alliance"]
	var decided_actions := ["pressure", "alienate", "lure", "prepare", "hijack", "self_protect", "wait_price"]
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
func _gen_narrative(action: String, target: String) -> String:
	var name: String = _country_name(country)
	var tname: String = _country_name(target)
	match action:
		"pressure": return "%s陈兵压境，向%s施加军事压力。" % [name, tname]
		"alienate": return "%s使者暗中活动，欲离间%s与其盟友。" % [name, tname]
		"lure": return "%s以割地重金利诱%s，欲结连横。" % [name, tname]
		"prepare": return "%s闭关备战，秣马厉兵。" % name
		"seek_alliance": return "%s遣使求盟%s，愿共抗强敌。" % [name, tname]
		"probe": return "%s遣密使潜入%s，探其君意。" % [name, tname]
		"observation": return "%s按兵不动，观望天下之变。" % name
		"wait_price": return "%s待价而沽，坐观%s加码。" % [name, tname]
		"hijack": return "%s见%s衰弱，欲趁火打劫。" % [name, tname]
		"self_protect": return "%s闭门自保，谢绝外使。" % name
		_: return "%s未有动作。" % name

func _gen_reason(action: String, target: String, ctx: Dictionary) -> String:
	var stance: String = String(ctx.get("player_stance", ""))
	var stance_hint: String = ""
	if stance == "hezong":
		stance_hint = "（察觉纵横家推合纵）"
	elif stance == "qin":
		stance_hint = "（察觉纵横家推亲秦）"
	match action:
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

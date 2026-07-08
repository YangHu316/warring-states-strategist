extends Node
# V3 AgentManager Autoload — 按国（3 君主）独立同步博弈
#
# 设计对齐 v7.3 §04-Agent架构：
#  - 每位君主独立评估、独立选择目标+动作
#  - 每回合最多 2 轮，第 1 轮全部 → 第 2 轮全部
#  - Agent 动作交由 Arbiter.settle_agent_action 结算国家三维
#  - 玩家打牌（含方向）→ 记录玩家立场 → 触发第 2 轮提前 + 重评估
#  - 第 2 轮结束后每位君主判定 summon / decided
#  - 全部就绪 → all_finished

const MonarchAIScript = preload("res://scripts/core/monarch_ai.gd")

signal agent_action(country: String, action: Dictionary)   # 单个 agent 动作（含 narrative/reason/deltas）
signal country_finished(country: String, settle: String)    # summon / decided
signal all_finished()
signal chat_message(country: String, target: String, text: String, is_public: bool)  # 聊天室发言
signal chat_settled(note: String)  # 朝议成交/威胁的数值结算播报

const COUNTRIES: Array = ["qin", "zhao", "qi"]

var ais: Dictionary = {}                     # country -> MonarchAI
var country_round: Dictionary = {}           # country -> 已完成轮数（0/1/2）
var country_state: Dictionary = {}           # country -> "running" / "summon" / "decided"
var country_last_action: Dictionary = {}     # country -> 上一轮动作 dict
var recent_actions: Array = []               # 最近所有 agent 动作（供 mock 决策做 opponents_history）
var active: bool = false
var key_event_tag: String = ""
var key_event_text: String = ""

# 玩家立场信号（由玩家打牌驱动）
var player_stance: String = ""

var _round_timer: Timer = null
var _pending_r2: bool = false
var _pending_step_count: int = 0

# 聊天室（v7.3.8；v7.4.2 意图机制）
var _chat_timer: Timer = null
var chat_history: Array = []
var chat_active: bool = false            # 朝议贯穿整个自由阶段（不随决策完成而停）
# 待回应的提议 {from, to, text, kind(""|"lure"|"alliance"), cede}
# 被提议方下一条优先发言；kind 决定应允结算方式（利诱=割城+中立约；同盟=form_alliance 含毁约判定与驰援）
var pending_proposal: Dictionary = {}
var _threat_settled_count: int = 0       # 每回合威胁结算上限（防刷纷乱）
const CHAT_INTENTS: Array = ["提议", "应允", "拒绝", "威胁", "试探", "陈情"]
const CHAT_INTERVAL_SEC: float = 20.0
const CHAT_HISTORY_MAX: int = 20
const CHAT_LEAK_PROBABILITY: float = 0.3  # 私聊漏给第三方的概率

func _ready() -> void:
	ais["qin"] = MonarchAIScript.make("qin")
	ais["zhao"] = MonarchAIScript.make("zhao")
	ais["qi"] = MonarchAIScript.make("qi")
	_round_timer = Timer.new()
	_round_timer.one_shot = true
	add_child(_round_timer)
	_round_timer.timeout.connect(_on_round_timer)
	_chat_timer = Timer.new()
	_chat_timer.one_shot = true
	add_child(_chat_timer)
	_chat_timer.timeout.connect(_on_chat_timer)

# === 生命周期 ===
func start_free_phase(event_tag: String = "", event_text: String = "") -> void:
	key_event_tag = event_tag
	key_event_text = event_text
	active = true
	player_stance = ""
	recent_actions.clear()
	chat_history.clear()
	chat_active = true
	# 上回合未获答复的提议作废入账（不了了之，非违诺）
	if not pending_proposal.is_empty():
		State.add_ledger("refuse", String(pending_proposal.get("to", "")), String(pending_proposal.get("from", "")),
			"%s之议未获答复，不了了之" % _country_name_short(String(pending_proposal.get("from", ""))))
	pending_proposal = {}
	_threat_settled_count = 0
	for c in COUNTRIES:
		country_round[c] = 0
		country_state[c] = "running"
		country_last_action[c] = {}
	_pending_r2 = false
	_round_timer.wait_time = 1.0
	_round_timer.start()
	# 聊天室：+8s 首条，之后每 20s 一条
	_chat_timer.wait_time = 8.0
	_chat_timer.start()

# 回合间重置：清博弈/朝议状态，但保留君主跨回合记忆与承诺账本
func reset() -> void:
	active = false
	chat_active = false
	country_round.clear()
	country_state.clear()
	country_last_action.clear()
	recent_actions.clear()
	chat_history.clear()
	pending_proposal = {}
	player_stance = ""
	_pending_r2 = false
	for c in COUNTRIES:
		var ai = ais.get(c, null)
		if ai != null and ai.has_method("reset_round_state"):
			ai.reset_round_state()
	if _round_timer != null and _round_timer.time_left > 0:
		_round_timer.stop()
	if _chat_timer != null and _chat_timer.time_left > 0:
		_chat_timer.stop()

# 整局重置（重开新局）：连君主记忆一起清
func full_reset() -> void:
	reset()
	for c in COUNTRIES:
		var ai = ais.get(c, null)
		if ai != null and ai.has_method("reset_run_state"):
			ai.reset_run_state()

# === 玩家打牌回调 ===
# direction: "push_hezong"/"push_qin"/"neutral"/"favor_hezong"/"favor_lianheng" 等
# card_id: "persuade"/"message"/"promise"/"alienate"/"spy"
func on_player_card_played(_target: String, card_id: String, direction: String, success: bool) -> void:
	if not success:
		return
	# 从方向提取立场信号
	var stance: String = _direction_to_stance(card_id, direction)
	if stance != "":
		player_stance = stance
	# 若还未完成第 2 轮 → 提前触发第 2 轮（0.5s 后）
	var need_r2: bool = false
	for c in COUNTRIES:
		if String(country_state.get(c, "")) == "running" and int(country_round.get(c, 0)) >= 1:
			need_r2 = true
			break
	if need_r2 and _round_timer != null:
		if _round_timer.time_left > 0.5 or _round_timer.time_left == 0:
			_round_timer.stop()
			_round_timer.wait_time = 0.5
			_round_timer.start()

func _direction_to_stance(card_id: String, direction: String) -> String:
	match direction:
		"push_hezong", "favor_hezong":
			return "hezong"
		"push_qin", "favor_lianheng":
			return "qin"
		"neutral":
			return "neutral"
	# 离间/刺探等无方向牌不动立场
	if card_id == "alienate":
		return "hezong"  # 离间通常利于合纵
	return ""

# === 轮次调度 ===
func _on_round_timer() -> void:
	if not active:
		return
	var min_completed: int = 999
	for c in COUNTRIES:
		if String(country_state.get(c, "")) == "running":
			min_completed = min(min_completed, int(country_round.get(c, 0)))
	if min_completed == 999:
		_finish()
		return
	var target_round: int = min_completed + 1
	var to_step: Array = []
	for c in COUNTRIES:
		if String(country_state.get(c, "")) == "running" and int(country_round.get(c, 0)) < target_round:
			to_step.append(c)

	# 并发发起决策：LLM async；未接入或 no_key 会立即回调 mock
	_pending_step_count = to_step.size()
	for c in to_step:
		_step_country_async(c, target_round)

func _step_country_async(country: String, round_num: int) -> void:
	var ai = ais.get(country, null)
	if ai == null:
		_on_step_complete()
		return
	var ctx: Dictionary = {
		"round": round_num,
		"key_event_tag": key_event_tag,
		"key_event_text": key_event_text,
		"world_attrs": State.world_attrs,
		"player_stance": player_stance,
		"opponents_history": recent_actions.duplicate(),
		"me_last_action": country_last_action.get(country, {}),
		"chat_lines": _chat_lines_for(country),
		"ledger_lines": State.ledger_lines_for(country),
		"pacts": {
			"zhao_qi": State.has_pact("zhao", "qi"),
			"qin_qi": State.has_pact("qin", "qi"),
			"qin_zhao": State.has_pact("qin", "zhao")
		},
		"war": WarManager.war_brief(),
		"national": State.national,
		"territory_line": State.territory_line(),
		"mil_alliance_zhao_qi": State.has_alliance("zhao", "qi"),
		"pending_busy": not pending_proposal.is_empty(),
		"pending_to_me": String(pending_proposal.get("to", "")) == country
	}
	ai.pick_action_async(ctx, func(action: Dictionary):
		_apply_action(country, round_num, action)
		_on_step_complete()
	)

func _apply_action(country: String, round_num: int, action: Dictionary) -> void:
	country_last_action[country] = action
	recent_actions.append(action)
	if recent_actions.size() > 12:
		recent_actions.pop_front()
	country_round[country] = round_num

	var settle_res: Dictionary = {}
	var arb = get_node_or_null("/root/Arbiter")
	if arb != null and arb.has_method("settle_agent_action"):
		settle_res = arb.settle_agent_action(action)
	action["deltas_note"] = String(settle_res.get("note", ""))

	emit_signal("agent_action", country, action)

	if round_num >= 2:
		# 定策入承诺账本（跨回合可被各国引述）
		State.add_ledger("decision", country, String(action.get("target_country", "")), String(action.get("narrative", "")).left(40))
		var settle: String = String(action.get("expected_settle", "summon"))
		if settle != "summon" and settle != "decided":
			settle = "summon"
		country_state[country] = settle
		emit_signal("country_finished", country, settle)

func _on_step_complete() -> void:
	_pending_step_count -= 1
	if _pending_step_count > 0:
		return
	# 本轮全部完成 → 判断下一轮
	var still_running: bool = false
	var any_at_r1: bool = false
	for c in COUNTRIES:
		if String(country_state.get(c, "")) == "running":
			still_running = true
			if int(country_round.get(c, 0)) < 2:
				any_at_r1 = true
	if not still_running:
		_finish()
		return
	if any_at_r1:
		_round_timer.wait_time = 1.0
		_round_timer.start()

# 保留同步版供内部/兼容使用（不推荐）
func _step_country(country: String, round_num: int) -> void:
	var ai = ais.get(country, null)
	if ai == null:
		return
	var ctx: Dictionary = {
		"round": round_num,
		"key_event_tag": key_event_tag,
		"key_event_text": key_event_text,
		"world_attrs": State.world_attrs,
		"player_stance": player_stance,
		"opponents_history": recent_actions.duplicate(),
		"me_last_action": country_last_action.get(country, {}),
		"chat_lines": _chat_lines_for(country),
		"ledger_lines": State.ledger_lines_for(country),
		"pacts": {
			"zhao_qi": State.has_pact("zhao", "qi"),
			"qin_qi": State.has_pact("qin", "qi"),
			"qin_zhao": State.has_pact("qin", "zhao")
		},
		"war": WarManager.war_brief(),
		"national": State.national,
		"territory_line": State.territory_line(),
		"mil_alliance_zhao_qi": State.has_alliance("zhao", "qi"),
		"pending_busy": not pending_proposal.is_empty(),
		"pending_to_me": String(pending_proposal.get("to", "")) == country
	}
	var action: Dictionary = ai.pick_action(ctx)
	_apply_action(country, round_num, action)

func _finish() -> void:
	active = false
	emit_signal("all_finished")

# === 查询 API（供 UI 使用）===
func get_country_status(country: String) -> String:
	var st: String = String(country_state.get(country, ""))
	if st == "running":
		var rn: int = int(country_round.get(country, 0))
		if rn == 0:
			return "谈判中·R1"
		return "谈判中·R%d" % (rn + 1)
	if st == "summon":
		return "召见"
	if st == "decided":
		return "决策已定"
	return ""

func is_country_summon(country: String) -> bool:
	return String(country_state.get(country, "")) == "summon"

func is_country_decided(country: String) -> bool:
	return String(country_state.get(country, "")) == "decided"

# v7.3.10：取该国 R2 决策时预生成的 proposed_action（召见前想好的问题）
# dialogue.gd setup 优先读此字段，避免玩家到了才调 LLM 想问题
func get_country_proposed_action(country: String) -> String:
	var last: Dictionary = country_last_action.get(country, {})
	return String(last.get("proposed_action", ""))

# 该国最近一轮的真实动作 id —— 面谈结算必须结算君主实际想做的事
func get_country_last_action_type(country: String) -> String:
	var last: Dictionary = country_last_action.get(country, {})
	return String(last.get("action_type", ""))

# 该国是否仍在谈判中（离间牌的时机窗）
func is_country_negotiating(country: String) -> bool:
	return String(country_state.get(country, "")) == "running"

# 该国当前意图摘要（刺探牌的情报内容）
func get_country_intent(country: String) -> String:
	var last: Dictionary = country_last_action.get(country, {})
	if last.is_empty():
		return ""
	var narrative: String = String(last.get("narrative", ""))
	var reason: String = String(last.get("reason", ""))
	var settle: String = String(last.get("expected_settle", ""))
	var settle_s: String = ""
	if settle == "summon":
		settle_s = "（其君犹疑，待人指路）"
	elif settle == "decided":
		settle_s = "（其意已决）"
	var out: String = narrative
	if reason != "":
		out += " 其谋：" + reason
	return out + settle_s

func all_pairs_done() -> bool:
	for c in COUNTRIES:
		if String(country_state.get(c, "")) == "running":
			return false
	return true

# 挑战决策已定：调用此方法把某国从 decided 改回 summon
func challenge_decided(country: String) -> void:
	if String(country_state.get(country, "")) == "decided":
		country_state[country] = "summon"
		emit_signal("country_finished", country, "summon")

# v7.3.5 面谈反应轮（群体智能）：面谈国已表态 → 另 2 国链式反应
func trigger_reaction_round(audience_country: String, verdict: String, player_summary: String) -> void:
	var others: Array = []
	for c in COUNTRIES:
		if c != audience_country:
			others.append(c)
	if others.size() < 2:
		return
	if randi() % 2 == 1:
		var tmp = others[0]
		others[0] = others[1]
		others[1] = tmp
	recent_actions.append({
		"actor": audience_country,
		"target_country": "",
		"action_type": "audience_" + verdict,
		"round": 0,
		"narrative": "纵横家面见%s王：%s" % [_country_name_short(audience_country), player_summary]
	})
	if recent_actions.size() > 12:
		recent_actions.pop_front()
	_react_step(others[0], others[1], audience_country, verdict, player_summary)

func _react_step(current: String, next_country: String, audience_country: String, verdict: String, player_summary: String) -> void:
	var ai = ais.get(current, null)
	if ai == null:
		if next_country != "":
			_react_step(next_country, "", audience_country, verdict, player_summary)
		return
	var ctx: Dictionary = {
		"round": 3,
		"key_event_tag": key_event_tag,
		"key_event_text": key_event_text,
		"world_attrs": State.world_attrs,
		"player_stance": player_stance,
		"opponents_history": recent_actions.duplicate(),
		"me_last_action": country_last_action.get(current, {}),
		"chat_lines": _chat_lines_for(current),
		"ledger_lines": State.ledger_lines_for(current),
		"war": WarManager.war_brief(),
		"national": State.national,
		"territory_line": State.territory_line(),
		"reaction_context": {
			"audience_country": audience_country,
			"verdict": verdict,
			"player_summary": player_summary
		}
	}
	if ai.has_method("pick_reaction_async"):
		ai.pick_reaction_async(ctx, func(action: Dictionary):
			_apply_action(current, 3, action)
			if next_country != "":
				_react_step(next_country, "", audience_country, verdict, player_summary)
		)
	else:
		var action: Dictionary = ai.pick_action(ctx)
		_apply_action(current, 3, action)
		if next_country != "":
			_react_step(next_country, "", audience_country, verdict, player_summary)

func _country_name_short(c: String) -> String:
	match c:
		"qin": return "秦"
		"zhao": return "赵"
		"qi": return "齐"
		_: return c

# 生成召见前情摘要：本回合三国 R1/R2 关键动作，供 dialogue 显示
func get_audience_briefing() -> String:
	if recent_actions.is_empty():
		return "（本回合尚无 Agent 博弈记录）"
	var per_country: Dictionary = {"qin": [], "zhao": [], "qi": []}
	for a in recent_actions:
		var d: Dictionary = a
		var actor: String = String(d.get("actor", ""))
		if per_country.has(actor):
			per_country[actor].append(d)
	var lines: Array = []
	var country_names := {"qin": "秦", "zhao": "赵", "qi": "齐"}
	for c in ["qin", "zhao", "qi"]:
		var acts: Array = per_country[c]
		if acts.is_empty():
			continue
		for a in acts:
			var d: Dictionary = a
			var rn: int = int(d.get("round", 0))
			var narrative: String = String(d.get("narrative", ""))
			var reason: String = String(d.get("reason", ""))
			var s: String = "· [%s R%d] %s" % [country_names.get(c, c), rn, narrative]
			if reason != "":
				s += "（%s）" % reason
			lines.append(s)
	return "\n".join(lines)

# v7.3.11：动态 3 句国家态度总结（异步）
# callback(text: String) —— 三句文言，每行一句，分别对应秦/赵/齐当前态度
func get_audience_briefing_async(callback: Callable) -> void:
	var llm = Engine.get_main_loop().root.get_node_or_null("LLMClient")
	if llm == null or not llm.is_ready():
		if callback.is_valid():
			callback.call(_mock_briefing())
		return
	var prompt: String = _build_briefing_prompt()
	llm.request(prompt, {"model": "deepseek-v4-flash", "timeout_sec": 8.0, "temperature": 0.7, "response_json": true},
		func(parsed: Variant, err: String):
			if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
				if callback.is_valid():
					callback.call(_mock_briefing())
				return
			var qin_line: String = String((parsed as Dictionary).get("qin", ""))
			var zhao_line: String = String((parsed as Dictionary).get("zhao", ""))
			var qi_line: String = String((parsed as Dictionary).get("qi", ""))
			if qin_line == "" or zhao_line == "" or qi_line == "":
				if callback.is_valid():
					callback.call(_mock_briefing())
				return
			var out: String = "秦：%s\n赵：%s\n齐：%s" % [qin_line, zhao_line, qi_line]
			if callback.is_valid():
				callback.call(out)
	)

func _build_briefing_prompt() -> String:
	var country_names := {"qin": "秦", "zhao": "赵", "qi": "齐"}
	var wa: Dictionary = State.world_attrs
	var world_line: String = "秦之霸业 %d / 六国之盟 %d / 天下纷乱 %d" % [
		int(wa.get("qin_baye", 0)), int(wa.get("liu_guo_meng", 0)), int(wa.get("tian_xia_fenluan", 0))
	]

	var recent_lines: Array = []
	for h in recent_actions:
		var d: Dictionary = h
		var actor: String = String(d.get("actor", ""))
		var narrative: String = String(d.get("narrative", ""))
		if actor != "" and narrative != "":
			recent_lines.append("· [%s] %s" % [country_names.get(actor, actor), narrative])
	if recent_lines.is_empty():
		recent_lines.append("（本回合尚无博弈记录）")

	var lines: Array = [
		"# 世界铁律：只有秦、赵、齐三国。",
		"",
		"# 你是史官，正为纵横家总结当前局势",
		"",
		"# 天下大势",
		world_line,
		"",
		"# 关键事件",
		String(key_event_text if key_event_text != "" else "（未知）"),
		"",
		"# 本回合博弈记录",
		"\n".join(recent_lines),
		"",
		"# 既往盟约与恩怨（跨回合）",
		("\n".join(State.ledger_lines_for("")) if State.ledger_lines_for("").size() > 0 else "（尚无）"),
		"",
		"# 任务",
		"用文言为纵横家总结**每国当下的态度立场**，一国一句 ≤ 30 字。",
		"要求：",
		"- 每句直接说明该国当前意向（如'秦欲东出、正遣使离间'、'赵犹疑，愿联齐而畏秦'、'齐观望渔利'）",
		"- 结合天下大势、既往盟约与博弈记录（有约必提，如'齐已受秦三城之诺'）",
		"- 若某国无记录，就基于大势推断",
		"",
		"# 输出（严格 JSON）：",
		'{"qin": "≤30字", "zhao": "≤30字", "qi": "≤30字"}'
	]
	return "\n".join(lines)

func _mock_briefing() -> String:
	return "秦：东出之志不改，正探六国虚实。\n赵：犹疑难决，欲联齐又畏秦压。\n齐：观望渔利，坐待秦赵消耗。"

# === 聊天室（v7.3.8） ===
func _on_chat_timer() -> void:
	if not chat_active:
		return
	# 有待回应的提议 → 被提议方优先发言（让对话连起来）；否则随机
	var speaker: String = ""
	var pending_to: String = String(pending_proposal.get("to", ""))
	if pending_to in COUNTRIES:
		speaker = pending_to
	else:
		speaker = COUNTRIES[randi() % COUNTRIES.size()]
	var ai = ais.get(speaker, null)
	if ai == null or not ai.has_method("chat_speak_async"):
		_schedule_next_chat()
		return
	var my_pending: Dictionary = pending_proposal if String(pending_proposal.get("to", "")) == speaker else {}
	var prev_entry: Dictionary = _last_chat_entry_by(speaker)
	var ctx: Dictionary = {
		"key_event_tag": key_event_tag,
		"key_event_text": key_event_text,
		"world_attrs": State.world_attrs,
		"player_stance": player_stance,
		"chat_history": _visible_chat_history_for(speaker),
		"recent_actions": recent_actions.duplicate(),
		"ledger_lines": State.ledger_lines_for(speaker),
		"pending_proposal": my_pending,
		"my_last_chat": String(prev_entry.get("text", "")),
		"war": WarManager.war_brief(),
		"national": State.national,
		"territory_line": State.territory_line(),
		"i_am_neutral_bound": State.is_neutral_bound(speaker),
		"proposer_breach": (State.has_breach_record(String(my_pending.get("from", ""))) if not my_pending.is_empty() else false),
		"cede_allowance": State.cede_allowance(speaker),
		"proposer_ceded_to_me": (int((State.gains.get(speaker + "|" + String(my_pending.get("from", "")), {}) as Dictionary).get("ceded", 0)) if not my_pending.is_empty() else 0)
	}
	# 保底：无论回调是否触发，15s 后强制排下一条（防 LLM hang）
	var scheduled: Array = [false]
	var _do_next = func():
		if scheduled[0]:
			return
		scheduled[0] = true
		_schedule_next_chat()
	# fallback timer
	var fb = get_tree().create_timer(15.0)
	fb.timeout.connect(func(): _do_next.call())
	ai.chat_speak_async(ctx, func(msg: Dictionary):
		if not chat_active:
			return
		var target: String = String(msg.get("target", ""))
		var text: String = String(msg.get("text", ""))
		var intent: String = String(msg.get("intent", "陈情"))
		var cede: int = clampi(int(msg.get("cede_cities", 0)), 0, 3)
		if not (intent in CHAT_INTENTS):
			intent = "陈情"
		if text != "":
			# 犟嘴熔断：同意图同对象且开头雷同 → 丢弃本条，等下一轮说点新的
			var prev: Dictionary = _last_chat_entry_by(speaker)
			if not prev.is_empty() and String(prev.get("intent", "")) == intent \
					and String(prev.get("target", "")) == target \
					and text.length() >= 8 and String(prev.get("text", "")).begins_with(text.left(8)):
				_do_next.call()
				return
			# visibility：谁能看到这条消息（除玩家总能看外）
			# 公聊 (all/空) → 全 3 国可见
			# 私聊 (specific target) → speaker + target 必看，第三国 30% 概率"听到风声"
			var visible_to: Array = [speaker]
			if target == "" or target == "all":
				for c in COUNTRIES:
					if not (c in visible_to):
						visible_to.append(c)
			else:
				if target in COUNTRIES and not (target in visible_to):
					visible_to.append(target)
				# 第三国听风
				for c in COUNTRIES:
					if not (c in visible_to) and randf() < CHAT_LEAK_PROBABILITY:
						visible_to.append(c)
			var is_public: bool = (target == "" or target == "all")
			var entry: Dictionary = {
				"country": speaker, "target": target, "text": text,
				"intent": intent, "visible_to": visible_to, "public": is_public
			}
			chat_history.append(entry)
			if chat_history.size() > CHAT_HISTORY_MAX:
				chat_history.pop_front()
			recent_actions.append({
				"actor": speaker, "target_country": target,
				"action_type": "chat", "round": 0,
				"narrative": "[朝议·%s] %s" % [intent, text]
			})
			if recent_actions.size() > 12:
				recent_actions.pop_front()
			_settle_chat_intent(speaker, target, text, intent, cede)
			emit_signal("chat_message", speaker, target, text, is_public)
		_do_next.call()
	)

# 意图机制：提议挂起 / 应允成约（同盟/利诱/割地按 kind 真结算）/ 拒绝销案 / 威胁生乱
func _settle_chat_intent(speaker: String, target: String, text: String, intent: String, cede: int = 0) -> String:
	var arb = get_node_or_null("/root/Arbiter")
	var note: String = ""
	match intent:
		"提议":
			if target in COUNTRIES:
				# 回合割地上限：许诺不得超过本回合余额（防无限割地）
				var cede_eff: int = mini(cede, State.cede_allowance(speaker))
				pending_proposal = {"from": speaker, "to": target, "text": text, "kind": "", "cede": cede_eff}
				var cede_s: String = ("，并许割%d城" % cede_eff) if cede_eff > 0 else ""
				State.add_ledger("propose", speaker, target, "%s向%s提议：%s%s" % [_country_name_short(speaker), _country_name_short(target), text.left(24), cede_s])
		"应允":
			if String(pending_proposal.get("to", "")) == speaker:
				var from_c: String = String(pending_proposal.get("from", ""))
				var kind: String = String(pending_proposal.get("kind", ""))
				if kind == "alliance":
					# 军事同盟：统一入口（含中立约毁约判定 + 战时驰援与重评估）
					note = String(WarManager.form_alliance(from_c, speaker))
					# 质城条款（危局求盟以城为质）：盟成即划转
					var zhi: int = mini(int(pending_proposal.get("cede", 0)), State.cede_allowance(from_c))
					if zhi > 0 and State.has_alliance(from_c, speaker):
						var zhi_moved: int = State.transfer_cities(from_c, speaker, zhi, "cede")
						if zhi_moved > 0:
							State.register_cede(from_c, zhi_moved)
							State.register_deal(from_c, speaker)
							note = _join_note(note, "%s纳质%d城予%s" % [_country_name_short(from_c), zhi_moved, _country_name_short(speaker)])
				elif int(pending_proposal.get("cede", 0)) > 0 and not State.can_deal(speaker, from_c):
					# 每对国家每回合至多一单资源交易
					State.add_ledger("refuse", speaker, from_c, "%s愿应而岁约已满，事缓来日" % _country_name_short(speaker))
					note = "%s与%s本回合已有成约，兹事缓议" % [_country_name_short(speaker), _country_name_short(from_c)]
				else:
					var already: bool = State.has_pact(speaker, from_c)
					State.add_ledger("pact", speaker, from_c, "%s应%s之议，两邦成约" % [_country_name_short(speaker), _country_name_short(from_c)])
					if not already and arb != null and arb.has_method("settle_chat_pact"):
						note = String(arb.settle_chat_pact(speaker, from_c).get("note", ""))
					# 割城条款兑现（受回合余额约束）：城池真转移 → 地图翻格
					var deal_cede: int = mini(int(pending_proposal.get("cede", 0)), State.cede_allowance(from_c))
					if deal_cede > 0 and from_c in COUNTRIES:
						var moved: int = State.transfer_cities(from_c, speaker, deal_cede, "cede")
						if moved > 0:
							State.register_cede(from_c, moved)
							State.register_deal(from_c, speaker)
							note = _join_note(note, "%s践约割%d城予%s" % [_country_name_short(from_c), moved, _country_name_short(speaker)])
					# 利诱成交 → 受利方立中立之约（约内结军事同盟 = 毁约）
					if kind == "lure":
						var until: int = State.current_round + 2
						State.set_neutral_deal(speaker, from_c, until)
						State.add_ledger("pact", speaker, from_c, "%s受%s之利，立中立之约（至第%d回合）" % [_country_name_short(speaker), _country_name_short(from_c), until])
						note = _join_note(note, "%s立中立之约（至第%d回合）" % [_country_name_short(speaker), until])
				pending_proposal = {}
		"拒绝":
			if String(pending_proposal.get("to", "")) == speaker:
				var from_c2: String = String(pending_proposal.get("from", ""))
				State.add_ledger("refuse", speaker, from_c2, "%s拒%s之议" % [_country_name_short(speaker), _country_name_short(from_c2)])
				pending_proposal = {}
		"威胁":
			if target in COUNTRIES:
				State.add_ledger("threat", speaker, target, "%s扬言胁%s" % [_country_name_short(speaker), _country_name_short(target)])
				if _threat_settled_count < 2 and arb != null and arb.has_method("settle_chat_threat"):
					note = String(arb.settle_chat_threat(speaker, target).get("note", ""))
					_threat_settled_count += 1
	if note != "":
		emit_signal("chat_settled", note)
	return note

static func _join_note(a: String, b: String) -> String:
	if a == "":
		return b
	return a + "；" + b

# === 决策层交易注入朝议（利诱/求盟走同一套应答机制；被提议方下一条优先发言） ===
func inject_proposal(from_c: String, to_c: String, text: String, kind: String, cede: int) -> bool:
	if not (from_c in COUNTRIES and to_c in COUNTRIES) or from_c == to_c:
		return false
	if not pending_proposal.is_empty():
		return false
	# 回合割地上限：报价不得超过余额；余额不足的割城报价直接不成立
	var cede_eff: int = mini(clampi(cede, 0, 3), State.cede_allowance(from_c))
	if cede > 0 and cede_eff <= 0:
		return false
	pending_proposal = {
		"from": from_c, "to": to_c, "text": text,
		"kind": kind, "cede": cede_eff
	}
	var extra: String = ""
	if cede > 0:
		extra += "，许割%d城" % cede
	State.add_ledger("propose", from_c, to_c, "%s向%s提议：%s%s" % [_country_name_short(from_c), _country_name_short(to_c), text.left(24), extra])
	var entry: Dictionary = {
		"country": from_c, "target": to_c, "text": text,
		"intent": "提议", "visible_to": [from_c, to_c], "public": false
	}
	chat_history.append(entry)
	if chat_history.size() > CHAT_HISTORY_MAX:
		chat_history.pop_front()
	recent_actions.append({
		"actor": from_c, "target_country": to_c,
		"action_type": "chat", "round": 0,
		"narrative": "[朝议·提议] " + text
	})
	if recent_actions.size() > 12:
		recent_actions.pop_front()
	emit_signal("chat_message", from_c, to_c, text, false)
	return true

# 立即应答挂起的提议（齐·待价而沽用）：合成一条朝议应答并结算
func answer_pending(country: String, accept: bool) -> String:
	if String(pending_proposal.get("to", "")) != country:
		return ""
	var from_c: String = String(pending_proposal.get("from", ""))
	var text: String = "可。此价孤受了，便依此议。" if accept else "价码不足，孤不应。"
	var intent: String = "应允" if accept else "拒绝"
	var entry: Dictionary = {
		"country": country, "target": from_c, "text": text,
		"intent": intent, "visible_to": [country, from_c], "public": false
	}
	chat_history.append(entry)
	if chat_history.size() > CHAT_HISTORY_MAX:
		chat_history.pop_front()
	emit_signal("chat_message", country, from_c, text, false)
	return _settle_chat_intent(country, from_c, text, intent, 0)

func _schedule_next_chat() -> void:
	if not chat_active:
		return
	if _chat_timer == null:
		return
	if _chat_timer.time_left > 0:
		return  # 已经在等
	_chat_timer.wait_time = CHAT_INTERVAL_SEC
	_chat_timer.start()

# 该君主的上一条朝议发言
func _last_chat_entry_by(country: String) -> Dictionary:
	for i in range(chat_history.size() - 1, -1, -1):
		var d: Dictionary = chat_history[i]
		if String(d.get("country", "")) == country:
			return d
	return {}

# 该君主可见的朝议近闻（供决策 prompt 用，格式化为行）
func _chat_lines_for(country: String, max_n: int = 3) -> Array:
	var vis: Array = _visible_chat_history_for(country)
	var out: Array = []
	for i in range(max(0, vis.size() - max_n), vis.size()):
		var d: Dictionary = vis[i]
		var tgt: String = String(d.get("target", ""))
		var to_s: String = "谓众" if (tgt == "" or tgt == "all") else ("谓" + _country_name_short(tgt))
		var it: String = String(d.get("intent", ""))
		var it_s: String = ("·" + it) if it != "" else ""
		out.append("%s%s%s：%s" % [_country_name_short(String(d.get("country", ""))), to_s, it_s, String(d.get("text", ""))])
	return out

# 返回该君主可见的历史（自己发的 + 公聊 + 目标是自己的私聊 + 第三方漏听到的）
func _visible_chat_history_for(country: String) -> Array:
	var out: Array = []
	for h in chat_history:
		var d: Dictionary = h
		var vis: Array = d.get("visible_to", [])
		if country in vis:
			out.append(d)
	return out

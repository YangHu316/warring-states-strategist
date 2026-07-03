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

# 聊天室（v7.3.8）
var _chat_timer: Timer = null
var chat_history: Array = []
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

func reset() -> void:
	active = false
	country_round.clear()
	country_state.clear()
	country_last_action.clear()
	recent_actions.clear()
	chat_history.clear()
	player_stance = ""
	_pending_r2 = false
	for c in COUNTRIES:
		var ai = ais.get(c, null)
		if ai != null and ai.has_method("reset_run_state"):
			ai.reset_run_state()
	if _round_timer != null and _round_timer.time_left > 0:
		_round_timer.stop()
	if _chat_timer != null and _chat_timer.time_left > 0:
		_chat_timer.stop()

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
		"country_attrs": State.country_attrs,
		"player_attrs": State.player_attrs,
		"player_stance": player_stance,
		"opponents_history": recent_actions.duplicate(),
		"me_last_action": country_last_action.get(country, {})
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
		"country_attrs": State.country_attrs,
		"player_attrs": State.player_attrs,
		"player_stance": player_stance,
		"opponents_history": recent_actions.duplicate(),
		"me_last_action": country_last_action.get(country, {})
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
		"narrative": "纵横家面见%s：%s（%s）" % [_country_name_short(audience_country), player_summary, verdict]
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
		"country_attrs": State.country_attrs,
		"player_attrs": State.player_attrs,
		"player_stance": player_stance,
		"opponents_history": recent_actions.duplicate(),
		"me_last_action": country_last_action.get(current, {}),
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

# === 聊天室（v7.3.8） ===
func _on_chat_timer() -> void:
	if not active:
		return
	# 随机选一个君主发言
	var speaker: String = COUNTRIES[randi() % COUNTRIES.size()]
	var ai = ais.get(speaker, null)
	if ai == null or not ai.has_method("chat_speak_async"):
		_schedule_next_chat()
		return
	var ctx: Dictionary = {
		"key_event_tag": key_event_tag,
		"key_event_text": key_event_text,
		"country_attrs": State.country_attrs,
		"player_stance": player_stance,
		"chat_history": _visible_chat_history_for(speaker),
		"recent_actions": recent_actions.duplicate()
	}
	# 保底：无论回调是否触发，10s 后强制排下一条（防 LLM hang）
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
		if not active:
			return
		var target: String = String(msg.get("target", ""))
		var text: String = String(msg.get("text", ""))
		if text != "":
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
				"visible_to": visible_to, "public": is_public
			}
			chat_history.append(entry)
			if chat_history.size() > CHAT_HISTORY_MAX:
				chat_history.pop_front()
			recent_actions.append({
				"actor": speaker, "target_country": target,
				"action_type": "chat", "round": 0,
				"narrative": "[朝议] " + text
			})
			if recent_actions.size() > 12:
				recent_actions.pop_front()
			emit_signal("chat_message", speaker, target, text, is_public)
		_do_next.call()
	)

func _schedule_next_chat() -> void:
	if not active:
		return
	if _chat_timer == null:
		return
	if _chat_timer.time_left > 0:
		return  # 已经在等
	_chat_timer.wait_time = CHAT_INTERVAL_SEC
	_chat_timer.start()

# 返回该君主可见的历史（自己发的 + 公聊 + 目标是自己的私聊 + 第三方漏听到的）
func _visible_chat_history_for(country: String) -> Array:
	var out: Array = []
	for h in chat_history:
		var d: Dictionary = h
		var vis: Array = d.get("visible_to", [])
		if country in vis:
			out.append(d)
	return out

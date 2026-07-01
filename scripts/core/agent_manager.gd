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

func _ready() -> void:
	ais["qin"] = MonarchAIScript.make("qin")
	ais["zhao"] = MonarchAIScript.make("zhao")
	ais["qi"] = MonarchAIScript.make("qi")
	_round_timer = Timer.new()
	_round_timer.one_shot = true
	add_child(_round_timer)
	_round_timer.timeout.connect(_on_round_timer)

# === 生命周期 ===
func start_free_phase(event_tag: String = "", event_text: String = "") -> void:
	key_event_tag = event_tag
	key_event_text = event_text
	active = true
	player_stance = ""
	recent_actions.clear()
	for c in COUNTRIES:
		country_round[c] = 0
		country_state[c] = "running"
		country_last_action[c] = {}
	_pending_r2 = false
	_round_timer.wait_time = 1.0
	_round_timer.start()

func reset() -> void:
	active = false
	country_round.clear()
	country_state.clear()
	country_last_action.clear()
	recent_actions.clear()
	player_stance = ""
	_pending_r2 = false
	for c in COUNTRIES:
		var ai = ais.get(c, null)
		if ai != null and ai.has_method("reset_run_state"):
			ai.reset_run_state()
	if _round_timer != null and _round_timer.time_left > 0:
		_round_timer.stop()

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

# 面谈反应轮（群体智能）：面谈国已表态 → 另 2 国**链式**反应
# audience_country: 玩家刚见过的国
# verdict: "accept" / "reject"
# player_summary: 一句话摘要（玩家意图）
# 链式：先随机选一国 A 反应 → 事件流广播 → B 基于 A 的动作再反应
func trigger_reaction_round(audience_country: String, verdict: String, player_summary: String) -> void:
	var others: Array = []
	for c in COUNTRIES:
		if c != audience_country:
			others.append(c)
	if others.size() < 2:
		return
	# 随机决定谁先反应
	if randi() % 2 == 1:
		var tmp = others[0]
		others[0] = others[1]
		others[1] = tmp
	# 记录一条"面谈已发生"作为 opponents_history 里的特殊 entry，供反应时读到
	recent_actions.append({
		"actor": audience_country,
		"target_country": "",
		"action_type": "audience_" + verdict,
		"round": 0,
		"narrative": "纵横家面见%s：%s（%s）" % [_country_name_short(audience_country), player_summary, "采纳" if verdict == "accept" else "拒绝"]
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

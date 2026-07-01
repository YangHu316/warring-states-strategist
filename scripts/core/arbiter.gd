extends Node
# V2 仲裁器 Autoload。负责：roll_card / parse_dialogue / apply_drift / check_ending / judge_mbti

# === 几率 ===
func roll_card(card_id: String, direction: String, target_country: String) -> Dictionary:
	var result: Dictionary = {
		"success": false,
		"deltas_player": {},
		"deltas_country": {},
		"intel": ""
	}
	var card: Card = _find_card(card_id)
	if card == null:
		push_warning("Arbiter.roll_card: unknown card %s" % card_id)
		return result

	# audience / intel 不走 roll
	if card_id == "audience" or card_id == "intel":
		result["success"] = true
		return result

	var base: int = int(card.base_rate)
	var coef: float = float(card.scale_coef)
	var attr: String = String(card.scale_attr)
	var attr_val: int = int(State.player_attrs.get(attr, 0))
	var rate: int = int(round(float(base) + float(attr_val) * coef))
	rate = clampi(rate, 5, 95)

	var roll: int = randi() % 100
	var success: bool = roll < rate
	result["success"] = success

	if not success:
		var on_fail: Dictionary = card.raw.get("on_fail", {"mingwang": -3})
		result["deltas_player"] = on_fail.duplicate()
		return result

	# 成功处理
	match card_id:
		"persuade", "message", "promise":
			var on_succ: Dictionary = card.raw.get("on_success", {})
			var dir_deltas: Variant = on_succ.get(direction, null)
			if typeof(dir_deltas) == TYPE_DICTIONARY:
				result["deltas_player"] = (dir_deltas as Dictionary).duplicate()
			else:
				# fallback neutral
				var fb: Variant = on_succ.get("neutral", {})
				if typeof(fb) == TYPE_DICTIONARY:
					result["deltas_player"] = (fb as Dictionary).duplicate()
		"alienate":
			var mengxin: int = int(State.country_attrs.get(target_country, {}).get("mengxin", 0))
			if mengxin > 30:
				var d1: Dictionary = card.raw.get("on_success_high_mengxin", {})
				result["deltas_player"] = d1.duplicate()
			else:
				var d2: Dictionary = card.raw.get("on_success_low_mengxin", {})
				result["deltas_player"] = d2.duplicate()
		"spy":
			var on_succ2: Dictionary = card.raw.get("on_success", {"xinji": 3})
			result["deltas_player"] = on_succ2.duplicate()
			result["intel"] = _gen_intel(target_country)
		_:
			pass
	return result

# === Agent 动作 → 国家三维结算（v7.3 §03-2.2） ===
# 输入 action: {actor, target_country, action_type, ...}
# 依设计表结算所有相关国家的三维变动。
# 返回：{deltas: {country: {attr:delta}}, note}
func settle_agent_action(action: Dictionary) -> Dictionary:
	var actor: String = String(action.get("actor", ""))
	var target: String = String(action.get("target_country", ""))
	var atype: String = String(action.get("action_type", ""))
	var deltas: Dictionary = {}

	match atype:
		"pressure":
			# 秦军事施压：目标国威 −5，秦战心 +3
			_add_delta(deltas, target, {"guowei": -5})
			_add_delta(deltas, actor, {"zhanxin": 3})
		"alienate":
			# 秦遣使离间：目标与另一国盟信 −8（离间目标是"某国 vs 另一国"，简化为目标国盟信 −8）
			_add_delta(deltas, target, {"mengxin": -8})
			# 另一非施动方也 −4（连锁）
			for c in ["qin", "zhao", "qi"]:
				if c != actor and c != target:
					_add_delta(deltas, c, {"mengxin": -4})
					break
		"lure":
			# 连横利诱：目标盟信向秦 +5（简化为目标 mengxin +5，代表投向秦）
			# 但同时该目标"疏远"另一非秦国 → 另一国 mengxin −3
			_add_delta(deltas, target, {"mengxin": 5})
			for c in ["qin", "zhao", "qi"]:
				if c != actor and c != target:
					_add_delta(deltas, c, {"mengxin": -3})
					break
		"prepare":
			# 备战/备战固境：己国威 +3 己战心 +5
			_add_delta(deltas, actor, {"guowei": 3, "zhanxin": 5})
		"seek_alliance":
			# 求盟联齐：双方盟信 +5
			_add_delta(deltas, actor, {"mengxin": 5})
			_add_delta(deltas, target, {"mengxin": 5})
		"probe":
			# 遣使试探：不改数值（获取意图）
			pass
		"observation":
			# 观望渔利：己战心 −2 己盟信 −2
			_add_delta(deltas, actor, {"zhanxin": -2, "mengxin": -2})
		"wait_price":
			# 待价而沽：与出价方盟信 +5（target 即出价方）
			_add_delta(deltas, target, {"mengxin": 5})
			_add_delta(deltas, actor, {"mengxin": 5})
		"hijack":
			# 趁火打劫：对方国威 −3 己国威 +2
			_add_delta(deltas, target, {"guowei": -3})
			_add_delta(deltas, actor, {"guowei": 2})
		"self_protect":
			# 闭门自保：无变化
			pass
		_:
			pass

	# 应用到 State
	for country in deltas.keys():
		var d: Dictionary = deltas[country]
		if not d.is_empty():
			State.apply_country_delta(country, d)

	return {"deltas": deltas, "note": _describe_delta(actor, atype, target, deltas)}

func _add_delta(deltas: Dictionary, country: String, d: Dictionary) -> void:
	if country == "":
		return
	if not deltas.has(country):
		deltas[country] = {}
	var cur: Dictionary = deltas[country]
	for k in d.keys():
		cur[k] = int(cur.get(k, 0)) + int(d[k])
	deltas[country] = cur

func _describe_delta(actor: String, atype: String, target: String, deltas: Dictionary) -> String:
	var frags: Array = []
	for c in deltas.keys():
		var d: Dictionary = deltas[c]
		var parts: Array = []
		for k in d.keys():
			var v: int = int(d[k])
			var sign_str: String = "+" if v >= 0 else ""
			parts.append("%s%s%d" % [_attr_label(k), sign_str, v])
		if parts.size() > 0:
			frags.append("%s[%s]" % [_country_name(c), ", ".join(parts)])
	return " ".join(frags)

func _attr_label(k: String) -> String:
	match k:
		"guowei": return "国威"
		"mengxin": return "盟信"
		"zhanxin": return "战心"
		_: return k

static func _country_name(c: String) -> String:
	match c:
		"qin": return "秦"
		"zhao": return "赵"
		"qi": return "齐"
		_: return c

# mock 兜底：LLM 断线时用。宽容度高一些，不要一律 reject。
# 综合分 = 长度分(0-4) + 关键词分(0-4) + 基线(2)，落在 [2, 10]
func parse_dialogue(text: String, monarch: String, direction: String) -> Dictionary:
	var t: String = text.strip_edges()
	var length_score: float = 0.0
	if t.length() >= 60:
		length_score = 4.0
	elif t.length() >= 30:
		length_score = 2.5
	elif t.length() >= 10:
		length_score = 1.0

	var kw_score: float = 0.0
	var accept_kws: Array = ["合纵", "抗秦", "结盟", "联齐", "联赵", "共抗", "唇齿", "唯有", "必须", "应", "当", "宜", "可"]
	var reject_kws: Array = ["投降", "不敢", "算了", "退兵", "臣服", "不能", "不愿", "无法"]
	for k in accept_kws:
		if t.find(k) >= 0:
			kw_score += 0.8
	for k in reject_kws:
		if t.find(k) >= 0:
			kw_score -= 1.5
	kw_score = clampf(kw_score, -3.0, 4.0)

	var score: float = clampf(2.0 + length_score + kw_score, 0.5, 9.5)
	var verdict: String = "accept" if score >= 6.0 else "reject"

	return {
		"verdict": verdict,
		"comp": score,
		"stance": score,
		"pers": score,
		"score": score
	}

# === 漂移 ===
func apply_drift() -> void:
	var pd: Dictionary = {"hezong": -4, "xinji": -3}
	if not State.acted_this_turn:
		pd["mingwang"] = -2
	State.apply_player_delta(pd)
	State.apply_country_delta("qin",  {"guowei": 5})
	State.apply_country_delta("zhao", {"guowei": 2, "mengxin": -2})
	State.apply_country_delta("qi",   {"guowei": 2, "mengxin": -2})

# === 终局 ===
func check_ending() -> Dictionary:
	var death_key: String = State.check_death()
	if death_key != "":
		return {"type": "death", "detail": death_key, "mbti_type": judge_mbti()}
	if State.current_round < State.max_round:
		return {"type": "none", "detail": "", "mbti_type": ""}
	var zhao_mx: int = int(State.country_attrs.get("zhao", {}).get("mengxin", 0))
	var qi_mx: int   = int(State.country_attrs.get("qi",   {}).get("mengxin", 0))
	var qin_gw: int  = int(State.country_attrs.get("qin",  {}).get("guowei", 0))
	var situation: String = "undecided"
	if zhao_mx >= 55 and qi_mx >= 55 and qin_gw <= 75:
		situation = "alliance_victory"
	elif (zhao_mx <= 30 or qi_mx <= 30) and qin_gw >= 80:
		situation = "lianheng_victory"
	return {"type": "situation", "detail": situation, "mbti_type": judge_mbti()}

# === 立场判定（v7.3.1） ===
func judge_stance() -> String:
	var hz: int = int(State.stance_scores.get("hezong", 0))
	var nt: int = int(State.stance_scores.get("neutral", 0))
	var qn: int = int(State.stance_scores.get("qin", 0))
	if hz > nt and hz > qn:
		return "hezong"
	if qn > nt and qn > hz:
		return "qin"
	if nt >= hz and nt >= qn:
		return "neutral"
	return "neutral"

func judge_mbti() -> String:
	return judge_stance()

# === 内部 ===
func _find_card(card_id: String) -> Card:
	for c in State.all_cards:
		if c != null and String(c.id) == card_id:
			return c as Card
	return null

func _gen_intel(target_country: String) -> String:
	var gw: int = int(State.country_attrs.get(target_country, {}).get("guowei", 0))
	var mx: int = int(State.country_attrs.get(target_country, {}).get("mengxin", 0))
	var zx: int = int(State.country_attrs.get(target_country, {}).get("zhanxin", 0))
	return "[情报]%s: 国威=%d 盟信=%d 战心=%d" % [target_country, gw, mx, zx]

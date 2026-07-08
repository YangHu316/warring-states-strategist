extends Node
# 仲裁器 Autoload（RFC-003 v7.4.0）。负责：roll_card / 世界数值结算 / apply_drift / check_ending / judge_stance
# 一切行动（玩家打牌、君主博弈、面谈立场）统一结算到 State.world_attrs 三维。

const _ATTR_LABELS: Dictionary = {
	"qin_baye": "秦之霸业",
	"liu_guo_meng": "六国之盟",
	"tian_xia_fenluan": "天下纷乱"
}

const _ACTION_CN: Dictionary = {
	"pressure": "军事施压", "alienate": "遣使离间", "lure": "连横利诱", "prepare": "备战",
	"seek_alliance": "求盟联齐", "probe": "遣使试探", "observation": "观望",
	"wait_price": "待价而沽", "hijack": "趁火打劫", "self_protect": "闭门自保",
	"declare_war": "兴兵"
}

# === 打牌判定：rate = base_rate + 情报牌加成（RFC-003 §5.2 方案 A，无属性加成） ===
func roll_card(card_id: String, direction: String, target_country: String, intel_bonus: int = 0) -> Dictionary:
	var result: Dictionary = {
		"success": false,
		"deltas_world": {},
		"intel": "",
		"rate": 0
	}
	var card: Card = _find_card(card_id)
	if card == null:
		push_warning("Arbiter.roll_card: unknown card %s" % card_id)
		return result

	if card_id == "audience" or card_id == "intel":
		result["success"] = true
		return result

	var rate: int = clampi(int(card.base_rate) + intel_bonus, 5, 95)
	result["rate"] = rate

	var roll: int = randi() % 100
	var success: bool = roll < rate
	result["success"] = success

	if not success:
		var on_fail: Dictionary = card.raw.get("on_fail", {"tian_xia_fenluan": 2})
		result["deltas_world"] = on_fail.duplicate()
		return result

	match card_id:
		"persuade", "message", "promise":
			var on_succ: Dictionary = card.raw.get("on_success", {})
			var dir_deltas: Variant = on_succ.get(direction, null)
			if typeof(dir_deltas) == TYPE_DICTIONARY:
				result["deltas_world"] = (dir_deltas as Dictionary).duplicate()
			else:
				var fb: Variant = on_succ.get("neutral", {})
				if typeof(fb) == TYPE_DICTIONARY:
					result["deltas_world"] = (fb as Dictionary).duplicate()
		"alienate":
			# 时机窗：目标仍在谈判中 → 全额拆盟；已定策 → 只添乱
			var in_talks: bool = false
			var am = get_node_or_null("/root/AgentManager")
			if am != null and am.has_method("is_country_negotiating"):
				in_talks = bool(am.is_country_negotiating(target_country))
			if in_talks:
				result["deltas_world"] = (card.raw.get("on_success_in_talks", {}) as Dictionary).duplicate()
			else:
				result["deltas_world"] = (card.raw.get("on_success_settled", {}) as Dictionary).duplicate()
		"spy":
			result["deltas_world"] = (card.raw.get("on_success", {"tian_xia_fenluan": 1}) as Dictionary).duplicate()
			result["intel"] = _gen_intel(target_country)
		_:
			pass
	return result

# === 君主博弈动作 → 世界数值（RFC-003-A §六；按 actor 分组，prepare/observation 各国含义不同） ===
const MONARCH_ACTION_DELTAS: Dictionary = {
	"qin": {
		"pressure":      {"qin_baye": 4, "tian_xia_fenluan": 3},
		"alienate":      {"liu_guo_meng": -5, "tian_xia_fenluan": 2},
		"lure":          {"qin_baye": 3, "liu_guo_meng": -3},
		"prepare":       {"qin_baye": 4}
	},
	"zhao": {
		"seek_alliance": {"liu_guo_meng": 5},
		"prepare":       {"liu_guo_meng": 2, "tian_xia_fenluan": -1},
		"probe":         {},
		"observation":   {"tian_xia_fenluan": 2}
	},
	"qi": {
		"observation":   {"tian_xia_fenluan": 3},
		"hijack":        {"tian_xia_fenluan": 4},
		"self_protect":  {"tian_xia_fenluan": -1}
	}
}

func settle_agent_action(action: Dictionary) -> Dictionary:
	var actor: String = String(action.get("actor", ""))
	var target: String = String(action.get("target_country", ""))
	var atype: String = String(action.get("action_type", ""))
	var am = get_node_or_null("/root/AgentManager")
	if atype == "declare_war":
		# 宣战交由战争管理器（横幅/账本/军费由其负责）；失败则退化为施压
		if WarManager.declare_war(actor, target):
			return {"deltas": {}, "note": ""}
		atype = "pressure"
	# === 资源型动作：真效果（RFC-004 Phase B；兵力单位=万） ===
	if atype == "prepare":
		State.apply_national_delta(actor, {"troops": 6})
		return {"deltas": {}, "note": "%s募兵整训（兵+6万，今兵%d万）" % [_country_name(actor), State.get_national(actor, "troops")]}
	if atype == "hijack":
		# 趁火打劫：对战后衰弱方（兵<40）真宣战；不具备条件则退化为旧添乱
		if State.get_national(actor, "troops") >= 50:
			for c in ["qin", "zhao", "qi"]:
				if c != actor and State.get_national(c, "troops") < 40 and WarManager.can_declare(actor, c):
					if WarManager.declare_war(actor, c):
						return {"deltas": {}, "note": ""}
		State.apply_world_delta({"tian_xia_fenluan": 4})
		return {"deltas": {"tian_xia_fenluan": 4}, "note": "%s·趁火打劫 → %s" % [_country_name(actor), describe_world_delta({"tian_xia_fenluan": 4})]}
	# === 交易型动作：注入朝议提议，由对方应答（RFC-004 §3.4；报价=城池，不涉财货） ===
	if atype == "lure" and am != null and am.has_method("inject_proposal"):
		# 交兵之国无中立之约可言：利诱自动转向第三方（远交近攻）——兜住 LLM 自选目标
		var wb_l: Dictionary = WarManager.war_brief()
		if not wb_l.is_empty():
			var wa_l: String = String(wb_l.get("attacker", ""))
			var wd_l: String = String(wb_l.get("defender", ""))
			if (actor == wa_l and target == wd_l) or (actor == wd_l and target == wa_l):
				for c3 in ["qin", "zhao", "qi"]:
					if c3 != actor and c3 != target:
						target = c3
						break
		if State.is_neutral_bound(target):
			State.apply_world_delta({"qin_baye": 2})
			return {"deltas": {}, "note": "%s与%s中立之约未满，遣使重申旧好而已" % [_country_name(actor), _country_name(target)]}
		if State.get_national(actor, "cities") < 22 or State.cede_allowance(actor) < 2:
			State.apply_world_delta({"qin_baye": 3, "liu_guo_meng": -3})
			return {"deltas": {}, "note": "%s·连横利诱（无城可许，仅施口惠） → %s" % [_country_name(actor), describe_world_delta({"qin_baye": 3, "liu_guo_meng": -3})]}
		var txt: String = "%s愿以城2座易%s之中立——勿助他国，安享其利。" % [_country_name(actor), _country_name(target)]
		if am.inject_proposal(actor, target, txt, "lure", 2):
			return {"deltas": {}, "note": "%s遣使赍礼入%s，许城2座以易中立（待其答复）" % [_country_name(actor), _country_name(target)]}
		State.apply_world_delta({"qin_baye": 3, "liu_guo_meng": -3})
		return {"deltas": {}, "note": "%s·连横利诱 → %s" % [_country_name(actor), describe_world_delta({"qin_baye": 3, "liu_guo_meng": -3})]}
	if atype == "seek_alliance" and am != null and am.has_method("inject_proposal"):
		if State.has_alliance(actor, target):
			State.apply_world_delta({"liu_guo_meng": 2})
			return {"deltas": {}, "note": "%s遣使巩固与%s之盟好" % [_country_name(actor), _country_name(target)]}
		var txt2: String = "%s愿与%s歃血为盟，共御强敌，同进同退。" % [_country_name(actor), _country_name(target)]
		# 兵临城下的守方求盟：割一城为质，以表诚意（质城随应盟划转）
		var zhi_cede: int = 0
		var wb: Dictionary = WarManager.war_brief()
		if String(wb.get("defender", "")) == actor and int(wb.get("waypoint", 0)) >= 3 \
				and State.cede_allowance(actor) >= 1 and State.get_national(actor, "cities") > 8:
			zhi_cede = 1
			txt2 = "%s愿纳一城为质，与%s歃血为盟——唇亡齿寒，望速发兵！" % [_country_name(actor), _country_name(target)]
		if am.inject_proposal(actor, target, txt2, "alliance", zhi_cede):
			return {"deltas": {}, "note": "%s遣使赴%s请结军事同盟（待其答复）" % [_country_name(actor), _country_name(target)]}
		State.apply_world_delta({"liu_guo_meng": 5})
		return {"deltas": {}, "note": "%s·求盟 → %s" % [_country_name(actor), describe_world_delta({"liu_guo_meng": 5})]}
	if atype == "wait_price" and am != null and am.has_method("answer_pending"):
		# 待价而沽等的是实利：太平时空口盟约不接、纳质之盟半数动心；
		# 但兵祸及身（自己是守方）则救亡高于价码，什么盟都接
		var pp: Dictionary = am.pending_proposal
		var pp_to_me: bool = String(pp.get("to", "")) == actor
		var im_defender: bool = String(WarManager.war_brief().get("defender", "")) == actor
		if pp_to_me and String(pp.get("kind", "")) == "alliance" and not im_defender:
			var pp_zhi: int = int(pp.get("cede", 0))
			if pp_zhi <= 0 or randf() < 0.65:
				var ans_no: String = String(am.answer_pending(actor, false))
				if ans_no != "":
					var why: String = "空口之盟不受" if pp_zhi <= 0 else "一城之质，未足易%s之兵" % _country_name(actor)
					return {"deltas": {}, "note": "%s待价而沽：%s" % [_country_name(actor), why]}
		var ans: String = String(am.answer_pending(actor, true))
		if ans != "":
			return {"deltas": {}, "note": ans}
		State.apply_world_delta({"tian_xia_fenluan": 2})
		return {"deltas": {}, "note": "%s待价而沽，然无人出价" % _country_name(actor)}
	# === 其余动作：舆论余量 ===
	var deltas: Dictionary = (MONARCH_ACTION_DELTAS.get(actor, {}) as Dictionary).get(atype, {})
	if deltas.is_empty():
		return {"deltas": {}, "note": ""}
	State.apply_world_delta(deltas)
	var label: String = String(_ACTION_CN.get(atype, atype))
	return {"deltas": deltas, "note": "%s·%s → %s" % [_country_name(actor), label, describe_world_delta(deltas)]}

# === 面谈立场结算：君主 proposed_action × 玩家立场 → 世界数值（RFC-003-A §五 33 条） ===
# 调参（RFC-003-A §十）：推合纵分支的 qin_baye -2 一律加大到 -3
const PROPOSED_ACTION_MAP: Dictionary = {
	"军事施压": "pressure", "遣使离间": "alienate", "连横利诱": "lure", "备战蓄力": "prepare",
	"求盟联齐": "seek_alliance", "备战固境": "prepare", "遣使试探": "probe", "骑墙观望": "observation",
	"观望渔利": "observation", "待价而沽": "wait_price", "趁火打劫": "hijack", "闭门自保": "self_protect"
}

const STANCE_AWARE_DELTAS: Dictionary = {
	"qin": {
		"pressure": {
			"推合纵": {"qin_baye": -3, "liu_guo_meng": 2, "tian_xia_fenluan": -1},
			"推亲秦": {"qin_baye": 5, "tian_xia_fenluan": 3},
			"中立":   {"qin_baye": 2, "tian_xia_fenluan": 2}
		},
		"alienate": {
			"推合纵": {"liu_guo_meng": 3, "tian_xia_fenluan": -2},
			"推亲秦": {"liu_guo_meng": -8, "qin_baye": 3, "tian_xia_fenluan": 2},
			"中立":   {"liu_guo_meng": -3, "tian_xia_fenluan": 1}
		},
		"lure": {
			"推合纵": {"qin_baye": -3, "liu_guo_meng": 2},
			"推亲秦": {"qin_baye": 4, "liu_guo_meng": -5},
			"中立":   {"qin_baye": 2, "liu_guo_meng": -2}
		},
		"prepare": {
			"推合纵": {"qin_baye": -3, "liu_guo_meng": 2},
			"推亲秦": {"qin_baye": 5},
			"中立":   {"qin_baye": 2}
		}
	},
	"zhao": {
		"seek_alliance": {
			"推合纵": {"liu_guo_meng": 6, "qin_baye": -3},
			"推亲秦": {"qin_baye": 3, "liu_guo_meng": -3},
			"中立":   {"liu_guo_meng": 3}
		},
		"prepare": {
			"推合纵": {"liu_guo_meng": 2, "qin_baye": -1},
			"推亲秦": {"qin_baye": 2, "liu_guo_meng": -2},
			"中立":   {"liu_guo_meng": 1}
		},
		"probe": {
			"推合纵": {"liu_guo_meng": 1},
			"推亲秦": {"qin_baye": 1},
			"中立":   {}
		},
		"observation": {
			"推合纵": {"liu_guo_meng": 3, "tian_xia_fenluan": -1},
			"推亲秦": {"qin_baye": 2, "tian_xia_fenluan": 2},
			"中立":   {"tian_xia_fenluan": 2}
		}
	},
	"qi": {
		"observation": {
			"推合纵": {"liu_guo_meng": 4, "tian_xia_fenluan": -2},
			"推亲秦": {"qin_baye": 2, "tian_xia_fenluan": 2},
			"中立":   {"tian_xia_fenluan": 2}
		},
		"wait_price": {
			"推合纵": {"liu_guo_meng": 3, "qin_baye": -3},
			"推亲秦": {"qin_baye": 3, "liu_guo_meng": -2},
			"中立":   {"qin_baye": 1}
		},
		"hijack": {
			"推合纵": {"liu_guo_meng": 2, "tian_xia_fenluan": -1},
			"推亲秦": {"qin_baye": 2, "tian_xia_fenluan": 3},
			"中立":   {"tian_xia_fenluan": 2}
		},
		"self_protect": {
			"推合纵": {"liu_guo_meng": 3},
			"推亲秦": {"qin_baye": 1},
			"中立":   {"tian_xia_fenluan": -1}
		}
	}
}

func settle_proposed_action_with_stance(monarch: String, proposed_action: String, stance: String, _target: String = "") -> Dictionary:
	var action_id: String = String(PROPOSED_ACTION_MAP.get(proposed_action, proposed_action))
	var deltas_by_stance: Dictionary = (STANCE_AWARE_DELTAS.get(monarch, {}) as Dictionary).get(action_id, {})
	if deltas_by_stance.is_empty():
		# LLM 给出的 action 不在该君主动作集内 → 全表兜底查
		for m in STANCE_AWARE_DELTAS.keys():
			var cand: Dictionary = (STANCE_AWARE_DELTAS[m] as Dictionary).get(action_id, {})
			if not cand.is_empty():
				deltas_by_stance = cand
				break
	# 未知立场（如自定义表态）按中立结算
	var deltas: Dictionary = deltas_by_stance.get(stance, deltas_by_stance.get("中立", {}))
	if deltas.is_empty():
		return {"deltas": {}, "note": "无变化"}
	State.apply_world_delta(deltas)
	var label: String = String(_ACTION_CN.get(action_id, action_id))
	var note: String = "%s·%s（%s）→ %s" % [_country_name(monarch), label, stance, describe_world_delta(deltas)]
	return {"deltas": deltas, "note": note}

func settle_proposed_action(monarch: String, proposed_action: String, target: String = "") -> Dictionary:
	return settle_proposed_action_with_stance(monarch, proposed_action, "中立", target)

# === 朝议成交/威胁 → 世界数值（小额；让说话有后果） ===
func settle_chat_pact(a: String, b: String) -> Dictionary:
	var deltas: Dictionary
	if a == "qin" or b == "qin":
		deltas = {"qin_baye": 2}
	else:
		deltas = {"liu_guo_meng": 2}
	State.apply_world_delta(deltas)
	return {"deltas": deltas, "note": "%s%s盟好初成 → %s" % [_country_name(a), _country_name(b), describe_world_delta(deltas)]}

func settle_chat_threat(a: String, b: String) -> Dictionary:
	var deltas: Dictionary = {"tian_xia_fenluan": 1}
	State.apply_world_delta(deltas)
	return {"deltas": deltas, "note": "%s威逼%s，天下侧目 → %s" % [_country_name(a), _country_name(b), describe_world_delta(deltas)]}

# === 描述工具 ===
func describe_world_delta(deltas: Dictionary) -> String:
	var parts: Array = []
	for k in deltas.keys():
		var v: int = int(deltas[k])
		if v == 0:
			continue
		var sign_str: String = "+" if v >= 0 else ""
		parts.append("%s%s%d" % [String(_ATTR_LABELS.get(k, k)), sign_str, v])
	return " ".join(parts)

static func _country_name(c: String) -> String:
	match c:
		"qin": return "秦"
		"zhao": return "赵"
		"qi": return "齐"
		_: return c

# === 漂移（回合 2/4 开始时，第 6 回合不漂移；含 RFC-003-A §十 调参：秦 +4→+3，乱 +2→+3） ===
func apply_drift() -> void:
	State.apply_world_delta({
		"qin_baye": 3,
		"liu_guo_meng": -3,
		"tian_xia_fenluan": 3
	})
# === 终局（RFC-004 Phase D：实体锚点）===
# 终局看摸得着的东西——城池与军事同盟；派生三维只用来判乱局。
func check_ending() -> Dictionary:
	if State.current_round < State.max_round:
		return {"type": "none", "detail": "", "mbti_type": ""}
	var qc: int = State.get_national("qin", "cities")
	var luan: int = int(State.world_attrs.get("tian_xia_fenluan", 0))
	var situation: String = "undecided"
	if qc >= 28:
		situation = "lianheng_victory"  # 秦净得三城以上（约一场大胜或两场小胜），东出已成
	elif State.has_alliance("zhao", "qi") and qc <= 25:
		situation = "alliance_victory"  # 同盟撑到终局且秦未得寸土
	elif luan >= 80 or int(State.stats.get("wars_started", 0)) >= 4:
		situation = "chaos"  # 四战连绵或乱值爆表：民不聊生
	return {"type": "situation", "detail": situation, "mbti_type": judge_stance()}

# === 立场判定 ===
func judge_stance() -> String:
	var hz: int = int(State.stance_scores.get("hezong", 0))
	var nt: int = int(State.stance_scores.get("neutral", 0))
	var qn: int = int(State.stance_scores.get("qin", 0))
	if hz > nt and hz > qn:
		return "hezong"
	if qn > nt and qn > hz:
		return "qin"
	return "neutral"

func judge_mbti() -> String:
	return judge_stance()

# === 内部 ===
func _find_card(card_id: String) -> Card:
	for c in State.all_cards:
		if c != null and String(c.id) == card_id:
			return c as Card
	return null

# 刺探情报：目标君主当前意图（开视野），无意图记录时回退大势快照
func _gen_intel(target_country: String) -> String:
	var am = get_node_or_null("/root/AgentManager")
	if am != null and am.has_method("get_country_intent"):
		var intent: String = String(am.get_country_intent(target_country))
		if intent != "":
			return "[情报·刺探%s] %s" % [_country_name(target_country), intent]
	var wa: Dictionary = State.world_attrs
	return "[情报·刺探%s] 其国未有动作。天下大势：秦之霸业%d 六国之盟%d 天下纷乱%d" % [
		_country_name(target_country),
		int(wa.get("qin_baye", 0)), int(wa.get("liu_guo_meng", 0)), int(wa.get("tian_xia_fenluan", 0))
	]

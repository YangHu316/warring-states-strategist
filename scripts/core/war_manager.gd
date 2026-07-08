extends Node
# WarManager Autoload（RFC-004 Phase A）
# 宣战 → 三点位行军（①刚出兵 ②行进半途 ③兵临城下）→ 交战/收兵/议和
# 军队的位置就是压力条：节拍自动推进（40s）+ 回合结算强制推进；
# 面谈心证三档经 settle_audience 映射为 收兵/减缓/疾进/求和/结盟驰援。

signal war_declared(war: Dictionary)
signal war_advanced(war: Dictionary)
signal war_slowed(war: Dictionary)
signal war_retreated(war: Dictionary, reason: String)
signal war_resolved(war: Dictionary, result: Dictionary)
signal war_banner(text: String)

const BEAT_SEC: float = 40.0
const WAYPOINT_MAX: int = 3
const COOLDOWN_ROUNDS: int = 2
const WAYPOINT_NAMES: Array = ["", "刚出兵", "行进半途", "兵临城下"]

var active_war: Dictionary = {}   # {attacker, defender, waypoint, round_declared}
var running: bool = false         # 自由行动阶段内节拍才走
var paused: bool = false          # 面谈期间暂停（结算不打断谈判）
var _cooldown: Dictionary = {}    # pair_key -> 可再宣战的回合
var _beat_timer: Timer = null

func _ready() -> void:
	_beat_timer = Timer.new()
	_beat_timer.one_shot = true
	add_child(_beat_timer)
	_beat_timer.timeout.connect(_on_beat)

# === 查询 ===
func has_war() -> bool:
	return not active_war.is_empty()

func waypoint() -> int:
	return int(active_war.get("waypoint", 0))

func war_role(country: String) -> String:
	if not has_war():
		return ""
	if country == String(active_war.get("attacker", "")):
		return "attacker"
	if country == String(active_war.get("defender", "")):
		return "defender"
	return "third"

func war_brief() -> Dictionary:
	if not has_war():
		return {}
	return {
		"attacker": active_war["attacker"],
		"defender": active_war["defender"],
		"waypoint": waypoint(),
		"waypoint_name": String(WAYPOINT_NAMES[waypoint()])
	}

func status_text() -> String:
	if not has_war():
		return ""
	return "%s军伐%s——%s（点位%d/3）" % [
		_cn(String(active_war["attacker"])), _cn(String(active_war["defender"])),
		String(WAYPOINT_NAMES[waypoint()]), waypoint()
	]

func can_declare(attacker: String, defender: String) -> bool:
	if has_war() or attacker == defender:
		return false
	if State.has_alliance(attacker, defender):
		return false  # 盟邦不相攻（欲攻须先毁盟）
	return State.current_round >= int(_cooldown.get(State.pair_key(attacker, defender), 0))

# === 生命周期 ===
func on_free_phase_start() -> void:
	running = true
	paused = false
	if has_war():
		_start_beat(BEAT_SEC)

func on_free_phase_end() -> void:
	running = false
	_beat_timer.stop()

# 回合结算：军队在途则强制推进一格（点3 则交战）——时间不等人
func on_round_settle() -> void:
	if has_war():
		advance("回合更替，大军不待")

func full_reset() -> void:
	active_war = {}
	_cooldown.clear()
	running = false
	paused = false
	_beat_timer.stop()

# === 宣战与行军 ===
func declare_war(attacker: String, defender: String, scripted: bool = false) -> bool:
	if not can_declare(attacker, defender):
		return false
	if not scripted and State.get_national(attacker, "troops") < 50:
		return false
	active_war = {
		"attacker": attacker, "defender": defender,
		"waypoint": 1, "round_declared": State.current_round,
		"reinforce": {}
	}
	State.stats["wars_started"] = int(State.stats.get("wars_started", 0)) + 1
	State.stats["wars_active"] = 1
	State.recompute_world()
	State.add_ledger("war", attacker, defender, "%s兴兵伐%s，大军拔营东进" % [_cn(attacker), _cn(defender)])
	emit_signal("war_declared", active_war.duplicate())
	emit_signal("war_banner", "%s军拔营！兵锋直指%s——" % [_cn(attacker), _cn(defender)])
	if running:
		_start_beat(BEAT_SEC)
	return true

func _start_beat(sec: float) -> void:
	_beat_timer.stop()
	_beat_timer.wait_time = sec
	_beat_timer.start()

func _on_beat() -> void:
	if not has_war():
		return
	if paused or not running:
		_start_beat(8.0)  # 面谈/非自由阶段中挂起，稍后重试
		return
	advance("")

func advance(reason: String = "") -> void:
	if not has_war():
		return
	var wp: int = waypoint()
	if wp >= WAYPOINT_MAX:
		resolve_battle()
		return
	active_war["waypoint"] = wp + 1
	var new_wp: int = wp + 1
	var att: String = String(active_war["attacker"])
	var def: String = String(active_war["defender"])
	var texts: Dictionary = {
		2: "%s军已过半程，%s告急！" % [_cn(att), _cn(def)],
		3: "%s军兵临%s城下——最后的斡旋窗口！" % [_cn(att), _cn(def)]
	}
	emit_signal("war_advanced", active_war.duplicate())
	emit_signal("war_banner", String(texts.get(new_wp, "")) + (("（%s）" % reason) if reason != "" else ""))
	_start_beat(BEAT_SEC)

func slow(reason: String) -> void:
	if not has_war():
		return
	_start_beat(BEAT_SEC * 2.0)
	emit_signal("war_slowed", active_war.duplicate())
	emit_signal("war_banner", "%s军放缓了脚步（%s）" % [_cn(String(active_war["attacker"])), reason])

func hasten(reason: String) -> void:
	if not has_war():
		return
	emit_signal("war_banner", "%s军疾进！（%s）" % [_cn(String(active_war["attacker"])), reason])
	advance(reason)

func retreat(reason: String) -> void:
	if not has_war():
		return
	var war: Dictionary = active_war.duplicate()
	var att: String = String(war["attacker"])
	var def: String = String(war["defender"])
	_cooldown[State.pair_key(att, def)] = State.current_round + COOLDOWN_ROUNDS
	State.add_ledger("war", att, def, "%s军鸣金收兵（%s）" % [_cn(att), reason])
	var back_note: String = _return_reinforcement(false)
	# 因合纵劝退 → 六国之盟涨；其余小幅添乱
	State.stats["wars_active"] = 0
	if reason.find("盟") >= 0 or reason.find("合纵") >= 0 or reason.find("驰援") >= 0 or reason.find("援") >= 0:
		State.apply_world_delta({"liu_guo_meng": 4})
	else:
		State.apply_world_delta({"tian_xia_fenluan": 1})
	active_war = {}
	_beat_timer.stop()
	emit_signal("war_retreated", war, reason)
	emit_signal("war_banner", "%s军鸣金收兵——%s%s" % [_cn(att), reason, ("（%s）" % back_note) if back_note != "" else ""])

# 攻方重评估：援军抵达/情报变化后调用——胜算不足则当众收兵（合纵却敌时刻）
func reevaluate() -> void:
	if not has_war():
		return
	var att: String = String(active_war["attacker"])
	var def: String = String(active_war["defender"])
	var att_power: float = float(State.get_national(att, "troops"))
	var def_power: float = float(State.get_national(def, "troops")) * 1.2 + _reinforce_troops()
	if att_power < def_power:
		retreat("敌援已至，胜算尽失")
	else:
		emit_signal("war_banner", "%s军斥候回报：仍有胜机，行军如故。" % _cn(att))

# 守方援军（驰援时从盟友兵力真实划拨，驻于守方）
func _reinforce_troops() -> float:
	var r: Dictionary = active_war.get("reinforce", {})
	return float(r.get("troops", 0))

# 驰援：盟友划拨半数兵力入守方战场（兵力变化全程可见），战后幸存者归国
func commit_reinforcement(ally: String) -> String:
	if not has_war():
		return ""
	var def: String = String(active_war["defender"])
	if ally == def or ally == String(active_war["attacker"]):
		return ""
	if not (active_war.get("reinforce", {}) as Dictionary).is_empty():
		return ""
	var n: int = int(floor(State.get_national(ally, "troops") * 0.5))
	if n <= 0:
		return ""
	State.apply_national_delta(ally, {"troops": -n})
	active_war["reinforce"] = {"ally": ally, "troops": n}
	State.add_ledger("war", ally, def, "%s发兵%d万驰援%s" % [_cn(ally), n, _cn(def)])
	emit_signal("war_banner", "%s发兵%d万驰援%s！" % [_cn(ally), n, _cn(def)])
	return "%s发兵%d万驰援%s" % [_cn(ally), n, _cn(def)]

# 战争结束归还援军（战斗折损三成，收兵/议和全数归国）
func _return_reinforcement(battle_happened: bool) -> String:
	var r: Dictionary = active_war.get("reinforce", {})
	if r.is_empty():
		return ""
	var ally: String = String(r.get("ally", ""))
	var n: int = int(r.get("troops", 0))
	var loss: int = int(ceil(n * 0.3)) if battle_happened else 0
	var back: int = maxi(n - loss, 0)
	State.apply_national_delta(ally, {"troops": back})
	if loss > 0:
		return "%s援军折损%d万，余部%d万归国" % [_cn(ally), loss, back]
	return "%s援军%d万归国" % [_cn(ally), back]

# === 议和（价码随点位上涨：城1 → 城2 → 城3，早介入便宜，晚介入割肉） ===
func peace_price() -> Dictionary:
	match waypoint():
		1: return {"cities": 1}
		2: return {"cities": 2}
		3: return {"cities": 3}
	return {}

func peace_price_text() -> String:
	var p: Dictionary = peace_price()
	if int(p.get("cities", 0)) > 0:
		return "城%d座" % int(p["cities"])
	return "无"

func make_peace() -> String:
	if not has_war():
		return ""
	var war: Dictionary = active_war.duplicate()
	var att: String = String(war["attacker"])
	var def: String = String(war["defender"])
	var terms: String = peace_price_text()
	var moved: int = State.transfer_cities(def, att, int(peace_price().get("cities", 0)), "peace")
	_cooldown[State.pair_key(att, def)] = State.current_round + COOLDOWN_ROUNDS
	State.stats["wars_active"] = 0
	State.add_ledger("pact", def, att, "%s纳%s以求和，%s罢兵" % [_cn(def), terms, _cn(att)])
	var back_note: String = _return_reinforcement(false)
	State.apply_world_delta({"tian_xia_fenluan": 2, "qin_baye": (3 if att == "qin" else 0)})
	active_war = {}
	_beat_timer.stop()
	var note: String = "%s献%s求和，%s军罢兵" % [_cn(def), terms, _cn(att)]
	if back_note != "":
		note += "（%s）" % back_note
	emit_signal("war_retreated", war, "议和")
	emit_signal("war_banner", note)
	return note + ("，割城 %d 座" % moved if moved > 0 else "")

# === 交战结算（RFC-004 §4.2 五档） ===
func resolve_battle() -> void:
	if not has_war():
		return
	var war: Dictionary = active_war.duplicate()
	var att: String = String(war["attacker"])
	var def: String = String(war["defender"])
	var att_power: float = float(State.get_national(att, "troops")) + float(war.get("momentum", 0)) + randf_range(-10.0, 10.0)
	var def_power: float = float(State.get_national(def, "troops")) * 1.2 + _reinforce_troops() + randf_range(-10.0, 10.0)
	var diff: float = att_power - def_power
	var result: Dictionary = {"attacker": att, "defender": def, "diff": diff}
	var note: String
	if diff >= 30.0:
		var moved: int = State.transfer_cities(def, att, 4)
		State.apply_national_delta(att, {"troops": -10})
		State.apply_national_delta(def, {"troops": -25})
		note = "%s军大破%s师，拔%d城！" % [_cn(att), _cn(def), moved]
		result["outcome"] = "att_major"
	elif diff >= 10.0:
		var moved2: int = State.transfer_cities(def, att, 2)
		State.apply_national_delta(att, {"troops": -15})
		State.apply_national_delta(def, {"troops": -20})
		note = "%s军小胜，夺%s%d城。" % [_cn(att), _cn(def), moved2]
		result["outcome"] = "att_minor"
	elif diff > -10.0:
		State.apply_national_delta(att, {"troops": -15})
		State.apply_national_delta(def, {"troops": -15})
		note = "两军鏖战不分胜负，各自折兵。"
		result["outcome"] = "stalemate"
	elif diff > -30.0:
		State.apply_national_delta(att, {"troops": -25})
		State.apply_national_delta(def, {"troops": -10})
		note = "%s军攻城不克，败退而归。" % _cn(att)
		result["outcome"] = "att_repelled"
	else:
		var back: int = State.transfer_cities(att, def, 1)
		State.apply_national_delta(att, {"troops": -30})
		State.apply_national_delta(def, {"troops": -8})
		note = "%s军溃败！%s乘胜反夺%d城！" % [_cn(att), _cn(def), back]
		result["outcome"] = "att_routed"
	# 大势联动：胜者得势，战火添乱
	var glue: Dictionary = {"tian_xia_fenluan": 5}
	if result["outcome"] in ["att_major", "att_minor"]:
		if att == "qin":
			glue["qin_baye"] = 8
		else:
			glue["liu_guo_meng"] = 6
	elif result["outcome"] in ["att_repelled", "att_routed"]:
		if att == "qin":
			glue["qin_baye"] = -6
			glue["liu_guo_meng"] = 6
		else:
			glue["qin_baye"] = 4
	var back_note: String = _return_reinforcement(true)
	if back_note != "":
		note += "（%s）" % back_note
	State.stats["wars_active"] = 0
	State.apply_world_delta(glue)
	State.add_ledger("war", att, def, note)
	_cooldown[State.pair_key(att, def)] = State.current_round + COOLDOWN_ROUNDS
	active_war = {}
	_beat_timer.stop()
	result["note"] = note
	result["player_instigated"] = bool(war.get("player_instigated", false))
	emit_signal("war_resolved", war, result)
	emit_signal("war_banner", "【战报】" + note)

# === 战时面谈结算（dialogue._apply_outcome 优先路由至此） ===
# 返回 {handled: bool, note: String}
func settle_audience(country: String, stance: String, outcome: String) -> Dictionary:
	if not has_war():
		return {"handled": false, "note": ""}
	var role: String = war_role(country)
	var att: String = String(active_war["attacker"])
	var def: String = String(active_war["defender"])
	match role:
		"attacker":
			if outcome == "采纳":
				if stance == "推亲秦":
					active_war["player_instigated"] = true  # 怂恿归因：战果将记在纵横家头上
					active_war["momentum"] = 12  # 一鼓作气：怂恿之师攻势更锐
					hasten("纵横家怂恿")
					return {"handled": true, "note": "%s王纳言，大军疾进一程，士气大振" % _cn(att)}
				elif stance == "推合纵":
					retreat("纵横家劝和")
					return {"handled": true, "note": "%s王纳言罢兵" % _cn(att)}
				else:
					slow("纵横家劝其持重")
					return {"handled": true, "note": "%s王允诺缓兵观望" % _cn(att)}
			elif outcome == "自决" and stance == "推合纵":
				slow("君主犹疑")
				return {"handled": true, "note": "%s王未允罢兵，然行军放缓" % _cn(att)}
			return {"handled": true, "note": "%s王不为所动，行军如故" % _cn(att)}
		"defender":
			if outcome == "采纳":
				if stance == "推合纵":
					var third: String = _third_country(att, def)
					if State.has_alliance(def, third):
						reevaluate()
						return {"handled": true, "note": "%s%s之盟已立，敌军重估战局" % [_cn(def), _cn(third)]}
					State.add_ledger("propose", def, third, "%s危局中遣使求%s驰援——待纵横家促成" % [_cn(def), _cn(third)])
					return {"handled": true, "note": "%s王纳搬救兵之策，遣使赴%s——先生可代为游说" % [_cn(def), _cn(third)]}
				elif stance == "中立":
					var pn: String = make_peace()
					return {"handled": true, "note": pn}
				else:
					var pn2: String = make_peace()
					State.add_ledger("audience", def, "", "%s王屈意求和，自此侧目事%s" % [_cn(def), _cn(att)])
					return {"handled": true, "note": pn2 + "——%s自此屈意事%s" % [_cn(def), _cn(att)]}
			return {"handled": true, "note": "%s王未决，城头戒备如故" % _cn(def)}
		"third":
			if outcome == "采纳":
				if stance == "推合纵":
					var note3: String = form_alliance(def, country)
					return {"handled": true, "note": note3 + "，战局为之一变"}
				elif stance == "推亲秦":
					State.add_ledger("refuse", country, def, "%s王明言不援%s，坐观成败" % [_cn(country), _cn(def)])
					return {"handled": true, "note": "%s王明言按兵不动" % _cn(country)}
			return {"handled": true, "note": "%s王静观其变" % _cn(country)}
	return {"handled": false, "note": ""}

# 息兵之诺：该国对各方的宣战冷却推迟 n 回合（纳合纵之谏的实体效果）
func impose_truce(country: String, rounds: int) -> void:
	for other in ["qin", "zhao", "qi"]:
		if other == country:
			continue
		var k: String = State.pair_key(country, other)
		_cooldown[k] = maxi(int(_cooldown.get(k, 0)), State.current_round + rounds)

# === 军事同盟统一入口（含毁约判定：中立之约在身者结盟即毁约公示） ===
func form_alliance(a: String, b: String) -> String:
	var notes: Array = []
	for x in [a, b]:
		if State.is_neutral_bound(x):
			var breach_note: String = State.register_breach(x)
			notes.append(breach_note)
			emit_signal("war_banner", breach_note)
	State.set_alliance(a, b, true)
	State.add_ledger("pact", a, b, "%s%s歃血为盟，共御强敌" % [_cn(a), _cn(b)])
	emit_signal("war_banner", "%s%s军事同盟成！" % [_cn(a), _cn(b)])
	# 战时结盟 = 许诺出兵：第三方立即划拨兵力驰援守方（兵力变化可见），再由攻方重评估
	if has_war():
		var def: String = String(active_war["defender"])
		var ally: String = ""
		if a == def and war_role(b) == "third":
			ally = b
		elif b == def and war_role(a) == "third":
			ally = a
		if ally != "":
			var cnote: String = commit_reinforcement(ally)
			if cnote != "":
				notes.append(cnote)
		reevaluate()
	var out: String = "%s%s之盟既成" % [_cn(a), _cn(b)]
	if notes.size() > 0:
		out += "（" + "；".join(notes) + "）"
	return out

func _third_country(a: String, b: String) -> String:
	for c in ["qin", "zhao", "qi"]:
		if c != a and c != b:
			return c
	return ""

static func _cn(c: String) -> String:
	match c:
		"qin": return "秦"
		"zhao": return "赵"
		"qi": return "齐"
		_: return c

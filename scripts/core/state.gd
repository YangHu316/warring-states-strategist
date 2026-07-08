extends Node
# State Autoload — 世界三维 + MBTI + 手牌（RFC-003 v7.4.0）

signal state_initialized
signal world_attrs_changed(attrs: Dictionary)
signal mbti_updated(scores: Dictionary)
signal mingwang_changed(value: int)
signal mingwang_depleted(kind: String)   # "silent_end"(归零) / "famous_death"(爆表)
signal action_points_changed(value: int)
signal action_points_exhausted

enum GameState { BOOT, READY, PLAYING, GAME_OVER }
var current_state: int = GameState.BOOT
var is_ready: bool = false

const INTEL_BONUS_PER_CARD: int = 5

# 世界三维（RFC-004 Phase B 起为混合派生，只读）：
#   结构基座 = f(城池/兵力占比, 盟约档位, 战争与毁约计数)   ← 国力是唯一事实来源
#   话术余量 world_residual = 卡牌/面谈/朝议/事件的舆论修正（apply_world_delta 只写这里）
#   world_attrs = clamp(基座 + 余量)，由 recompute_world() 统一写入
var world_attrs: Dictionary = {
	"qin_baye": 50,        # 秦之霸业：秦国东出 / 连横 / 单极霸权的进展
	"liu_guo_meng": 40,    # 六国之盟：赵齐合纵 / 多极抗秦 / 联盟巩固
	"tian_xia_fenluan": 30 # 天下纷乱：各方观望 / 局部冲突 / 失序
}
var world_residual: Dictionary = {"qin_baye": 0.0, "liu_guo_meng": 0.0, "tian_xia_fenluan": 0.0}

# 结构计数（喂派生公式；WarManager/毁约路径维护）
var stats: Dictionary = {"wars_started": 0, "wars_active": 0, "deals_broken": 0, "pacts_broken": 0}

# 中立之约：accepter -> {"with": 出资方, "until": 失效回合}（约内结军事同盟 = 毁约）
var neutral_deals: Dictionary = {}
# 毁约劣迹：country -> 毁约发生回合（影响他国应约概率与 LLM 语境）
var breach_flags: Dictionary = {}

# 国力（城池 + 兵力；兵力单位=万。财货不入结算——r4 评审删除）
signal national_changed(country: String)

var national: Dictionary = {
	"qin":  {"cities": 25, "troops": 80},
	"zhao": {"cities": 18, "troops": 60},
	"qi":   {"cities": 20, "troops": 45}
}

# 军事同盟（无序对 key "a|b"；战时面谈/求盟促成，触发参战与攻方重评估）
var alliances: Dictionary = {}

# 占领构成（仅供地图翻格显示）：key "home|holder" -> holder 现持有的 home 本土城数
var occupied: Dictionary = {}

# 领土出处账（AI 认知铁案）：key "holder|home" -> {"ceded": 受割让数, "conquered": 攻取数}
var gains: Dictionary = {}

# 回合博弈界限：每国每回合割地上限 / 每对国家每回合资源交易上限
const CEDE_CAP_PER_ROUND: int = 3
var ceded_this_round: Dictionary = {}   # country -> 本回合已割城数
var deals_this_round: Dictionary = {}   # pair_key -> 本回合已成交资源交易数

# === 玩家生存层（RFC-004 Phase C · 无恢复制：用完即结束） ===
# 名望：0–100 命条，归零「无声而终」/爆表「名动天下者死」即死；无自救台阶
var mingwang: int = 50
# 行动力：每回合 10 点，回合更替时补满；当回合耗尽仅不能再行动
const AP_TOTAL: int = 10
var action_points: int = AP_TOTAL
# 君主衔恨（阴谋败露/怠慢/公开与其作对累积；影响心证初值与应约概率）
var grudges: Dictionary = {}        # country -> 怨值
# 最近一次面谈结果（心证初值恩怨修正用）
var last_audience: Dictionary = {}  # country -> "采纳"/"自决"/"拒绝"

func apply_mingwang(delta: int) -> void:
	if delta == 0:
		return
	mingwang = clampi(mingwang + delta, 0, 100)
	emit_signal("mingwang_changed", mingwang)
	if mingwang <= 0:
		emit_signal("mingwang_depleted", "silent_end")
	elif mingwang >= 100:
		emit_signal("mingwang_depleted", "famous_death")

# 边缘加速（每回合开始）：名声自我发酵/墙倒众人推——推向极端，不是恢复
func apply_mingwang_edge() -> void:
	if mingwang >= 80:
		apply_mingwang(2)
	elif mingwang <= 20:
		apply_mingwang(-2)

# 行动力每回合更替时补满（r10：改回合制预算，耗尽只废本回合，不再触发终局）
func refill_action_points() -> void:
	action_points = AP_TOTAL
	emit_signal("action_points_changed", action_points)

func spend_ap(n: int = 1) -> bool:
	if action_points < n:
		return false
	action_points -= n
	emit_signal("action_points_changed", action_points)
	if action_points <= 0:
		emit_signal("action_points_exhausted")
	return true

func add_grudge(country: String, reason: String) -> void:
	grudges[country] = int(grudges.get(country, 0)) + 1
	add_ledger("grudge", country, "", "%s王衔恨于纵横家（%s）" % [_cname(country), reason])

func has_grudge(country: String) -> bool:
	return int(grudges.get(country, 0)) > 0

# MBTI
var stance_scores: Dictionary = {"hezong": 0, "neutral": 0, "qin": 0}
var mbti_scores: Dictionary = {"T":0, "F":0, "S":0, "N":0, "P":0, "J":0, "A":0, "E":0, "neutral":0}
var mbti_answers: Array = []

# 回合
var current_round: int = 1
var max_round: int = 6

# 手牌
var action_hand: Array = []  # Array[Card]
var intel_hand: Array = []  # 情报牌另存（Dictionary）
var pending_intel: Array = []  # 本回合行动产生的情报，回合结束时转入 intel_hand

# 地点 / 状态
var player_location: String = "qin"
var country_states: Dictionary = {"qin":"idle", "zhao":"idle", "qi":"idle"}
var acted_this_turn: bool = false

# 承诺账本：跨回合的盟约/恩怨/定策/纳谏记录（仅游戏重启时清空）
# entry = {round, type("propose"/"pact"/"refuse"/"threat"/"decision"/"audience"), actor, target, text}
var ledger: Array = []
const LEDGER_MAX: int = 18

# 资源缓存（由 DataLoader 填充）
var all_cards: Array = []  # Array[Card]
var all_questions: Array = []
var events: Array = []
var monarch_mock: Dictionary = {}
var endings: Dictionary = {}
var monarch_data: Dictionary = {}

const LEGAL_TRANSITIONS: Dictionary = {
	GameState.BOOT: [GameState.READY],
	GameState.READY: [GameState.PLAYING, GameState.READY],
	GameState.PLAYING: [GameState.GAME_OVER, GameState.READY],
	GameState.GAME_OVER: [GameState.READY]
}

func _ready() -> void:
	is_ready = true
	recompute_world()
	emit_signal("state_initialized")

func change_state(new_state: int) -> bool:
	if current_state == new_state:
		return true
	var allowed: Array = LEGAL_TRANSITIONS.get(current_state, [])
	if new_state in allowed:
		current_state = new_state
		return true
	push_warning("State.change_state: illegal %s -> %s" % [current_state, new_state])
	return false

# === 世界三维（混合派生） ===
# 话术类修正入余量通道；结构变化（国力/盟约/战争）自动触发重算
func apply_world_delta(d: Dictionary) -> void:
	if d == null or d.is_empty():
		return
	for k in d.keys():
		var key: String = String(k)
		if world_residual.has(key):
			world_residual[key] = float(world_residual[key]) + float(d[k])
	recompute_world()

# 时局冷却：纷乱余量随回合消退（旧闻渐冷）；霸/盟余量为结构性承诺，不衰减
func decay_world_residual() -> void:
	world_residual["tian_xia_fenluan"] = float(world_residual.get("tian_xia_fenluan", 0.0)) * 0.75
	recompute_world()

func recompute_world() -> void:
	var totc: float = 0.0
	var tott: float = 0.0
	for c in ["qin", "zhao", "qi"]:
		totc += float(get_national(c, "cities"))
		tott += float(get_national(c, "troops"))
	totc = maxf(totc, 1.0)
	tott = maxf(tott, 1.0)
	# 秦之霸业 = 0.6×城池占比% + 0.6×兵力占比%
	var base_qin: float = 60.0 * float(get_national("qin", "cities")) / totc \
		+ 60.0 * float(get_national("qin", "troops")) / tott
	# 六国之盟 = 盟约档位（军事同盟50 / 通好25 / 无0）+ 0.4×赵齐兵力占比%
	var tier: float = 0.0
	if has_alliance("zhao", "qi"):
		tier = 50.0
	elif has_pact("zhao", "qi"):
		tier = 25.0
	var base_meng: float = tier + 40.0 * (float(get_national("zhao", "troops")) + float(get_national("qi", "troops"))) / tott
	# 天下纷乱 = 进行中战争×15 + 已爆发战争×5 + 违诺×8 + 毁约×10
	var base_luan: float = float(stats.get("wars_active", 0)) * 15.0 + float(stats.get("wars_started", 0)) * 5.0 \
		+ float(stats.get("deals_broken", 0)) * 8.0 + float(stats.get("pacts_broken", 0)) * 10.0
	world_attrs["qin_baye"] = clampi(int(round(base_qin + float(world_residual["qin_baye"]))), 0, 100)
	world_attrs["liu_guo_meng"] = clampi(int(round(base_meng + float(world_residual["liu_guo_meng"]))), 0, 100)
	world_attrs["tian_xia_fenluan"] = clampi(int(round(base_luan + float(world_residual["tian_xia_fenluan"]))), 0, 100)
	emit_signal("world_attrs_changed", world_attrs)

# === 中立之约与毁约 ===
func set_neutral_deal(accepter: String, sponsor: String, until_round: int) -> void:
	neutral_deals[accepter] = {"with": sponsor, "until": until_round}

func is_neutral_bound(country: String) -> bool:
	var nd: Dictionary = neutral_deals.get(country, {})
	return not nd.is_empty() and current_round <= int(nd.get("until", 0))

# 毁约登记（约内结盟等）：计数入派生公式 + 劣迹标记 + 账本
func register_breach(country: String) -> String:
	var nd: Dictionary = neutral_deals.get(country, {})
	var sponsor: String = String(nd.get("with", ""))
	neutral_deals.erase(country)
	stats["pacts_broken"] = int(stats.get("pacts_broken", 0)) + 1
	breach_flags[country] = current_round
	var note: String = "%s毁中立之约（负%s之诺）——天下侧目" % [_cname(country), _cname(sponsor)]
	add_ledger("broken", country, sponsor, note)
	recompute_world()
	return note

func has_breach_record(country: String) -> bool:
	return breach_flags.has(country)

# === 国力 ===
func get_national(country: String, key: String) -> int:
	return int((national.get(country, {}) as Dictionary).get(key, 0))

func apply_national_delta(country: String, d: Dictionary) -> void:
	if not national.has(country) or d == null or d.is_empty():
		return
	var n: Dictionary = national[country]
	for k in d.keys():
		var key: String = String(k)
		if n.has(key):
			var cap: int = 40 if key == "cities" else 100
			n[key] = clampi(int(n[key]) + int(d[k]), 0, cap)
	national[country] = n
	emit_signal("national_changed", country)
	recompute_world()

# 城池守恒转移，返回实际转移数
# mode：出处账目——"cede"=主动割让（交易）/ "peace"=城下之盟（议和）/ "war"=兵锋攻取
func transfer_cities(from_c: String, to_c: String, n: int, mode: String = "war") -> int:
	if not (national.has(from_c) and national.has(to_c)) or n <= 0:
		return 0
	var avail: int = int(national[from_c]["cities"])
	var moved: int = mini(n, avail)
	if moved <= 0:
		return 0
	national[from_c]["cities"] = avail - moved
	national[to_c]["cities"] = int(national[to_c]["cities"]) + moved
	# 占领构成：先归还 to 被 from 占走的本土格，剩余才翻 from 的本土格
	var back_key: String = to_c + "|" + from_c
	var back: int = mini(moved, int(occupied.get(back_key, 0)))
	if back > 0:
		occupied[back_key] = int(occupied[back_key]) - back
		if int(occupied[back_key]) <= 0:
			occupied.erase(back_key)
		_reduce_gains(from_c, to_c, back)
	var rest: int = moved - back
	if rest > 0:
		var take_key: String = from_c + "|" + to_c
		occupied[take_key] = int(occupied.get(take_key, 0)) + rest
		var g_key: String = to_c + "|" + from_c
		var g: Dictionary = gains.get(g_key, {"ceded": 0, "conquered": 0})
		var bucket: String = "conquered" if mode == "war" else "ceded"
		g[bucket] = int(g.get(bucket, 0)) + rest
		gains[g_key] = g
	# 领土变更中央记账（铁案）：出处写明，AI 不得颠倒或否认
	var verb: String
	match mode:
		"cede":
			verb = "%s主动割%d城予%s" % [_cname(from_c), moved, _cname(to_c)]
		"peace":
			verb = "%s献%d城求和于%s（城下之盟）" % [_cname(from_c), moved, _cname(to_c)]
		_:
			verb = "%s兵锋攻取%s之地%d城" % [_cname(to_c), _cname(from_c), moved]
	add_ledger("territory", to_c, from_c, "%s（%s现存城%d，%s现有城%d）" % [
		verb, _cname(from_c), int(national[from_c]["cities"]), _cname(to_c), int(national[to_c]["cities"])
	])
	emit_signal("national_changed", from_c)
	emit_signal("national_changed", to_c)
	recompute_world()
	return moved

# 收复失地时按"先冲攻取、再冲受让"递减对方的出处账
func _reduce_gains(holder: String, home: String, n: int) -> void:
	var key: String = holder + "|" + home
	var g: Dictionary = gains.get(key, {})
	if g.is_empty():
		return
	var c: int = int(g.get("conquered", 0))
	var take: int = mini(n, c)
	g["conquered"] = c - take
	var remain: int = n - take
	if remain > 0:
		g["ceded"] = maxi(int(g.get("ceded", 0)) - remain, 0)
	if int(g.get("conquered", 0)) <= 0 and int(g.get("ceded", 0)) <= 0:
		gains.erase(key)
	else:
		gains[key] = g

# 割地余额（回合博弈界限）
func cede_allowance(country: String) -> int:
	return maxi(CEDE_CAP_PER_ROUND - int(ceded_this_round.get(country, 0)), 0)

func register_cede(country: String, n: int) -> void:
	ceded_this_round[country] = int(ceded_this_round.get(country, 0)) + n

func can_deal(a: String, b: String) -> bool:
	return int(deals_this_round.get(pair_key(a, b), 0)) < 1

func register_deal(a: String, b: String) -> void:
	deals_this_round[pair_key(a, b)] = int(deals_this_round.get(pair_key(a, b), 0)) + 1

func reset_round_limits() -> void:
	ceded_this_round.clear()
	deals_this_round.clear()

# holder 现持有多少 home 的本土城（地图翻格显示用）
func get_occupied(home: String, holder: String) -> int:
	return int(occupied.get(home + "|" + holder, 0))

# 领土实录：各国现城/兵 + 占领构成——喂给全部 LLM prompt 的铁案
func territory_line() -> String:
	var parts: Array = []
	for c in ["qin", "zhao", "qi"]:
		var seg: String = "%s 城%d 兵%d万" % [_cname(c), get_national(c, "cities"), get_national(c, "troops")]
		var holds: Array = []
		for h in ["qin", "zhao", "qi"]:
			if h == c:
				continue
			var g: Dictionary = gains.get(c + "|" + h, {})
			var ceded: int = int(g.get("ceded", 0))
			var conq: int = int(g.get("conquered", 0))
			if ceded > 0:
				holds.append("受%s割让%d城" % [_cname(h), ceded])
			if conq > 0:
				holds.append("夺%s地%d城" % [_cname(h), conq])
		if holds.size() > 0:
			seg += "（" + "、".join(holds) + "）"
		parts.append(seg)
	return " ｜ ".join(parts)

static func _cname(c: String) -> String:
	match c:
		"qin": return "秦"
		"zhao": return "赵"
		"qi": return "齐"
		_: return c

static func pair_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a

func set_alliance(a: String, b: String, on: bool) -> void:
	if on:
		alliances[pair_key(a, b)] = true
	else:
		alliances.erase(pair_key(a, b))
	recompute_world()

func has_alliance(a: String, b: String) -> bool:
	return bool(alliances.get(pair_key(a, b), false))

# === 承诺账本 ===
func add_ledger(type: String, actor: String, target: String, text: String) -> void:
	if text == "":
		return
	ledger.append({"round": current_round, "type": type, "actor": actor, "target": target, "text": text})
	if ledger.size() > LEDGER_MAX:
		_evict_ledger()

# 分级淘汰：例行定策最先挤出，盟约（pact）最后才动——承诺不能比流水账先失忆
func _evict_ledger() -> void:
	for i in range(ledger.size()):
		if String((ledger[i] as Dictionary).get("type", "")) == "decision":
			ledger.remove_at(i)
			return
	for i in range(ledger.size()):
		if String((ledger[i] as Dictionary).get("type", "")) != "pact":
			ledger.remove_at(i)
			return
	ledger.pop_front()

# 与该国相关的账本条目（actor/target 涉及它，或公开条目），格式化为提示行
# 盟约条目必带（不受 max_n 截断），其余按时间取最近
func ledger_lines_for(country: String, max_n: int = 8) -> Array:
	var pacts: Array = []
	var others: Array = []
	for e in ledger:
		var d: Dictionary = e
		var actor: String = String(d.get("actor", ""))
		var target: String = String(d.get("target", ""))
		if country == "" or actor == country or target == country or target == "" or target == "all":
			if String(d.get("type", "")) == "pact":
				pacts.append(d)
			else:
				others.append(d)
	var need: int = max_n - pacts.size()
	if need < 0:
		need = 0
	if others.size() > need:
		others = others.slice(others.size() - need)
	var chosen: Array = pacts + others
	chosen.sort_custom(func(a, b): return int((a as Dictionary).get("round", 0)) < int((b as Dictionary).get("round", 0)))
	var out: Array = []
	for d2 in chosen:
		out.append("[第%d回合] %s" % [int((d2 as Dictionary).get("round", 0)), String((d2 as Dictionary).get("text", ""))])
	return out

func has_pact(a: String, b: String) -> bool:
	for e in ledger:
		var d: Dictionary = e
		if String(d.get("type", "")) != "pact":
			continue
		var x: String = String(d.get("actor", ""))
		var y: String = String(d.get("target", ""))
		if (x == a and y == b) or (x == b and y == a):
			return true
	return false

# === MBTI 录答 ===
func record_mbti_answer(qid: String, dim: String, choice: String) -> void:
	mbti_answers.append({"qid": qid, "dim": dim, "choice": choice})
	if stance_scores.has(choice):
		stance_scores[choice] = int(stance_scores[choice]) + 1
	elif mbti_scores.has(choice):
		mbti_scores[choice] = int(mbti_scores[choice]) + 1
	emit_signal("mbti_updated", stance_scores)

# === 调试 ===
func dump_state() -> String:
	var s := ""
	s += "=== State Dump ===\n"
	s += "round=%d/%d  state=%s  loc=%s  acted=%s\n" % [current_round, max_round, current_state, player_location, str(acted_this_turn)]
	s += "world: qin_baye=%d liu_guo_meng=%d tian_xia_fenluan=%d\n" % [
		int(world_attrs.get("qin_baye",0)),
		int(world_attrs.get("liu_guo_meng",0)),
		int(world_attrs.get("tian_xia_fenluan",0))
	]
	for c in ["qin","zhao","qi"]:
		s += "%s: state=%s\n" % [c, String(country_states.get(c, "idle"))]
	s += "hand: action=%d intel=%d  cards_loaded=%d  events=%d  q=%d\n" % [
		action_hand.size(), intel_hand.size(), all_cards.size(), events.size(), all_questions.size()
	]
	s += "mbti: %s\n" % str(mbti_scores)
	return s

# 旧名兼容
func dump() -> String:
	return dump_state()

func reset() -> void:
	world_residual = {"qin_baye": 0.0, "liu_guo_meng": 0.0, "tian_xia_fenluan": 0.0}
	stats = {"wars_started": 0, "wars_active": 0, "deals_broken": 0, "pacts_broken": 0}
	national = {
		"qin":  {"cities": 25, "troops": 80},
		"zhao": {"cities": 18, "troops": 60},
		"qi":   {"cities": 20, "troops": 45}
	}
	alliances.clear()
	occupied.clear()
	gains.clear()
	neutral_deals.clear()
	breach_flags.clear()
	reset_round_limits()
	mingwang = 50
	action_points = AP_TOTAL
	grudges.clear()
	last_audience.clear()
	recompute_world()
	stance_scores = {"hezong": 0, "neutral": 0, "qin": 0}
	mbti_scores = {"T":0, "F":0, "S":0, "N":0, "P":0, "J":0, "A":0, "E":0, "neutral":0}
	mbti_answers.clear()
	current_round = 1
	action_hand.clear()
	intel_hand.clear()
	pending_intel.clear()
	player_location = "qin"
	country_states = {"qin":"idle", "zhao":"idle", "qi":"idle"}
	acted_this_turn = false
	ledger.clear()

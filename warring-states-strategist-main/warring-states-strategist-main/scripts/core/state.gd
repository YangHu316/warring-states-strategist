extends Node
# V2 State Autoload — 玩家三维 + 国家三维 + MBTI + 手牌

signal state_initialized
signal player_attrs_changed(attrs: Dictionary)
signal country_attrs_changed(country: String, attrs: Dictionary)
signal mbti_updated(scores: Dictionary)

enum GameState { BOOT, READY, PLAYING, GAME_OVER }
var current_state: int = GameState.BOOT
var is_ready: bool = false

const INTEL_BONUS_PER_CARD: int = 5

# 玩家三维
var player_attrs: Dictionary = {"hezong": 40, "mingwang": 50, "xinji": 40}

# 国家三维
var country_attrs: Dictionary = {
	"qin":  {"guowei": 70, "mengxin": 30, "zhanxin": 60},
	"zhao": {"guowei": 50, "mengxin": 60, "zhanxin": 40},
	"qi":   {"guowei": 55, "mengxin": 45, "zhanxin": 25}
}

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

# 资源缓存（由 DataLoader 填充）
var all_cards: Array = []  # Array[Card]
var all_questions: Array = []
var events: Array = []
var monarch_mock: Dictionary = {}
var endings: Dictionary = {}

# 旧 API 桥接（D1.5 main.gd 读 “favor” / “monarch_data” 避免破坏）
var favor: Dictionary = {"qin":50, "zhao":50, "qi":50}
var monarch_data: Dictionary = {}

const LEGAL_TRANSITIONS: Dictionary = {
	GameState.BOOT: [GameState.READY],
	GameState.READY: [GameState.PLAYING, GameState.READY],
	GameState.PLAYING: [GameState.GAME_OVER, GameState.READY],
	GameState.GAME_OVER: [GameState.READY]
}

func _ready() -> void:
	is_ready = true
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

# === 玩家属性 ===
func apply_player_delta(d: Dictionary) -> void:
	if d == null or d.is_empty():
		return
	for k in d.keys():
		var key: String = String(k)
		if player_attrs.has(key):
			var v: int = int(player_attrs[key]) + int(d[k])
			player_attrs[key] = clampi(v, 0, 100)
	emit_signal("player_attrs_changed", player_attrs)

# === 国家属性 ===
func apply_country_delta(country: String, d: Dictionary) -> void:
	if not country_attrs.has(country):
		push_warning("apply_country_delta: unknown country=%s" % country)
		return
	if d == null or d.is_empty():
		return
	var attrs: Dictionary = country_attrs[country]
	for k in d.keys():
		var key: String = String(k)
		if attrs.has(key):
			var v: int = int(attrs[key]) + int(d[k])
			attrs[key] = clampi(v, 0, 100)
	country_attrs[country] = attrs
	emit_signal("country_attrs_changed", country, attrs)

# === 即死检测 ===
func check_death() -> String:
	var hz: int = int(player_attrs.get("hezong", 50))
	var mw: int = int(player_attrs.get("mingwang", 50))
	var xj: int = int(player_attrs.get("xinji", 50))
	if hz <= 0:
		return "suspected_qin_spy"
	if hz >= 100:
		return "hezong_martyr"
	if mw <= 0:
		return "silent_end"
	if mw >= 100:
		return "tall_tree"
	if xj <= 0:
		return "no_move"
	if xj >= 100:
		return "backfire"
	return ""

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
	s += "player: hezong=%d mingwang=%d xinji=%d\n" % [
		int(player_attrs.get("hezong",0)),
		int(player_attrs.get("mingwang",0)),
		int(player_attrs.get("xinji",0))
	]
	for c in ["qin","zhao","qi"]:
		var a: Dictionary = country_attrs.get(c, {})
		s += "%s: guowei=%d mengxin=%d zhanxin=%d state=%s\n" % [
			c, int(a.get("guowei",0)), int(a.get("mengxin",0)), int(a.get("zhanxin",0)),
			String(country_states.get(c, "idle"))
		]
	s += "hand: action=%d intel=%d  cards_loaded=%d  events=%d  q=%d\n" % [
		action_hand.size(), intel_hand.size(), all_cards.size(), events.size(), all_questions.size()
	]
	s += "mbti: %s\n" % str(mbti_scores)
	return s

# 旧名兼容
func dump() -> String:
	return dump_state()

func add_favor(country: String, delta: int) -> void:
	# 旧名兼容（D1.5）：map 到 mengxin
	if favor.has(country):
		favor[country] = clampi(int(favor[country]) + delta, 0, 100)
	apply_country_delta(country, {"mengxin": delta})

func reset() -> void:
	player_attrs = {"hezong": 40, "mingwang": 50, "xinji": 40}
	country_attrs = {
		"qin":  {"guowei": 70, "mengxin": 30, "zhanxin": 60},
		"zhao": {"guowei": 50, "mengxin": 60, "zhanxin": 40},
		"qi":   {"guowei": 55, "mengxin": 45, "zhanxin": 25}
	}
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
	favor = {"qin":50, "zhao":50, "qi":50}

extends CanvasLayer
# 打牌确认弹窗：目标国 + 情报组合 + 方向

signal card_played(direction: String, target: String, intel_indices: Array)

var card: Card = null
var _target: String = ""
var _intel_selected: Dictionary = {}  # idx -> true

@onready var card_info: Label = $Center/Box/VBox/CardInfoLabel
@onready var target_qin: Button = $Center/Box/VBox/TargetHBox/TargetQin
@onready var target_zhao: Button = $Center/Box/VBox/TargetHBox/TargetZhao
@onready var target_qi: Button = $Center/Box/VBox/TargetHBox/TargetQi
@onready var intel_hbox: HBoxContainer = $Center/Box/VBox/IntelScroll/IntelHBox
@onready var rate_label: Label = $Center/Box/VBox/RateLabel
@onready var d1: Button = $Center/Box/VBox/Dir1
@onready var d2: Button = $Center/Box/VBox/Dir2
@onready var d3: Button = $Center/Box/VBox/Dir3
@onready var cancel_btn: Button = $Center/Box/VBox/Cancel

const DIR_LABELS: Dictionary = {
	"push_hezong": "推合纵",
	"push_qin": "推亲秦",
	"neutral": "中立",
	"favor_hezong": "利合纵",
	"favor_lianheng": "利连横",
	"aid": "承诺援助",
	"ally": "承诺结盟"
}
const CN: Dictionary = {"qin": "秦", "zhao": "赵", "qi": "齐"}

func _ready() -> void:
	cancel_btn.pressed.connect(func():
		emit_signal("card_played", "", "", [])
	)
	target_qin.pressed.connect(func(): _pick_target("qin"))
	target_zhao.pressed.connect(func(): _pick_target("zhao"))
	target_qi.pressed.connect(func(): _pick_target("qi"))

func setup(c: Card, default_target: String = "") -> void:
	card = c
	card_info.text = "%s：%s" % [c.name, c.description]
	_pick_target(default_target if default_target != "" else State.player_location)
	_build_intel_list()
	_build_direction_buttons()
	_refresh_rate()

func _pick_target(t: String) -> void:
	_target = t
	target_qin.button_pressed = (t == "qin")
	target_zhao.button_pressed = (t == "zhao")
	target_qi.button_pressed = (t == "qi")
	_refresh_rate()

func _build_intel_list() -> void:
	for child in intel_hbox.get_children():
		child.queue_free()
	_intel_selected.clear()
	for i in range(State.intel_hand.size()):
		var item: Variant = State.intel_hand[i]
		var txt: String = String(item)
		var b := Button.new()
		b.custom_minimum_size = Vector2(180, 70)
		b.toggle_mode = true
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.text = txt
		b.add_theme_font_size_override("font_size", 11)
		var captured_idx: int = i
		b.toggled.connect(func(pressed: bool):
			if pressed:
				_intel_selected[captured_idx] = true
			else:
				_intel_selected.erase(captured_idx)
			_refresh_rate()
		)
		intel_hbox.add_child(b)

func _build_direction_buttons() -> void:
	var dirs: Array = card.directions if card != null else []
	var btns: Array = [d1, d2, d3]
	for i in range(btns.size()):
		var b: Button = btns[i]
		for con in b.pressed.get_connections():
			b.pressed.disconnect(con.callable)
		if not card.requires_direction:
			if i == 0:
				b.text = "确认打出"
				b.visible = true
				b.pressed.connect(func(): _emit(""))
			else:
				b.visible = false
			continue
		if i < dirs.size():
			var dkey: String = String(dirs[i])
			var eff: String = _dir_effect_desc(dkey)
			b.text = String(DIR_LABELS.get(dkey, dkey)) + (("  （" + eff + "）") if eff != "" else "")
			b.visible = true
			var key_str: String = dkey
			b.pressed.connect(func(): _emit(key_str))
		else:
			b.visible = false

func _refresh_rate() -> void:
	if card == null:
		return
	var base_rate: int = int(card.base_rate)
	var bonus: int = _intel_selected.size() * State.INTEL_BONUS_PER_CARD
	var rate: int = clampi(base_rate + bonus, 5, 95)
	var target_disp: String = String(CN.get(_target, _target)) if _target != "" else "未选"
	var extra: String = ""
	if card.id == "alienate":
		var am = get_node_or_null("/root/AgentManager")
		var neg: bool = am != null and am.has_method("is_country_negotiating") and bool(am.is_country_negotiating(_target))
		if neg:
			extra = "\n时机正好：%s谈判中 → 全额拆盟（六国之盟-5 天下纷乱+3）" % target_disp
		else:
			extra = "\n时机已过：%s已定策 → 仅添乱（天下纷乱+2）" % target_disp
	elif card.id == "spy":
		extra = "\n成功：窥知%s君主当前意图（精确情报牌）" % target_disp
	rate_label.text = "目标：%s | 基础 %d%% + 情报×%d = %d%%%s" % [target_disp, base_rate, _intel_selected.size(), rate, extra]

# 该方向成功时的世界数值变化预览
func _dir_effect_desc(dkey: String) -> String:
	if card == null:
		return ""
	var on_succ: Dictionary = card.raw.get("on_success", {})
	var deltas: Variant = on_succ.get(dkey, null)
	if typeof(deltas) != TYPE_DICTIONARY or (deltas as Dictionary).is_empty():
		return ""
	var arb = get_node_or_null("/root/Arbiter")
	if arb != null and arb.has_method("describe_world_delta"):
		return String(arb.describe_world_delta(deltas))
	return ""

func _emit(direction: String) -> void:
	if _target == "":
		rate_label.text = "请先选目标国"
		return
	var indices: Array = _intel_selected.keys()
	emit_signal("card_played", direction, _target, indices)

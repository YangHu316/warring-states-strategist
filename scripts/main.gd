extends Node2D
# V2 Main — 大地图主场景控制器

@onready var top_bar_label: Label = $UILayer/TopBar/TopBarLabel
@onready var key_event_banner: Label = $UILayer/KeyEventBanner
@onready var country_info_panel: PanelContainer = $UILayer/CountryInfoPanel
@onready var country_info_label: Label = $UILayer/CountryInfoPanel/CountryInfoLabel
@onready var event_stream: RichTextLabel = $UILayer/EventStreamPanel/EventStream
@onready var action_cards_hbox: HBoxContainer = $UILayer/HandPanel/HBox/ActionPanel/ActionCardsHBox
@onready var intel_cards_hbox: HBoxContainer = $UILayer/HandPanel/HBox/IntelPanel/IntelScroll/IntelCardsHBox
@onready var next_turn_button: Button = $UILayer/ActionButtonsVBox/NextTurnButton
@onready var dump_button: Button = $UILayer/ActionButtonsVBox/DumpButton
@onready var restart_button: Button = $UILayer/ActionButtonsVBox/RestartButton
@onready var debug_label: Label = $UILayer/DebugLabel
@onready var turn_manager: Node = $TurnManagerNode
@onready var player_icon: Sprite2D = $MapLayer/PlayerIcon
@onready var status_qin: Label = $MapLayer/NodeQin/StatusQin
@onready var status_zhao: Label = $MapLayer/NodeZhao/StatusZhao
@onready var status_qi: Label = $MapLayer/NodeQi/StatusQi
@onready var area_qin: Area2D = $MapLayer/NodeQin/AreaQin
@onready var area_zhao: Area2D = $MapLayer/NodeZhao/AreaZhao
@onready var area_qi: Area2D = $MapLayer/NodeQi/AreaQi


# Chinese font for CJK display support
var _chinese_font: Font

var country_positions: Dictionary = {
	"qin": Vector2(280, 460),
	"zhao": Vector2(800, 340),
	"qi": Vector2(1320, 460)
}

var sfx_play: AudioStream
var sfx_success: AudioStream
var sfx_fail: AudioStream
var sfx_turn: AudioStream
var sfx_death: AudioStream
var _sfx_player: AudioStreamPlayer

var _current_event_tag: String = "default"
var _current_event_text: String = ""
var _moving: bool = false
var _free_phase_started: bool = false

func _ready() -> void:
	# Load Chinese font for dynamic UI
	if ResourceLoader.exists("res://assets/fonts/NotoSansSC-Regular.ttf"):
		_chinese_font = load("res://assets/fonts/NotoSansSC-Regular.ttf")

	_load_sfx()
	_sfx_player = AudioStreamPlayer.new()
	add_child(_sfx_player)

	# DataLoader 信号
	if typeof(DataLoader) == TYPE_OBJECT:
		if DataLoader.loaded:
			_on_data_loaded(true)
		elif not DataLoader.is_connected("data_loaded", Callable(self, "_on_data_loaded")):
			DataLoader.connect("data_loaded", Callable(self, "_on_data_loaded"))

	if turn_manager != null:
		if turn_manager.has_signal("turn_started"):
			turn_manager.connect("turn_started", Callable(self, "_on_turn_started"))
		if turn_manager.has_signal("phase_changed"):
			turn_manager.connect("phase_changed", Callable(self, "_on_phase_changed"))

	next_turn_button.pressed.connect(_on_next_turn_pressed)
	dump_button.pressed.connect(_on_dump_pressed)
	restart_button.pressed.connect(_on_restart_pressed)

	# 点击地图节点 — 采用 input_event
	area_qin.input_event.connect(func(_v, ev, _s): _on_node_click_event("qin", ev))
	area_zhao.input_event.connect(func(_v, ev, _s): _on_node_click_event("zhao", ev))
	area_qi.input_event.connect(func(_v, ev, _s): _on_node_click_event("qi", ev))

	# AgentManager 信号（V3：按国博弈）
	if typeof(AgentManager) == TYPE_OBJECT:
		AgentManager.agent_action.connect(_on_agent_action)
		AgentManager.country_finished.connect(_on_country_finished)
		AgentManager.all_finished.connect(_on_all_finished)

	# State 信号
	if typeof(State) == TYPE_OBJECT:
		State.player_attrs_changed.connect(_on_player_attrs_changed)
		State.country_attrs_changed.connect(_on_country_attrs_changed)

	_refresh_top_bar()
	_update_player_icon()

func _load_sfx() -> void:
	sfx_play = load("res://assets/audio/sfx_card_play.wav")
	sfx_success = load("res://assets/audio/sfx_success.wav")
	sfx_fail = load("res://assets/audio/sfx_fail.wav")
	sfx_turn = load("res://assets/audio/sfx_turn.wav")
	sfx_death = load("res://assets/audio/sfx_death.wav")

func play_sfx(name_str: String) -> void:
	if _sfx_player == null:
		return
	var s: AudioStream = null
	match name_str:
		"play": s = sfx_play
		"success": s = sfx_success
		"fail": s = sfx_fail
		"turn": s = sfx_turn
		"death": s = sfx_death
	if s != null:
		_sfx_player.stream = s
		_sfx_player.play()

func _on_data_loaded(success: bool) -> void:
	if not success:
		debug_label.text = "ERROR: data load failed"
		return
	var llm = get_node_or_null("/root/LLMClient")
	var llm_status: String = "off"
	if llm != null:
		llm_status = "ready" if llm.is_ready() else "no-key"
	debug_label.text = "Ready - Cards:%d MBTI:%d Events:%d | LLM:%s" % [State.all_cards.size(), State.all_questions.size(), State.events.size(), llm_status]
	push_event("[系统] LLM 状态: %s" % llm_status)
	if State.current_state == State.GameState.READY:
		State.change_state(State.GameState.PLAYING)
	call_deferred("_start_round_flow")

func _start_round_flow() -> void:
	_free_phase_started = false
	_show_mbti_questions_for_round()

func _show_mbti_questions_for_round() -> void:
	var qs: Array = []
	for q in State.all_questions:
		if typeof(q) == TYPE_DICTIONARY and int(q.get("round", -1)) == State.current_round:
			var qid: String = String(q.get("id", ""))
			var already: bool = false
			for ans in State.mbti_answers:
				if String(ans.get("qid", "")) == qid:
					already = true
					break
			if not already:
				qs.append(q)
	if qs.is_empty():
		_after_mbti_phase()
		return
	_pop_mbti(qs)

func _pop_mbti(qs: Array) -> void:
	if qs.is_empty():
		_after_mbti_phase()
		return
	var q: Dictionary = qs.pop_front()
	var popup_scene := load("res://scenes/mbti_popup.tscn")
	if popup_scene == null:
		_after_mbti_phase()
		return
	var popup = popup_scene.instantiate()
	add_child(popup)
	if popup.has_method("setup"):
		popup.setup(q)
	if popup.has_signal("answered"):
		popup.answered.connect(func(qid: String, dim: String, choice: String):
			State.record_mbti_answer(qid, dim, choice)
			push_event("[谋士] 回答%s -> %s" % [qid, choice])
			popup.queue_free()
			call_deferred("_pop_mbti", qs)
		)

func _after_mbti_phase() -> void:
	if _free_phase_started:
		return
	_free_phase_started = true
	_resolve_key_event()
	_draw_action_cards()
	_refresh_hand_ui()
	_refresh_top_bar()
	if turn_manager != null:
		turn_manager.start_free_phase()
	next_turn_button.disabled = true
	if typeof(AgentManager) == TYPE_OBJECT:
		AgentManager.start_free_phase(_current_event_tag, _current_event_text)

func _resolve_key_event() -> void:
	var rn: int = State.current_round
	var candidates: Array = []
	for e in State.events:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var rng: Array = e.get("round_range", [1, 6])
		if rng.size() < 2:
			continue
		if rn >= int(rng[0]) and rn <= int(rng[1]):
			candidates.append(e)
	var chosen: Dictionary = {}
	if candidates.size() > 0:
		chosen = candidates[randi() % candidates.size()]
	_current_event_tag = String(chosen.get("state_tag", "default"))
	_current_event_text = String(chosen.get("text", ""))
	key_event_banner.text = _current_event_text
	push_event("[事] " + _current_event_text)

func _draw_action_cards() -> void:
	var pool: Array = []
	for c in State.all_cards:
		if c == null:
			continue
		var cid: String = String(c.id)
		if cid == "intel" or cid == "audience":
			continue
		pool.append(c)
	if pool.is_empty():
		return
	var draw_count: int = 2
	for i in range(draw_count):
		State.action_hand.append(pool[randi() % pool.size()])
	push_event("[抽] 抽 %d 张（手牌共 %d）" % [draw_count, State.action_hand.size()])

func _refresh_hand_ui() -> void:
	for child in action_cards_hbox.get_children():
		child.queue_free()
	for child in intel_cards_hbox.get_children():
		child.queue_free()
	for i in range(State.action_hand.size()):
		var c: Card = State.action_hand[i] as Card
		if c == null:
			continue
		var b := Button.new()
		b.custom_minimum_size = Vector2(110, 130)
		b.text = "%s\n%d%%" % [c.name, _preview_rate(c)]
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(func(): _on_action_card_pressed(i))
		if _chinese_font:
			b.add_theme_font_override("font", _chinese_font)
		action_cards_hbox.add_child(b)
	for i in range(State.intel_hand.size()):
		var item: Variant = State.intel_hand[i]
		var txt: String = String(item) if typeof(item) != TYPE_DICTIONARY else String((item as Dictionary).get("text", "情报"))
		var b2 := Button.new()
		b2.custom_minimum_size = Vector2(160, 60)
		b2.text = txt
		b2.add_theme_font_size_override("font_size", 11)
		b2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if _chinese_font:
			b2.add_theme_font_override("font", _chinese_font)
		intel_cards_hbox.add_child(b2)

func _preview_rate(c: Card) -> int:
	if c == null:
		return 0
	var attr_val: int = int(State.player_attrs.get(c.scale_attr, 0))
	var rate: int = int(round(float(c.base_rate) + float(attr_val) * float(c.scale_coef)))
	return clampi(rate, 5, 95)

func _on_action_card_pressed(idx: int) -> void:
	if idx < 0 or idx >= State.action_hand.size():
		return
	var c: Card = State.action_hand[idx] as Card
	if c == null:
		return
	_pop_card_modal(c, idx, State.player_location, false, "")

# unified: 打牌确认 modal（选目标 + 情报组合 + 方向）
# is_active_audience: 若为 true，成功后打开面谈自输模式；失败仅名望-3
func _pop_card_modal(c: Card, idx: int, default_target: String, is_active_audience: bool, audience_country: String) -> void:
	var pscn := load("res://scenes/direction_popup.tscn")
	if pscn == null:
		_resolve_card_play(c, idx, "", default_target)
		return
	var pop = pscn.instantiate()
	add_child(pop)
	if pop.has_method("setup"):
		pop.setup(c, default_target)
	if pop.has_signal("card_played"):
		pop.card_played.connect(func(dir: String, target: String, intel_indices: Array):
			pop.queue_free()
			if target == "":
				return
			var success: bool = _resolve_card_play(c, idx, dir, target, intel_indices)
			if is_active_audience:
				if success:
					var was_decided: bool = false
					if typeof(AgentManager) == TYPE_OBJECT:
						was_decided = AgentManager.is_country_decided(audience_country)
						if was_decided and AgentManager.has_method("challenge_decided"):
							AgentManager.challenge_decided(audience_country)
					var mode2: String = "summon" if was_decided else "active"
					_open_dialogue(audience_country, mode2)
				else:
					push_event("[你] 请见%s不成——名望已扣" % _country_name(audience_country))
		)

func _resolve_card_play(c: Card, idx: int, direction: String, target: String, intel_indices: Array = []) -> bool:
	var arb = get_node("/root/Arbiter")
	var intel_bonus: int = intel_indices.size() * State.INTEL_BONUS_PER_CARD
	var res: Dictionary = arb.roll_card(c.id, direction, target, intel_bonus)
	var success: bool = bool(res.get("success", false))
	var dp: Dictionary = res.get("deltas_player", {})
	if dp != null and not dp.is_empty():
		State.apply_player_delta(dp)
	var dc: Dictionary = res.get("deltas_country", {})
	if dc != null and not dc.is_empty():
		State.apply_country_delta(target, dc)
	if idx >= 0 and idx < State.action_hand.size():
		State.action_hand.remove_at(idx)
	# 消耗组合的情报牌（从大到小索引删）
	var sorted_intel = intel_indices.duplicate()
	sorted_intel.sort()
	sorted_intel.reverse()
	for i in sorted_intel:
		if i >= 0 and i < State.intel_hand.size():
			State.intel_hand.remove_at(i)
	State.acted_this_turn = true
	var bonus_txt: String = ("+情报×%d" % intel_indices.size()) if intel_indices.size() > 0 else ""
	var msg: String = "[你] %s%s%s·%s -> %s (%d%%)" % [c.name, ("·" + direction if direction != "" else ""), bonus_txt, target, ("成功" if success else "失败"), int(res.get("rate", 0))]
	push_event(msg)
	if success:
		var placeholder: String = "[情报·%s] %s%s成功" % [_country_name(target), c.name, ("·" + direction if direction != "" else "")]
		var idx_placeholder: int = State.intel_hand.size()
		State.intel_hand.append(placeholder)
		_request_intel_narration(idx_placeholder, c, direction, target)
	_refresh_hand_ui()
	_refresh_top_bar()
	if typeof(AgentManager) == TYPE_OBJECT:
		AgentManager.on_player_card_played(target, c.id, direction, success)
	_check_death_and_react()
	return success

func _request_intel_narration(intel_idx: int, c: Card, direction: String, target: String) -> void:
	var llm = get_node_or_null("/root/LLMClient")
	if llm == null or not llm.is_ready():
		return
	var attrs: Dictionary = State.country_attrs.get(target, {})
	var monarch_names = {"qin": "秦王", "zhao": "赵王", "qi": "齐王"}
	var dir_labels = {
		"push_hezong": "推合纵", "push_qin": "推亲秦", "neutral": "中立",
		"favor_hezong": "利合纵", "favor_lianheng": "利连横",
		"aid": "承诺援助", "ally": "承诺结盟"
	}
	var dir_disp: String = String(dir_labels.get(direction, direction))
	var lines: Array = [
		"# 世界铁律：这个世界只有三个国家，秦、赵、齐。不存在韩魏楚燕等其他国家。你的叙事只能提及秦赵齐。",
		"# 你是战国时期的一位史官，负责记录纵横家的行动。",
		"# 事件",
		"纵横家对%s打出了「%s%s」并成功。" % [_country_name(target), c.name, ("·" + dir_disp if dir_disp != "" else "")],
		"",
		"# %s当前状态" % monarch_names.get(target, "君主"),
		"国威%d 盟信%d 战心%d" % [int(attrs.get("guowei",0)), int(attrs.get("mengxin",0)), int(attrs.get("zhanxin",0))],
		"",
		"# 关键事件",
		_current_event_text,
		"",
		"# 输出（严格 JSON，无多余文字）：",
		"{",
		'  "intel": "≤50 字情报文本，一句话概括这次行动引发的连锁反应或君主的私下反应。用第三人称叙事口吻。"',
		"}"
	]
	var prompt = "\n".join(lines)
	llm.request(prompt, {"model": "deepseek-v4-flash", "timeout_sec": 5.0, "temperature": 0.9, "response_json": true},
		func(parsed: Variant, err: String):
			if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
				return
			var narrative: String = String((parsed as Dictionary).get("intel", ""))
			if narrative == "":
				return
			if intel_idx < 0 or intel_idx >= State.intel_hand.size():
				return
			State.intel_hand[intel_idx] = "[情报·%s] %s" % [_country_name(target), narrative]
			_refresh_hand_ui()
	)

func _check_death_and_react() -> void:
	var dk: String = State.check_death()
	if dk != "":
		play_sfx("death")
		call_deferred("_go_ending", "death", dk)

func _on_node_click_event(country: String, ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_on_node_clicked(country)

func _on_node_clicked(country: String) -> void:
	if _moving:
		return
	if State.player_location == country:
		_interact_country(country)
		return
	_move_player_to(country)

func _move_player_to(country: String) -> void:
	_moving = true
	var pos: Vector2 = country_positions.get(country, player_icon.position)
	var tween := create_tween()
	tween.tween_property(player_icon, "position", pos, 1.5)
	tween.finished.connect(func():
		State.player_location = country
		_moving = false
		push_event("[你] 抵达 %s" % _country_name(country))
		_interact_country(country)
	)

func _interact_country(country: String) -> void:
	var status: String = ""
	if typeof(AgentManager) == TYPE_OBJECT:
		status = AgentManager.get_country_status(country)
	if status == "召见":
		_open_dialogue(country, "summon")
	elif status == "决策已定":
		_pop_decided_modal(country)
	else:
		# 空闲 / 谈判中 → 主动请见：先选牌打
		_pop_active_audience_picker(country)

func _pop_active_audience_picker(country: String) -> void:
	# 防御：picker 打开前若已被召见，直接开面谈跳过打牌
	if typeof(AgentManager) == TYPE_OBJECT and AgentManager.is_country_summon(country):
		_open_dialogue(country, "summon")
		return
	if State.action_hand.is_empty():
		push_event("[你] 手中无牌，无法请见 %s" % _country_name(country))
		return
	var layer := CanvasLayer.new()
	layer.layer = 12
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(cc)
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(560, 380)
	cc.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	box.add_child(vb)
	var t := Label.new()
	t.text = "选一张行动牌请见 %s" % _country_name(country)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 18)
	t.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	vb.add_child(t)
	var hint := Label.new()
	hint.text = "牌打成功 → 见到君主，只能自输入；失败 → 名望 -3，见不到"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	vb.add_child(hint)
	for i in range(State.action_hand.size()):
		var c: Card = State.action_hand[i] as Card
		if c == null:
			continue
		var b := Button.new()
		b.custom_minimum_size = Vector2(500, 44)
		b.text = "%s（%d%%）" % [c.name, _preview_rate(c)]
		b.add_theme_font_size_override("font_size", 15)
		var captured_i: int = i
		var captured_c: Card = c
		b.pressed.connect(func():
			layer.queue_free()
			_pop_card_modal(captured_c, captured_i, country, true, country)
		)
		vb.add_child(b)
	var cancel := Button.new()
	cancel.text = "取消"
	cancel.add_theme_font_size_override("font_size", 13)
	cancel.pressed.connect(func(): layer.queue_free())
	vb.add_child(cancel)

func _open_dialogue(country: String, mode: String = "summon") -> void:
	var dscn := load("res://scenes/dialogue.tscn")
	if dscn == null:
		return
	var d = dscn.instantiate()
	get_tree().root.add_child(d)
	if d.has_method("setup"):
		d.setup(country, _current_event_text, mode)
	if d.has_signal("audience_settled"):
		d.audience_settled.connect(func(country2: String, verdict: String, _player_text: String, summary: String):
			push_event("[反应] 三国听闻%s面谈结果，各有动作……" % _country_name(country2))
			if typeof(AgentManager) == TYPE_OBJECT and AgentManager.has_method("trigger_reaction_round"):
				AgentManager.trigger_reaction_round(country2, verdict, summary)
		)
	if d.has_signal("dialogue_finished"):
		d.dialogue_finished.connect(func(country2: String, _verdict: String):
			if d != null and is_instance_valid(d):
				d.queue_free()
			_update_country_status_labels()
			_refresh_top_bar()
			_check_death_and_react()
			State.country_states[country2] = "done"
		)

func _pop_decided_modal(country: String) -> void:
	# 简化 modal。为避免多场景文件。状态按钮动态生成。
	var layer := CanvasLayer.new()
	layer.layer = 9
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(cc)
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(480, 240)
	cc.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	box.add_child(vb)
	var t := Label.new()
	t.text = "%s已决策" % _country_name(country)
	t.add_theme_font_size_override("font_size", 20)
	t.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _chinese_font:
		t.add_theme_font_override("font", _chinese_font)
	if _chinese_font:
		t.add_theme_font_override("font", _chinese_font)
	vb.add_child(t)
	var d := Label.new()
	d.text = "%s君闭门不听。可打牌挑战以重启召见。" % _country_name(country)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.add_theme_font_size_override("font_size", 14)
	if _chinese_font:
		d.add_theme_font_override("font", _chinese_font)
	vb.add_child(d)
	var bch := Button.new()
	bch.text = "打牌挑战"
	if _chinese_font:
		bch.add_theme_font_override("font", _chinese_font)
	vb.add_child(bch)
	var bcl := Button.new()
	bcl.text = "离开"
	if _chinese_font:
		bcl.add_theme_font_override("font", _chinese_font)
	vb.add_child(bcl)
	bcl.pressed.connect(func(): layer.queue_free())
	bch.pressed.connect(func():
		layer.queue_free()
		if State.action_hand.is_empty():
			push_event("[你] 手中无牌，无法挑战 %s" % _country_name(country))
			return
		_pop_active_audience_picker(country)
	)

func _on_agent_action(country: String, action: Dictionary) -> void:
	var narrative: String = String(action.get("narrative", ""))
	var reason: String = String(action.get("reason", ""))
	var deltas_note: String = String(action.get("deltas_note", ""))
	var msg: String = "[%s R%d] %s" % [_country_name(country), int(action.get("round", 0)), narrative]
	if reason != "":
		msg += " —— %s" % reason
	if deltas_note != "":
		msg += "  《%s》" % deltas_note
	push_event(msg)
	_update_country_status_labels()

func _on_country_finished(country: String, settle: String) -> void:
	var name_str: String = _country_name(country)
	var settle_disp: String = "召见" if settle == "summon" else "决策已定"
	push_event("[%s] 博弈完成 → %s" % [name_str, settle_disp])
	_update_country_status_labels()

func _on_all_finished() -> void:
	next_turn_button.disabled = false
	push_event("[谈判] 三对均结，可进入下回合")
	_update_country_status_labels()

func _update_country_status_labels() -> void:
	if typeof(AgentManager) != TYPE_OBJECT:
		return
	status_qin.text = _fmt_country_status("qin")
	status_zhao.text = _fmt_country_status("zhao")
	status_qi.text = _fmt_country_status("qi")

func _fmt_country_status(country: String) -> String:
	var st: String = AgentManager.get_country_status(country)
	var attrs: Dictionary = State.country_attrs.get(country, {})
	var line1: String = "%s [%s]" % [_country_name(country), st]
	var line2: String = "威%d 盟%d 战%d" % [
		int(attrs.get("guowei", 0)),
		int(attrs.get("mengxin", 0)),
		int(attrs.get("zhanxin", 0))
	]
	return "%s\n%s" % [line1, line2]

func _on_next_turn_pressed() -> void:
	# 二次确认：是否有 summon 未处理
	var unhandled: Array = []
	for c in ["qin", "zhao", "qi"]:
		if AgentManager.is_country_summon(c) and String(State.country_states.get(c, "")) != "done":
			unhandled.append(c)
	if unhandled.size() > 0:
		_pop_confirm_skip(unhandled)
		return
	_proceed_to_next_turn()

func _pop_confirm_skip(unhandled: Array) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 9
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(cc)
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(420, 220)
	cc.add_child(box)
	var vb := VBoxContainer.new()
	box.add_child(vb)
	var t := Label.new()
	var names: Array = []
	for c in unhandled:
		names.append(_country_name(c))
	t.text = "还有 %s 召见未处理，是否进入下回合？" % "、".join(names)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.add_theme_font_size_override("font_size", 14)
	if _chinese_font:
		t.add_theme_font_override("font", _chinese_font)
	if _chinese_font:
		t.add_theme_font_override("font", _chinese_font)
	vb.add_child(t)
	var bok := Button.new()
	bok.text = "确认进入"
	if _chinese_font:
		bok.add_theme_font_override("font", _chinese_font)
	vb.add_child(bok)
	var bc := Button.new()
	bc.text = "取消"
	if _chinese_font:
		bc.add_theme_font_override("font", _chinese_font)
	vb.add_child(bc)
	bc.pressed.connect(func(): layer.queue_free())
	bok.pressed.connect(func():
		layer.queue_free()
		_proceed_to_next_turn()
	)

func _proceed_to_next_turn() -> void:
	play_sfx("turn")
	if typeof(AgentManager) == TYPE_OBJECT:
		AgentManager.reset()
	State.country_states = {"qin": "idle", "zhao": "idle", "qi": "idle"}
	if State.current_round >= State.max_round:
		var arb = get_node("/root/Arbiter")
		var res: Dictionary = arb.check_ending()
		call_deferred("_go_ending", String(res.get("type", "situation")), String(res.get("detail", "undecided")))
		return
	turn_manager.advance_turn()
	var dk: String = State.check_death()
	if dk != "":
		play_sfx("death")
		call_deferred("_go_ending", "death", dk)
		return
	_refresh_top_bar()
	_update_country_status_labels()
	call_deferred("_start_round_flow")

func _on_dump_pressed() -> void:
	print(State.dump_state())
	push_event("[调试] 状态已打印控制台")

func _on_restart_pressed() -> void:
	State.reset()
	State.mbti_answers.clear()
	if typeof(AgentManager) == TYPE_OBJECT:
		AgentManager.reset()
	get_tree().reload_current_scene()

func _go_ending(kind: String, detail: String) -> void:
	if typeof(AgentManager) == TYPE_OBJECT:
		AgentManager.reset()
	var arb = get_node("/root/Arbiter")
	var ending_data: Dictionary = {"kind": kind, "detail": detail, "stance": arb.judge_stance()}
	var f := FileAccess.open("user://ending.dat", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(ending_data))
		f.close()
	get_tree().change_scene_to_file("res://scenes/ending.tscn")

func _on_turn_started(round_num: int) -> void:
	_refresh_top_bar()

func _on_phase_changed(p: String) -> void:
	print("[Phase] %s round=%d" % [p, State.current_round])

func _on_player_attrs_changed(_attrs: Dictionary) -> void:
	_refresh_top_bar()

func _on_country_attrs_changed(_country: String, _attrs: Dictionary) -> void:
	_update_country_status_labels()

func _refresh_top_bar() -> void:
	top_bar_label.text = "回合 %d/%d   合纵 %d   名望 %d   心计 %d" % [
		State.current_round, State.max_round,
		int(State.player_attrs.get("hezong", 0)),
		int(State.player_attrs.get("mingwang", 0)),
		int(State.player_attrs.get("xinji", 0))
	]

func _update_player_icon() -> void:
	var pos: Vector2 = country_positions.get(State.player_location, Vector2(180, 360))
	player_icon.position = pos

func push_event(text: String) -> void:
	if event_stream == null:
		return
	event_stream.append_text(text + "\n")

static func _country_name(c: String) -> String:
	match c:
		"qin": return "秦"
		"zhao": return "赵"
		"qi": return "齐"
		_: return c

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_dump"):
		print(State.dump_state())

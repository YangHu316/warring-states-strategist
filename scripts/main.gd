extends Node2D
# V2 Main — 大地图主场景控制器

@onready var top_bar_label: Label = $UILayer/TopBar/TopBarLabel
@onready var key_event_banner: Label = $UILayer/KeyEventBanner
@onready var country_info_panel: PanelContainer = $UILayer/CountryInfoPanel
@onready var country_info_label: Label = $UILayer/CountryInfoPanel/CountryInfoLabel
@onready var event_stream: RichTextLabel = $UILayer/EventStreamPanel/VBox/EventStreamScroll/EventStream
@onready var event_stream_panel: PanelContainer = $UILayer/EventStreamPanel
@onready var event_stream_toggle: Button = $UILayer/EventStreamPanel/VBox/TitleBar/EventStreamToggle
@onready var event_stream_scroll: ScrollContainer = $UILayer/EventStreamPanel/VBox/EventStreamScroll
@onready var chatroom_panel: Control = $UILayer/ChatRoomPanel
@onready var chatroom_toggle: TextureButton = $UILayer/ChatRoomPanel/VBox/ChatToggle
@onready var chatroom_scroll: ScrollContainer = $UILayer/ChatRoomPanel/VBox/ChatScroll
@onready var chatroom_log: RichTextLabel = $UILayer/ChatRoomPanel/VBox/ChatScroll/ChatLog
@onready var chatroom_bg_expand: TextureRect = $UILayer/ChatRoomPanel/BgExpand
@onready var action_cards_hbox: HBoxContainer = $UILayer/HandPanel/HBox/ActionPanel/ActionCardsHBox
@onready var intel_cards_hbox: HBoxContainer = $UILayer/HandPanel/HBox/IntelPanel/IntelScroll/IntelCardsHBox
@onready var hand_panel: PanelContainer = $UILayer/HandPanel
@onready var action_buttons_vbox: VBoxContainer = $UILayer/ActionButtonsVBox
@onready var next_turn_button: Button = $UILayer/ActionButtonsVBox/NextTurnButton
@onready var dump_button: Button = $UILayer/ActionButtonsVBox/DumpButton
@onready var restart_button: Button = $UILayer/ActionButtonsVBox/RestartButton
@onready var debug_label: Label = $UILayer/DebugLabel
@onready var summon_notice: PanelContainer = $UILayer/SummonNotice
@onready var summon_label: Label = $UILayer/SummonNotice/VBox/SummonLabel
@onready var summon_hint: Label = $UILayer/SummonNotice/VBox/SummonHint
@onready var summon_confirm_btn: Button = $UILayer/SummonNotice/VBox/ConfirmButton
@onready var turn_manager: Node = $TurnManagerNode
@onready var player_icon: Sprite2D = $MapLayer/PlayerIcon
@onready var status_qin: Label = $MapLayer/NodeQin/StatusQin
@onready var status_zhao: Label = $MapLayer/NodeZhao/StatusZhao
@onready var status_qi: Label = $MapLayer/NodeQi/StatusQi
@onready var area_qin: Area2D = $MapLayer/NodeQin/AreaQin
@onready var area_zhao: Area2D = $MapLayer/NodeZhao/AreaZhao
@onready var area_qi: Area2D = $MapLayer/NodeQi/AreaQi
@onready var map_layer: Node2D = $MapLayer


# Chinese font for CJK display support
var _chinese_font: Font

# 召见标记：country -> Sprite2D（红色感叹号，城池右上角）
# 召见触发时显示；玩家进入该国 dialogue 时隐藏
var _summon_marks: Dictionary = {}
# 密信标记：每对国家至多一枚图标（新私信只更新内容不叠加）；点开截获、阅后从地图移除
var _secret_letter_marks: Array = []
var _secret_letters_by_pair: Dictionary = {}  # 无序对 key "a|b" -> Button
# 本回合是否已自然生成过密信（chat_message 触发）；用于 _on_all_finished 兜底
var _turn_secret_letter_spawned: bool = false
# v7.3.10：玩家是否正在 dialogue 场景（用于约束地图事件只在主地图出现）
var _in_dialogue: bool = false
# 待弹召见通知（若召见触发时玩家正在 dialogue，延后到回主地图再弹）
var _pending_summon_notice: String = ""

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
var _mbti_delta_done: Dictionary = {}   # qid -> 已结算立场抉择代价
var _ending_fired: bool = false
var _pending_death_kind: String = ""    # 面谈中触发的死亡/耗竭，回大地图后结算
var _moving: bool = false
var _free_phase_started: bool = false
var _event_panel_expanded: bool = false
const _EVENT_PANEL_COLLAPSED_TOP: float = -226.0
const _EVENT_PANEL_EXPANDED_TOP: float = -490.0
const _EVENT_LINE_MAX: int = 50
const _EVENT_MAX_LINES: int = 60
var _event_lines: Array = []  # 播报 bbcode 行缓冲（裁剪重建时保色）

# === 世界播报事件分类（v7.3.10 重设计 —— 新闻栏目式分板块） ===
# 调用 push_event(text, EventType.XXX) 指定分类；不传默认 SYSTEM
enum EventType {
	WORLD,    # 天下大势：关键事件 / 阶段变更 / 反应触发 / 谈判结束
	STATE,    # 三国动向：国家三维变化
	PLAYER,   # 你的行动：抵达 / 请见 / 打牌 / 抽牌 / MBTI 答题
	SYSTEM,   # 系统：LLM 状态 / 调试
}
# 栏目配色：tag=前缀徽章文字, color=bbcode 颜色
const _EVENT_TYPE_META: Dictionary = {
	EventType.WORLD:  {"tag": "天下", "color": "#ffd766"},
	EventType.STATE:  {"tag": "三国", "color": "#66d0ff"},
	EventType.PLAYER: {"tag": "你",   "color": "#a0ff90"},
	EventType.SYSTEM: {"tag": "系统", "color": "#888888"},
}

const _DIR_LABELS: Dictionary = {
	"push_hezong": "推合纵", "push_qin": "推亲秦", "neutral": "中立",
	"favor_hezong": "利好合纵之消息", "favor_lianheng": "利好连横之消息",
	"aid": "承诺援助", "ally": "承诺结盟"
}

static func _dir_label(d: String) -> String:
	return String(_DIR_LABELS.get(d, d))

const _CARD_TEXTURES: Dictionary = {
	"persuade": "res://assets/sprites/card_persuade.png",
	"message":  "res://assets/sprites/card_message.png",
	"promise":  "res://assets/sprites/card_promise.png",
	"alienate": "res://assets/sprites/card_alienate.png",
	"spy":      "res://assets/sprites/card_spy.png",
	"intel":    "res://assets/sprites/card_intel_art.png",
}

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
	event_stream_toggle.pressed.connect(_toggle_event_panel)
	chatroom_toggle.pressed.connect(_toggle_chatroom_panel)
	call_deferred("_offset_chatroom_scroll")
	if summon_confirm_btn != null:
		summon_confirm_btn.pressed.connect(_on_summon_notice_confirm)

	# 初始化 3 个城池的召见红色感叹号标记（初始隐藏）
	_init_summon_marks()
	# 地图板块覆盖层（三国拆分件叠原图：浅色分区 + 割城翻格）
	_init_region_overlays()
	_update_country_status_labels()

	# 点击地图节点 — 采用 input_event
	area_qin.input_event.connect(func(_v, ev, _s): _on_node_click_event("qin", ev))
	area_zhao.input_event.connect(func(_v, ev, _s): _on_node_click_event("zhao", ev))
	area_qi.input_event.connect(func(_v, ev, _s): _on_node_click_event("qi", ev))

	# AgentManager 信号（V3：按国博弈）
	if typeof(AgentManager) == TYPE_OBJECT:
		AgentManager.agent_action.connect(_on_agent_action)
		AgentManager.country_finished.connect(_on_country_finished)
		AgentManager.all_finished.connect(_on_all_finished)
		if AgentManager.has_signal("chat_message"):
			AgentManager.chat_message.connect(_on_chat_message)
		if AgentManager.has_signal("chat_settled"):
			AgentManager.chat_settled.connect(func(note: String): push_event(note, EventType.STATE))

	# State 信号
	if typeof(State) == TYPE_OBJECT:
		State.world_attrs_changed.connect(_on_world_attrs_changed)
		State.national_changed.connect(func(_c: String):
			_update_country_status_labels()
			_refresh_region_cells()
		)
		State.mingwang_changed.connect(func(_v: int): _refresh_top_bar())
		State.mingwang_depleted.connect(_on_mingwang_depleted)
		State.action_points_changed.connect(func(_v: int): _refresh_top_bar())
		State.action_points_exhausted.connect(_on_ap_exhausted)

	# WarManager 信号（RFC-004 Phase A：三点位行军可视化）
	if typeof(WarManager) == TYPE_OBJECT:
		WarManager.war_banner.connect(_show_war_banner)
		WarManager.war_declared.connect(_on_war_declared)
		WarManager.war_advanced.connect(_on_war_advanced)
		WarManager.war_slowed.connect(func(_w: Dictionary): pass)
		WarManager.war_retreated.connect(func(w: Dictionary, _r: String): _on_war_over(w))
		WarManager.war_resolved.connect(func(w: Dictionary, res: Dictionary):
			_on_war_over(w)
			# 怂恿归因：你撺掇的战争，胜负记你账上
			if bool(res.get("player_instigated", false)):
				var oc: String = String(res.get("outcome", ""))
				if oc in ["att_major", "att_minor"]:
					State.apply_mingwang(5)
					push_event("你怂恿之战大获全胜——连横之功名动列国（名望+5）", EventType.PLAYER)
				elif oc in ["att_repelled", "att_routed"]:
					State.apply_mingwang(-6)
					push_event("你怂恿之战一败涂地——祸国之名传遍天下（名望−6）", EventType.PLAYER)
		)

	_refresh_top_bar()
	_update_player_icon()
	_setup_key_event_banner_bg()
	_setup_action_button_bg()
	_setup_event_stream_bg()

func _setup_action_button_bg() -> void:
	var bar_path := "res://assets/ui/bar_btn_bg.png"
	if not ResourceLoader.exists(bar_path):
		return
	var sbt := StyleBoxTexture.new()
	sbt.texture = load(bar_path)
	sbt.texture_margin_left = 0.0
	sbt.texture_margin_top = 0.0
	sbt.texture_margin_right = 0.0
	sbt.texture_margin_bottom = 0.0
	sbt.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sbt.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	for btn in [next_turn_button, dump_button, restart_button]:
		btn.add_theme_stylebox_override("normal", sbt)
		btn.add_theme_stylebox_override("hover", sbt)
		btn.add_theme_stylebox_override("pressed", sbt)
		btn.add_theme_stylebox_override("disabled", sbt)
	next_turn_button.custom_minimum_size.y = 60.0
	dump_button.custom_minimum_size.y = 45.0
	restart_button.custom_minimum_size.y = 45.0

func _setup_event_stream_bg() -> void:
	var bg_path := "res://assets/ui/dialog_bg01.png"
	if not ResourceLoader.exists(bg_path):
		return
	# 面板本身透明：这样「未展开」时只显示标题栏，不显示背景框；
	# 背景框挂在下方滚动区，展开后才出现，且位于标题栏下面。
	event_stream_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	# 卷轴纸张背景图挂到滚动容器 EventStreamScroll：它在标题栏下方、
	# 只在展开时可见，且尺寸固定（不随文字滚动），大小与上一步一致。
	var sbt := StyleBoxTexture.new()
	sbt.texture = load(bg_path)
	sbt.texture_margin_left = 0.0
	sbt.texture_margin_top = 0.0
	sbt.texture_margin_right = 0.0
	sbt.texture_margin_bottom = 0.0
	sbt.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sbt.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	# 向外扩绘：左右保持不变（宽度不变），上下加大让卷轴框整体拉长
	sbt.expand_margin_left = 18.0
	sbt.expand_margin_right = 18.0
	sbt.expand_margin_top = 52.0
	sbt.expand_margin_bottom = 52.0
	event_stream_scroll.add_theme_stylebox_override("panel", sbt)
	# 文字底透明，用左右内边距整体缩窄、一排少几个字，并让文字落在卷轴框内
	# 左边距须避开卷轴左侧卷边美术（贴图向左外扩 18px）
	var text_sb := StyleBoxEmpty.new()
	text_sb.content_margin_left = 56.0
	text_sb.content_margin_right = 16.0
	text_sb.content_margin_top = 14.0
	text_sb.content_margin_bottom = 16.0
	event_stream.add_theme_stylebox_override("normal", text_sb)
	event_stream.add_theme_color_override("default_color", Color(0, 0, 0, 1))
	# 确保按词自动换行，让文字随缩窄后的宽度重新折行
	event_stream.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _setup_key_event_banner_bg() -> void:
	var banner_path := "res://assets/ui/key_event_banner.png"
	if not ResourceLoader.exists(banner_path):
		return
	var sbt := StyleBoxTexture.new()
	sbt.texture = load(banner_path)
	sbt.texture_margin_left = 0.0
	sbt.texture_margin_top = 0.0
	sbt.texture_margin_right = 0.0
	sbt.texture_margin_bottom = 0.0
	sbt.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sbt.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	key_event_banner.add_theme_stylebox_override("normal", sbt)

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
	push_event("LLM 状态: %s" % llm_status, EventType.SYSTEM)
	if State.current_state == State.GameState.READY:
		State.change_state(State.GameState.PLAYING)
	call_deferred("_start_round_flow")

func _start_round_flow() -> void:
	_free_phase_started = false
	_push_round_separators()
	_show_mbti_questions_for_round()

# 回合分隔线：写入右下世界播报与右上朝议栏，隔开每一回合的信息
# （朝议栏窄，分隔线短一截以免折行）
func _push_round_separators() -> void:
	var rn: int = State.current_round
	var months: String = "%d–%d月" % [rn * 2 - 1, rn * 2]
	if event_stream != null:
		_event_append("[color=#8a6d3b]━━━━━━━━ 第 %d 回合 · %s ━━━━━━━━[/color]\n" % [rn, months])
	if chatroom_log != null:
		chatroom_log.append_text("[color=#8a6d3b]━━ 第 %d 回合 · %s ━━[/color]\n" % [rn, months])

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
			# 立场抉择有代价（防重复结算：answered 信号可能多次发射）
			if not _mbti_delta_done.get(qid, false):
				_mbti_delta_done[qid] = true
				match choice:
					"hezong":
						State.apply_mingwang(2)
						State.add_grudge("qin", "当廷倡合纵")
						push_event("你当廷表态倡合纵——名望+2，秦王衔恨", EventType.PLAYER)
					"qin":
						State.apply_mingwang(2)
						State.add_grudge("zhao", "当廷附连横")
						push_event("你当廷表态附连横——名望+2，赵王衔恨", EventType.PLAYER)
					_:
						State.apply_mingwang(-1)
						push_event("你顾左右而言他——沉默也有代价（名望−1）", EventType.PLAYER)
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
	if typeof(WarManager) == TYPE_OBJECT:
		WarManager.on_free_phase_start()

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
		# 带战争脚本的事件优先（首局第一场战争必发——黄金十分钟）；
		# 多条战争事件随机取一：秦的兵锋可能指向赵，也可能指向齐
		var war_events: Array = []
		for e2 in candidates:
			if typeof(e2) == TYPE_DICTIONARY and (e2 as Dictionary).has("war"):
				war_events.append(e2)
		if war_events.size() > 0:
			chosen = war_events[randi() % war_events.size()]
	_current_event_tag = String(chosen.get("state_tag", "default"))
	_current_event_text = String(chosen.get("text", ""))
	key_event_banner.text = _current_event_text
	push_event("关键事件：" + _current_event_text, EventType.WORLD)
	# 关键事件本身撬动大势（RFC-003-A §七）
	var wd: Variant = chosen.get("world_delta", {})
	if typeof(wd) == TYPE_DICTIONARY and not (wd as Dictionary).is_empty():
		State.apply_world_delta(wd)
		var arb = get_node_or_null("/root/Arbiter")
		if arb != null and arb.has_method("describe_world_delta"):
			push_event("大势因之而变：%s" % arb.describe_world_delta(wd), EventType.STATE)
	# 脚本化开战（RFC-004：R1「秦军拔营伐赵」，延迟 2 秒让地图先渲染）
	var war_cfg: Variant = chosen.get("war", {})
	if typeof(war_cfg) == TYPE_DICTIONARY and not (war_cfg as Dictionary).is_empty():
		var wc: Dictionary = war_cfg
		get_tree().create_timer(2.0).timeout.connect(func():
			if typeof(WarManager) == TYPE_OBJECT:
				WarManager.declare_war(String(wc.get("attacker", "qin")), String(wc.get("defender", "zhao")), true)
		)

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
	push_event("抽 %d 张（手牌共 %d）" % [draw_count, State.action_hand.size()], EventType.PLAYER)

func _refresh_hand_ui() -> void:
	for child in action_cards_hbox.get_children():
		child.queue_free()
	for child in intel_cards_hbox.get_children():
		child.queue_free()
	for i in range(State.action_hand.size()):
		var c: Card = State.action_hand[i] as Card
		if c == null:
			continue
		var tex_path: String = String(_CARD_TEXTURES.get(c.id, ""))
		var b := TextureButton.new()
		b.custom_minimum_size = Vector2(120, 155)
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_SCALE
		b.modulate = Color(1.25, 1.2, 1.15, 1)
		if tex_path != "" and ResourceLoader.exists(tex_path):
			b.texture_normal = load(tex_path)
		b.pressed.connect(func(): _on_action_card_pressed(i))
		var rate_lbl := Label.new()
		rate_lbl.text = "%d%%" % _preview_rate(c)
		rate_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		rate_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rate_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		rate_lbl.add_theme_font_size_override("font_size", 14)
		rate_lbl.add_theme_color_override("font_color", Color(1, 0.95, 0.7))
		if _chinese_font:
			rate_lbl.add_theme_font_override("font", _chinese_font)
		b.add_child(rate_lbl)
		action_cards_hbox.add_child(b)
	for i in range(State.intel_hand.size()):
		var item: Variant = State.intel_hand[i]
		var txt: String = String(item) if typeof(item) != TYPE_DICTIONARY else String((item as Dictionary).get("text", "情报"))
		var b2 := TextureButton.new()
		b2.custom_minimum_size = Vector2(120, 155)
		b2.ignore_texture_size = true
		b2.stretch_mode = TextureButton.STRETCH_SCALE
		b2.modulate = Color(1.25, 1.2, 1.15, 1)
		var intel_path: String = String(_CARD_TEXTURES.get("intel", ""))
		if intel_path != "" and ResourceLoader.exists(intel_path):
			b2.texture_normal = load(intel_path)
		var lbl := Label.new()
		lbl.text = txt
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(1, 1, 1))
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var hover_bg := StyleBoxFlat.new()
		hover_bg.bg_color = Color(0, 0, 0, 0.55)
		hover_bg.corner_radius_top_left = 3
		hover_bg.corner_radius_top_right = 3
		hover_bg.corner_radius_bottom_left = 3
		hover_bg.corner_radius_bottom_right = 3
		hover_bg.content_margin_left = 4.0
		hover_bg.content_margin_right = 4.0
		hover_bg.content_margin_top = 4.0
		hover_bg.content_margin_bottom = 4.0
		lbl.add_theme_stylebox_override("normal", hover_bg)
		lbl.visible = false
		if _chinese_font:
			lbl.add_theme_font_override("font", _chinese_font)
		b2.add_child(lbl)
		b2.mouse_entered.connect(func(): lbl.visible = true)
		b2.mouse_exited.connect(func(): lbl.visible = false)
		intel_cards_hbox.add_child(b2)

func _preview_rate(c: Card) -> int:
	if c == null:
		return 0
	return clampi(int(c.base_rate), 5, 95)

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
					push_event("请见%s不成——徒增纷乱" % _country_name(audience_country), EventType.PLAYER)
		)

func _resolve_card_play(c: Card, idx: int, direction: String, target: String, intel_indices: Array = []) -> bool:
	if not State.spend_ap(1):
		push_event("心力已尽，无力再动", EventType.PLAYER)
		return false
	var arb = get_node("/root/Arbiter")
	var intel_bonus: int = intel_indices.size() * State.INTEL_BONUS_PER_CARD
	var res: Dictionary = arb.roll_card(c.id, direction, target, intel_bonus)
	var success: bool = bool(res.get("success", false))
	var dw: Dictionary = res.get("deltas_world", {})
	if dw != null and not dw.is_empty():
		State.apply_world_delta(dw)
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
	var msg: String = "%s%s%s·%s -> %s (%d%%)" % [c.name, ("·" + direction if direction != "" else ""), bonus_txt, target, ("成功" if success else "失败"), int(res.get("rate", 0))]
	push_event(msg, EventType.PLAYER)
	if dw != null and not dw.is_empty() and arb.has_method("describe_world_delta"):
		push_event("大势因之而变：%s" % arb.describe_world_delta(dw), EventType.STATE)
	# 名望结算：阳谋扬名、阴谋不显、败露重挫且君主衔恨（RFC-004 §5.2）
	if success:
		if c.id == "persuade" or c.id == "promise":
			State.apply_mingwang(2)
	else:
		match c.id:
			"alienate":
				State.apply_mingwang(-4)
				State.add_grudge(target, "离间之谋败露")
			"spy":
				State.apply_mingwang(-3)
				State.add_grudge(target, "细作被擒")
			"message":
				State.apply_mingwang(-3)
				State.add_grudge(target, "所传之信被识破")
			"persuade", "promise":
				State.apply_mingwang(-2)
	if success:
		# 传信成功 → 入承诺账本，目标国后续决策/面谈会引述这条消息
		if c.id == "message":
			State.add_ledger("message", "player", target, "纵横家致书%s（%s）" % [_country_name(target), _dir_label(direction)])
		# 刺探的情报是精确的君主意图（arbiter 生成），不再交给 LLM 叙事改写
		var spy_intel: String = String(res.get("intel", ""))
		if c.id == "spy" and spy_intel != "":
			State.intel_hand.append(spy_intel)
		else:
			var placeholder: String = "[情报·%s] %s%s成功" % [_country_name(target), c.name, ("·" + direction if direction != "" else "")]
			var idx_placeholder: int = State.intel_hand.size()
			State.intel_hand.append(placeholder)
			_request_intel_narration(idx_placeholder, c, direction, target)
	_refresh_hand_ui()
	_refresh_top_bar()
	if typeof(AgentManager) == TYPE_OBJECT:
		AgentManager.on_player_card_played(target, c.id, direction, success)
	return success

func _request_intel_narration(intel_idx: int, c: Card, direction: String, target: String) -> void:
	var llm = get_node_or_null("/root/LLMClient")
	if llm == null or not llm.is_ready():
		return
	var wa: Dictionary = State.world_attrs
	var monarch_names = {"qin": "秦王", "zhao": "赵王", "qi": "齐王"}
	var dir_disp: String = _dir_label(direction)
	var lines: Array = [
		"# 世界铁律：这个世界只有三个国家，秦、赵、齐。不存在韩魏楚燕等其他国家。你的叙事只能提及秦赵齐。",
		"# 你是战国时期的一位史官，负责记录纵横家的行动。",
		"# 事件",
		"纵横家对%s打出了「%s%s」并成功。" % [_country_name(target), c.name, ("·" + dir_disp if dir_disp != "" else "")],
		"",
		"# 当前天下大势",
		"秦之霸业%d 六国之盟%d 天下纷乱%d" % [int(wa.get("qin_baye",0)), int(wa.get("liu_guo_meng",0)), int(wa.get("tian_xia_fenluan",0))],
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
	if not State.spend_ap(1):
		push_event("心力已尽，无力再动", EventType.PLAYER)
		return
	_moving = true
	var pos: Vector2 = country_positions.get(country, player_icon.position)
	if pos.x < player_icon.position.x:
		player_icon.flip_h = false
	elif pos.x > player_icon.position.x:
		player_icon.flip_h = true
	var tween := create_tween()
	tween.tween_property(player_icon, "position", pos, 1.5)
	tween.finished.connect(func():
		State.player_location = country
		_moving = false
		push_event("抵达 %s" % _country_name(country), EventType.PLAYER)
		_interact_country(country)
	)

func _interact_country(country: String) -> void:
	# 战时优先：任何国家的面谈都围绕当前战事（劝和/求和/驰援）
	if typeof(WarManager) == TYPE_OBJECT and WarManager.has_war():
		_open_dialogue(country, "war")
		return
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
		push_event("手中无牌，无法请见 %s" % _country_name(country), EventType.PLAYER)
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
	hint.text = "牌打成功 → 见到君主，只能自输入；失败 → 天下纷乱 +2，见不到"
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
	if not State.spend_ap(1):
		push_event("心力已尽，无力再谈", EventType.PLAYER)
		return
	var dscn := load("res://scenes/dialogue.tscn")
	if dscn == null:
		return
	var d = dscn.instantiate()
	get_tree().root.add_child(d)
	# v7.3.10：进入 dialogue 场景 —— 标记位 + 隐藏所有大地图专属 UI/标记
	_in_dialogue = true
	# 进入对话 → 隐藏大地图专属 UI（事件框/回合大信息/国家信息面板/三国朝议）
	# 防止 dialogue 场景的 VBox 压在 main 的 TopBar/KeyEventBanner 上；
	# 三国朝议在对话中已经被 ChatBox 取代，整个 panel 隐藏
	if event_stream_panel != null:
		event_stream_panel.visible = false
	if chatroom_panel != null:
		chatroom_panel.visible = false
	if top_bar_label != null and top_bar_label.get_parent() is Control:
		(top_bar_label.get_parent() as Control).visible = false
	if key_event_banner != null:
		key_event_banner.visible = false
	if country_info_panel != null:
		country_info_panel.visible = false
	if hand_panel != null:
		hand_panel.visible = false
	if action_buttons_vbox != null:
		action_buttons_vbox.visible = false
	# v7.3.10：玩家进入该国对话 → 隐藏所有召见标记（红感叹号不可在其他界面出现）
	_hide_all_summon_marks()
	# v7.3.10：dialogue 期间隐藏所有密信图标 + 召见通知（防遮挡 / 不可在其他界面出现）
	_set_secret_letters_visible(false)
	_set_war_visuals_visible(false)
	if summon_notice != null:
		summon_notice.visible = false
	# 面谈期间暂停行军节拍（谈判桌上时间静止，结算不打断对话）
	if typeof(WarManager) == TYPE_OBJECT:
		WarManager.paused = true
	var ev_for_dialogue: String = _current_event_text
	if typeof(WarManager) == TYPE_OBJECT and WarManager.has_war():
		ev_for_dialogue += "\n【战况】" + WarManager.status_text()
	if d.has_method("setup"):
		d.setup(country, ev_for_dialogue, mode)
	if d.has_signal("audience_settled"):
		d.audience_settled.connect(func(country2: String, verdict: String, _player_text: String, summary: String):
			push_event("三国听闻%s面谈结果，各有动作……" % _country_name(country2), EventType.WORLD)
			# v7.3.10：玩家面谈结果概括推进朝议（紫金色，区别于三国）
			_append_player_summary_to_chatroom(country2, verdict, summary)
			if typeof(AgentManager) == TYPE_OBJECT and AgentManager.has_method("trigger_reaction_round"):
				AgentManager.trigger_reaction_round(country2, verdict, summary)
		)
	if d.has_signal("dialogue_finished"):
		d.dialogue_finished.connect(func(country2: String, _verdict: String):
			if d != null and is_instance_valid(d):
				d.queue_free()
			# v7.3.10：离开 dialogue 场景 —— 清标记位 + 恢复所有大地图专属 UI/标记
			_in_dialogue = false
			# 恢复大地图专属 UI
			if event_stream_panel != null:
				event_stream_panel.visible = true
			if chatroom_panel != null:
				chatroom_panel.visible = true
			if top_bar_label != null and top_bar_label.get_parent() is Control:
				(top_bar_label.get_parent() as Control).visible = true
			if key_event_banner != null:
				key_event_banner.visible = true
			if hand_panel != null:
				hand_panel.visible = true
			if action_buttons_vbox != null:
				action_buttons_vbox.visible = true
			_update_country_status_labels()
			# 修复 bug: dialogue 期间追加的情报牌需要刷新到手牌 UI
			_refresh_hand_ui()
			_refresh_top_bar()
			State.country_states[country2] = "done"
			# v7.3.10：回主地图 → 恢复密信图标 + 智能恢复召见标记（只对仍 summon 的亮）
			_set_secret_letters_visible(true)
			_set_war_visuals_visible(true)
			if typeof(WarManager) == TYPE_OBJECT:
				WarManager.paused = false
			_refresh_all_summon_marks()
			# v7.3.10：若有延后的召见通知，现在弹出
			if _pending_summon_notice != "":
				var pending: String = _pending_summon_notice
				_pending_summon_notice = ""
				_pop_summon_notice(pending)
			# 面谈期间触发的名望即死/行动力耗竭，回大地图后结算
			if _pending_death_kind != "":
				var dk: String = _pending_death_kind
				_pending_death_kind = ""
				_queue_ending(dk)
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
			push_event("手中无牌，无法挑战 %s" % _country_name(country), EventType.PLAYER)
			return
		_pop_active_audience_picker(country)
	)

func _on_agent_action(country: String, action: Dictionary) -> void:
	var narrative: String = String(action.get("narrative", ""))
	var reason: String = String(action.get("reason", ""))
	var deltas_note: String = String(action.get("deltas_note", ""))
	var round_num: int = int(action.get("round", 0))
	# v7.3.9：narrative（白话文事件记载）→ 三国朝议栏；deltas_note → 世界动态
	# reason 是 LLM 的内心独白（常以"基于我..."开头），仅写入 recent_actions 供上送 LLM，不再显示给玩家
	if narrative != "":
		var tag: String = ("[R%d] " % round_num) if round_num > 0 else ""
		var line: String = tag + narrative
		_append_chatroom(country, line)
	if deltas_note != "":
		push_event(deltas_note, EventType.STATE)
	_update_country_status_labels()

func _on_country_finished(country: String, settle: String) -> void:
	var name_str: String = _country_name(country)
	var settle_disp: String = "召见" if settle == "summon" else "决策已定"
	push_event("%s → %s" % [name_str, settle_disp], EventType.WORLD)
	_update_country_status_labels()
	# 仅当该国首次被召见（且未被处理过）时弹中央通知；后续反应轮不再弹
	if settle == "summon" and String(State.country_states.get(country, "")) != "done":
		# v7.3.10：若玩家正在 dialogue 场景，延后弹召见通知到回主地图时
		if _in_dialogue:
			_pending_summon_notice = country
		else:
			_pop_summon_notice(country)
		# 城池图标右上角亮红色感叹号（v7.3.10：地图可点击事件）
		_show_summon_mark(country)

func _on_all_finished() -> void:
	next_turn_button.disabled = false
	push_event("三对均结，可进入下回合", EventType.WORLD)
	_update_country_status_labels()
	# v7.3.10：兜底 —— 若本回合无自然 chat_message 触发密信，生成一封"密语风闻"
	_spawn_fallback_secret_letter()

func _update_country_status_labels() -> void:
	if typeof(AgentManager) != TYPE_OBJECT:
		return
	status_qin.text = _fmt_country_status("qin")
	status_zhao.text = _fmt_country_status("zhao")
	status_qi.text = _fmt_country_status("qi")

func _fmt_country_status(country: String) -> String:
	var st: String = AgentManager.get_country_status(country)
	# v7.3.10：玩家已处理过的召见/决策 → 显示"已面谈"，不再持续显示"[召见]"
	if String(State.country_states.get(country, "")) == "done":
		st = "已面谈"
	return "%s [%s]\n城%d 兵%d万" % [
		_country_name(country), st,
		State.get_national(country, "cities"), State.get_national(country, "troops")
	]

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
	# 怠慢召见：召而不至，傲慢之名（名望−3 + 君主衔恨）
	for c in ["qin", "zhao", "qi"]:
		if AgentManager.is_country_summon(c) and String(State.country_states.get(c, "")) != "done":
			State.apply_mingwang(-3)
			State.add_grudge(c, "召而不至")
			push_event("怠慢%s王之召——傲慢之名传出（名望−3）" % _country_name(c), EventType.PLAYER)
	# 回合结算：军队在途则强制推进一格（点3 → 交战）——时间不等人
	if typeof(WarManager) == TYPE_OBJECT:
		WarManager.on_round_settle()
		WarManager.on_free_phase_end()
	if typeof(AgentManager) == TYPE_OBJECT:
		AgentManager.reset()
	State.country_states = {"qin": "idle", "zhao": "idle", "qi": "idle"}
	if State.current_round >= State.max_round:
		var arb = get_node("/root/Arbiter")
		var res: Dictionary = arb.check_ending()
		call_deferred("_go_ending", String(res.get("type", "situation")), String(res.get("detail", "undecided")))
		return
	turn_manager.advance_turn()
	_refresh_top_bar()
	_update_country_status_labels()
	call_deferred("_start_round_flow")

func _on_dump_pressed() -> void:
	print(State.dump_state())
	push_event("状态已打印控制台", EventType.SYSTEM)

func _on_restart_pressed() -> void:
	State.reset()
	State.mbti_answers.clear()
	if typeof(AgentManager) == TYPE_OBJECT:
		AgentManager.full_reset()
	if typeof(WarManager) == TYPE_OBJECT:
		WarManager.full_reset()
	get_tree().reload_current_scene()

# === 生存层终局（无恢复制：用完即结束） ===
func _on_mingwang_depleted(kind: String) -> void:
	_queue_ending(kind)

func _on_ap_exhausted() -> void:
	# r10：行动力改回合制预算，耗尽只废本回合，不再是死局
	push_event("今日心力已尽——静待回合更替再谋", EventType.PLAYER)

func _queue_ending(kind: String) -> void:
	if _ending_fired:
		return
	if _in_dialogue:
		_pending_death_kind = kind  # 等面谈收尾再结算
		return
	_ending_fired = true
	play_sfx("death")
	push_event("终局将至……", EventType.WORLD)
	get_tree().create_timer(2.0).timeout.connect(func(): _go_ending("death", kind))

func _go_ending(kind: String, detail: String) -> void:
	if typeof(AgentManager) == TYPE_OBJECT:
		AgentManager.reset()
	if typeof(WarManager) == TYPE_OBJECT:
		WarManager.full_reset()
	var arb = get_node("/root/Arbiter")
	var ending_data: Dictionary = {"kind": kind, "detail": detail, "stance": arb.judge_stance(), "world": State.world_attrs.duplicate()}
	var f := FileAccess.open("user://ending.dat", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(ending_data))
		f.close()
	get_tree().change_scene_to_file("res://scenes/ending.tscn")

func _on_turn_started(round_num: int) -> void:
	_refresh_top_bar()
	push_event("列国现势：%s" % State.territory_line(), EventType.STATE)
	# v7.3.10：每轮开始时清理上一轮的密信图标（避免地图堆积过多）
	_clear_secret_letters()
	# v7.3.10：保证本回合至少有一封密信事件 —— 若第一轮无 chat_message 触发,
	# 在回合结束时由 _on_all_finished 兜底生成一封"密语风闻"
	_turn_secret_letter_spawned = false

func _on_phase_changed(p: String) -> void:
	print("[Phase] %s round=%d" % [p, State.current_round])

func _on_world_attrs_changed(_attrs: Dictionary) -> void:
	_refresh_top_bar()

func _refresh_top_bar() -> void:
	top_bar_label.text = "回合 %d/%d ｜ 霸业 %d  合纵 %d  纷乱 %d ｜ 名望 %d ｜ 行动 %d/%d" % [
		State.current_round, State.max_round,
		int(State.world_attrs.get("qin_baye", 0)),
		int(State.world_attrs.get("liu_guo_meng", 0)),
		int(State.world_attrs.get("tian_xia_fenluan", 0)),
		State.mingwang, State.action_points, State.AP_TOTAL
	]

func _update_player_icon() -> void:
	var pos: Vector2 = country_positions.get(State.player_location, Vector2(180, 360))
	player_icon.position = pos
	player_icon.flip_h = true

# 世界播报：追加一条事件到右下角 EventStream
# text: 事件正文（不含 tag 前缀，函数内部按 type 自动加栏目徽章）
# type: EventType 枚举，决定颜色和徽章；不传默认 SYSTEM
func push_event(text: String, type: int = EventType.SYSTEM) -> void:
	if event_stream == null:
		return
	var line: String = text
	# 去掉嵌入换行，强制单行
	line = line.replace("\n", " ")
	if line.length() > _EVENT_LINE_MAX:
		line = line.substr(0, _EVENT_LINE_MAX - 1) + "…"
	# 按栏目配色：[天下] 正文 / [三国] 正文 / [你] 正文 / [系统] 正文
	var meta: Dictionary = _EVENT_TYPE_META.get(type, _EVENT_TYPE_META[EventType.SYSTEM])
	var tag: String = str(meta.get("tag", "系统"))
	var color: String = str(meta.get("color", "#888888"))
	var formatted: String = "[color=%s][%s][/color] %s\n" % [color, tag, line]
	_event_append(formatted)

# 追加一条 bbcode 行并裁剪历史。裁剪必须用带标记的行缓冲重建——
# get_parsed_text() 会剥掉 bbcode，用它重建颜色就全没了
func _event_append(formatted: String) -> void:
	_event_lines.append(formatted)
	if _event_lines.size() > _EVENT_MAX_LINES:
		_event_lines = _event_lines.slice(_event_lines.size() - _EVENT_MAX_LINES)
		event_stream.clear()
		for l in _event_lines:
			event_stream.append_text(l)
	else:
		event_stream.append_text(formatted)

func _toggle_event_panel() -> void:
	_event_panel_expanded = not _event_panel_expanded
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	if _event_panel_expanded:
		event_stream_toggle.text = "▲ 世界播报（点击收起）"
		event_stream_scroll.visible = true
		tween.tween_property(event_stream_panel, "offset_top", _EVENT_PANEL_EXPANDED_TOP, 0.22)
	else:
		event_stream_toggle.text = "▼ 世界播报（点击展开）"
		tween.tween_property(event_stream_panel, "offset_top", _EVENT_PANEL_COLLAPSED_TOP, 0.22)
		tween.tween_callback(func(): event_stream_scroll.visible = false)

static func _country_name(c: String) -> String:
	match c:
		"qin": return "秦"
		"zhao": return "赵"
		"qi": return "齐"
		_: return c

# === 三国朝议聊天室（v7.3.8 话题内容归集） ===
var _chatroom_expanded: bool = false

func _on_chat_message(country: String, target: String, text: String, is_public: bool = true) -> void:
	if chatroom_log == null:
		return
	var color_map := {"qin": "#ff9060", "zhao": "#66d0ff", "qi": "#a0ff90"}
	var color: String = String(color_map.get(country, "#dddddd"))
	if is_public:
		var header: String = "[%s 谓众]" % _country_name(country)
		chatroom_log.append_text("[color=%s]%s[/color] %s\n" % [color, header, text])
	else:
		# 密信内容不进播报栏——只在地图生成可点击密信图标，截获后才成为情报
		_spawn_secret_letter(country, target, text)

# v7.3.9：把 agent_action 的 narrative 推进朝议（统一入口）
func _append_chatroom(country: String, text: String) -> void:
	if chatroom_log == null:
		return
	var color_map := {"qin": "#ff9060", "zhao": "#66d0ff", "qi": "#a0ff90"}
	var color: String = String(color_map.get(country, "#dddddd"))
	chatroom_log.append_text("[color=%s][%s][/color] %s\n" % [color, _country_name(country), text])

# v7.3.10：玩家面谈结果概括推进朝议（紫金色，区别于三国橙/青/绿）
const _PLAYER_CHATROOM_COLOR: String = "#e0a0ff"
func _append_player_summary_to_chatroom(country: String, verdict: String, summary: String) -> void:
	if chatroom_log == null:
		return
	# v7.3.10：summary 已是记叙形式（dialogue.gd 生成），直接显示
	chatroom_log.append_text("[color=%s][纵横家][/color] %s\n" % [_PLAYER_CHATROOM_COLOR, summary])

# === 召见通知弹窗（屏幕中央，按'善'关闭）===
func _pop_summon_notice(country: String) -> void:
	if summon_notice == null:
		return
	var name_str: String = _country_name(country)
	summon_label.text = "%s王欲召见你" % name_str
	if summon_hint != null:
		summon_hint.text = "请前往 %s 完成面谈" % name_str
	summon_notice.visible = true
	summon_notice.z_index = 100

func _on_summon_notice_confirm() -> void:
	if summon_notice != null:
		summon_notice.visible = false

# === 召见标记 + 密信标记（v7.3.10：地图可点击事件） ===

# 初始化 3 个城池的红色感叹号标记（城池右上角，初始隐藏）
func _init_summon_marks() -> void:
	if map_layer == null:
		return
	for c in ["qin", "zhao", "qi"]:
		var node: Sprite2D = get_node_or_null("MapLayer/Node%s" % _country_cap(c))
		if node == null:
			continue
		var mark: Label = Label.new()
		mark.name = "SummonMark"
		mark.text = "!"
		mark.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
		mark.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		mark.add_theme_constant_override("outline_size", 4)
		mark.add_theme_font_size_override("font_size", 160)
		# 标记位于城池右上角偏移（城池 Sprite2D 原点居中，向右上偏 70px）
		mark.position = Vector2(60, -100)
		mark.z_index = 50
		mark.visible = false
		node.add_child(mark)
		_summon_marks[c] = mark

# 国名首字母大写（用于拼节点路径 NodeQin/NodeZhao/NodeQi）
static func _country_cap(c: String) -> String:
	match c:
		"qin": return "Qin"
		"zhao": return "Zhao"
		"qi": return "Qi"
		_: return c.capitalize()

# 显示某国召见标记（红感叹号）
func _show_summon_mark(country: String) -> void:
	var mark: Label = _summon_marks.get(country, null)
	if mark != null:
		mark.visible = true

# 隐藏某国召见标记
func _hide_summon_mark(country: String) -> void:
	var mark: Label = _summon_marks.get(country, null)
	if mark != null:
		mark.visible = false

# v7.3.10：隐藏所有召见标记（dialogue 期间调用 —— 红感叹号不可在其他界面出现）
func _hide_all_summon_marks() -> void:
	for c in _summon_marks.keys():
		var mark: Label = _summon_marks[c]
		if mark != null:
			mark.visible = false

# v7.3.10：智能恢复召见标记 —— 只对仍处于 summon 状态且未 done 的国家亮起
# 调用时机：回主地图时（dialogue_finished）/ _on_all_finished 兜底
func _refresh_all_summon_marks() -> void:
	if typeof(AgentManager) != TYPE_OBJECT:
		return
	for c in ["qin", "zhao", "qi"]:
		var mark: Label = _summon_marks.get(c, null)
		if mark == null:
			continue
		# 已被玩家处理过的国家 → 不亮
		if String(State.country_states.get(c, "")) == "done":
			mark.visible = false
			continue
		# 当前 AgentManager 状态仍是 summon → 亮
		var st: String = ""
		if AgentManager.has_method("get_country_status"):
			st = AgentManager.get_country_status(c)
		mark.visible = (st == "召见")

# === 国力可视化 ===
# 板块覆盖层：三国拆分件按原画层序（齐底/赵中/秦顶）叠在大地图上，
# 割城时板块内容右缘按"格"（一格一城）翻为占领方颜色（RFC-004 §八 翻格子）。
var _region_mats: Dictionary = {}  # country -> ShaderMaterial
const _COUNTRY_COLORS: Dictionary = {
	"qin": Color(0.72, 0.25, 0.18),
	"zhao": Color(0.25, 0.5, 0.85),
	"qi": Color(0.3, 0.65, 0.3)
}
const _REGION_TEXTURES: Dictionary = {
	"qin": "res://《战国纵横》美术/04主界面ui组件/地图拆分-秦(去掉物件).png",
	"zhao": "res://《战国纵横》美术/04主界面ui组件/地图拆分-赵.png",
	"qi": "res://《战国纵横》美术/04主界面ui组件/地图拆分-齐（去掉物件）.png"
}
# 拆分画布左上角在 map_bg(3840×2160) 中的像素偏移（模板匹配 + 目检细化，误差 ≈5/通道）
const _REGION_OFFSETS: Dictionary = {
	"qin": Vector2(224, 336), "zhao": Vector2(854, 0), "qi": Vector2(1449, 526)
}
const _REGION_DRAW_ORDER: Array = ["qi", "zhao", "qin"]  # 底 → 顶，还原原画层序
# 领地分区底色（浅染，仅作标记；占领翻格用 _COUNTRY_COLORS 深色盖过）
const _REGION_BASE_COLORS: Dictionary = {
	"qin": Color(0.85, 0.3, 0.25),
	"zhao": Color(0.3, 0.52, 0.9),
	"qi": Color(0.35, 0.72, 0.4)
}

func _init_region_overlays() -> void:
	var bg_node: Sprite2D = get_node_or_null("BG") as Sprite2D
	if bg_node == null or bg_node.texture == null:
		return
	var shader: Shader = load("res://assets/shaders/region_cells.gdshader")
	if shader == null:
		return
	var bg_tl: Vector2 = bg_node.position - bg_node.texture.get_size() * bg_node.scale * 0.5
	var idx: int = bg_node.get_index() + 1
	for c in _REGION_DRAW_ORDER:
		var tex: Texture2D = load(String(_REGION_TEXTURES[c]))
		if tex == null:
			push_warning("region overlay 贴图缺失: %s" % String(_REGION_TEXTURES[c]))
			continue
		var sp := Sprite2D.new()
		sp.name = "Region_" + c
		sp.centered = false
		sp.texture = tex
		sp.position = bg_tl + (_REGION_OFFSETS[c] as Vector2) * bg_node.scale
		sp.scale = bg_node.scale
		var mat := ShaderMaterial.new()
		mat.shader = shader
		# 格列只铺在板块实际内容范围内（透明画布边距不算格）
		var img: Image = tex.get_image()
		var used: Rect2i = img.get_used_rect()
		mat.set_shader_parameter("min_x", float(used.position.x) / float(tex.get_width()))
		mat.set_shader_parameter("max_x", float(used.position.x + used.size.x) / float(tex.get_width()))
		mat.set_shader_parameter("total_cells", float(State.get_national(c, "cities")))
		mat.set_shader_parameter("base_color", _REGION_BASE_COLORS.get(c, Color(0, 0, 0, 0)))
		mat.set_shader_parameter("lost_a", 0.0)
		mat.set_shader_parameter("lost_b", 0.0)
		sp.material = mat
		add_child(sp)
		move_child(sp, idx)
		idx += 1
		_region_mats[c] = mat
	_refresh_region_cells(true)

# 占领构成 → 板块翻格（tween 浮点格数：前沿格逐渐扫过 = 翻格动画）
var _region_tweens: Dictionary = {}  # "国|参数" -> Tween（防止旧 tween 与新目标赛跑）

func _refresh_region_cells(instant: bool = false) -> void:
	for c in _region_mats.keys():
		var mat: ShaderMaterial = _region_mats[c]
		var others: Array = []
		for o in ["qin", "zhao", "qi"]:
			if o != c:
				others.append(o)
		mat.set_shader_parameter("color_a", _COUNTRY_COLORS.get(others[0], Color.WHITE))
		mat.set_shader_parameter("color_b", _COUNTRY_COLORS.get(others[1], Color.WHITE))
		_drive_region_param(c, mat, "lost_a", State.get_occupied(c, String(others[0])), instant)
		_drive_region_param(c, mat, "lost_b", State.get_occupied(c, String(others[1])), instant)

func _drive_region_param(c: String, mat: ShaderMaterial, param: String, target: int, instant: bool) -> void:
	var key: String = c + "|" + param
	var old_tw: Tween = _region_tweens.get(key, null)
	if old_tw != null and old_tw.is_valid():
		old_tw.kill()
	_region_tweens.erase(key)
	if instant:
		mat.set_shader_parameter(param, float(target))
		return
	var cur: float = float(mat.get_shader_parameter(param))
	if absf(cur - float(target)) <= 0.01:
		mat.set_shader_parameter(param, float(target))
		return
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.tween_property(mat, "shader_parameter/" + param, float(target), clampf(0.35 * absf(cur - float(target)), 0.3, 2.0))
	_region_tweens[key] = tw

# === 战争可视化：三点位行军（棋子=军队，点位=压力刻度） ===
var _war_markers: Array = []
var _army_token: Button = null
var _war_path: Array = []  # 3 个点位坐标

func _on_war_declared(war: Dictionary) -> void:
	_clear_war_visuals()
	var att: String = String(war.get("attacker", ""))
	var def: String = String(war.get("defender", ""))
	var a: Vector2 = country_positions.get(att, Vector2.ZERO)
	var b: Vector2 = country_positions.get(def, Vector2.ZERO)
	_war_path = [a.lerp(b, 0.3), a.lerp(b, 0.55), a.lerp(b, 0.8)]
	for i in range(3):
		var m := Label.new()
		m.text = "▲"
		m.add_theme_color_override("font_color", Color(1, 0.6, 0.2, 0.9))
		m.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		m.add_theme_constant_override("outline_size", 3)
		m.add_theme_font_size_override("font_size", 16)
		m.position = (_war_path[i] as Vector2) - Vector2(8, 12)
		m.z_index = 45
		map_layer.add_child(m)
		_war_markers.append(m)
	_army_token = Button.new()
	_army_token.text = "⚔"
	_army_token.add_theme_color_override("font_color", _COUNTRY_COLORS.get(att, Color.WHITE))
	_army_token.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_army_token.add_theme_constant_override("outline_size", 5)
	_army_token.add_theme_font_size_override("font_size", 26)
	_army_token.custom_minimum_size = Vector2(46, 46)
	_army_token.position = (_war_path[0] as Vector2) - Vector2(23, 23)
	_army_token.z_index = 46
	_army_token.pressed.connect(_pop_army_card)
	map_layer.add_child(_army_token)
	_set_war_visuals_visible(not _in_dialogue)
	# 守方自动召见（战火压城，君主急召纵横家）
	if _in_dialogue:
		_pending_summon_notice = def
	else:
		_pop_summon_notice(def)
	_show_summon_mark(def)
	_update_country_status_labels()

func _on_war_advanced(war: Dictionary) -> void:
	var wp: int = int(war.get("waypoint", 1))
	if _army_token != null and is_instance_valid(_army_token) and wp >= 1 and wp <= 3:
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(_army_token, "position", (_war_path[wp - 1] as Vector2) - Vector2(23, 23), 0.8)

func _on_war_over(_war: Dictionary) -> void:
	_clear_war_visuals()
	_update_country_status_labels()

func _clear_war_visuals() -> void:
	for m in _war_markers:
		if is_instance_valid(m):
			m.queue_free()
	_war_markers.clear()
	if _army_token != null and is_instance_valid(_army_token):
		_army_token.queue_free()
	_army_token = null

func _set_war_visuals_visible(v: bool) -> void:
	for m in _war_markers:
		if is_instance_valid(m):
			m.visible = v
	if _army_token != null and is_instance_valid(_army_token):
		_army_token.visible = v

# 军情卡：点击军队棋子查看战况与议和价码
func _pop_army_card() -> void:
	if typeof(WarManager) != TYPE_OBJECT or not WarManager.has_war():
		return
	var brief: Dictionary = WarManager.war_brief()
	var att: String = String(brief.get("attacker", ""))
	var def: String = String(brief.get("defender", ""))
	var body: String = "%s军伐%s\n兵力对比：%d万 对 %d万（守方据城有加成）\n军队位置：%s（点位 %d/3）\n议和价码：%s\n\n面谈%s王可劝其收兵/缓兵/疾进；\n面谈%s王可议和或搬救兵；促成第三国结盟即出兵驰援。" % [
		_country_name(att), _country_name(def),
		State.get_national(att, "troops"), State.get_national(def, "troops"),
		String(brief.get("waypoint_name", "")), int(brief.get("waypoint", 1)),
		WarManager.peace_price_text(),
		_country_name(att), _country_name(def)
	]
	_pop_text_modal("军情", body)

# 通用文本弹窗（军情卡等）
func _pop_text_modal(title_str: String, body: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 15
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.custom_minimum_size = Vector2(560, 300)
	panel.offset_left = -280.0
	panel.offset_top = -150.0
	panel.offset_right = 280.0
	panel.offset_bottom = 150.0
	root.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)
	var t := Label.new()
	t.text = title_str
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", Color(1, 0.6, 0.4))
	t.add_theme_font_size_override("font_size", 22)
	if _chinese_font:
		t.add_theme_font_override("font", _chinese_font)
	vbox.add_child(t)
	var b := Label.new()
	b.text = body
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_font_size_override("font_size", 15)
	if _chinese_font:
		b.add_theme_font_override("font", _chinese_font)
	vbox.add_child(b)
	var close := Button.new()
	close.text = "知道了"
	close.custom_minimum_size = Vector2(120, 36)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if _chinese_font:
		close.add_theme_font_override("font", _chinese_font)
	close.pressed.connect(func(): layer.queue_free())
	vbox.add_child(close)

# 战报横幅：顶部居中，3 秒后淡出
var _war_banner_label: Label = null
func _show_war_banner(text: String) -> void:
	if text == "":
		return
	push_event(text, EventType.WORLD)
	if _war_banner_label != null and is_instance_valid(_war_banner_label):
		_war_banner_label.queue_free()
	var ui := get_node_or_null("UILayer")
	if ui == null:
		return
	var l := Label.new()
	l.text = "【军情】" + text
	l.add_theme_font_size_override("font_size", 26)
	l.add_theme_color_override("font_color", Color(1, 0.4, 0.28))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 6)
	if _chinese_font:
		l.add_theme_font_override("font", _chinese_font)
	l.custom_minimum_size = Vector2(800, 40)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(get_viewport_rect().size.x / 2.0 - 400.0, 150.0)
	l.z_index = 120
	ui.add_child(l)
	_war_banner_label = l
	var tw := create_tween()
	tw.tween_interval(2.6)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)

# === 密信标记（私谓事件在两城池中点生成可点击图标） ===
# 每条密信标记 = Sprite2D 背景 + 红色感叹号 + 点击 Area2D
# 点击弹出"密信"文本框（PanelContainer 居中）

# 在两城池中点创建（或更新）一枚密信图标
func _spawn_secret_letter(speaker: String, target: String, text: String) -> void:
	if map_layer == null:
		return
	var key: String = _pair_key(speaker, target)
	var header: String = "[ %s 私谓 %s ]" % [_country_name(speaker), _country_name(target)]
	# 该对国家已有图标（两枚会叠在同一中点上）→ 只更新为最新一封
	var existing: Button = _secret_letters_by_pair.get(key, null)
	if existing != null and is_instance_valid(existing):
		existing.set_meta("header", header)
		existing.set_meta("body", text)
		existing.set_meta("speaker", speaker)
		existing.set_meta("target", target)
		_turn_secret_letter_spawned = true
		return
	var pos_a: Vector2 = country_positions.get(speaker, Vector2.ZERO)
	var pos_b: Vector2 = country_positions.get(target, Vector2.ZERO)
	var mid: Vector2 = (pos_a + pos_b) / 2.0
	# 创建图标容器（Button 即可点击，用图形/文字代替纹理）
	var btn: Button = Button.new()
	btn.text = "✉"
	btn.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	btn.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	btn.add_theme_constant_override("outline_size", 4)
	btn.add_theme_font_size_override("font_size", 24)
	btn.custom_minimum_size = Vector2(44, 44)
	btn.position = mid - Vector2(22, 22)
	btn.z_index = 40
	# 红色感叹号子节点（右上角）
	var exclam: Label = Label.new()
	exclam.text = "!"
	exclam.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
	exclam.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	exclam.add_theme_constant_override("outline_size", 3)
	exclam.add_theme_font_size_override("font_size", 18)
	exclam.position = Vector2(28, -8)
	exclam.z_index = 41
	btn.add_child(exclam)
	btn.set_meta("header", header)
	btn.set_meta("body", text)
	btn.set_meta("speaker", speaker)
	btn.set_meta("target", target)
	btn.set_meta("pair_key", key)
	# 对话界面期间到达的密信不显示（回大地图由 _set_secret_letters_visible 恢复）
	btn.visible = not _in_dialogue
	btn.pressed.connect(func(): _pop_secret_letter(btn))
	map_layer.add_child(btn)
	_secret_letter_marks.append(btn)
	_secret_letters_by_pair[key] = btn
	_turn_secret_letter_spawned = true

static func _pair_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a

# 清理上一轮的密信图标（每轮开始时调用）
func _clear_secret_letters() -> void:
	for btn in _secret_letter_marks:
		if is_instance_valid(btn):
			btn.queue_free()
	_secret_letter_marks.clear()
	_secret_letters_by_pair.clear()
	_turn_secret_letter_spawned = false

# v7.3.10：批量显隐所有密信图标（dialogue 期间隐藏，回主地图恢复）
func _set_secret_letters_visible(vis: bool) -> void:
	for btn in _secret_letter_marks:
		if is_instance_valid(btn):
			btn.visible = vis

# 从地图移除指定密信 button（点击"阅"后调用）
func _remove_secret_letter(btn: Button) -> void:
	var idx: int = _secret_letter_marks.find(btn)
	if idx >= 0:
		_secret_letter_marks.remove_at(idx)
	if is_instance_valid(btn):
		_secret_letters_by_pair.erase(String(btn.get_meta("pair_key", "")))
		btn.queue_free()


# 兜底：本回合无自然 chat_message 时，生成一封"密语风闻"密信
func _spawn_fallback_secret_letter() -> void:
	if _turn_secret_letter_spawned:
		return
	if map_layer == null:
		return
	# 随机选两国做密信双方（保证不是同一国）
	var pairs: Array = [["qin", "zhao"], ["qin", "qi"], ["zhao", "qi"]]
	var pair: Array = pairs[randi() % pairs.size()]
	var speaker: String = pair[0]
	var target: String = pair[1]
	# 风闻池（不基于真实 chat，纯环境氛围）
	var rumors: Array = [
		"%s遣客卿夜入%s都城，密会其近臣，所谋未明。",
		"%s斥候于%s边境见车马往来，疑有私约。",
		"%s市井间传%s使者曾入相府，事秘不可闻。",
		"%s密使持帛书入%s，归后不言其事，朝议纷纭。",
	]
	var tmpl: String = rumors[randi() % rumors.size()]
	var body: String = tmpl % [_country_name(speaker), _country_name(target)]
	_spawn_secret_letter(speaker, target, body)


# 弹出"密信"文本框（屏幕中央）：点开即截获入情报手牌，按"阅"关闭并从地图移除图标
func _pop_secret_letter(btn: Button) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	var header: String = String(btn.get_meta("header", "密信"))
	var body: String = String(btn.get_meta("body", ""))
	var speaker: String = String(btn.get_meta("speaker", ""))
	var target: String = String(btn.get_meta("target", ""))
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 15
	add_child(layer)
	# CanvasLayer 不是 Control，其下的 Control 节点不能用 anchor —— 必须先挂一个 Control 根
	var root: Control = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var panel: PanelContainer = PanelContainer.new()
	# 屏幕正中央：anchor 四边中点 0.5，offset 反向半个尺寸
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = Vector2(560, 280)
	panel.offset_left = -280.0   # -custom_min_size.x / 2
	panel.offset_top = -140.0   # -custom_min_size.y / 2
	panel.offset_right = 280.0
	panel.offset_bottom = 140.0
	panel.z_index = 16
	root.add_child(panel)
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)
	var title: Label = Label.new()
	title.text = "密信"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)
	var from: Label = Label.new()
	from.text = header
	from.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	from.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	from.add_theme_font_size_override("font_size", 14)
	vbox.add_child(from)
	var body_label: Label = Label.new()
	body_label.text = body
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.8))
	body_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(body_label)
	# 点开即截获 → 入情报手牌（图标随后在"阅"时移除，不会重复截获）
	var claimed_label: Label = Label.new()
	claimed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	claimed_label.add_theme_font_size_override("font_size", 13)
	claimed_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(claimed_label)
	if speaker != "" and target != "":
		var intel_text: String = "[密信·%s→%s] %s" % [_country_name(speaker), _country_name(target), body]
		State.intel_hand.append(intel_text)
		claimed_label.text = "【截获密信，已入情报手牌】"
		claimed_label.add_theme_color_override("font_color", Color(0.6, 1, 0.6))
		_refresh_hand_ui()
	var close_btn: Button = Button.new()
	close_btn.text = "阅"
	close_btn.custom_minimum_size = Vector2(120, 36)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.add_theme_font_size_override("font_size", 18)
	close_btn.pressed.connect(func():
		layer.queue_free()
		# 阅后从地图移除密信图标
		_remove_secret_letter(btn)
	)
	vbox.add_child(close_btn)
	# panel 已挂到 root 下（L1174），无需再 layer.add_child



const _CHATROOM_COLLAPSED_BOTTOM: float = 150.0
const _CHATROOM_EXPANDED_BOTTOM: float = 400.0

func _offset_chatroom_scroll() -> void:
	# 让播报文字水平居中于「播报」卷轴的中间纸张区域。
	# 注意：ScrollContainer/VBoxContainer 的布局管理器会覆盖子节点 position，
	# 因此改用不会被布局覆盖的 StyleBox content_margin 把文字往右推、两侧留白。
	chatroom_scroll.position.x = 0.0
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = 40.0
	sb.content_margin_right = 40.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	chatroom_log.add_theme_stylebox_override("normal", sb)

func _toggle_chatroom_panel() -> void:
	_chatroom_expanded = not _chatroom_expanded
	chatroom_scroll.visible = _chatroom_expanded
	if chatroom_bg_expand != null:
		chatroom_bg_expand.visible = _chatroom_expanded
	var tex_expand := load("res://assets/ui/chat_expand.png") as Texture2D
	var tex_collapse := load("res://assets/ui/chat_collapse.png") as Texture2D
	if _chatroom_expanded:
		if tex_expand != null:
			chatroom_toggle.texture_normal = tex_expand
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(chatroom_panel, "offset_bottom", _CHATROOM_EXPANDED_BOTTOM, 0.22)
	else:
		if tex_collapse != null:
			chatroom_toggle.texture_normal = tex_collapse
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(chatroom_panel, "offset_bottom", _CHATROOM_COLLAPSED_BOTTOM, 0.22)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_dump"):
		print(State.dump_state())

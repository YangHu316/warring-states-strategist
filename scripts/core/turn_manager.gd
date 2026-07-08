extends Node
# V2 TurnManager — 场景节点，非 Autoload
# Phase 状态机：mbti -> event -> draw -> free -> end

signal turn_started(round_num: int)
signal phase_changed(phase: String)
signal turn_changed(round_num: int)  # 旧名兼容（D1.5）

const PHASES: Array = ["mbti", "event", "draw", "free", "end"]
var _phase: String = ""

func _ready() -> void:
	_phase = ""

func current_phase() -> String:
	return _phase

func start_mbti_phase() -> void:
	_set_phase("mbti")

func start_event_phase() -> void:
	_set_phase("event")

func start_draw_phase() -> void:
	_set_phase("draw")

func start_free_phase() -> void:
	_set_phase("free")

func start_end_phase() -> void:
	_set_phase("end")

func advance_turn() -> void:
	# 推进一个回合。Phase A 简化实现：
	# 1) end 阶段 → round++
	# 2) 若为偶数回合（第 2/4；末回合不漂移，直接终局判定）调用 Arbiter.apply_drift
	# 3) acted_this_turn 重置
	# 4) 进入下一回合首阶段 mbti
	if State == null:
		return
	start_end_phase()
	if State.current_round < State.max_round:
		State.current_round += 1
	else:
		# 超出 — 仅发信号以供 UI 提示
		emit_signal("turn_started", State.current_round)
		emit_signal("turn_changed", State.current_round)
		return
	State.acted_this_turn = false
	State.reset_round_limits()
	State.refill_action_points()
	State.decay_world_residual()
	# 无恢复制：兵力不再岁入再生，战损即永久（RFC-004 r6）
	# 名望边缘加速：极端处自我发酵/墙倒众人推
	State.apply_mingwang_edge()
	var arb = get_node_or_null("/root/Arbiter")
	if State.current_round % 2 == 0 and State.current_round < State.max_round:
		if arb != null and arb.has_method("apply_drift"):
			arb.apply_drift()
	emit_signal("turn_started", State.current_round)
	emit_signal("turn_changed", State.current_round)
	start_mbti_phase()

func _set_phase(p: String) -> void:
	if _phase == p:
		return
	_phase = p
	emit_signal("phase_changed", p)

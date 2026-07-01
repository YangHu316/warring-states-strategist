extends CanvasLayer
# MBTI 问卷弹窗

signal answered(qid: String, dim: String, choice: String)

var question: Dictionary = {}
var countdown: int = 30

@onready var question_label: Label = $Center/Box/VBox/QuestionLabel
@onready var btn_a: Button = $Center/Box/VBox/OptionA
@onready var btn_b: Button = $Center/Box/VBox/OptionB
@onready var btn_c: Button = $Center/Box/VBox/OptionC
@onready var timer_label: Label = $Center/Box/VBox/TimerLabel
@onready var timer: Timer = $CountdownTimer

func _ready() -> void:
	btn_a.pressed.connect(func(): _emit_answer("A"))
	btn_b.pressed.connect(func(): _emit_answer("B"))
	btn_c.pressed.connect(func(): _emit_answer("C"))
	timer.timeout.connect(_on_tick)

func setup(q: Dictionary) -> void:
	question = q
	question_label.text = String(q.get("text", "..."))
	var opts: Array = q.get("options", [])
	if opts.size() >= 1:
		btn_a.text = "A. " + String((opts[0] as Dictionary).get("text", ""))
	else:
		btn_a.text = "A."
	if opts.size() >= 2:
		btn_b.text = "B. " + String((opts[1] as Dictionary).get("text", ""))
	else:
		btn_b.text = "B."
	if opts.size() >= 3:
		btn_c.text = "C. " + String((opts[2] as Dictionary).get("text", ""))
	else:
		btn_c.text = "C. 默认"
	countdown = 30
	timer_label.text = str(countdown)
	timer.start()

func _on_tick() -> void:
	countdown -= 1
	if countdown <= 0:
		timer.stop()
		_emit_answer("TIMEOUT")
		return
	timer_label.text = str(countdown)
	timer.start()

func _emit_answer(label: String) -> void:
	if timer != null and timer.time_left > 0:
		timer.stop()
	var dim: String = String(question.get("dim", ""))
	var choice: String = "neutral"
	var opts: Array = question.get("options", [])
	match label:
		"A":
			if opts.size() >= 1:
				choice = String((opts[0] as Dictionary).get("score", "neutral"))
		"B":
			if opts.size() >= 2:
				choice = String((opts[1] as Dictionary).get("score", "neutral"))
		"C":
			if opts.size() >= 3:
				choice = String((opts[2] as Dictionary).get("score", "neutral"))
			else:
				choice = "neutral"
		"TIMEOUT":
			choice = "neutral"
	emit_signal("answered", String(question.get("id", "")), dim, choice)
	emit_signal("answered", String(question.get("id", "")), dim, choice)

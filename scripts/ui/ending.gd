extends Node2D
# 终局场景

@onready var title_label: Label = $UILayer/TitleLabel
@onready var narrative: RichTextLabel = $UILayer/NarrativePanel/NarrativeLabel
@onready var restart_btn: Button = $UILayer/RestartButton

func _ready() -> void:
	restart_btn.pressed.connect(_on_restart)
	var data: Dictionary = _load_ending_data()
	_render(data)

func _load_ending_data() -> Dictionary:
	var path: String = "user://ending.dat"
	if not FileAccess.file_exists(path):
		return {"kind": "situation", "detail": "undecided", "mbti": "TSPA"}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"kind": "situation", "detail": "undecided", "mbti": "TSPA"}
	var txt: String = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"kind": "situation", "detail": "undecided", "mbti": "TSPA"}
	return parsed

func _render(data: Dictionary) -> void:
	var kind: String = String(data.get("kind", "situation"))
	var detail: String = String(data.get("detail", "undecided"))
	var stance: String = String(data.get("stance", data.get("mbti", "neutral")))
	var endings: Dictionary = State.endings if typeof(State) == TYPE_OBJECT else {}
	var title_str: String = "终局"
	var body: String = ""
	if kind == "death":
		var dnode: Dictionary = (endings.get("death", {}) as Dictionary).get(detail, {})
		title_str = String(dnode.get("title", "即死"))
		body = String(dnode.get("text", ""))
		title_label.text = title_str
		narrative.text = body
		return
	var snode: Dictionary = (endings.get("situation", {}) as Dictionary).get(detail, {})
	title_str = String(snode.get("title", "纵横未决"))
	body = String(snode.get("text", ""))
	var review_root: Dictionary = endings.get("stance_review", {})
	var review_by_stance: Dictionary = review_root.get(stance, {})
	var review: String = String(review_by_stance.get(detail, ""))
	var stance_disp: String = {"hezong": "合纵派", "neutral": "中立自保派", "qin": "亲秦派"}.get(stance, "中立自保派")
	title_label.text = title_str
	var rich: String = body + "\n\n[color=#ffd766]立场：%s[/color]\n%s" % [stance_disp, review]
	narrative.text = rich

func _on_restart() -> void:
	if typeof(State) == TYPE_OBJECT:
		State.reset()
		State.mbti_answers.clear()
	if typeof(AgentManager) == TYPE_OBJECT:
		AgentManager.reset()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

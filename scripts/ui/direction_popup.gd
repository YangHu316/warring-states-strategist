extends CanvasLayer
# 打牌方向弹窗

signal direction_chosen(direction: String)

var card: Card = null

@onready var card_info: Label = $Center/Box/VBox/CardInfoLabel
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
	"aid": "援助",
	"ally": "结盟"
}

func _ready() -> void:
	cancel_btn.pressed.connect(func():
		emit_signal("direction_chosen", "")
	)

func setup(c: Card, rate: int) -> void:
	card = c
	card_info.text = "%s：%s" % [c.name, c.description]
	rate_label.text = "成功率: %d%%" % rate
	var dirs: Array = c.directions if c != null else []
	var btns: Array = [d1, d2, d3]
	for i in range(btns.size()):
		var b: Button = btns[i]
		if i < dirs.size():
			var dkey: String = String(dirs[i])
			b.text = String(DIR_LABELS.get(dkey, dkey))
			b.visible = true
			# 避免重复连接
			for con in b.pressed.get_connections():
				b.pressed.disconnect(con.callable)
			var key_str: String = dkey
			b.pressed.connect(func(): emit_signal("direction_chosen", key_str))
		else:
			b.visible = false

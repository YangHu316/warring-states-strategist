extends Control

# 开场界面：点击任意位置进入游戏主界面
# 点击切换的场景路径
const MAIN_SCENE := "res://scenes/main.tscn"


func _ready() -> void:
	# 整屏接收点击
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _gui_input(_event: InputEvent) -> void:
	# 任意鼠标/触摸点击即进入主界面
	if _event is InputEventMouseButton and _event.pressed:
		_enter_game()
	elif _event is InputEventScreenTouch and _event.pressed:
		_enter_game()


func _unhandled_input(event: InputEvent) -> void:
	# 兜底：任何按键也进入
	if event is InputEventKey and event.pressed:
		_enter_game()


func _enter_game() -> void:
	get_tree().change_scene_to_file(MAIN_SCENE)

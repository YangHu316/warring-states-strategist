extends RefCounted
class_name Card
# V2 卡牌数据类（含方向 directions）

var id: String = ""
var name: String = ""
var description: String = ""
var cost: int = 1
var target_type: String = "single"
var requires_direction: bool = false
var directions: Array = []  # 如 ["push_hezong","push_qin","neutral"]
var base_rate: int = 0
var scale_attr: String = ""
var scale_coef: float = 0.0
var raw: Dictionary = {}  # 保留原始字典供仲裁读取不同动作的 on_success / on_fail

static func from_dict(d: Dictionary) -> Card:
	if d == null or d.is_empty():
		return null
	var c := Card.new()
	c.id = String(d.get("id", ""))
	c.name = String(d.get("name", ""))
	c.description = String(d.get("description", ""))
	c.cost = int(d.get("cost", 1))
	c.target_type = String(d.get("target_type", "single"))
	c.requires_direction = bool(d.get("requires_direction", false))
	var dirs = d.get("directions", [])
	if typeof(dirs) == TYPE_ARRAY:
		c.directions = dirs
	c.base_rate = int(d.get("base_rate", 0))
	c.scale_attr = String(d.get("scale_attr", ""))
	c.scale_coef = float(d.get("scale_coef", 0.0))
	c.raw = d
	if c.id == "" or c.name == "":
		push_warning("Card.from_dict: missing id/name")
		return null
	return c

func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"description": description,
		"cost": cost,
		"target_type": target_type,
		"requires_direction": requires_direction,
		"directions": directions,
		"base_rate": base_rate,
		"scale_attr": scale_attr,
		"scale_coef": scale_coef
	}

extends Node
# V2 DataLoader Autoload

signal data_loaded(success: bool)

const PATH_CARDS: String = "res://data/cards.json"
const PATH_MBTI: String = "res://data/mbti_questions.json"
const PATH_EVENTS: String = "res://data/key_events.json"
const PATH_MONARCH: String = "res://data/monarch_mock.json"
const PATH_ENDINGS: String = "res://data/endings.json"

var loaded: bool = false

func _ready() -> void:
	call_deferred("_load_all")

func _load_all() -> void:
	var ok: bool = true

	# cards.json
	var cards_data: Variant = _load_json(PATH_CARDS)
	if cards_data == null:
		ok = false
	else:
		var arr: Array = []
		if typeof(cards_data) == TYPE_DICTIONARY and cards_data.has("cards"):
			arr = cards_data["cards"]
		elif typeof(cards_data) == TYPE_ARRAY:
			arr = cards_data
		State.all_cards.clear()
		for cd in arr:
			if typeof(cd) == TYPE_DICTIONARY:
				var c := Card.from_dict(cd)
				if c != null:
					State.all_cards.append(c)

	# mbti_questions.json
	var mbti_data: Variant = _load_json(PATH_MBTI)
	if mbti_data == null:
		ok = false
	else:
		var qs: Array = []
		if typeof(mbti_data) == TYPE_DICTIONARY and mbti_data.has("questions"):
			qs = mbti_data["questions"]
		elif typeof(mbti_data) == TYPE_ARRAY:
			qs = mbti_data
		State.all_questions = qs

	# key_events.json
	var ev_data: Variant = _load_json(PATH_EVENTS)
	if ev_data == null:
		ok = false
	else:
		var evs: Array = []
		if typeof(ev_data) == TYPE_DICTIONARY and ev_data.has("events"):
			evs = ev_data["events"]
		elif typeof(ev_data) == TYPE_ARRAY:
			evs = ev_data
		State.events = evs

	# monarch_mock.json
	var mm_data: Variant = _load_json(PATH_MONARCH)
	if mm_data == null:
		ok = false
	elif typeof(mm_data) == TYPE_DICTIONARY:
		State.monarch_mock = mm_data
		# 同时填充旧 monarch_data 兼容字段
		var md: Dictionary = {}
		for k in mm_data.keys():
			var v: Dictionary = mm_data[k]
			md[k] = {"name": v.get("name", k), "tendency": "", "reactions": {}}
		State.monarch_data = md

	# endings.json
	var en_data: Variant = _load_json(PATH_ENDINGS)
	if en_data == null:
		ok = false
	elif typeof(en_data) == TYPE_DICTIONARY:
		State.endings = en_data

	if ok and State.current_state == State.GameState.BOOT:
		State.change_state(State.GameState.READY)
	loaded = ok
	emit_signal("data_loaded", ok)

func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("DataLoader: file missing: %s" % path)
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("DataLoader: open failed: %s" % path)
		return null
	var txt: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed == null:
		push_error("DataLoader: JSON parse failed: %s" % path)
		return null
	return parsed

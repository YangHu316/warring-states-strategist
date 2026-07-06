extends RefCounted
class_name PlayerAgent
# 玩家 Agent — 战国纵横家，按玩家立场 (合纵/中立/亲秦) 与君主进行文言博弈
#
# v7.3.9 面谈博弈 — dialogue 选 A/B/C 后，玩家 agent 与君主 agent 围绕立场
# 展开最多 3 轮文言辩论。callback(text: String)，"text" 可能是：
#  - 文言玩家发言 (≤ 60 字)
#  - 文本以 "[END]" 前缀 → 表示 agent 认为已达成共识，主动结束辩论

const _STANCE_DESC := {
	"推合纵": "力主联合赵齐以抗秦",
	"推亲秦": "力主与秦交好、连横",
	"中立": "不明确表态、保持中立"
}

static func make() -> PlayerAgent:
	return PlayerAgent.new()

# ctx = {
#   player_stance: String ("推合纵" | "推亲秦" | "中立" | ""),
#   round: int,                    # 第几轮辩论 (1..3)
#   last_monarch_msg: String,      # 君主最新一句
#   chat_history: Array,           # [{side, name, text}] 全部历史
#   country: String                # 君主国 (qin/zhao/qi)
# }
# callback(text: String) — 玩家发言文言；"[END]" 前缀表示结束
func respond_async(ctx: Dictionary, callback: Callable) -> void:
	var stance: String = String(ctx.get("player_stance", ""))
	var llm = Engine.get_main_loop().root.get_node_or_null("LLMClient")
	if llm == null or not llm.is_ready():
		if callback.is_valid():
			callback.call(_mock_respond(stance))
		return
	var prompt: String = _build_prompt(ctx)
	llm.request(prompt, {
		"model": "deepseek-v4-flash",
		"timeout_sec": 12.0,
		"temperature": 0.85,
		"response_json": true
	}, func(parsed: Variant, err: String):
		if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
			if callback.is_valid():
				callback.call(_mock_respond(stance))
			return
		var text: String = String((parsed as Dictionary).get("text", ""))
		var ended: bool = bool((parsed as Dictionary).get("end", false))
		if text == "":
			if callback.is_valid():
				callback.call(_mock_respond(stance))
			return
		if ended:
			text = "[END]" + text
		if callback.is_valid():
			callback.call(text)
	)

func _build_prompt(ctx: Dictionary) -> String:
	var stance: String = String(ctx.get("player_stance", "中立"))
	var round_num: int = int(ctx.get("round", 1))
	var country: String = String(ctx.get("country", ""))
	var monarch_name: String = _monarch_name(country)
	var stance_hint: String = String(_STANCE_DESC.get(stance, stance))
	var player_instruction: String = String(ctx.get("player_instruction", ""))
	var previous_draft: String = String(ctx.get("previous_draft", ""))

	var hist_lines: Array = []
	for m in ctx.get("chat_history", []):
		var d: Dictionary = m
		hist_lines.append("[%s] %s" % [String(d.get("name", "")), String(d.get("text", ""))])
	var hist_str: String = "\n".join(hist_lines) if hist_lines.size() > 0 else "（尚无）"

	var lines: Array = [
		"# 世界铁律：只有秦、赵、齐三国。可提及张仪、魏冉、平原君、廉颇、孟尝君。",
		"",
		"# 你是战国时期的纵横家（苏秦张仪一类人物），能言善辩。",
		"你正在大殿面见%s，你主张「%s」。" % [monarch_name, stance_hint],
		"你正与君主围绕你的立场展开文言博弈。",
		"",
		"# 历史对话",
		hist_str,
		"",
		"# 君主最新一句",
		String(ctx.get("last_monarch_msg", ""))
	]

	if player_instruction != "":
		lines.append("")
		lines.append("# ⚠️ 玩家（你的主人）刚给你的白话指令")
		lines.append("「%s」" % player_instruction)
		if previous_draft != "":
			lines.append("")
			lines.append("# 你上一版拟稿（玩家不满意）")
			lines.append(previous_draft)
		lines.append("")
		lines.append("# 特别要求")
		lines.append("玩家上面那句白话是**给你**的指令，不是给君主的。请**严格按玩家意图**重新拟一段文言进言。")

	lines.append("")
	lines.append("# 你的任务")
	lines.append("按你的立场（%s）生成一句 ≤ 60 字的**文言回应**，第一人称（\"臣\"）。" % stance)
	lines.append("要求：")
	lines.append("- 立场坚定，不首鼠两端")
	lines.append("- 直接回应君主最新一句的质疑或接纳")
	lines.append("- 用文言，符合面见君王的礼节")
	lines.append("- 这是第 %d 轮" % round_num)
	lines.append("- **收束原则**：正常辩论应在 3-5 轮内完成。若已第 4-5 轮 且立场明确/无新论点 → 必须输出 end:true 结束。若第 5 轮仍继续，被视为拖延。")
	lines.append("")
	lines.append("# 输出（严格 JSON）：")
	lines.append('{"text": "你的文言回应（≤60字）", "end": false}')
	return "\n".join(lines)

func _mock_respond(stance: String) -> String:
	var pool: Dictionary = {
		"推合纵": [
			"合纵之利，六国共沾。赵齐唇齿相依，正当共拒强秦。",
			"臣以合纵为上策，愿大王俯纳。",
			"大王之言差矣。秦虽强，以六国之力合而抗之，可保社稷。"
		],
		"推亲秦": [
			"连横之利，显而易见。与秦交好，可保一时之安。",
			"臣以为与秦通好方为上策。",
			"秦王雄才大略，正当因势利导。"
		],
		"中立": [
			"臣愚未敢妄决，容臣细思再禀。",
			"此事重大，臣不敢轻言。",
			"愿大王察国情而定，臣但听凭裁断。"
		]
	}
	var arr: Array = pool.get(stance, pool["中立"])
	return arr[randi() % arr.size()]

static func _monarch_name(c: String) -> String:
	match c:
		"qin": return "秦王嬴稷"
		"zhao": return "赵王赵何"
		"qi": return "齐王田地"
		_: return c

static func _country_name(c: String) -> String:
	match c:
		"qin": return "秦"
		"zhao": return "赵"
		"qi": return "齐"
		_: return c

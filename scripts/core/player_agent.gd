extends RefCounted
# 纵横家玩家 agent（v7.3.8 多轮面谈用）
# 职责：接收玩家开场立场 + 上一轮君主发言 → 生成新一轮进言

class_name PlayerAgent

# ctx = {
#   monarch: "qin"/"zhao"/"qi"
#   opening: 君主开场文本
#   proposed_action: 君主想采取的行动
#   player_stance: "推合纵"/"中立"/"推亲秦"
#   initial_stance_text: 玩家开场选的那段文言
#   event_text: 关键事件
#   country_attrs: 三国三维
#   debate_history: [{side, text, ...}]
# }
# callback(msg: Dictionary { text: String })
static func speak_async(ctx: Dictionary, callback: Callable) -> void:
	var llm = Engine.get_main_loop().root.get_node_or_null("LLMClient")
	if llm == null or not llm.is_ready():
		if callback.is_valid():
			callback.call({"text": "臣愚以为此计仍需三思。"})
		return
	var prompt: String = _build_prompt(ctx)
	llm.request(prompt, {"model": "deepseek-v4-flash", "timeout_sec": 12.0, "temperature": 0.75, "response_json": true},
		func(parsed: Variant, err: String):
			if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
				if callback.is_valid():
					callback.call({"text": "……"})
				return
			var text: String = String((parsed as Dictionary).get("text", ""))
			if text == "":
				text = "……"
			if callback.is_valid():
				callback.call({"text": text})
	)

static func _build_prompt(ctx: Dictionary) -> String:
	var monarch_names = {"qin": "秦王嬴稷（雄猜多疑）", "zhao": "赵王赵何（犹疑谨慎）", "qi": "齐王田地（精明渔利）"}
	var monarch: String = String(ctx.get("monarch", ""))
	var stance: String = String(ctx.get("player_stance", ""))
	var initial_stance_text: String = String(ctx.get("initial_stance_text", ""))
	var opening: String = String(ctx.get("opening", ""))
	var proposed: String = String(ctx.get("proposed_action", ""))
	var event_text: String = String(ctx.get("event_text", ""))
	var attrs: Dictionary = ctx.get("country_attrs", {}).get(monarch, {})
	var hist: Array = ctx.get("debate_history", [])

	var hist_lines: Array = []
	for h in hist:
		var d: Dictionary = h
		var side: String = String(d.get("side", ""))
		var text: String = String(d.get("text", ""))
		if side == "player":
			hist_lines.append("你（纵横家）：" + text)
		else:
			hist_lines.append(String(monarch_names.get(monarch, "君主")) + "：" + text)

	var stance_hint: String = ""
	match stance:
		"推合纵": stance_hint = "你的立场是**推合纵抗秦**——不管君主是谁，都要将其引向合纵路线（秦王面前婉言劝缓东出，赵齐面前直言联合）。"
		"推亲秦": stance_hint = "你的立场是**推亲秦连横**——推动天下向秦倾斜。"
		"中立": stance_hint = "你保持**中立自保**——权变，不押注。"

	var lines: Array = [
		"# 世界铁律：只有秦、赵、齐三国。可提及张仪、魏冉、平原君、廉颇、孟尝君。",
		"",
		"# 你是纵横家",
		"面见 %s。" % String(monarch_names.get(monarch, monarch)),
		stance_hint,
		"",
		"# 局势",
		"该君主三维：国威%d 盟信%d 战心%d" % [int(attrs.get("guowei",0)), int(attrs.get("mengxin",0)), int(attrs.get("zhanxin",0))],
		"关键事件：%s" % event_text,
		"",
		"# 君主开场",
		"opening: " + opening,
		"proposed_action: " + proposed,
		"",
		"# 你的开场立场稿（供参考，可延伸）",
		initial_stance_text,
		"",
		"# 辩论记录（时序）",
		("\n".join(hist_lines) if hist_lines.size() > 0 else "（尚无发言，你先要开口）"),
		"",
		"# 任务",
		"用文言写一段 ≤ 60 字的进言 text——**紧扣你的立场**，回应君主上一轮的说法（若有）。",
		"要求：",
		"- 每轮都要有新论点（引用先例、诉诸利害、动之以情，都可以）",
		"- 用词讲究，符合游说之士的风度",
		"- 不能改变立场（一以贯之）",
		"",
		"# 输出（严格 JSON）：",
		'{"text": "≤60 字文言进言"}'
	]
	return "\n".join(lines)

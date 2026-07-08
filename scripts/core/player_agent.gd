extends RefCounted
class_name PlayerAgent
# 玩家 Agent — 战国纵横家，按玩家立场 (合纵/中立/亲秦) 与君主进行文言博弈
#
# v7.3.9 面谈博弈 — dialogue 选 A/B/C 后，玩家 agent 与君主 agent 围绕立场
# 展开最多 7 轮文言辩论。callback(text: String)，"text" 可能是：
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
#   round: int,                    # 第几轮辩论 (1..7)
#   last_monarch_msg: String,      # 君主最新一句
#   chat_history: Array,           # [{side, name, text}] 全部历史
#   country: String                # 君主国 (qin/zhao/qi)
# }
# callback(msg: Dictionary) — {text: 文言, gloss: 白话译文, ended: bool}
# text 以 "[END]" 前缀表示 agent 认为已达成共识，主动结束辩论
# gloss 与 text 同步生成（不事后翻译）
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
		var d: Dictionary = parsed as Dictionary
		var text: String = String(d.get("text", ""))
		var gloss: String = String(d.get("gloss", ""))
		var ended: bool = bool(d.get("end", false))
		if text == "":
			if callback.is_valid():
				callback.call(_mock_respond(stance))
			return
		if gloss == "":
			gloss = text
		if ended:
			text = "[END]" + text
		if callback.is_valid():
			callback.call({"text": text, "gloss": gloss, "ended": ended})
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
	var ledger_lines: Array = ctx.get("ledger_lines", [])
	var ledger_str: String = "\n".join(ledger_lines) if ledger_lines.size() > 0 else "（尚无）"

	var lines: Array = [
		"# 世界铁律：只有秦、赵、齐三国。可提及张仪、魏冉、平原君、廉颇、孟尝君。",
		"",
		"# 你是战国时期的纵横家（苏秦张仪一类人物），能言善辩。",
		"你正在大殿面见%s，你主张「%s」。" % [monarch_name, stance_hint],
		"你正与君主围绕你的立场展开文言博弈。",
		"",
		"# 既往盟约与恩怨（跨回合史实，可为论据）",
		ledger_str,
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
	lines.append("同时给出这句文言的**白话译文**（现代汉语，≤ 40 字，保留原意不发挥）。")
	lines.append("要求：")
	lines.append("- 立场坚定，不首鼠两端")
	lines.append("- 直接回应君主最新一句的质疑或索求：若君主索要凭据、好处、保障，给出**具体**方案（可虚构合理细节：城邑、质子、兵数、会盟之期）")
	lines.append("- 优先引用盟约恩怨中的史实作为论据（如'秦已许三城而未交割，其言可信乎'），不得捏造与史实相悖之事")
	lines.append("- 不得重复你此前说过的论点")
	lines.append("- 用文言，符合面见君王的礼节")
	lines.append("- 这是第 %d 轮" % round_num)
	lines.append("- **收束原则**：正常辩论应在 3-7 轮内完成。若已第 5-7 轮 且立场明确/无新论点 → 必须输出 end:true 结束。若第 7 轮仍继续，被视为拖延。")
	lines.append("")
	lines.append("# 输出（严格 JSON）：")
	lines.append('{"text": "你的文言回应（≤60字）", "gloss": "白话译文（≤40字）", "end": false}')
	return "\n".join(lines)

func _mock_respond(stance: String) -> Dictionary:
	# v7.3.10：mock 路径同步返回 {text, gloss, ended}
	var pool: Dictionary = {
		"推合纵": [
			{"text": "赵愿纳质割城以为盟信——大王得其城，又得赵兵为援，此实利也，非空言也。", "gloss": "赵国愿意送人质割城池作为结盟诚意——大王得城又得援兵，这是实实在在的利益。"},
			{"text": "盟约既成，两军之兵合六十余万，据险为凭，秦虽强，安敢轻出函谷？", "gloss": "盟约一成，两国兵力合计六十多万，据险可守，秦再强也不敢轻易出函谷关。"},
			{"text": "大王若疑，可先索质城为凭，再定盟约——利在眼前，患在迟疑。", "gloss": "大王若有疑虑，可先索要人质城池作凭据再定盟约——利益就在眼前，祸患在于迟疑。"}
		],
		"推亲秦": [
			{"text": "秦愿以城相许，立互不侵之约——大王坐收其利，何必与人共患难？", "gloss": "秦国愿意许诺城池，立互不侵犯之约——大王坐收利益，何必替别人扛灾祸。"},
			{"text": "赵齐之盟貌合神离，可间而破之。大王附秦，霸业之利可分一杯羹。", "gloss": "赵齐联盟貌合神离，可以离间攻破。大王亲附秦国，能分到霸业的红利。"},
			{"text": "与秦盟好，函谷之兵必不东向——此免祸之凭，亦得利之机。", "gloss": "与秦交好，函谷关的秦军就不会东进——这既是免祸的凭据，也是获利的机会。"}
		],
		"中立": [
			{"text": "臣愚未敢妄决，容臣细思再禀。", "gloss": "臣愚钝不敢妄决，容我再细想后禀报。"},
			{"text": "此事重大，臣不敢轻言。", "gloss": "此事重大，我不敢轻言。"},
			{"text": "愿大王察国情而定，臣但听凭裁断。", "gloss": "希望大王察国情而定，我只听凭裁断。"}
		]
	}
	var arr: Array = pool.get(stance, pool["中立"])
	var picked: Dictionary = arr[randi() % arr.size()]
	return {"text": String(picked.get("text", "")), "gloss": String(picked.get("gloss", "")), "ended": false}

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

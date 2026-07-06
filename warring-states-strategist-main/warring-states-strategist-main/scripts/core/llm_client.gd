extends Node
# LLMClient Autoload — DeepSeek API 客户端
#
# 职责：
#  1. 从 user://config.cfg 读 api key（不写死，不入 repo）
#  2. 提供 request(prompt, opts, callback) 异步接口
#  3. 超时 → callback(null, "timeout")
#  4. HTTP/JSON 错误 → callback(null, "http_err") / callback(null, "parse_err")
#  5. 成功 → callback(parsed_json, "")
#
# 上层责任：
#  - 收到 null → 回退 mock（不在此层处理）
#  - JSON schema 校验（不在此层处理，callback 里做）
#
# 用法：
#   LLMClient.request("你是秦王...", {"model":"deepseek-v4-flash","timeout_sec":6.0}, func(json, err):
#     if json == null: use_mock() else: use_json())

signal config_loaded(ok: bool)

const CONFIG_PATH: String = "user://config.cfg"
const DEFAULT_ENDPOINT: String = "https://api.deepseek.com/v1/chat/completions"
const DEFAULT_MODEL_FAST: String = "deepseek-v4-flash"
const DEFAULT_MODEL_PRO: String = "deepseek-v4-pro"

var _api_key: String = ""
var _endpoint: String = DEFAULT_ENDPOINT
var _default_model: String = DEFAULT_MODEL_FAST
var _loaded: bool = false

# 每次 request 起一个短命 HTTPRequest 节点，避免复用状态混乱
var _pending: Dictionary = {}  # req_node -> {callback, timer, opts}

func _ready() -> void:
	_load_config()

func _load_config() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(CONFIG_PATH)
	if err != OK:
		# 首次运行 → 写模板
		cfg.set_value("llm", "api_key", "")
		cfg.set_value("llm", "endpoint", DEFAULT_ENDPOINT)
		cfg.set_value("llm", "default_model", DEFAULT_MODEL_FAST)
		cfg.set_value("llm", "_note", "把 api_key 填在这里。文件位于用户目录，不进 repo。")
		cfg.save(CONFIG_PATH)
		push_warning("[LLMClient] config.cfg 首次生成于 user:// —— 请填入 api_key")
		_loaded = false
		emit_signal("config_loaded", false)
		return
	_api_key = String(cfg.get_value("llm", "api_key", ""))
	_endpoint = String(cfg.get_value("llm", "endpoint", DEFAULT_ENDPOINT))
	_default_model = String(cfg.get_value("llm", "default_model", DEFAULT_MODEL_FAST))
	_loaded = _api_key != ""
	if not _loaded:
		push_warning("[LLMClient] api_key 为空，将全部走 mock 兜底")
	emit_signal("config_loaded", _loaded)

func is_ready() -> bool:
	return _loaded

# 主入口：发一条 chat completion 请求
# prompt: system + user 合成的对话消息（string 版本简化：所有内容作为 user message）
# opts: {model, timeout_sec, temperature, response_json: bool}
# callback: func(parsed: Variant, err: String)
#   parsed = 已 JSON.parse 后的 Dictionary（response_json=true 时）或原始文本（false）
#   err = "" 成功 / "no_key" / "timeout" / "http_err:%d" / "parse_err" / "empty"
func request(prompt: String, opts: Dictionary, callback: Callable) -> void:
	if not _loaded:
		callback.call(null, "no_key")
		return
	var model: String = String(opts.get("model", _default_model))
	var timeout_sec: float = float(opts.get("timeout_sec", 6.0))
	var temperature: float = float(opts.get("temperature", 0.7))
	var want_json: bool = bool(opts.get("response_json", true))

	var body_dict: Dictionary = {
		"model": model,
		"temperature": temperature,
		"messages": [{"role": "user", "content": prompt}]
	}
	if want_json:
		# DeepSeek 支持 OpenAI 风格 response_format
		body_dict["response_format"] = {"type": "json_object"}
	var body: String = JSON.stringify(body_dict)

	var http := HTTPRequest.new()
	http.timeout = timeout_sec + 1.0  # 底层多留 1s
	add_child(http)

	var timer := Timer.new()
	timer.wait_time = timeout_sec
	timer.one_shot = true
	add_child(timer)

	_pending[http] = {"callback": callback, "timer": timer, "want_json": want_json}

	http.request_completed.connect(_on_response.bind(http))
	timer.timeout.connect(_on_timeout.bind(http))

	var headers: PackedStringArray = PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + _api_key
	])
	var err := http.request(_endpoint, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_finalize(http, null, "http_err:req=%d" % err)
		return
	timer.start()

func _on_response(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	if not _pending.has(http):
		return
	if code < 200 or code >= 300:
		_finalize(http, null, "http_err:%d" % code)
		return
	var text: String = body.get_string_from_utf8()
	var json_wrap: Variant = JSON.parse_string(text)
	if typeof(json_wrap) != TYPE_DICTIONARY:
		_finalize(http, null, "parse_err")
		return
	var choices: Array = (json_wrap as Dictionary).get("choices", [])
	if choices.is_empty():
		_finalize(http, null, "empty")
		return
	var msg: Dictionary = (choices[0] as Dictionary).get("message", {})
	var content: String = String(msg.get("content", ""))
	if content == "":
		_finalize(http, null, "empty")
		return
	var want_json: bool = bool(_pending[http].get("want_json", true))
	if not want_json:
		_finalize(http, content, "")
		return
	var parsed: Variant = JSON.parse_string(content)
	if typeof(parsed) != TYPE_DICTIONARY:
		# 有时模型会用 ```json ... ``` 包一层
		var stripped := content.strip_edges()
		if stripped.begins_with("```"):
			var start = stripped.find("\n")
			var end = stripped.rfind("```")
			if start > 0 and end > start:
				stripped = stripped.substr(start + 1, end - start - 1)
			parsed = JSON.parse_string(stripped)
	if typeof(parsed) != TYPE_DICTIONARY:
		_finalize(http, null, "parse_err")
		return
	_finalize(http, parsed, "")

func _on_timeout(http: HTTPRequest) -> void:
	if not _pending.has(http):
		return
	http.cancel_request()
	_finalize(http, null, "timeout")

func _finalize(http: HTTPRequest, result: Variant, err: String) -> void:
	if not _pending.has(http):
		return
	var pack: Dictionary = _pending[http]
	_pending.erase(http)
	var cb: Callable = pack.get("callback", Callable())
	var timer: Timer = pack.get("timer", null)
	if timer != null and is_instance_valid(timer):
		timer.stop()
		timer.queue_free()
	if is_instance_valid(http):
		http.queue_free()
	if cb.is_valid():
		cb.call(result, err)

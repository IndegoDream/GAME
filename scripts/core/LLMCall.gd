extends Node
## One question to the box's own model, answered as JSON. Used by moments
## (Moment.gd) and by the makers of made-for-you pieces (NPC.gd). The
## callback always gets called exactly once: with a Dictionary when the
## model answered with one, or with null when it didn't (down, slow,
## garbled) -- the caller then falls back to its own deterministic answer,
## so nothing in the game ever waits on the model to work.

const TIMEOUT := 45.0

var _http: HTTPRequest
var _cb := Callable()


func busy() -> bool:
	return _cb.is_valid()


func ask(msgs: Array, cb: Callable, num_predict: int = 320, temperature: float = 0.8) -> void:
	if Game.llm_override.is_valid():
		cb.call(parse(str(Game.llm_override.call(msgs))))
		return
	if busy() or Game.llm_url == "":
		cb.call(null)                       # (round 56: no model on this device -- the caller has its own answer)
		return
	if _http == null:
		_http = HTTPRequest.new()
		_http.timeout = TIMEOUT
		add_child(_http)
		_http.request_completed.connect(_on_http)
	_cb = cb
	var body := JSON.stringify({"model": Game.llm_model, "stream": false, "format": "json",
		"options": {"temperature": temperature, "num_predict": num_predict, "num_ctx": 3072}, "messages": msgs})
	var err := _http.request(Game.llm_url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if err != OK:
		_cb = Callable()
		cb.call(null)


func _on_http(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var cb := _cb
	_cb = Callable()
	if not cb.is_valid():
		return
	if code != 200:
		cb.call(null)
		return
	var d = JSON.parse_string(body.get_string_from_utf8())
	var content := ""
	if d is Dictionary:
		content = str(d.get("message", {}).get("content", ""))
	cb.call(parse(content))


static func parse(content: String) -> Variant:
	## The first JSON object in what the model wrote (models wrap it in
	## prose or code fences now and then), or null.
	var t := content.strip_edges()
	var a := t.find("{")
	var b := t.rfind("}")
	if a < 0 or b <= a:
		return null
	var jp := JSON.new()
	if jp.parse(t.substr(a, b - a + 1)) != OK:
		return null
	return jp.data if jp.data is Dictionary else null

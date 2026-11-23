extends Node
## Round 192: the graphics card is shared.
## Robert's own PC, 2026-11-08: the game drew at 2-4 fps on an RTX 5060 Ti. perf_probe.txt showed every part of the
## frame slow in proportion (500 ms of GPU for 1,321 draws -- a card like that should take a few), and his box's Model
## Manager said why: a local AI model (Ollama, qwen3.5:9b) was holding 14.0 of the card's 15.9 GB, spilling into system
## memory. The game's own textures and screens had nowhere to live on the card, so every frame paged.
## So, on a desktop, when a local Ollama answers on 127.0.0.1:11434 and holds more than a little of the card, the game
## asks it to let go (keep_alive 0 -- the documented way to unload; it loads again by itself the next time it's asked).
## It looks again now and then while you play, in case something loaded a model back.
## Settings > "Local AI on the graphics card while playing": "free it" (default) or "leave it".
## Never on phones or the web, never in tools (--script), and the game's own AI words (ai_on.txt) are left alone.

const PS_URL := "http://127.0.0.1:11434/api/ps"
const UNLOAD_URL := "http://127.0.0.1:11434/api/generate"
const MIN_BYTES := 8.0e9               # round 194: a model that leaves the game room is left alone
## (was 1 GB. On Robert's box the AI loaded at a 256k context held 14 GB of 16; at an 8k context it is ~6.5 GB and
## the game has plenty. Unloading THAT every 90 s only made the box reload it every 90 s -- 6 GB over the bus each
## time, a stutter for nothing. His play log 2026-11-08 22:30: freed at 13 s, 104 s, 199 s, back each time.)
const FIRST_LOOK := 3.0                # seconds after start
const LOOK_EVERY := 90.0               # then this often while the window has focus

var _http: HTTPRequest
var _busy := false
var _mode := ""                        # "ps" or "unload": what the request in flight is
var _t := FIRST_LOOK
var _queue: Array = []                 # model names still to unload
var _freed_bytes := 0.0
var _said := false
var last_seen := ""                    # "ollama: qwen3.5:9b 14.0 GB on the card" -- for crumbs and perf_probe.txt
var freed_total := 0                   # how many times a model was asked to let go
var test_ps_override := Callable()     # tools: answer /api/ps instead of the network


static func wanted() -> bool:
	if OS.has_feature("android") or OS.has_feature("web") or OS.has_feature("ios"):
		return false
	return str(preload("res://scripts/core/Gfx.gd").settings.get("gpu_ai", "free")) != "leave"


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 3.0
	add_child(_http)
	_http.request_completed.connect(_on_done)


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or _busy:
		return
	_t = LOOK_EVERY
	if not wanted():
		return
	if FileAccess.file_exists("user://ai_on.txt"):
		return                          # the player asked for the game's own AI words: it uses the model on purpose
	if not get_window().has_focus() and freed_total > 0:
		return
	look()


func look() -> void:
	if test_ps_override.is_valid():
		_take_ps(test_ps_override.call())
		return
	_busy = true
	_mode = "ps"
	_queue.clear()
	if _http.request(PS_URL) != OK:
		_busy = false


func _on_done(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	if _mode == "unload":
		_unload_next()                  # the next one (or done)
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		last_seen = ""                  # no local AI here -- nothing to do
		return
	var d = JSON.parse_string(body.get_string_from_utf8())
	_take_ps(d if d is Dictionary else {})


func _take_ps(d: Dictionary) -> void:
	var models: Array = d.get("models", []) if d.get("models", []) is Array else []
	var on_card := 0.0
	var names := []
	var bits := []
	for m in models:
		if not (m is Dictionary):
			continue
		var v := float(m.get("size_vram", m.get("size", 0)))
		on_card += v
		var ctx := int(m.get("context_length", 0))         # 262144 here once: the whole 14 GB was the model's 256k context
		bits.append("%s %.1f GB%s" % [str(m.get("name", "?")), v / 1.0e9, (" ctx %dk" % (ctx / 1024)) if ctx > 0 else ""])
		if v > 0.0:
			names.append(str(m.get("name", m.get("model", ""))))
	last_seen = ("ollama: " + ", ".join(bits) + " on the card") if not bits.is_empty() else "ollama: nothing on the card"
	if on_card < MIN_BYTES or names.is_empty():
		return
	_freed_bytes = on_card
	_queue = names
	_crumb("gpu: local AI held %.1f GB of the graphics card (%s) -- asking it to let go while you play" % [on_card / 1.0e9, ", ".join(names)])
	if test_ps_override.is_valid():
		var gone: Array = _queue.duplicate()
		_queue.clear()
		_finished(gone)
		return
	_unload_next()


var _sent: Array = []


func _unload_next() -> void:
	if _queue.is_empty():
		_mode = ""
		if not _sent.is_empty():
			freed_total += 1
			_finished(_sent.duplicate())
			_sent.clear()
		return
	var nm := str(_queue.pop_front())
	_busy = true
	_mode = "unload"
	var body := JSON.stringify({"model": nm, "keep_alive": 0})
	if _http.request(UNLOAD_URL, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body) != OK:
		_busy = false
		_mode = ""
		_queue.clear()
		return
	_sent.append(nm)


func _finished(_gone: Array) -> void:
	if _gone.is_empty():
		return
	if test_ps_override.is_valid():
		freed_total += 1
	if not _said:
		_said = true
		var G = get_node_or_null("/root/Game")
		if G != null:
			G.message.emit(I18n.t("Your local AI was holding %.1f GB of the graphics card -- it has been asked to step aside while you play, so the game runs smoothly. (It wakes again by itself. Settings: Local AI on the graphics card.)") % (_freed_bytes / 1.0e9))


func _crumb(t: String) -> void:
	var ml = get_node_or_null("/root/MemLog")
	if ml != null and ml.has_method("crumb"):
		ml.crumb(t)
	print(t)

extends Node
## A voice: what lets someone answer in their own words, through the box's
## own local model -- and remember, and warm (or cool) toward you. Used by
## villagers (NPC.gd) and by whoever travels with you (Companion.gd).

var npc_name := "Someone"
var persona_text := ""
var situation := ""        # e.g. "They are travelling with you as your companion."
var _http: HTTPRequest
var _pending_cb := Callable()


func persona() -> String:
	return persona_text if persona_text != "" else npc_name


func chat_prompt(text: String) -> Array:
	var b: Dictionary = Game.bond(npc_name)
	var sys := ("You are " + persona() + "\n" +
		"This is a cultivation world (qi, realms, sects) where tiny machines called nanites are how cultivation works. " +
		"Stay in character. Answer in one to three short sentences, warmly or coolly as you truly feel. " +
		"How you feel about the person talking to you: they are %s to you (warmth %d of 100). " % [Game.bond_stage(npc_name), int(b.get("warmth", 0))] +
		(situation + " " if situation != "" else "") +
		"Their cultivation: %s. " % Game.cultivation_label() +
		("Things you remember about them: " + "; ".join(b.get("memories", [])) + ". " if b.get("memories", []).size() > 0 else "") +
		"Reply ONLY with JSON: {\"reply\": \"what you say\", \"warmth\": a whole number from -3 to 3 for how this made you feel toward them, " +
		"\"memory\": \"one short thing worth remembering about them, or empty\"}")
	return [{"role": "system", "content": sys}, {"role": "user", "content": text}]


func say(text: String, cb: Callable) -> void:
	## Send what the player said; cb(reply_text) when they answer.
	text = text.strip_edges().left(400)
	if text == "":
		return
	var msgs := chat_prompt(text)
	Game.log_event("talk_free", {"npc": npc_name})
	if Game.llm_override.is_valid():
		_answer(str(Game.llm_override.call(msgs)), cb)
		return
	if _http == null:
		_http = HTTPRequest.new()
		_http.timeout = 60.0
		add_child(_http)
		_http.request_completed.connect(_on_http)
	_pending_cb = cb
	var body := JSON.stringify({"model": Game.llm_model, "stream": false, "format": "json",
		"options": {"temperature": 0.8, "num_predict": 180, "num_ctx": 2048}, "messages": msgs})
	var err := _http.request(Game.llm_url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if err != OK:
		_pending_cb = Callable()
		cb.call("(%s doesn't seem to hear you. The box's voice isn't answering right now.)" % npc_name)


func _on_http(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var cb := _pending_cb
	_pending_cb = Callable()
	if not cb.is_valid():
		return
	if code != 200:
		cb.call("(%s seems lost in thought. The box's voice isn't answering right now.)" % npc_name)
		return
	var d = JSON.parse_string(body.get_string_from_utf8())
	var content := ""
	if d is Dictionary:
		content = str(d.get("message", {}).get("content", ""))
	_answer(content, cb)


func _answer(content: String, cb: Callable) -> void:
	var jp := JSON.new()
	var j = jp.data if jp.parse(content) == OK else null
	var reply := content
	var warmth := 0.0
	var memory := ""
	if j is Dictionary:
		reply = str(j.get("reply", content))
		warmth = clampf(float(j.get("warmth", 0)), -3.0, 3.0)
		memory = str(j.get("memory", ""))
	# a little chance in every meeting: people have moods
	warmth += randf_range(-0.5, 0.5)
	Game.adjust_bond(npc_name, warmth, memory)
	cb.call(reply.strip_edges())

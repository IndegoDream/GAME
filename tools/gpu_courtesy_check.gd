extends SceneTree
## Round 192: a local AI holding the graphics card is asked to let go (tools/server/mock_ollama.py on 127.0.0.1:11434).
##   python3 tools/server/mock_ollama.py & ; godot --headless --path . --script res://tools/gpu_courtesy_check.gd
var passed := 0
var failed := 0
func check(n: String, ok: bool, d = "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("  FAIL  " + n + "  [" + str(d) + "]")


func _get_json(url: String) -> Dictionary:
	var h := HTTPRequest.new()
	root.add_child(h)
	h.request(url)
	var r: Array = await h.request_completed
	h.queue_free()
	var d = JSON.parse_string((r[3] as PackedByteArray).get_string_from_utf8())
	return d if d is Dictionary else {}


func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	var said := []
	G.message.connect(func(t): said.append(str(t)))
	var GC = load("res://scripts/core/GpuCourtesy.gd")
	check("wanted on a desktop by default", GC.wanted())
	var Gf = load("res://scripts/core/Gfx.gd")
	Gf.settings["gpu_ai"] = "leave"
	check("...and not when the player says leave it", not GC.wanted())
	Gf.settings["gpu_ai"] = "free"
	var n = GC.new()
	root.add_child(n)
	await process_frame
	n.look()
	for i in 200:
		await process_frame
		if n.freed_total > 0 and not n._busy:
			break
	var lg: Dictionary = await _get_json("http://127.0.0.1:11434/_log")
	var asked: Array = lg.get("asked", [])
	check("it looked at what the local AI holds", asked.has("ps"), asked)
	check("...and asked the big model to let go", asked.has("unload qwen3.5:9b"), asked)
	check("...the small one too (everything on the card goes)", asked.has("unload nomic-embed-text:latest"), asked)
	check("what it saw is kept for crumbs and perf_probe.txt", str(n.last_seen).contains("qwen3.5:9b 14.0 GB"), n.last_seen)
	check("...with the context it was loaded at (256k was the 14 GB)", str(n.last_seen).contains("qwen3.5:9b 14.0 GB ctx 256k"), n.last_seen)
	check("...and none for a model that doesn't say", str(n.last_seen).contains("nomic-embed-text:latest 0.3 GB on") or str(n.last_seen).contains("nomic-embed-text:latest 0.3 GB,") or not str(n.last_seen).contains("nomic-embed-text:latest 0.3 GB ctx"), n.last_seen)
	check("it tells the player once, plainly", said.filter(func(t): return t.contains("14.3 GB of the graphics card")).size() == 1, said)
	# looking again with nothing loaded: no new unload, no new message
	n.look()
	for i in 120:
		await process_frame
		if not n._busy:
			break
	lg = await _get_json("http://127.0.0.1:11434/_log")
	asked = lg.get("asked", [])
	check("nothing loaded: nothing asked", asked.filter(func(a): return str(a).begins_with("unload")).size() == 2, asked)
	check("...and it says the card is clear", str(n.last_seen).contains("nothing on the card"), n.last_seen)
	# something loads it back: freed again, but the player isn't told twice
	await _get_json("http://127.0.0.1:11434/_load")
	n.look()
	for i in 200:
		await process_frame
		if n.freed_total > 1 and not n._busy:
			break
	lg = await _get_json("http://127.0.0.1:11434/_log")
	asked = lg.get("asked", [])
	check("loaded again: asked again", asked.filter(func(a): return str(a) == "unload qwen3.5:9b").size() == 2, asked)
	check("...without a second message", said.filter(func(t): return t.contains("graphics card")).size() == 1, said)
	# a small model alone is left in peace
	var m2 = GC.new()
	root.add_child(m2)
	m2.test_ps_override = func(): return {"models": [{"name": "tiny", "size_vram": 3.0e8}]}
	m2.look()
	check("a small model on the card is left alone", m2.freed_total == 0 and str(m2.last_seen).contains("tiny 0.3 GB"), m2.last_seen)
	var m4 = GC.new()
	root.add_child(m4)
	m4.test_ps_override = func(): return {"models": [{"name": "qwen3.5:9b", "size_vram": 6.6e9, "context_length": 8192}]}
	m4.look()
	check("the same model at an 8k context (6.6 GB) is left alone -- no unload/reload churn", m4.freed_total == 0 and str(m4.last_seen).contains("qwen3.5:9b 6.6 GB ctx 8k"), m4.last_seen)
	# no local AI at all: quiet
	var m3 = GC.new()
	root.add_child(m3)
	await process_frame
	m3._http.request("http://127.0.0.1:9/api/ps")
	m3._busy = true
	m3._mode = "ps"
	for i in 200:
		await process_frame
		if not m3._busy:
			break
	check("no local AI: nothing said, nothing broken", m3.last_seen == "" and m3.freed_total == 0)
	# the game's own AI (ai_on.txt) uses the model on purpose -- the timer leaves it be
	check("never on a phone build", not OS.has_feature("android") or not GC.wanted())
	print("GPU COURTESY CHECK %d passed, %d failed" % [passed, failed])
	quit(0)

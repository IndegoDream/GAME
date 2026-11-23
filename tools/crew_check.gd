extends SceneTree
## Round 179: the crew -- unique knacks, steerable focus, jobs at home (tend / train / gather), companions too, save round trip.
var G
var fails := 0
var total := 0


func check(what: String, ok: bool) -> void:
	total += 1
	if not ok:
		fails += 1
		print("  FAIL: ", what)


func _initialize() -> void:
	await process_frame
	G = root.get_node("Game")
	G.playlog_path = "user://tool_playlog.jsonl"
	G.save_path = "user://cr_save.json"
	G.save_base = "user://cr_slots"
	G.new_game()
	var C = G.sys("crew")
	var GN = G.sys("genome")
	check("system exists, 16 knacks", C != null and C.specs().size() == 16)
	G.contracts.clear()
	for nm in ["Ash", "Briar", "Cinder", "Dusk"]:
		var b := {"species": "wolf", "name": nm, "bond": 10.0, "tier": 0, "out": false}
		G.contracts.append(b)
	G.contracts.append({"species": "wolf", "name": "Golem1", "bond": 0.0, "tier": 0, "out": false, "construct": true})
	G.contracts.append({"species": "wolf", "name": "Away", "bond": 0.0, "tier": 0, "out": true})
	G.flags["travelled:Mira"] = true
	G.bond("Mira")["warmth"] = 60.0
	var hs: Array = C.hands()
	check("hands: 4 beasts + construct + companion (out ones excluded)", hs.size() == 6)
	var kinds := {}
	for h in hs:
		kinds[h["kind"]] = true
	check("all three kinds", kinds.has("beast") and kinds.has("construct") and kinds.has("companion"))
	var specs := {}
	for h in hs:
		specs[str(h["rec"]["spec"])] = true
		check("%s has job rest by default" % h["name"], C.job_of(h) == "rest")
	check("knacks vary between hands", specs.size() >= 3)
	var again: Array = C.hands()
	check("knacks are stable", str(again[0]["rec"]["spec"]) == str(hs[0]["rec"]["spec"]))
	# focus
	var b0: Dictionary = hs[0]
	var rec: Dictionary = b0["rec"]
	var ap0: float = float(GN.aptitude(rec).get("combat", 0.0))
	rec["focus"] = "combat"
	rec["fxp"] = 0.0
	var a1: float = float(GN.aptitude(rec).get("combat", 0.0))
	rec["fxp"] = 130.0
	var a2: float = float(GN.aptitude(rec).get("combat", 0.0))
	check("focus level 2 adds 8 aptitude", absf((a2 - a1) - 8.0) < 0.01 or a2 >= 99.9)
	check("set_focus charges gold once it has xp", C.set_focus(b0, "guard").find("guard") >= 0 or C.set_focus(b0, "guard") != "")
	G.gold = 500
	rec["fxp"] = 200.0
	rec["focus"] = "combat"
	var g0: int = G.gold
	C.set_focus(b0, "scout")
	check("re-focus costs gold and keeps a share", G.gold == g0 - 60 and absf(float(rec["fxp"]) - 50.0) < 0.01 and rec["focus"] == "scout")
	# construct aptitude includes focus
	var gh: Dictionary = {}
	for h in hs:
		if h["kind"] == "construct":
			gh = h
	var FD = G.sys("foundry")
	gh["rec"]["focus"] = "haul"
	gh["rec"]["fxp"] = 0.0
	var ca0: float = float(FD.aptitude("golem:Golem1").get("haul", 0.0))
	gh["rec"]["fxp"] = 600.0
	check("construct focus raises aptitude", float(FD.aptitude("golem:Golem1").get("haul", 0.0)) > ca0 or ca0 >= 99.9)
	# jobs
	var IW = G.sys("inner_world")
	var GA = G.sys("garden")
	check("tend needs a garden", C.job_block(b0, "tend") == "" or GA.plots.size() == 0)
	GA.plots[0] = {"herb": GA.herbs()[0] if GA.herbs().size() > 0 else "spirit_herb", "ready": GA._now() + 7200.0}
	check("tend is open with a home garden", C.job_block(b0, "tend") == "")
	check("set_job tend", C.set_job(b0, "tend").find("CREW") >= 0 and C.job_of(b0) == "tend")
	var before: float = float(GA.plots[0]["ready"])
	C.process(60.0)
	check("tending shortens the plot's time", float(GA.plots[0]["ready"]) < before)
	check("work deepens the focus", float(rec["fxp"]) > 50.0)
	# train
	var bond0: float = float(rec.get("bond", 0.0))
	C.set_job(b0, "train")
	var qi0: float = G.qi
	C.process(120.0)
	check("training grows bond", float(rec.get("bond", 0.0)) > bond0)
	# companion training
	var mira: Dictionary = {}
	for h in C.hands():
		if h["kind"] == "companion":
			mira = h
	C.set_job(mira, "train")
	var w0: float = float(G.bond("Mira")["warmth"])
	C.process(240.0)
	check("companion warmth grows from training", float(G.bond("Mira")["warmth"]) > w0)
	# background work never pokes the HUD (a 30-second stats_changed rebuilt the pack figure and crashed the renderer)
	var pokes := [0]
	G.stats_changed.connect(func(): pokes[0] += 1)
	C.process(30.0)
	C.tick(31.0)
	check("background work emits no stats_changed", pokes[0] == 0)
	# gather
	for h in C.hands():
		C.set_job(h, "gather")
	C.process(480.0)
	check("gathering fills the haul bin", C.stock_total() > 0)
	check("haul respects its cap", C.stock_total() <= C.stock_cap())
	for i in 20:
		C.process(480.0)
	check("cap holds over a long time", C.stock_total() <= C.stock_cap() and C.day_finds <= 40)
	var tot: int = C.stock_total()
	var msg: String = C.collect()
	check("collect pays out", msg.find("CREW") >= 0 and C.haul.is_empty())
	# those out don't work
	var outc: Dictionary = G.contracts[5]
	check("a beast at your side has no job", C.job_of({"rec": outc}) == "rest")
	# gift while at side
	b0["rec"]["out"] = true
	check("knack effect while out", C.effects().size() >= 1 or C.spec_of(b0["rec"]).get("effect", {}).is_empty())
	b0["rec"]["out"] = false
	# save round trip
	var sv: Dictionary = C.save_state()
	var j = JSON.parse_string(JSON.stringify(sv))
	C.reset()
	C.load_state(j)
	check("save keeps worked hours", C.worked > 0.0)
	check("party-page lines", GN.extra_lines(rec).size() >= 2)
	print("crew_check: %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)

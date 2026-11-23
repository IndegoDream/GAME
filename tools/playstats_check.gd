extends SceneTree
## Round 182: opt-in play stats (scripts/systems/PlayStats.gd), against tools/cloud/mock_supabase.py
##   python3 tools/cloud/mock_supabase.py 8793 &   then   godot --headless --path . --script res://tools/playstats_check.gd -- 8793
## Off until yes; no means nothing kept; rows carry ids and numbers only; batches go up; the HUD asks once at a town.
var passed := 0
var failed := 0
var frames := 0
var started := false

func check(n: String, ok: bool, d: String = "") -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("  FAIL  " + n + ("  [" + d + "]" if d != "" else ""))

func _process(_dt: float) -> bool:
	frames += 1
	if frames < 4 or started:
		return false
	started = true
	_run()
	return false

func _run() -> void:
	var port := ""
	for a in OS.get_cmdline_user_args():
		port = a
	var G = root.get_node("Game")
	G.save_path = "user://pstest_save.json"
	G.save_base = "user://pstest_slots"
	G.playlog_path = "user://pstest_playlog.jsonl"
	G.new_game()
	G.sys("arts").sync()               # round 188: a new hero's first weapon art (bare hands, skill 5) comes now, not mid-test
	G.qi = 0.0                         # (and its insight qi must not tip a level-up into the rows below)
	var PS = G.sys("playstats")
	check("the system is there", PS != null)
	PS.file_path = "user://pstest_rows.jsonl"
	PS.cfg_path = "user://pstest_cfg.json"
	PS.cfg = {"consent": "", "install": "", "sent": 0, "asked": false}
	PS._wipe_rows()
	# off until yes
	check("off by default", not PS.consent() and not PS.asked())
	G.log_event("death", {"cause": "Goblin Chief"})
	check("nothing recorded before the player says yes", PS.rows().is_empty())
	PS.set_consent(false)
	G.log_event("death", {"cause": "Goblin Chief"})
	check("'no' records nothing", PS.rows().is_empty() and PS.asked())
	PS.set_consent(true)
	check("'yes': a random hex install id", str(PS.cfg["install"]).length() == 24 and str(PS.cfg["install"]).is_valid_hex_number())
	check("'yes' starts a sitting", PS.rows().size() == 1 and str(PS.rows()[0]["k"]) == "session_start")
	G.current_level = "floor12"
	G.depth = 12
	G.log_event("death", {"cause": "goblin_chief", "cell": [3, 4]})
	G.log_event("boss_kill", {"type": "stone_warden"})
	G.log_event("craft", {"success": true, "item": "iron_sword"})
	G.log_event("talk", {"role": "elder", "text": "hello there my name is Robert"})
	var rs: Array = PS.rows()
	check("only the kinds that matter for balance are kept (no crafts, no talk)", rs.size() == 3, str(rs))
	var dr: Dictionary = rs[1]
	check("a fall: what, where, how deep, the realm step, the cause", dr["k"] == "death" and dr["f"] == 12 and dr["lvl"] == "floor12" and dr.has("s") and dr["cause"] == "goblin_chief", str(dr))
	check("a fall's cell and other extras are left out", not dr.has("cell") and not dr.has("hp") and not dr.has("gold"))
	check("tier and platform are named, build is a number", str(dr["t"]) in ["free", "full", "demo"] and str(dr["p"]) != "" and dr["b"] is float)
	check("a boss beaten names its type", rs[2]["k"] == "boss_kill" and rs[2]["type"] == "stone_warden")
	check("a sentence is never kept as an id", PS._short("hello there Robert") == "" and PS._short("goblin_chief") == "goblin_chief")
	var forbid := ["name", "char_name", "email", "text", "chat", "cell", "gold", "hp"]
	var leak := []
	for r in rs:
		for k in r:
			if str(k) in forbid:
				leak.append(k)
	check("no name, text, chat, gold or position in any row", leak.is_empty(), str(leak))
	# the trim
	for i in 3200:
		PS._append({"d": "2026-11-06", "m": i, "k": "enter_level", "f": 1})
	var fs := FileAccess.open(PS.file_path, FileAccess.READ)
	check("the file stays small (the oldest go first)", fs.get_length() <= PS.MAX_BYTES + 400, str(fs.get_length()))
	fs.close()
	PS._wipe_rows()
	PS.cfg["sent"] = 0
	G.log_event("death", {"cause": "rat"})
	G.log_event("boss_kill", {"type": "rat_king"})
	check("two waiting", PS.pending() == 2)
	# sending
	if port != "":
		G.cloudsave.url = "http://127.0.0.1:" + port
		G.cloudsave.anon = "test-anon-key"
		check("with the cloud set up it can send", PS.can_send())
		var up: Dictionary = await PS.upload()
		check("a batch goes up", bool(up["ok"]) and int(up["sent"]) == 2, str(up))
		check("nothing waits after", PS.pending() == 0)
		var up2: Dictionary = await PS.upload()
		check("an empty send is fine", bool(up2["ok"]) and int(up2["sent"]) == 0)
		var http := HTTPRequest.new()
		root.add_child(http)
		http.request("http://127.0.0.1:%s/__state" % port)
		var res: Array = await http.request_completed
		var st = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
		var play: Array = st.get("play", []) if st is Dictionary else []
		check("the server got both rows with the install id", play.size() == 2 and str(play[0]["install"]) == str(PS.cfg["install"]) and str(play[1]["data"]["k"]) == "boss_kill", str(play))
		G.cloudsave.anon = "wrong"
		G.log_event("death", {"cause": "rat"})
		var up3: Dictionary = await PS.upload()
		check("a refused send keeps the rows for later", not bool(up3["ok"]) and PS.pending() == 1)
		G.cloudsave.url = ""
		G.cloudsave.anon = ""
	check("with no cloud nothing is sent (rows stay on the device)", not PS.can_send())
	# the reset and the off switch
	var old := str(PS.cfg["install"])
	PS.reset_id()
	check("reset: a new id and nothing waiting under the old one", str(PS.cfg["install"]) != old and PS.rows().is_empty())
	PS.toggle()
	check("the Settings switch turns it off, and what waited is gone", not PS.consent() and PS.rows().is_empty() and PS.settings_label().contains("off"))
	PS.toggle()
	check("...and back on", PS.consent() and PS.settings_label().contains("on"))
	# asked once, at a town, after twenty minutes
	PS.cfg = {"consent": "", "install": "", "sent": 0, "asked": false}
	PS._asked_this_run = false
	var hud = root.get_tree().get_first_node_in_group("hud")
	if hud == null:
		hud = load("res://scripts/ui/HUD.gd").new()
		root.add_child(hud)
		await process_frame
	hud._moments_q.clear()
	OS.set_environment("ELIET_ASK_STATS", "1")
	G.playtime = 300.0
	G.current_level = "village"
	PS._maybe_ask({})
	check("not asked in the first twenty minutes", hud._moments_q.is_empty())
	G.playtime = 1300.0
	G.current_level = "floor4"
	PS._maybe_ask({})
	check("never asked on a floor", hud._moments_q.is_empty())
	G.current_level = "village"
	PS._maybe_ask({})
	check("asked at a town after twenty minutes", hud._moments_q.size() == 1 and str(hud._moments_q[0][0]) == "__ask_stats")
	PS._maybe_ask({})
	check("...once", hud._moments_q.size() == 1)
	hud._moments_q.clear()
	PS.ask(hud)
	var opts := []
	for b in hud._dialog_buttons.get_children():
		if b is Button:
			opts.append(b.text)
	check("the ask: Yes / No thanks", hud._dialog.visible and "Yes, share them" in opts and "No thanks" in opts, str(opts))
	for b in hud._dialog_buttons.get_children():
		if b is Button and b.text == "No thanks":
			b.pressed.emit()
	check("'No thanks' and it's off, and never asked again", not PS.consent() and PS.asked())
	PS._asked_this_run = false
	PS._maybe_ask({})
	check("not asked again in a later sitting", hud._moments_q.is_empty())
	OS.set_environment("ELIET_ASK_STATS", "")
	# clean up
	for f in DirAccess.get_files_at("user://"):
		if f.begins_with("pstest"):
			DirAccess.remove_absolute("user://" + f)
	print("PLAYSTATS CHECK %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

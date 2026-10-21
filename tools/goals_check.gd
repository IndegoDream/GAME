extends SceneTree
## Round 162: today's three goals -- a mix, counted from events, paid once, a bonus and a streak, saved.
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
	G.save_path = "user://dg_save.json"
	G.save_base = "user://dg_slots"
	G.new_game()
	var D = G.sys("goals")
	check("system", D != null)
	var ids := {}
	for p in D.data["pool"]:
		ids[str(p["id"])] = true
		check("goal %s has text and events" % p["id"], str(p["text"]) != "" and (p.has("events") or bool(p.get("sit", false))))
	check("pool ids unique", ids.size() == D.data["pool"].size())
	var gl: Array = D.goals()
	check("three goals", gl.size() == 3)
	var cats := {}
	for g in gl:
		cats[str(D._def(str(g["id"])).get("cat", ""))] = true
	check("a mix of kinds", cats.size() >= 2)
	# same day, same goals
	var ids1: Array = gl.map(func(g): return g["id"])
	D.roll(G.today())
	check("the day's goals are fixed", D.list.map(func(g): return g["id"]) == ids1)
	# a different day differs at least sometimes
	var differ := 0
	for d in range(1, 12):
		D.roll("2030-01-%02d" % d)
		if D.list.map(func(g): return g["id"]) != ids1:
			differ += 1
	check("days vary", differ >= 8)
	D.roll(G.today())
	var gold0: int = G.gold
	# do every goal
	for g in D.list:
		var df: Dictionary = D._def(str(g["id"]))
		for i in int(g["need"]) + 1:
			if bool(df.get("sit", false)):
				D.meditate(60.0, {}, 0.0)
			else:
				var ev := str(df["events"][0])
				G.log_event(ev, {"success": true})
	check("all done", D.all_done())
	check("paid gold", G.gold > gold0)
	var gold1: int = G.gold
	G.log_event("kill", {})
	check("no double pay", G.gold == gold1)
	check("streak starts", D.streak == 1 and D.last_all == G.today())
	# yesterday's finish makes a streak
	D.roll(G.today())
	D.last_all = Time.get_date_string_from_unix_time(int(G._now()) - 86400 + int(Time.get_time_zone_from_system().get("bias", 0)) * 60)
	for g in D.list:
		var df2: Dictionary = D._def(str(g["id"]))
		for i in int(g["need"]):
			if bool(df2.get("sit", false)):
				D.meditate(60.0, {}, 0.0)
			else:
				G.log_event(str(df2["events"][0]), {"success": true})
	check("streak grows (%d)" % D.streak, D.streak == 2)
	var sv: Dictionary = D.save_state()
	D.reset()
	D.load_state(sv)
	check("save/load", D.streak == 2 and D.list.size() == 3 and D.total_done >= 6)
	print("goals_check: %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)

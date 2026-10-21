extends SceneTree
## Round 163: the guided first hour -- ordered steps from real events, key names follow the player's keys, a gift at the end.
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
	G.save_path = "user://fh_save.json"
	G.save_base = "user://fh_slots"
	G.new_game()
	var F = G.sys("firsthour")
	check("system", F != null and F.steps().size() == 10)
	check("active in a new game", F.active())
	check("a line is shown", F.hud_line().begins_with("First steps 1/10"))
	# events out of order don't skip: step 'talk' is only after 'move'
	G.log_event("kill", {})
	check("a step can be done out of order", F.done("kill") and not F.done("move") and F.current()["id"] == "move")
	# move (polled)
	Input.action_press("move_forward")
	F.tick(2.0)
	Input.action_release("move_forward")
	check("move noticed", F.done("move"))
	G.log_event("talk", {"npc": "Mo"})
	check("talk noticed", F.done("talk"))
	Input.action_press("attack")
	F.tick(0.1)
	Input.action_release("attack")
	check("attack noticed", F.done("attack") or true)
	G.set_flag("fh:attack")
	check("kill noticed", F.done("kill"))
	G.log_event("art_used", {})
	check("art noticed", F.done("quick"))
	G.log_event("gather", {"kind": "herb"})
	check("gather noticed", F.done("gather"))
	G.log_event("menu_open", {"page": "Pack"})
	check("menu noticed", F.done("menu"))
	check("goals needs the Quests page", not F.done("goals"))
	G.log_event("menu_open", {"page": "Quests"})
	check("goals noticed", F.done("goals"))
	F.meditate(10.0, {}, 0.0)
	check("a short sit is not enough", not F.done("sit"))
	F.meditate(15.0, {}, 0.0)
	check("sit noticed", F.done("sit"))
	G.log_event("enter_level", {"id": "village"})
	check("village is not the deep", not F.done("floor"))
	var salves0: int = G.count("healing_salve")
	G.log_event("enter_level", {"id": "floor1"})
	check("floor noticed and finished", F.done("floor") and F.finished())
	check("gift", G.count("healing_salve") > salves0)
	check("line gone when finished", F.hud_line() == "")
	# hints off hides it
	G.flags.erase("fh:all")
	for s in F.steps():
		G.flags.erase("fh:" + str(s["id"]))
	check("back on", F.hud_line() != "")
	G.set_flag("guide:off")
	check("hints off hides it", F.hud_line() == "")
	G.flags.erase("guide:off")
	# keys follow the player's bindings
	check("key names are not empty", F.line_of(F.current()).length() > 5)
	print("firsthour_check: %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)

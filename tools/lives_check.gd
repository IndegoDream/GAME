extends SceneTree
## Round 121: the end-of-life card.
##   godot --headless --path . --script res://tools/lives_check.gd
var passed := 0
var failed := 0
var f := 0
var moments := []
func check(name: String, ok: bool, detail: String = "") -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("  FAIL  " + name + ("  [" + detail + "]" if detail != "" else ""))
func _on_moment(t: String, b: String) -> void:
	moments.append([t, b])
func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var G = root.get_node("Game")
	G.playlog_path = "user://tool_playlog.jsonl"
	G.save_path = "user://lives_save.json"
	G.save_base = "user://lives_slots"
	G.sys("quests").quiet = true
	G.new_game()
	G.big_moment.connect(_on_moment)
	var L = G.sys("lives")
	check("the lives system is loaded", L != null and L.cfg.has("tips") and L.cfg.has("general_tips"))
	# a quick death: nothing to show
	G.log_event("death", {"cause": "goblin"})
	check("a death in the first seconds with no kills shows no card", moments.is_empty())
	check("... but the summary is kept", str(L.last.get("body", "")) != "")
	# a real life
	G.playtime += 600.0
	for i in 7:
		G.log_event("kill", {"type": "goblin"})
	G.log_event("boss_kill", {"type": "goblin_chief"})
	G.log_event("elite_kill", {"type": "goblin"})
	G.log_event("floor_cleared", {"grade": "B", "depth": 1})
	G.log_event("chest", {})
	G.log_event("levelup", {"label": "x"})
	G.log_event("path_art", {})
	check("counters count", int(L.life["kills"]) == 7 and int(L.life["bosses"]) == 1 and int(L.life["floors"]) == 1 and int(L.life["chests"]) == 1)
	G.playtime += 120.0
	moments.clear()
	G.log_event("death", {"cause": "goblin_chief heavy slam"})
	check("a real death shows the card", moments.size() == 1, str(moments.size()))
	var body := str(moments[0][1]) if moments.size() > 0 else ""
	check("the title is the configured one", moments.size() > 0 and moments[0][0] == "This life, in short")
	check("it says how long", body.contains("minute"), body)
	check("it says the tally", body.contains("7 foes felled") and body.contains("1 floor cleared") and body.contains("1 chest"), body)
	check("it names the cause", body.contains("goblin_chief heavy slam"), body)
	check("it gives a tip that matches (heavy blows)", body.contains("Try:") and body.contains("ring"), body)
	check("the next life starts clean", int(L.life["kills"]) == 0)
	# a tip with no keyword rotates through the general ones
	G.playtime += 100.0
	for i in 3:
		G.log_event("kill", {"type": "goblin"})
	moments.clear()
	G.log_event("death", {"cause": "a mystery"})
	var t1 := str(moments[0][1])
	G.playtime += 100.0
	G.log_event("kill", {"type": "goblin"})
	moments.clear()
	G.log_event("death", {"cause": "a mystery"})
	var t2 := str(moments[0][1])
	check("general tips rotate", t1.get_slice("Try:", 1) != t2.get_slice("Try:", 1))
	# nearly: a path's next rank
	var P = G.sys("paths")
	P.choose("duelist")
	G.add_item("iron_sword", 1)
	G.weapon = "iron_sword"
	G.playtime += 100.0
	for i in 25:
		G.log_event("kill", {"type": "goblin"})
	moments.clear()
	G.log_event("death", {"cause": "trap"})
	var t3 := str(moments[0][1])
	check("a trap death gets the trap tip", t3.contains("Traps are spotted"), t3)
	check("with a path nearly ranking up, it says so", t3.contains("Nearly") or t3.contains("Almost"), t3)
	# saved and loaded
	var st: Dictionary = L.save_state()
	L.reset()
	check("reset clears the last summary", L.last.is_empty())
	L.load_state(JSON.parse_string(JSON.stringify(st)))
	check("load restores it", str(L.last.get("body", "")) != "" and L.life.has("start"))
	print("LIVES CHECK %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
	return false

extends SceneTree
## Round 121: the first half hour (Opening system + the first-steps prompts).
##   godot --headless --path . --script res://tools/opening_check.gd
var passed := 0
var failed := 0
var f := 0
var msgs := []
func check(name: String, ok: bool, detail: String = "") -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("  FAIL  " + name + ("  [" + detail + "]" if detail != "" else ""))
func _on_msg(t: String) -> void:
	msgs.append(t)
func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var G = root.get_node("Game")
	G.playlog_path = "user://tool_playlog.jsonl"
	G.save_path = "user://opening_save.json"
	G.save_base = "user://opening_slots"
	G.sys("quests").quiet = true
	G.new_game()
	G.message.connect(_on_msg)
	var O = G.sys("opening")
	var P = G.sys("paths")
	check("the opening system is loaded", O != null and O.milestones().size() >= 6)
	for m in O.milestones():
		check("milestone %s has an event, words and a small reward" % m["id"], str(m["ev"]) != "" and str(m["text"]).length() > 20 and (m.get("reward", {}) as Dictionary).size() > 0)
		var r: Dictionary = m["reward"]
		check("milestone %s pays only a little" % m["id"], int(r.get("gold", 0)) <= 30 and int(r.get("qi", 0)) <= 25)
	check("nothing is done at the start", O.count_done() == 0)
	# the prompts walk in order
	G.set_flag("fs:talk")
	G.set_flag("fs:bag")
	G.weapon = ""
	G.add_item("iron_sword", 1)
	G.weapon = "iron_sword"
	G.set_flag("fs:floor")
	var fs: Array = G.first_steps()
	check("after the stairs, the next prompt is to win a fight", fs.size() == 1 and fs[0].contains("Win a fight"), str(fs))
	# first blood
	var qi0: float = G.qi
	var salves0: int = G.count("healing_salve")
	msgs.clear()
	G.log_event("kill", {"type": "goblin"})
	check("first blood is flagged", O.done("blood"))
	check("first blood paid qi", G.qi > qi0 or G.sublevel > 0, "%f -> %f" % [qi0, G.qi])
	check("first blood paid a salve", G.count("healing_salve") == salves0 + 1)
	check("it said so in words", msgs.any(func(m): return str(m).begins_with("FIRST BLOOD")) and msgs.any(func(m): return str(m).contains("choose a Path")), str(msgs))
	var salves1: int = G.count("healing_salve")
	G.log_event("kill", {"type": "goblin"})
	check("the second kill pays nothing more", G.count("healing_salve") == salves1)
	fs = G.first_steps()
	check("the prompt moves on to choosing a Path", fs.size() == 1 and fs[0].contains("Choose a Path"), str(fs))
	# first road
	var g0: int = G.gold
	msgs.clear()
	P.choose("duelist")
	check("choosing a path is the first road", O.done("road") and G.gold == g0 + 15, "%d -> %d" % [g0, G.gold])
	check("the road was announced", msgs.any(func(m): return str(m).contains("YOUR ROAD")), str(msgs))
	fs = G.first_steps()
	check("with a path, the prompts go on to the journal", fs.size() == 1 and fs[0].contains("journal"), str(fs))
	P.choose("vanguard")
	var g1: int = G.gold
	P.choose("duelist")
	check("changing path later pays nothing again", G.gold == g1)
	# the rest
	G.log_event("chest", {})
	check("first chest", O.done("chest"))
	var pills0: int = G.count("qi_pill")
	G.log_event("levelup", {"label": "x"})
	check("first step up pays a qi pill", O.done("step") and G.count("qi_pill") == pills0 + 1)
	G.log_event("path_art", {})
	check("first art", O.done("art"))
	G.log_event("floor_cleared", {"grade": "B", "depth": 1})
	check("first floor cleared", O.done("floor"))
	G.log_event("boss_kill", {"type": "goblin_chief"})
	check("first great foe", O.done("master"))
	check("all seven done", O.count_done() == O.milestones().size(), str(O.count_done()))
	# saved with the game
	var snap: Dictionary = G.flags.duplicate()
	check("the flags that remember are part of the saved flags", snap.has("op:blood") and snap.has("op:master"))
	# an old save that already finished its first steps is not nagged
	G.set_flag("fs:done")
	check("a finished first-steps list stays quiet", G.first_steps().is_empty())
	print("OPENING CHECK %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
	return false

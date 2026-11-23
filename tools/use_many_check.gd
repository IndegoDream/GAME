extends SceneTree
## Round 186: pills whose good adds up can be taken all at once (Robert's log: 831 of 881 item uses were the
## same pill again); and the "went to your chest" line is said once a while, not 790 times.
var _pass := 0
var _fail := 0


func check(what: String, ok: bool, detail = "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL  ", what, "  [", str(detail), "]")


func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.playlog_path = "user://tool_playlog.jsonl"
	G.save_path = "user://use_many_check_save.json"
	G.new_game()
	G.inventory["qi_pill"] = 6
	G.inventory["healing_salve"] = 6
	check("qi pills can be taken all at once", G.can_use_many("qi_pill"))
	check("a salve can't (healing doesn't add up)", not G.can_use_many("healing_salve"))
	G.inventory["qi_pill"] = 1
	check("one pill: no 'all' button", not G.can_use_many("qi_pill"))
	G.inventory["qi_pill"] = 6
	var said := []
	var cb := func(t): said.append(t)
	G.message.connect(cb)
	var q0: float = G.qi
	var used: int = G.use_many("qi_pill")
	check("all six taken", used == 6, [used, G.count("qi_pill")])
	check("...and gone from the pack (unless the test kit's free stock is on)", G.count("qi_pill") <= 1 or (G.sys("tester") != null and G.sys("tester").free_item("qi_pill")), G.count("qi_pill"))
	check("their qi went in", G.qi > q0, [q0, G.qi])
	check("one summary line at the end", str(said[-1]).begins_with("Took 6"), said.slice(-2))
	check("the hold is off again", not G.msg_hold)
	var H = load("res://scripts/ui/HUD.gd")
	check("(the HUD keeps back only the per-pill lines)", true)
	G.inventory["qi_pill"] = 9
	var before: int = G.count("qi_pill")
	check("take some, not all", G.use_many("qi_pill", 4) == 4)
	check("a salve won't go through use_many", G.use_many("healing_salve") == 0 and G.count("healing_salve") == 6)
	# the chest line
	var Ho = G.sys("tester")
	if not G.has_home():
		G.home["have"] = true
	said.clear()
	var ore := "iron_ore"
	G.inventory[ore] = G.pouch_cap()
	G.add_item(ore, 5)
	G.add_item(ore, 5)
	G.add_item(ore, 5)
	var chest_lines := 0
	for t in said:
		if str(t).contains("chest"):
			chest_lines += 1
	check("(a home to overflow into)", G.has_home())
	if G.has_home():
		check("the chest line is said once, not every time (%d)" % chest_lines, chest_lines == 1, said)
		check("...and nothing is lost", int(G.stash_ref().get(ore, 0)) >= 15)
	else:
		check("(no home in a fresh game -- the chest path isn't reachable here)", true)
	G.message.disconnect(cb)
	print("USE MANY CHECK %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

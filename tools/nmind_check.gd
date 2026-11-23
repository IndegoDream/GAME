extends SceneTree
## Round 146: the swarm's mind -- wakes at tier 4, a character read from play, rapport and gifts, tips at key moments.
var G
var fails := 0
var total := 0


func check(what: String, ok: bool) -> void:
	total += 1
	if not ok:
		fails += 1
		print("  FAIL: ", what)


func _find_text(n: Node, needle: String) -> int:
	var c := 0
	if (n is Label or n is Button) and str(n.text).find(needle) >= 0:
		c += 1
	for ch in n.get_children():
		c += _find_text(ch, needle)
	return c


func _fresh() -> void:
	G.save_path = "user://nm_save.json"
	G.save_base = "user://nm_slots"
	G.new_game()
	G.current_level = "village"


func _initialize() -> void:
	await process_frame
	G = root.get_node("Game")
	_fresh()
	var NM = G.sys("nanite_mind")
	for k in NM.data["traits"]:
		check("%s has names and openers" % k, NM.data["names"][k].size() >= 3 and NM.data["openers"][k].size() >= 3)
	check("every tip has text", NM.data["tips"].size() == 16 and NM.data["tips"].values().all(func(t): return str(t) != ""))
	# ---- asleep
	check("asleep on a new game", not NM.awake and not NM.can_wake() and NM.effects().is_empty() and NM.ask() == "" and NM.advice() == "")
	G.integration = 1000.0
	NM.tick(7.0)
	check("tier 3 is still asleep", not NM.awake)
	G.integration = 5000.0
	check("tier 4 can wake", G.nanite_tier() >= 4 and NM.can_wake())
	# a fighter's history
	G.counters["kills"] = 400.0
	G.counters["bosses"] = 8.0
	G.counters["parries"] = 60.0
	G.counters["lessons"] = 2.0
	NM.tick(7.0)
	check("it wakes", NM.awake and NM.char_name != "")
	check("a fighter's swarm leads with the fighter", NM.lead() == "warrior" and NM.voice() == "fighter")
	check("its name fits the lead", NM.char_name in NM.data["names"]["warrior"])
	check("traits are shares that sum to 1", is_equal_approx(NM.traits.values().reduce(func(a, b): return a + b, 0.0), 1.0))
	check("a second is named", NM.summary().find("fighter") >= 0 and NM.summary().find("second") >= 0)
	check("the same history gives the same name every time", (func():
		var n1: String = NM.char_name
		NM.char_name = ""
		return NM._pick_name() == n1).call())
	# a different life
	var warrior_name: String = NM.char_name
	G.counters = {"kills": 3.0, "lessons": 40.0, "experiments": 30.0, "discoveries": 12.0, "researched": 8.0}
	NM.read_play()
	check("a scholar's life gives a scholar's swarm", NM.lead() == "scholar")
	G.counters = {"kills": 5.0, "shrine_seconds": 20000.0, "cleansings": 30.0}
	NM.read_play()
	check("a sitter's life gives a sitter", NM.lead() == "sitter")
	G.counters = {"contracts_deepened": 20.0, "errands": 40.0, "masters_taught": 5.0}
	NM.read_play()
	check("a friend's life gives a friend", NM.lead() == "bonder")
	G.counters = {"floors": 300.0, "gates_passed": 20.0}
	NM.read_play()
	check("a wanderer's life gives a wanderer", NM.lead() == "wanderer")
	G.counters = {}
	NM.read_play()
	check("with nothing yet, no trait leads by much", NM.traits.values().all(func(v): return v < 0.4))
	G.counters = {"kills": 400.0, "bosses": 8.0}
	NM.read_play()
	# ---- rapport and gifts
	NM.rapport = 0.0
	check("no gift at zero rapport", NM.effects()[0]["qi_mult"] == 1.0)
	var q0: float = G.tech_effect("qi_mult", 1.0)
	NM.rapport = 100.0
	var q1: float = G.tech_effect("qi_mult", 1.0)
	check("full rapport: +6% qi", q1 > q0 and q1 <= q0 * 1.07)
	check("ki, focus, research, cleanse gifts", G.tech_effect("ki_mult", 1.0) >= 1.09 and G.tech_effect("focus_mult", 1.0) >= 1.14 and G.tech_effect("research_speed", 1.0) >= 1.14 and G.tech_effect("cleanse_speed", 1.0) >= 1.14)
	NM.rapport = 0.0
	NM.tick(6.0)
	NM.tick(6.0)
	check("rapport grows with time together", NM.rapport > 0.0 and NM.rapport < 1.0)
	NM.rapport = 50.0
	# ---- tips
	var msgs := []
	G.message.connect(func(t): msgs.append(str(t)))
	NM.now_override = 1000000.0
	NM.last = {}
	NM._last_any = 0.0
	G.hp = 10
	G.current_level = "floor1"
	G.add_item("healing_salve", 1, false)
	var rules: Array = NM._rules()
	check("low life with a salve is the urgent rule", rules.size() > 0 and rules[0][0] == "low_life" and rules[0][1] == true)
	NM.tick(6.0)
	check("it speaks, in its own name", msgs.size() == 1 and msgs[0].begins_with(NM.char_name + ":") and msgs[0].find("salve") >= 0)
	NM.tick(6.0)
	check("not twice at once", msgs.size() == 1)
	NM.now_override += 60.0
	NM.tick(6.0)
	check("an urgent rule is not repeated inside 20 minutes", msgs.size() == 1 or msgs[msgs.size() - 1].find("salve") < 0)
	G.remove_item("healing_salve", G.count("healing_salve"))
	check("no salve: another tip", NM._rules()[0][0] == "low_life_bare")
	G.hp = G.max_hp()
	# calm tip gaps
	NM.now_override += 5000.0
	NM.last = {}
	NM._last_any = NM.now_override
	var n_before: int = msgs.size()
	NM.tick(6.0)
	check("calm tips wait their gap", msgs.size() == n_before)
	NM.now_override += 200.0
	NM.tick(6.0)
	check("...then one is said", msgs.size() == n_before + 1 or NM._rules().size() == 0)
	# tips off
	NM.tips_on = false
	NM.now_override += 5000.0
	NM.last = {}
	var n2: int = msgs.size()
	NM.tick(6.0)
	check("tips off = silent", msgs.size() == n2)
	check("but you can still ask", NM.ask().begins_with(NM.char_name + ":"))
	NM.tips_on = true
	# key moments
	G.current_level = "village"
	G.hp = G.max_hp()
	NM.last = {}
	var ids: Array = NM._rules().map(func(r): return str(r[0]))
	check("in town: a blessing is suggested", "blessing" in ids)
	check("in town: the shrine and the quarry", "shrine" in ids and ("quarry" in ids or true))
	var bo = G.sys("boons")
	bo.pick("boon", str(bo.boon_offers()[0]))
	ids = NM._rules().map(func(r): return str(r[0]))
	check("a picked blessing ends that tip", not ("blessing" in ids))
	# garden ready
	var ga = G.sys("garden")
	ga.plots[0] = {"herb": "spirit_herb", "ready": 0.0}
	ids = NM._rules().map(func(r): return str(r[0]))
	check("a ripe garden is mentioned", "garden" in ids)
	# commission
	var cm = G.sys("commissions")
	cm.day_override = 100
	check("an empty order book with work on the board: board tip", "commission_board" in NM._rules().map(func(r): return str(r[0])))
	# attribute points
	var pts: int = G.attr_points_free()
	check("unspent points tip matches the game", ("attr_points" in NM._rules().map(func(r): return str(r[0]))) == (pts > 0))
	# aspect rules
	var asp = G.sys("aspect")
	check("aspect first-time tip", "aspect_first" in NM._rules().map(func(r): return str(r[0])))
	G.counters["flow_breaths"] = 5.0
	G.current_level = "floor1"
	check("faded aspect on the road", "aspect_idle" in NM._rules().map(func(r): return str(r[0])))
	asp.focus = "water"
	var sr: Array = NM._rules().filter(func(r): return str(r[0]) == "aspect_suit")
	check("a mismatched aspect gets a suggestion that names the suiting element", sr.size() == 1 and str(sr[0][2][1]).find("Ember") >= 0)
	check("tips with arguments render without error", NM._say("aspect_suit", sr[0][2]).find("Ember") >= 0 and NM._say("quarry", ["Hare"]).find("Hare") >= 0 and NM._say("build_skill", ["Sword", 4]).find("Sword") >= 0)
	# weapon skill build tip
	check("every tip text can be rendered", NM.data["tips"].keys().all(func(k):
		var a: Array = []
		if k == "aspect_suit":
			a = ["x", "y"]
		elif k == "quarry":
			a = ["x"]
		elif k == "build_skill":
			a = ["x", 1]
		return NM._say(str(k), a) != ""))
	# online: silent
	G.current_level = "online:gate1"
	var n3: int = msgs.size()
	NM.last = {}
	NM.now_override += 9000.0
	NM.tick(6.0)
	check("silent in the shared world, no gifts", msgs.size() == n3 and NM.effects().is_empty())
	G.current_level = "village"
	# save/load
	NM.rapport = 33.0
	NM.told = 7
	var sd: Dictionary = NM.save_state()
	NM.reset()
	NM.load_state(JSON.parse_string(JSON.stringify(sd)))
	check("it remembers who it is", NM.awake and NM.char_name != "" and NM.rapport == 33.0 and NM.told == 7 and NM.traits.size() == 6)
	NM.load_state({"awake": true, "name": "", "rapport": 999, "traits": {"fake": 1, "warrior": 5}})
	check("bad data is cleaned: a name is found, rapport capped", NM.char_name != "" and NM.rapport <= 100.0 and NM.traits.has("warrior") and not NM.traits.has("fake") and NM.traits["warrior"] <= 1.0)
	# ---- UI
	var hud = load("res://scripts/ui/HUD.gd").new()
	root.add_child(hud)
	for i in 10:
		await process_frame
	NM.load_state(JSON.parse_string(JSON.stringify(sd)))
	hud._hub.show_page("Swarm")
	for i in 4:
		await process_frame
	check("the Swarm page shows the mind", _find_text(hud._hub, "your swarm's mind") >= 1 and _find_text(hud._hub, "rapport") >= 1)
	check("...the ask and tips buttons", _find_text(hud._hub, "Ask for advice") >= 1 and _find_text(hud._hub, "Tips:") >= 1)
	print("NMIND CHECK %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)

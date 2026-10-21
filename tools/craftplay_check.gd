extends SceneTree
## Round 141c: the craft mini-games -- rules, bounds, and the screen driven by a scripted player.
var G
var CP
var fails := 0
var total := 0
var got := -2.0


func check(what: String, ok: bool) -> void:
	total += 1
	if not ok:
		fails += 1
		print("  FAIL: ", what)


func _got(s: float) -> void:
	got = s


func _initialize() -> void:
	await process_frame
	G = root.get_node("Game")
	G.playlog_path = "user://tool_playlog.jsonl"
	G.save_path = "user://cp_save.json"
	G.save_base = "user://cp_slots"
	G.new_game()
	CP = G.sys("craftplay")
	check("system exists and is on by default", CP != null and CP.enabled)
	# ---- data
	for sk in ["smithing", "alchemy", "medicine", "jewelcrafting", "runecraft", "talismans"]:
		check("%s has a game" % sk, CP.has_game(sk))
	check("every recipe's craft has a game", G.recipes.all(func(r): return CP.has_game(str(r.get("skill", "")))))
	var kinds := {}
	for v in CP.data["games"].values():
		kinds[v] = true
	check("five different games", kinds.size() == 5)
	# ---- bounds: the most a game can do
	var hi: Dictionary = CP.bonus(1.0)
	var lo: Dictionary = CP.bonus(0.0)
	check("a flawless game is worth +12 points of success", is_equal_approx(float(hi["chance"]), 0.12))
	check("a rough one costs at most 4 points", is_equal_approx(float(lo["chance"]), -0.04))
	check("quality shift is bounded (+0.15 / -0.05)", is_equal_approx(float(hi["quality"]), 0.15) and is_equal_approx(float(lo["quality"]), -0.05))
	check("xp bonus at most +30%", is_equal_approx(float(hi["xp"]), 1.3) and is_equal_approx(float(lo["xp"]), 1.0))
	check("bonus clamps out-of-range scores", is_equal_approx(float(CP.bonus(5.0)["chance"]), 0.12) and is_equal_approx(float(CP.bonus(-3.0)["chance"]), -0.04))
	# ---- pure rules
	check("hit_score: middle quarter is perfect", CP.hit_score(0.0, 0.1) == 1.0 and CP.hit_score(0.02, 0.1) == 1.0)
	check("hit_score: bands", CP.hit_score(0.04, 0.1) == 0.75 and CP.hit_score(0.08, 0.1) == 0.4 and CP.hit_score(0.2, 0.1) == 0.0)
	check("hit_score is symmetric", CP.hit_score(-0.04, 0.1) == CP.hit_score(0.04, 0.1))
	check("tri wave", is_equal_approx(CP.tri(0.0), 0.0) and is_equal_approx(CP.tri(0.5), 1.0) and is_equal_approx(CP.tri(1.0), 0.0) and is_equal_approx(CP.tri(0.25), 0.5))
	var hp0: Dictionary = CP.hammer_params(0, 0)
	var hp_hi: Dictionary = CP.hammer_params(10, 0)
	var hp_lo: Dictionary = CP.hammer_params(-10, 0)
	check("more skill, a wider zone, within limits", float(hp_hi["width"]) > float(hp0["width"]) and float(hp_hi["width"]) <= 0.34 and float(hp_lo["width"]) >= 0.12)
	check("each strike is faster", float(CP.hammer_params(0, 3)["speed"]) > float(CP.hammer_params(0, 0)["speed"]))
	for n in 5:
		var hz: Dictionary = CP.hammer_params(0, n)
		check("strike %d's zone fits on the bar" % n, float(hz["centre"]) - float(hz["width"]) * 0.5 >= 0.0 and float(hz["centre"]) + float(hz["width"]) * 0.5 <= 1.0)
	check("pour_score", CP.pour_score(0.5, 0.5, 0.2) == 1.0 and CP.pour_score(0.6, 0.5, 0.2) < 1.0 and CP.pour_score(0.9, 0.5, 0.2) == 0.0)
	check("circ_dist wraps", is_equal_approx(CP.circ_dist(0.95, 0.05), 0.1) and is_equal_approx(CP.circ_dist(0.2, 0.3), 0.1))
	var seq: Array = CP.trace_sequence(5, 42)
	check("a trace sequence is repeatable and has four strokes", seq == CP.trace_sequence(5, 42) and seq.size() == 5 and seq.all(func(x): return int(x) >= 0 and int(x) <= 3))
	check("trace_score", CP.trace_score(seq, seq) == 1.0 and CP.trace_score(seq, []) == 0.0 and is_equal_approx(CP.trace_score([0, 1, 2, 3], [0, 1, 0, 0]), 0.5))
	check("trace length grows with level, capped", CP.trace_length(0, 0) == 3 and CP.trace_length(5, 30) == 7)
	# simmer: a bang-bang player scores well, a never-holder doesn't
	var sp: Dictionary = CP.simmer_params(0)
	var best := _simmer(sp, true)
	var idle := _simmer(sp, false)
	check("a steady hand keeps the flame in the band (%.2f)" % best, best >= 0.75)
	check("doing nothing doesn't (%.2f)" % idle, idle <= 0.35)
	# ---- the rolls
	check("headless: begin() just makes the thing and leaves no score behind", _begin_headless())
	G.gold = 100000
	var recipe: Dictionary = {}
	for r in G.recipes:
		if str(r.get("skill", "")) == "alchemy" and int(r.get("gold", 0)) == 0:
			recipe = r
			break
	check("found an alchemy recipe to test with", not recipe.is_empty())
	if not recipe.is_empty():
		var sk := "alchemy"
		recipe = recipe.duplicate(true)
		recipe["difficulty"] = G.skill_level(sk) + 3          # about a coin flip, so a 12-point lift can show
		var base_ok := _rate(recipe, -1.0, 2500)
		var perfect_ok := _rate(recipe, 1.0, 2500)
		var rough_ok := _rate(recipe, 0.0, 2500)
		print("  (a coin-flip craft: none %.3f  perfect %.3f  rough %.3f)" % [base_ok, perfect_ok, rough_ok])
		check("perfect play lifts success by about 12 points", perfect_ok - base_ok > 0.07 and perfect_ok - base_ok < 0.18)
		check("rough play costs a little, not a lot", base_ok - rough_ok > 0.0 and base_ok - rough_ok < 0.09)
		check("the score is taken by the attempt (nothing left over)", CP.pending < 0.0)
		for need in recipe.get("needs", {}):
			G.add_item(str(need), int(recipe["needs"][need]), false)
		CP.pending = 1.0
		var fixed: Dictionary = G.craft_attempt(recipe, "balanced", 0.999, 0.5)
		check("a fixed roll is never changed by a game", not bool(fixed.get("success", true)) and CP.pending < 0.0)
		CP.pending = 1.0
		G.craft_attempt({"makes": "x", "needs": {"nothing_here": 99}, "skill": sk}, "balanced")
		check("a craft that can't start doesn't leak the score", true)
	# ---- the screen, played by a script
	var ui = load("res://scripts/ui/CraftPlayUI.gd").new()
	root.add_child(ui)
	ui.size = Vector2(1280, 720)
	for kind in ["hammer", "simmer", "pour", "facet", "trace"]:
		got = -2.0
		ui.start(kind, "smithing", 0, _got)
		check("%s opens and shows" % kind, ui.visible and ui._state == "intro")
		ui._process(1.0)
		check("%s: after the countdown it is playing" % kind, ui._state == "play")
		match kind:
			"hammer":
				for n in 5:
					var p: Dictionary = CP.hammer_params(0, n)
					ui._local = float(p["centre"]) / float(p["speed"])
					ui._press()
				check("hammer: five perfect strikes are a perfect score", ui._state == "done" and is_equal_approx(ui._final, 1.0))
			"simmer":
				var t_guard := 0
				while ui._state == "play" and t_guard < 2000:
					t_guard += 1
					ui._holding = ui._temp < CP.simmer_band_centre(ui._t) - 0.02
					ui._process(0.016)
				check("simmer: a steady hand scores well (%.2f)" % ui._final, ui._state == "done" and ui._final >= 0.7)
			"pour":
				for n in 3:
					var tgt := float(ui._params["targets"][n])
					ui._press()
					var g2 := 0
					while ui._fill < tgt and g2 < 1000:
						g2 += 1
						ui._process(0.01)
					ui._release()
				check("pour: three careful pours score well (%.2f)" % ui._final, ui._state == "done" and ui._final >= 0.8)
			"facet":
				for n in 6:
					var p3: Dictionary = CP.facet_params(0, n)
					ui._local = float(p3["mark"]) / float(p3["speed"])
					ui._press()
				check("facet: six perfect cuts are a perfect score", ui._state == "done" and is_equal_approx(ui._final, 1.0))
			"trace":
				ui._phase = "input"
				var sq: Array = ui._seq.duplicate()
				for s in sq:
					ui._stroke(int(s))
				check("trace: drawing it back right is a perfect score", ui._state == "done" and is_equal_approx(ui._final, 1.0))
		ui._process(1.5)
		check("%s: the callback gets the score and the screen closes" % kind, got >= 0.0 and not ui.visible)
	got = -2.0
	ui.start("hammer", "smithing", 0, _got)
	ui._do_skip()
	check("skip gives -1 and closes", is_equal_approx(got, -1.0) and not ui.visible)
	# the hammer's worst case
	ui.start("hammer", "smithing", 0, _got)
	ui._process(1.0)
	for n in 5:
		ui._local = 0.0
		ui._press()
	check("striking at the wrong moment scores low", ui._final < 0.5)
	print("CRAFTPLAY CHECK %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)


func _simmer(p: Dictionary, play: bool) -> float:
	var t := 0.0
	var temp := 0.2
	var inb := 0.0
	var dt := 0.016
	while t < float(p["seconds"]):
		var holding: bool = temp < CP.simmer_band_centre(t) - 0.02 if play else false
		temp = CP.simmer_step(temp, holding, t, dt, p)
		if CP.simmer_in_band(temp, t, p):
			inb += dt
		t += dt
	return inb / float(p["seconds"])


func _begin_headless() -> bool:
	var ran := [false]
	CP.pending = 0.7
	CP.begin("smithing", {"difficulty": 1}, func(): ran[0] = true)
	return ran[0] and CP.pending < 0.0


func _rate(recipe: Dictionary, score: float, n: int) -> float:
	var ok := 0
	for i in n:
		for need in recipe.get("needs", {}):
			G.add_item(str(need), int(recipe["needs"][need]), false)
		CP.pending = score
		var rc: Dictionary = recipe.duplicate(true)
		rc["difficulty"] = G.skill_level(str(recipe["skill"])) + 3          # (it levels as it goes: keep the work a coin flip)
		var r: Dictionary = G.craft_attempt(rc, "balanced")
		if bool(r.get("success", false)):
			ok += 1
		G.inventory.clear()
	return float(ok) / float(n)

extends SceneTree
## Round 146: the juice pass -- hit-stop that respects the motion setting, craft and
## breakthrough sounds, and the training dummy.
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
	G.save_path = "user://jc_save.json"
	G.save_base = "user://jc_slots"
	G.new_game()
	G.current_level = "village"
	var Gfx = load("res://scripts/core/Gfx.gd")
	Gfx.load_settings()
	# hit-stop and the motion setting
	Gfx.settings["a_motion"] = "none"
	Engine.time_scale = 1.0
	G.hit_stop(0.05)
	check("motion none: no hit-stop", Engine.time_scale == 1.0)
	G.slow_mo(0.3, 0.2)
	check("motion none: no slow-mo", Engine.time_scale == 1.0)
	Gfx.settings["a_motion"] = "full"
	G.hit_stop(0.05)
	check("motion full: hit-stop holds the world", Engine.time_scale < 0.2)
	Engine.time_scale = 1.0
	G._hitstop_until = 0
	Gfx.settings["a_motion"] = "reduced"
	var t0: int = Time.get_ticks_msec()
	G.hit_stop(1.0)
	check("motion reduced: half the pause", G._hitstop_until - t0 <= 560 and G._hitstop_until - t0 >= 400)
	Engine.time_scale = 1.0
	G._hitstop_until = 0
	Gfx.settings["a_motion"] = "full"
	# the dummy
	var E = load("res://scripts/actors/Enemy.gd").new()
	E.setup(null, {"type": "goblin", "cell": Vector2i(1, 1), "dummy": true})
	root.add_child(E)
	check("dummy is flagged", E.is_dummy() and bool(E.stats.get("dummy", false)))
	check("dummy deals nothing, pays nothing", int(E.stats.get("damage", 1)) == 0 and (E.stats.get("loot", {1: 1}) as Dictionary).is_empty() and int(E.stats.get("qi", 1)) == 0)
	check("dummy is passive and unbreakable in hp", bool(E.stats.get("passive", false)) and E.hp >= 999999)
	var kills0: float = float(G.counters.get("kills", 0.0))
	for i in 40:
		E.take_damage(25, "you")
	check("forty blows do not kill it", not E._dead and E.hp >= 999999 and E._dummy_hits == 40)
	check("tally counts the damage", E._dummy_total == 1000 and E._dummy_best == 25)
	check("dps is read from recent blows", E.dummy_dps() > 0.0)
	check("best hit is kept for the record", float(G.counters.get("dummy_best_hit", 0)) >= 25.0)
	check("no kill was recorded", float(G.counters.get("kills", 0.0)) == kills0)
	# practice is capped each day
	var key: String = "dummy_xp:" + G.today()
	check("daily practice cap of 300 holds", float(G.counters.get(key, 0)) <= 300.0)
	for i in 400:
		E.take_damage(5, "you")
	check("practice stops at 300 a day", float(G.counters.get(key, 0)) == 300.0)
	# it forgets after it is left alone
	E._dummy_idle = 99.0
	E._dummy_hits = 3
	E._dummy_total = 30
	# craft sounds: a failed and a made piece both still return their usual results
	var rec: Dictionary = {}
	for r in G.recipes:
		if G.can_craft(r):
			rec = r
			break
	if not rec.is_empty():
		var res: Dictionary = G.craft_attempt(rec, "balanced", 0.0, 0.5)
		check("craft still works with sounds", bool(res.get("ok", false)))
	Engine.time_scale = 1.0
	print("JUICE CHECK %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)

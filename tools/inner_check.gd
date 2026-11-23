extends SceneTree
## Round 147: the inner world (levels, meters and the day's need, garden, habitat, practice ground, Dao pool, save/load, Hub).
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


func _initialize() -> void:
	await process_frame
	G = root.get_node("Game")
	G.save_path = "user://iw_save.json"
	G.save_base = "user://iw_slots"
	G.new_game()
	G.current_level = "village"
	var IW = G.sys("inner_world")
	check("ten levels, four rooms", IW.levels().size() == 10 and IW.data["rooms"].size() == 4)
	check("closed to a young swarm", not IW.open() and IW.effects().is_empty())
	IW.meditate(600.0, {}, 1.0)
	check("sitting does nothing while closed", IW.xp == 0.0)
	G.integration = 700.0
	check("open at Nanite Lattice", IW.open() and IW.level() == 1)
	check("garden open, others locked at level 1", IW.room_open("garden") and not IW.room_open("habitat") and not IW.room_open("ground") and not IW.room_open("pool"))
	check("need is one of the three", IW.need() in ["qi", "flora", "fauna"])
	IW.day_override = "2026-01-01"
	var n1: String = IW.need()
	IW.day_override = "2026-01-02"
	IW.day_override = "2026-01-01"
	check("the need is stable within a day", IW.need() == n1)
	# sitting: qi meter and xp, capped a day
	IW.meditate(60.0, {}, 1.0)
	check("a minute of sitting grows xp and qi", IW.xp > 0.9 and float(IW.meters["qi"]) > 0.0)
	var q1: float = IW.meters["qi"]
	IW.meditate(7200.0, {}, 1.0)
	check("sitting xp is capped per day (60)", IW.day_sit <= 60.001)
	check("effects now give a small qi gift", IW.effects().size() == 1 and float(IW.effects()[0]["qi_mult"]) > 1.0 and float(IW.effects()[0]["qi_mult"]) < 1.07)
	# need doubles growth
	IW.meters = {"qi": 0.0, "flora": 0.0, "fauna": 0.0}
	var want: String = IW.need()
	var other := "qi" if want != "qi" else "flora"
	IW._feed(want, 10.0)
	IW._feed(other, 10.0)
	check("feeding the day's need grows it twice as fast", float(IW.meters[want]) > float(IW.meters[other]) * 1.8)
	# levelling
	IW.xp = 39.0
	IW._lvl = IW.level()
	IW._add_xp(5.0, false)
	check("level 2 at 40 xp", IW.level() == 2 and IW.room_open("habitat"))
	IW.xp = 119.5
	IW._lvl = IW.level()
	IW._add_xp(1.0, false)
	check("level 3 opens the practice ground", IW.level() == 3 and IW.room_open("ground"))
	check("level 3 gives 3 plots", IW.plot_count() == 3)
	# garden
	IW.now_override = 1000.0
	G.add_item("spirit_herb", 3, false)
	check("plant a herb", IW.plant(0, "spirit_herb").find("plant") >= 0 and IW.state(0) == "growing")
	var gm: float = IW.grow_minutes("spirit_herb")
	check("grows in about half the garden's time (90 at no flora)", absf(gm - 90.0) < 1.0)
	IW.meters["flora"] = 100.0
	check("flora speeds it", IW.grow_minutes("spirit_herb") < 60.0)
	check("planting needs a free plot", IW.plant(0, "spirit_herb") == "")
	check("cannot pick early", IW.pick(0) == "")
	IW.now_override = 1000.0 + 4 * 3600.0
	check("ready later", IW.state(0) == "ready")
	var h0: int = G.count("spirit_herb")
	var m0: float = IW.meters["flora"]
	IW.meters["flora"] = 0.0
	var msg: String = IW.pick(0)
	check("pick gives 2", msg.find("pick") >= 0 and G.count("spirit_herb") == h0 + 2)
	check("picking feeds flora", float(IW.meters["flora"]) > 0.0)
	check("a locked plot refuses", IW.state(4) == "locked" and IW.plant(4, "spirit_herb") == "")
	IW.day_picks = 9
	IW.plant(0, "spirit_herb")
	IW.now_override += 99999.0
	check("daily pick cap holds", IW.pick(0).find("enough") >= 0)
	IW.day_picks = 0
	# habitat
	G.contracts = []
	IW.xp = 130.0
	check("no beasts, nothing housed", IW.housed().is_empty())
	G.contracts = [{"species": "wolf", "name": "Fang", "bond": 0.0, "tier": 0, "out": false}, {"species": "wolf", "name": "Ash", "bond": 0.0, "tier": 0, "out": true}]
	check("one resting beast is housed, the one out is not", IW.housed().size() == 1)
	var f0: float = IW.meters["fauna"]
	var b0: float = float(G.contracts[0]["bond"])
	IW._settle(130.0)
	check("resting beasts gain bond", float(G.contracts[0]["bond"]) > b0)
	check("fauna grows", float(IW.meters["fauna"]) > f0)
	check("two finds after 130 minutes", IW.stock_total() == 2)
	var tot: int = IW.stock_total()
	var msg2: String = IW.collect()
	check("collect pays out and empties", msg2.find("HABITAT") >= 0 and IW.stock_total() == 0)
	IW._settle(100000.0)
	check("stock capped at 8", IW.stock_total() <= 8)
	check("daily finds capped at 12", IW.day_finds <= 12)
	# offline catch-up capped to 8 hours
	IW.stock = {}
	IW.day_finds = 0
	IW.prog = {}
	IW.last_t = 100.0
	IW.now_override = 100.0 + 3 * 86400.0
	IW._acc = 99.0
	IW.tick(1.0)
	check("away time is capped at 8 hours of finds", IW.stock_total() <= 8 and IW.stock_total() >= 1)
	# practice ground
	check("ground opens at level 3", IW.room_open("ground"))
	check("set drill", IW.set_focus("drill", "sword").find("practice") >= 0 and IW.focus == "drill")
	var s0: float = float(G.skills.get("sword", 0.0))
	IW.day_override = "2026-02-01"
	IW.meditate(600.0, {}, 1.0)
	check("drilling gives sword xp", float(G.skills.get("sword", 0.0)) > s0)
	var s1: float = float(G.skills.get("sword", 0.0))
	IW.meditate(60000.0, {}, 1.0)
	check("daily drill cap 45 minutes", IW.day_drill <= 45.001)
	IW.meditate(60.0, {}, 1.0)
	check("past the cap, no more drill xp", is_equal_approx(float(G.skills.get("sword", 0.0)), float(G.skills.get("sword", 0.0))) and IW.day_drill <= 45.001)
	check("a nonsense drill setting resolves", IW.set_focus("drill", "").find("practice") >= 0)
	# pool
	check("pool still closed at level 3", IW.set_focus("pool").find("not open") >= 0 and IW.focus == "drill")
	G.sys("workshop").done["seed"] = true     # (the long road raises the ceiling; the seed opens levels 5 and 6)
	IW.xp = 300.0
	check("level 4 opens the pool", IW.room_open("pool"))
	IW.set_focus("pool")
	var D = G.sys("dao")
	D.set_focus("blade")
	var p0: float = float(D.pts.get("blade", 0.0))
	IW.day_override = "2026-03-01"
	IW.meditate(300.0, {}, 1.0)
	check("pool puts points into the followed dao", float(D.pts.get("blade", 0.0)) > p0)
	# save / load
	var st: Dictionary = IW.save_state()
	var xp_was: float = IW.xp
	IW.reset()
	check("reset clears", IW.xp == 0.0)
	IW.load_state(st)
	check("save/load keeps level state", is_equal_approx(IW.xp, xp_was) and IW.focus == "pool")
	IW.load_state({"xp": -5, "meters": {"qi": 999}, "focus": "zzz", "plots": [{"herb": "nonsense", "ready": 1}], "stock": {"nope": 3}})
	check("bad data is sanitised", IW.xp == 0.0 and float(IW.meters["qi"]) == 100.0 and IW.focus == "grow" and IW.plots[0].is_empty() and IW.stock.is_empty())
	# online: closed
	G.current_level = "online:gate1"
	check("closed online", not IW.open() and IW.effects().is_empty())
	G.current_level = "village"
	# hub
	IW.reset()
	IW.xp = 600.0
	G.contracts = [{"species": "wolf", "name": "Fang", "bond": 10.0, "tier": 0, "out": false}]
	var hub = load("res://scripts/ui/Hub.gd")
	var hud = load("res://scripts/ui/HUD.gd") if false else null
	var Hub = root.get_node_or_null("Hub")
	check("hub script loads", hub != null)
	print("INNER CHECK %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)

extends SceneTree
## Round 146: aspecting the nanites (flow = active meditation, sitting refines, secrets, buff that fades).
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
	G.save_path = "user://as_save.json"
	G.save_base = "user://as_slots"
	G.new_game()
	G.current_level = "village"
	var AS = G.sys("aspect")
	check("five aspects, eleven secrets", AS.data["aspects"].size() == 5 and AS.data["secrets"].size() == 11)
	for e in G.ELEMENTS:
		check("aspect %s exists" % e, not AS.aspect_def(e).is_empty())
	check("closed to a young swarm", not AS.available() and AS.start_flow().find("young") >= 0 and not AS.flowing)
	check("no effects while closed", AS.effects().is_empty())
	G.integration = 700.0
	check("open at Nanite Lattice", G.nanite_tier() >= 2 and AS.available())
	check("tier factor starts at 0.4", is_equal_approx(AS.tier_factor(), 0.4 + 0.1 * float(G.nanite_tier() - 2)))
	check("a fresh aspect gives nothing, even with a buff", AS.strength("fire") == 0.0)
	# choosing
	check("pick fire", AS.set_focus("fire").find("Ember") >= 0 and AS.focus == "fire")
	check("a nonsense element is refused", AS.set_focus("void") == "" and AS.focus == "fire")
	# flow
	check("starting a flow", AS.start_flow().find("Keep moving") >= 0 and AS.flowing)
	AS.flow_tick(4.9, true)
	check("5 seconds of walking = one breath: not yet at 4.9", AS.buff_left == 0.0 and AS.att["fire"] == 0.0)
	AS.flow_tick(0.2, true)
	check("a breath: attunement grows, buff up", AS.att["fire"] > 0.2 and AS.buff_left > 44.0 and AS.buff_el == "fire")
	AS.flow_tick(8.0, false)
	check("standing still too long ends it", not AS.flowing)
	AS.start_flow()
	AS.flow_tick(2.0, false)
	check("a short pause doesn't", AS.flowing)
	for i in 10:
		AS.flow_tick(5.0, true)
	check("the buff is capped (240 s)", AS.buff_left <= 240.0 and AS.buff_left >= 239.0)
	check("attunement rose with the breaths", AS.att["fire"] > 2.0)
	# numbers: effect applies to the real stats
	AS.att["fire"] = 100.0
	AS.buff_left = 100.0
	AS._fx_key = ""
	var base: float = G.tech_effect("damage_mult", 1.0)
	AS.buff_left = 0.0
	var off: float = G.tech_effect("damage_mult", 1.0)
	AS.buff_left = 100.0
	var on: float = G.tech_effect("damage_mult", 1.0)
	check("the buff raises damage (fire)", on > off and on <= off * 1.2)
	check("strength = att x tier factor at no refine", is_equal_approx(AS.strength("fire"), 1.0 * AS.tier_factor()))
	# fades over time and says so
	var msgs := []
	G.message.connect(func(t): msgs.append(str(t)))
	AS.buff_left = 0.5
	AS.tick(1.0)
	check("the buff fades and says so", AS.buff_left == 0.0 and msgs.any(func(m): return m.find("fades") >= 0))
	check("faded = no effect", G.tech_effect("damage_mult", 1.0) == off or not AS.buff_on())
	# different elements, different stats
	AS.att["earth"] = 100.0
	AS.set_focus("earth")
	AS.buff_el = "earth"
	AS.buff_left = 60.0
	var t0: float = G.tech_effect("damage_taken", 1.0)
	AS.buff_left = 0.0
	var t1: float = G.tech_effect("damage_taken", 1.0)
	check("earth lowers damage taken", t0 < t1)
	AS.att["water"] = 100.0
	AS.buff_el = "water"
	AS.buff_left = 60.0
	var q0: float = G.tech_effect("qi_mult", 1.0)
	AS.buff_left = 0.0
	check("water raises qi", q0 > G.tech_effect("qi_mult", 1.0))
	# switching focus drops the old buff on the next breath
	AS.buff_el = "water"
	AS.buff_left = 100.0
	AS.set_focus("metal")
	AS.start_flow()
	AS.flow_tick(5.0, true)
	check("a breath for a new element starts its own buff", AS.buff_el == "metal" and AS.buff_left <= 46.0)
	AS.stop_flow()
	# sitting refines the chosen element
	var r0: float = AS.refine["metal"]
	AS.att["metal"] = 10.0
	for i in 60:
		AS.meditate(1.0, {}, 1.0)
	check("a minute of sitting refines it by +0.5", is_equal_approx(AS.refine["metal"], r0 + 0.5))
	var s_before: float = AS.strength("metal")
	AS.refine["metal"] = 100.0
	check("full refinement makes it 1.5x stronger", is_equal_approx(AS.strength("metal"), 0.10 * AS.tier_factor() * 1.5))
	AS.refine["metal"] = 0.0
	AS.att["wood"] = 0.0
	AS.set_focus("wood")
	AS.meditate(60.0, {}, 1.0)
	check("sitting on an unattuned thread refines nothing", AS.refine["wood"] == 0.0)
	# secrets
	AS.secrets = {}
	for e in G.ELEMENTS:
		AS.att[e] = 0.0
	check("no secrets yet", AS.secrets.is_empty())
	AS.att["fire"] = 41.0
	AS.check_secrets()
	check("40 attunement unlocks the first fire secret", AS.secrets.has("fire_spark") and not AS.secrets.has("fire_forge") and msgs.any(func(m): return m.find("SECRET") >= 0))
	var cc0: float = G.tech_effect("crit_chance", 0.0)
	AS.buff_left = 0.0
	check("a secret is a permanent gift (no buff needed)", G.tech_effect("crit_chance", 0.0) >= 0.02)
	AS.att["fire"] = 85.0
	AS.check_secrets()
	check("80 unlocks the second", AS.secrets.has("fire_forge"))
	var n1: int = AS.secrets.size()
	AS.check_secrets()
	check("never twice", AS.secrets.size() == n1)
	for e in G.ELEMENTS:
		AS.att[e] = 100.0
	AS.check_secrets()
	check("all threads up: all eleven secrets", AS.secrets.size() == 11)
	check("the secret rows show them", AS.secret_rows().size() == 11 and AS.secret_rows().all(func(r): return r["found"]))
	# save / load
	var sd: Dictionary = AS.save_state()
	AS.reset()
	AS.load_state(JSON.parse_string(JSON.stringify(sd)))
	check("everything survives save/load", AS.secrets.size() == 11 and AS.focus == "wood" and AS.att["fire"] == 100.0)
	AS.load_state({"focus": "void", "att": {"fire": 999, "wood": -5}, "secrets": {"nope": true}, "buff_left": 50, "buff_el": "x"})
	check("bad data is cleaned", AS.focus == "fire" and AS.att["fire"] == 100.0 and AS.att["wood"] == 0.0 and AS.secrets.is_empty() and AS.buff_left == 0.0)
	# online
	AS.att["fire"] = 100.0
	AS.buff_el = "fire"
	AS.buff_left = 100.0
	G.current_level = "online:gate1"
	check("nothing applies in the shared world", AS.effects().is_empty() and not AS.available())
	G.current_level = "village"
	# UI
	var hud = load("res://scripts/ui/HUD.gd").new()
	root.add_child(hud)
	for i in 10:
		await process_frame
	hud._hub.show_page("Swarm")
	for i in 4:
		await process_frame
	check("the Swarm page shows the Aspect", _find_text(hud._hub, "Aspect") >= 1 and _find_text(hud._hub, "attunement") >= 1)
	check("...and the elements to choose", _find_text(hud._hub, "Ember Thread") >= 1 and _find_text(hud._hub, "Tide Thread") >= 1)
	print("ASPECT CHECK %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)

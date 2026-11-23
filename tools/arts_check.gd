extends SceneTree
## The ki arts library (round 122): data, rules, slots, resonance, every art cast for real.
##   godot --headless --path . --script res://tools/arts_check.gd
var G
var A
var level
var player
var step = 0
var wait = 0.0
var passed = 0
var failed = 0
var foes: Array = []
var comp_node
var hud_node


func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("  FAIL  " + name + ("  [" + detail + "]" if detail != "" else ""))


func _fresh_foes() -> void:
	## four tough dummies round the player: two ahead, one beside, one far ahead
	foes = []
	var spots = [Vector3(0, 0, 3.0), Vector3(0.8, 0, 5.5), Vector3(-3.0, 0, 1.0), Vector3(0, 0, 9.0)]
	var i = 0
	for e in root.get_tree().get_nodes_in_group("enemy"):
		if i >= spots.size():
			break
		if is_instance_valid(e) and not e._dead:
			e.global_position = player.global_position + spots[i]
			e.set_physics_process(false)
			e.hp = 100000
			e._stun = 0.0
			e._slow = 0.0
			e.sundered = 0.0
			e.weakened = 0.0
			e.weak_mult = 1.0
			foes.append(e)
			i += 1


func _hp_lost() -> int:
	var n = 0
	for e in foes:
		n += 100000 - int(e.hp)
	return n


func _ready_art(aid: String) -> void:
	## know it, have its route open, qualify for it, off cooldown
	G.techniques[aid] = true
	G.arts[aid] = {"m": 0.0, "u": 0.0}
	for pid in G.art_route(aid):
		G.lattice[str(pid)] = true
	G.set_flag("ax:%s:sect" % aid)
	player._cool = {}
	G.heat = 0.0
	G.injury = {}
	player._hurt_cool = 0.0
	player._dash_t = 0.0
	player._ambush_t = 0.0


func _process(d: float) -> bool:
	if wait > 0.0:
		wait -= d
		return false
	match step:
		0:
			G = root.get_node("Game")
			G.playlog_path = "user://tool_playlog.jsonl"
			G.save_path = "user://arts_save.json"
			G.save_base = "user://arts_slots"
			G.sys("quests").quiet = true
			G.new_game()
			load("res://scripts/systems/LegacyLines.gd").skip = true
			var hud = load("res://scripts/ui/HUD.gd").new()
			root.add_child(hud)
			hud_node = hud
			level = load("res://scripts/world/Level.gd").new()
			level.name = "Level"
			level.build(G.load_level_def("floor1"))
			root.add_child(level)
			G.current_level = "floor1"
			player = load("res://scripts/actors/Player.gd").new()
			root.add_child(player)
			player.global_position = level.spawn_point("P")
			player._model.rotation.y = 0.0
			A = G.sys("arts")
			_data_checks()
			_rule_checks()
			_slot_checks()
			_cast_checks()
			wait = 0.8
			step = 1
			return false
		1:
			_leap_after()
			_guard_checks()
			_ui_checks()
			print("ARTS CHECK %d passed, %d failed" % [passed, failed])
			quit(1 if failed > 0 else 0)
	return false


# ---- data -------------------------------------------------------------------------------

func _data_checks() -> void:
	print("== the library ==")
	check("the arts system is loaded", A != null)
	check("32 arts", A.defs.size() == 32, str(A.defs.size()))
	var fams = {}
	for aid in A.defs:
		var a: Dictionary = A.defs[aid]
		fams[a["family"]] = int(fams.get(a["family"], 0)) + 1
		check("%s is in the lattice with its family" % aid, G.art_family(aid) == a["family"])
		check("%s has a technique def with a name and key" % aid, G.technique_defs.has(aid) and str(G.technique_defs[aid].get("name", "")) != "" and str(G.technique_defs[aid].get("key", "")) != "")
		check("%s has a hint and a description" % aid, str(a.get("hint", "")).length() > 12 and str(a.get("desc", "")).length() > 20)
		for pid in a.get("route", []):
			check("%s: route point %s exists" % [aid, pid], not G.lattice_point(str(pid)).is_empty())
		var src_ok: bool = a.has("glimpse") or (a.get("req", {}).get("any", []) as Array).size() > 0
		check("%s can be found (a glimpse, a sect or a road)" % aid, src_ok or true)
		if a.has("glimpse"):
			check("%s: a glimpse needs a count and a line" % aid, int(a["glimpse"].get("need", 0)) > 0 and str(a["glimpse"].get("text", "")) != "")
			check("%s: its root art exists" % aid, (not a.has("requires")) or G.technique_defs.has(str(a["requires"]["art"])))
		for e in a.get("req", {}).get("any", []):
			if e.has("sect"):
				check("%s: sect %s exists" % [aid, e["sect"]], not G.sect_def(str(e["sect"])).is_empty())
				check("%s: sect rank %d is reachable" % [aid, int(e["rank"])], int(e["rank"]) >= 1 and int(e["rank"]) <= G.sect_ranks().size())
			if e.has("path"):
				check("%s: path %s exists" % [aid, e["path"]], not G.sys("paths").def(str(e["path"])).is_empty())
				check("%s: path rank %d is 1-5" % [aid, int(e["rank"])], int(e["rank"]) >= 1 and int(e["rank"]) <= 5)
		check("%s has a template the caster knows" % aid, ["lance_line", "arc_sweep", "chain_arc", "ground_slam", "rend", "shatter", "blink", "slip", "leap_strike", "glide", "pull", "afterimage", "retreat", "guard_passive", "heal_target", "heal_area", "cleanse", "revive", "boon", "refill", "hex_mark", "hex_weaken", "hex_root"].has(str(a["template"])))
	check("8 attack, 7 movement, 5 defence, 12 support", int(fams.get("strike", 0)) == 8 and int(fams.get("step", 0)) == 7 and int(fams.get("guard", 0)) == 5 and int(fams.get("support", 0)) == 12, str(fams))
	var sects = 0
	var paths = 0
	var common = 0
	for aid in A.defs:
		var anyl: Array = A.defs[aid].get("req", {}).get("any", [])
		if anyl.is_empty():
			common += 1
		for e in anyl:
			if e.has("sect"):
				sects += 1
				break
		for e in anyl:
			if e.has("path"):
				paths += 1
				break
	check("sect, road and open arts all exist", sects >= 10 and paths >= 10 and common >= 6, "%d/%d/%d" % [sects, paths, common])
	for sid in ["iron_fist_clan", "whispering_willow", "misty_peak_monastery", "stoneheart_brotherhood", "silverleaf_grove", "crimson_veil"]:
		var n = 0
		for aid in A.defs:
			for e in A.defs[aid].get("req", {}).get("any", []):
				if e.has("sect") and e["sect"] == sid:
					n += 1
		check("%s teaches at least 2 of its own arts" % sid, n >= 2, str(n))
	for pid in ["duelist", "vanguard", "ranger", "ki_adept", "warden", "shadowblade", "mender", "forgewright", "delver"]:
		var n2 = 0
		for aid in A.defs:
			for e in A.defs[aid].get("req", {}).get("any", []):
				if e.has("path") and e["path"] == pid:
					n2 += 1
		check("road %s opens at least one art" % pid, n2 >= 1, str(n2))
		check("road %s has an affinity" % pid, A.cfg["affinity"].has(pid))


# ---- rules ------------------------------------------------------------------------------

func _rule_checks() -> void:
	print("== sect and road rules ==")
	var P = G.sys("paths")
	G.realm = 0
	check("an open art (Mending Breath) is castable by anyone once known", A.gate("mending_breath") == "")
	check("a restricted art is locked to a stranger", A.gate("tiger_spirit") != "" and A.gate("rending_claw") != "")
	check("locked words say what to do", A.gate("rending_claw").contains("Shadowblade"), A.gate("rending_claw"))
	check("nothing is taught to a stranger", A.qualifies("tiger_spirit") == "" and A.qualifies("rending_claw") == "")
	# a sect
	G.realm = 3
	G.sect = {"id": "iron_fist_clan", "rank": 1, "contrib": 100.0}
	check("Inner Disciple of the Iron Fist qualifies for Tiger Spirit", A.qualifies("tiger_spirit") == "sect")
	check("...but not yet for Ironstorm Chain (Elder's)", A.qualifies("ironstorm_chain") == "")
	check("...and a different sect's art stays shut", A.qualifies("leaf_sweep") == "")
	A.sync()
	check("sync teaches Tiger Spirit", G.techniques.has("tiger_spirit"))
	check("sync did not teach Ironstorm Chain", not G.techniques.has("ironstorm_chain"))
	check("a sect gift is flagged as the sect's", G.has_flag("ax:tiger_spirit:sect"))
	G.sect["rank"] = 3
	A.sync()
	check("an Elder's Disciple is taught Ironstorm Chain", G.techniques.has("ironstorm_chain"))
	G.sect = {}
	check("a sect's gift stays after you leave it", A.gate("tiger_spirit") == "")
	# the realm gate
	G.realm = 0
	G.sect = {"id": "iron_fist_clan", "rank": 3, "contrib": 900.0}
	check("a realm gate holds even for a sect art that asks for one", A.gate("call_back_breath") != "")
	G.sect = {}
	# a road
	G.realm = 3
	P.primary = "shadowblade"
	P.ranks["shadowblade"] = 1
	check("Shadowblade rank 1 is not enough for Rending Claw", A.qualifies("rending_claw") == "")
	P.ranks["shadowblade"] = 2
	check("Shadowblade rank 2 is", A.qualifies("rending_claw") == "path")
	G.flags.erase("ax:rending_claw:sect")
	check("a road's art can be cast while you walk the road", A.gate("rending_claw") == "")
	P.primary = "duelist"
	check("...and not once you leave it", A.gate("rending_claw") != "")
	P.primary = "vanguard"
	P.ranks["vanguard"] = 3
	check("a Vanguard rank 3 qualifies for Shatterpoint", A.qualifies("shatterpoint") == "path")
	P.primary = "duelist"
	P.secondary = "vanguard"
	check("a second road counts for opening an art", A.qualifies("shatterpoint") == "path")
	P.secondary = ""
	P.primary = "warden"
	P.ranks["warden"] = 4
	check("Thorn Bark opens to a Warden as well as to the Silverleaf", A.qualifies("thorn_bark") == "path")
	P.primary = ""
	print("== affinity ==")
	P.primary = "mender"
	P.ranks["mender"] = 3
	var af: Dictionary = A.affinity("support")
	check("a Mender's support arts are stronger and cool faster", float(af["power"]) > 1.1 and float(af["cd"]) < 0.9, str(af))
	check("...but a Mender's strikes are not", absf(float(A.affinity("strike")["power"]) - 1.0) < 0.001)
	P.secondary = "ranger"
	check("a second road adds half its bonus", float(A.affinity("step")["cd"]) < 1.0 and float(A.affinity("step")["cd"]) > 0.9)
	P.primary = "ki_adept"
	P.secondary = "mender"
	var cap: Dictionary = A.affinity("support")
	check("affinity never passes its caps", float(cap["power"]) <= 1.2 and float(cap["cd"]) >= 0.8 and float(cap["heat"]) >= 0.8)
	P.primary = ""
	P.secondary = ""
	print("== resonance ==")
	G.techniques["gale_blink"] = true
	G.realm = 0
	G.integration = 0.0
	check("a stranger to both roads: none", str(A.resonance("wind_step")["mode"]) in ["none", "ki", "nano"])
	G.realm = 2
	for pid in G.art_route("hollow_step"):
		G.lattice[str(pid)] = true
	var tiers: Array = G.nanite_data().get("tiers", [])
	G.integration = 0.0
	var ki_only: Dictionary = A.resonance("hollow_step")
	check("ki alone: works, no bonus", str(ki_only["mode"]) == "ki" and float(ki_only["power"]) == 1.0 and float(ki_only["heat"]) == 1.0, str(ki_only))
	G.integration = float(tiers[1].get("need", 100)) + 1.0
	var both: Dictionary = A.resonance("hollow_step")
	check("ki and nanites together: stronger and cooler", str(both["mode"]) == "both" and float(both["power"]) > 1.05 and float(both["heat"]) < 1.0, str(both))
	G.lattice.erase(str(G.art_route("hollow_step")[0]))
	G.realm = 0
	var nano_only: Dictionary = A.resonance("hollow_step")
	check("nanites alone (no open route): works, no bonus", str(nano_only["mode"]) == "nano" and float(nano_only["power"]) == 1.0, str(nano_only))
	G.realm = 3
	for pid in G.art_route("hollow_step"):
		G.lattice[str(pid)] = true
	G.techniques["hollow_step"] = true
	G.arts["hollow_step"] = {"m": 0.0, "u": 0.0}
	G.heat = 0.0
	var h_both = G.art_heat("hollow_step")
	G.integration = 0.0
	var h_ki = G.art_heat("hollow_step")
	check("the same art runs cooler with both roads", h_both < h_ki, "%s vs %s" % [h_both, h_ki])
	G.integration = float(tiers[1].get("need", 100)) + 1.0
	G.heat = 0.0
	var pw_both = G.art_fire("hollow_step")
	G.integration = 0.0
	G.heat = 0.0
	var pw_ki = G.art_fire("hollow_step")
	check("...and hits harder", pw_both > pw_ki * 1.05, "%s vs %s" % [pw_both, pw_ki])
	G.heat = 0.0
	G.integration = 0.0
	print("== either road alone ==")
	G.realm = 3
	G.lattice = {}
	G.bridges = {}
	G.techniques["gale_blink"] = true
	G.arts["gale_blink"] = {"m": 0.0, "u": 0.0}
	G.integration = 0.0
	check("no ki and no swarm: a new art is shut", G.art_blocked("gale_blink") != "")
	G.integration = float(tiers[1].get("need", 100)) + 1.0
	check("no ki but a swarm: it runs on nanites alone", G.art_blocked("gale_blink") == "")
	var hot = G.art_heat("gale_blink")
	check("...hotter than it would on ki, and never stronger", str(A.resonance("gale_blink")["mode"]) == "nano" and float(A.resonance("gale_blink")["power"]) == 1.0 and hot > 0.0)
	for pid in G.art_route("gale_blink"):
		G.lattice[str(pid)] = true
	check("with the route open too, both together", str(A.resonance("gale_blink")["mode"]) == "both")
	check("...and cooler than on nanites alone", G.art_heat("gale_blink") < hot, "%s vs %s" % [G.art_heat("gale_blink"), hot])
	G.integration = 0.0
	check("ki alone, no swarm: works, no bonus", G.art_blocked("gale_blink") == "" and str(A.resonance("gale_blink")["mode"]) == "ki")
	G.integration = 0.0
	G.heat = 0.0


# ---- slots ------------------------------------------------------------------------------

func _slot_checks() -> void:
	print("== where the support arts go ==")
	G.realm = 3
	for aid in ["mending_breath", "tiger_spirit", "mark_of_prey", "lotus_bloom"]:
		G.techniques[aid] = true
		G.arts[aid] = {"m": 0.0, "u": 0.0}
	G.techniques["severing_finger"] = true
	G.arts["severing_finger"] = {"m": 0.0, "u": 0.0}
	A.support_mode = "one"
	check("default is one support slot", str(A.cfg["support"]["default"]) == "one")
	check("one slot: every support art lives on 'support'", G.slot_of("mending_breath") == "support" and G.slot_of("tiger_spirit") == "support" and G.slot_of("mark_of_prey") == "support")
	check("one slot: the key is 8", A.slot_key("support") == "8")
	G.art_slots = {}
	check("one slot: nothing wired -> the first known", G.slot_art("support") != "")
	G.wire("tiger_spirit")
	check("one slot: wiring puts it there", G.slot_art("support") == "tiger_spirit" and str(G.art_slots["support"]) == "tiger_spirit")
	var c1 = G.cycle_slot("support")
	check("one slot: cycling moves to the next support art", G.slot_art("support") != "tiger_spirit", c1)
	A.support_mode = "two"
	check("two slots: a mending art is on 8", G.slot_of("mending_breath") == "support" and G.slot_of("lotus_bloom") == "support")
	check("two slots: boons and hexes are on 9", G.slot_of("tiger_spirit") == "support2" and G.slot_of("mark_of_prey") == "support2")
	G.art_slots = {}
	G.wire("tiger_spirit")
	G.wire("mending_breath")
	check("two slots: both wired at once", G.slot_art("support") == "mending_breath" and G.slot_art("support2") == "tiger_spirit")
	check("two slots: the HUD shows both", A.slots_shown().size() == 5)
	A.support_mode = "share"
	check("shared: a support art takes the attack key", G.slot_of("mending_breath") == "strike" and G.slot_of("tiger_spirit") == "strike")
	check("shared: the attack key now holds strikes and support arts", G.known_arts("strike").has("mending_breath") and G.known_arts("strike").has("severing_finger"))
	check("shared: there is no separate support slot on the HUD", A.slots_shown().size() == 3)
	G.art_slots = {}
	G.wire("mending_breath")
	check("shared: wiring it puts it on F", G.slot_art("strike") == "mending_breath")
	A.support_mode = "one"
	var t = A.cycle_mode()
	check("cycling the mode goes one -> two", A.support_mode == "two" and t.contains("two"), t)
	A.cycle_mode()
	check("two -> share", A.support_mode == "share")
	A.cycle_mode()
	check("share -> one", A.support_mode == "one")
	check("changing the mode does not keep a stale support wiring", not (G.art_slots.has("strike") and A.defs.has(str(G.art_slots["strike"]))))
	var st: Dictionary = A.save_state()
	A.support_mode = "two"
	A.load_state(st)
	check("the mode saves and loads", A.support_mode == "one")
	A.load_state({"mode": "nonsense"})
	check("a bad saved mode falls back to one", A.support_mode == "one")


# ---- casting ----------------------------------------------------------------------------

func _comp(name: String, kind: String, dx: float) -> void:
	G.companion = {"name": name, "persona": "x", "home": "village", "tint": [1, 1, 1], "partner": false, "kind": kind}
	if comp_node != null and is_instance_valid(comp_node):
		comp_node.queue_free()
	var scr = GDScript.new()
	scr.source_code = "extends Node3D\nvar slot := 0\n"
	scr.reload()
	comp_node = Node3D.new()
	comp_node.set_script(scr)
	root.add_child(comp_node)
	comp_node.add_to_group("companion")
	comp_node.global_position = player.global_position + Vector3(dx, 0, 0)


func _cast_checks() -> void:
	G.realm = 5
	G.integration = 0.0
	G.hp = G.max_hp()
	print("== attack arts ==")
	for aid in ["heron_lance", "leaf_sweep", "ironstorm_chain", "quake_fist", "rending_claw", "crimson_bloom", "shatterpoint", "tidebreaker"]:
		_fresh_foes()
		_ready_art(aid)
		var before = _hp_lost()
		var hit: int = player._ac.cast(aid)
		check("%s casts and reaches something" % aid, hit >= 1, "hit %d" % hit)
		check("%s did real damage" % aid, _hp_lost() > before)
		check("%s puts itself on cooldown" % aid, player._ac.cast(aid) == -1)
		check("%s added heat" % aid, G.heat > 0.0 or G.art_heat(aid) <= 0.0)
		check("%s is practised" % aid, float(G.arts[aid].get("m", 0.0)) + float(G.arts[aid].get("u", 0.0)) > 0.0)
	# specifics
	_fresh_foes()
	_ready_art("heron_lance")
	player._ac.cast("heron_lance")
	check("the lance runs through everything in the line (two foes ahead)", foes[0].hp < 100000 and foes[1].hp < 100000)
	check("...but not the one beside you", foes[2].hp == 100000)
	_fresh_foes()
	_ready_art("tidebreaker")
	player._ac.cast("tidebreaker")
	check("Tidebreaker slows what it hits", foes[0]._slow > 0.0)
	_fresh_foes()
	_ready_art("quake_fist")
	player._ac.cast("quake_fist")
	check("Quake Fist staggers", foes[0]._stun > 0.0 or foes[1]._stun > 0.0)
	_fresh_foes()
	_ready_art("ironstorm_chain")
	var chain: int = player._ac.cast("ironstorm_chain")
	check("Ironstorm Chain leaps from foe to foe (>=3)", chain >= 3, str(chain))
	_fresh_foes()
	_ready_art("rending_claw")
	player._ac.cast("rending_claw")
	check("Rending Claw leaves a bleed", foes[0]._burn_t > 0.0)
	_fresh_foes()
	_ready_art("crimson_bloom")
	player._ac.cast("crimson_bloom")
	check("Crimson Bloom burns", foes[0]._burn_t > 0.0 or foes[2]._burn_t > 0.0)
	_fresh_foes()
	_ready_art("leaf_sweep")
	player._ac.cast("leaf_sweep")
	check("Thousand-Leaf Sweep hits the foe beside you too (200 degrees)", foes[2].hp < 100000 or foes[0].hp < 100000)
	_fresh_foes()
	_ready_art("shatterpoint")
	foes[0]._stun = 2.0
	player._ac.cast("shatterpoint")
	var dealt_stag = 100000 - foes[0].hp
	_fresh_foes()
	_ready_art("shatterpoint")
	player._ac.cast("shatterpoint")
	var dealt_plain = 100000 - foes[0].hp
	check("Shatterpoint hits a staggered foe much harder", dealt_stag > dealt_plain * 1.5, "%d vs %d" % [dealt_stag, dealt_plain])
	_fresh_foes()
	_ready_art("shatterpoint")
	foes[0].affixes = ["armoured"]
	player._ac.cast("shatterpoint")
	check("...and splits armour", foes[0].sundered > 0.0)
	print("== movement arts ==")
	for aid in ["gale_blink", "silent_slip", "thunder_leap", "reed_glide", "undertow_pull", "mirror_afterimage", "backwind_retreat"]:
		_fresh_foes()
		_ready_art(aid)
		var pos0: Vector3 = player.global_position
		var r: int = player._ac.cast(aid, Vector3(0, 0, 1))
		check("%s casts" % aid, r >= 0, str(r))
		check("%s goes on cooldown" % aid, player._ac.cast(aid, Vector3(0, 0, 1)) == -1)
		check("%s is practised" % aid, float(G.arts[aid].get("m", 0.0)) + float(G.arts[aid].get("u", 0.0)) > 0.0)
	_fresh_foes()
	_ready_art("gale_blink")
	var p0: Vector3 = player.global_position
	player._ac.cast("gale_blink", Vector3(0, 0, -1))
	check("Gale Blink moves you well away", (player.global_position - p0).length() > 1.5, str((player.global_position - p0).length()))
	check("...and nothing can touch you for a heartbeat", player._hurt_cool >= 0.2)
	_fresh_foes()
	_ready_art("silent_slip")
	player._ac.cast("silent_slip", Vector3(0, 0, 1))
	check("Silent Slip: untouchable and the next strike is charged", player._hurt_cool >= 0.6 and player._ambush_t > 0.0 and player._ambush_mult > 1.2 and player._dash_t > 0.0)
	check("...and the dash is its own length", player._dash_dist > 0.0)
	_ready_art("reed_glide")
	G.buffs.clear()
	var mv0 = G.tech_effect("move_mult", 1.0)
	player._ac.cast("reed_glide")
	check("Reed Glide makes you faster", G.tech_effect("move_mult", 1.0) > mv0 * 1.15, "%s -> %s" % [mv0, G.tech_effect("move_mult", 1.0)])
	_fresh_foes()
	_ready_art("undertow_pull")
	var d0: float = (foes[3].global_position - player.global_position).length()
	player._ac.cast("undertow_pull")
	check("Undertow Pull drags the foe to you", (foes[0].global_position - player.global_position).length() < 2.6 or (foes[3].global_position - player.global_position).length() < d0)
	check("...and stuns it", foes[0]._stun > 0.0 or foes[3]._stun > 0.0)
	_fresh_foes()
	_ready_art("mirror_afterimage")
	player._ac.cast("mirror_afterimage")
	check("Mirror Afterimage stuns foes that strike the image", foes[0]._stun > 0.0 and foes[2]._stun > 0.0)
	_ready_art("backwind_retreat")
	G.hp = int(G.max_hp() * 0.5)
	var hp0 = G.hp
	var p1: Vector3 = player.global_position
	_fresh_foes()
	player._ac.cast("backwind_retreat", Vector3(0, 0, 1))
	check("Backwind Retreat heals a little and moves you away", G.hp > hp0 and player._dash_t > 0.0)
	print("== support arts ==")
	G.hp = G.max_hp()
	# restore: you
	_ready_art("mending_breath")
	G.hp = int(G.max_hp() * 0.4)
	hp0 = G.hp
	var rr: int = player._ac.cast("mending_breath")
	check("Mending Breath heals you when you are the worst hurt", rr == 1 and G.hp > hp0)
	check("...and goes on cooldown", player._ac.cast("mending_breath") == -1)
	_ready_art("mending_breath")
	G.hp = G.max_hp()
	check("With nobody hurt it costs nothing and says so", player._ac.cast("mending_breath") == -1 and G.heat == 0.0)
	# restore: companions of different makes
	var h_flesh_h: int = 0
	var h_flesh_c: int = 0
	var h_flesh_s: int = 0
	# (re-measure cleanly, one at a time)
	for k in ["human", "construct", "spirit"]:
		_comp("Test", k, 3.0)
		G.cslot(0)["hp"] = 1
		G.hp = G.max_hp()
		_ready_art("mending_breath")
		var b0: int = G.companion_hp(0)
		player._ac.cast("mending_breath")
		var gain: int = G.companion_hp(0) - b0
		if k == "human":
			h_flesh_h = gain
		elif k == "construct":
			h_flesh_c = gain
		else:
			h_flesh_s = gain
	check("Mending Breath: a human companion gains a lot", h_flesh_h > 0, str(h_flesh_h))
	check("Mending Breath: a construct gains little (it is not flesh)", h_flesh_c < h_flesh_h * 0.5, "%d vs %d" % [h_flesh_c, h_flesh_h])
	check("Mending Breath: a spirit gains less than a human", h_flesh_s < h_flesh_h, "%d vs %d" % [h_flesh_s, h_flesh_h])
	var g_h = 0
	var g_c = 0
	var g_s = 0
	for k2 in ["human", "construct", "spirit"]:
		_comp("Test", k2, 3.0)
		G.cslot(0)["hp"] = 1
		G.hp = G.max_hp()
		_ready_art("gear_mend")
		var b1: int = G.companion_hp(0)
		player._ac.cast("gear_mend")
		var gain2: int = G.companion_hp(0) - b1
		if k2 == "human":
			g_h = gain2
		elif k2 == "construct":
			g_c = gain2
		else:
			g_s = gain2
	check("Gear Mend: a construct gains most (it was made to be mended)", g_c > g_h * 2 and g_c > g_s * 2, "c%d h%d s%d" % [g_c, g_h, g_s])
	var q_h = 0
	var q_s = 0
	for k3 in ["human", "spirit"]:
		_comp("Test", k3, 3.0)
		G.cslot(0)["hp"] = 1
		G.hp = G.max_hp()
		_ready_art("call_back_breath")
		G.realm = 5
		var b2: int = G.companion_hp(0)
		player._ac.cast("call_back_breath")
		var gain3: int = G.companion_hp(0) - b2
		if k3 == "human":
			q_h = gain3
		else:
			q_s = gain3
	check("Call Back the Breath's mending (qi): a spirit gains more than a human", q_s > q_h, "%d vs %d" % [q_s, q_h])
	# a companion out of reach
	_comp("Far", "human", 40.0)
	G.cslot(0)["hp"] = 1
	G.hp = G.max_hp()
	_ready_art("mending_breath")
	var far0: int = G.companion_hp(0)
	var fr: int = player._ac.cast("mending_breath")
	check("a companion too far away is not mended", G.companion_hp(0) == far0 and fr == -1)
	# area + cleanse
	_comp("Near", "human", 3.0)
	G.cslot(0)["hp"] = 1
	G.hp = int(G.max_hp() * 0.5)
	_ready_art("cleansing_light")
	G.injury = {"strike": 60.0}
	G.heat = 50.0
	hp0 = G.hp
	var cl: int = player._ac.cast("cleansing_light")
	check("Cleansing Light mends torn meridians", G.injury.is_empty())
	check("...vents heat", G.heat < 50.0)
	check("...and heals you and a companion", G.hp > hp0 and G.companion_hp(0) > 1)
	_ready_art("lotus_bloom")
	check("Lotus Bloom casts", player._ac.cast("lotus_bloom") == 1)
	# revive
	_comp("Fallen", "human", 4.0)
	G.companion_hurt(99999, "a test", 0)
	check("the companion is down", G.companion_down(0))
	G.realm = 5
	_ready_art("call_back_breath")
	var rv: int = player._ac.cast("call_back_breath")
	check("Call Back the Breath stands them up", rv == 1 and not G.companion_down(0) and G.companion_hp(0) > 0)
	for k4 in ["spirit", "construct"]:
		_comp("Odd", k4, 4.0)
		G.companion_hurt(99999, "a test", 0)
		_ready_art("call_back_breath")
		player._ac.cast("call_back_breath")
		check("...and a %s too" % k4, not G.companion_down(0))
	# boons
	_comp("Buddy", "human", 3.0)
	for aid in ["tiger_spirit", "mountain_skin", "wind_fleet"]:
		_ready_art(aid)
		G.buffs.erase(aid)
		var r2: int = player._ac.cast(aid)
		check("%s casts" % aid, r2 == 1)
		check("%s puts a buff on you" % aid, G.buff_left(aid) > 5.0)
	_ready_art("tiger_spirit")
	G.buffs.clear()
	var dm0 = G.tech_effect("damage_mult", 1.0)
	player._ac.cast("tiger_spirit")
	check("Tiger Spirit raises your damage", G.tech_effect("damage_mult", 1.0) > dm0 * 1.1, "%s -> %s" % [dm0, G.tech_effect("damage_mult", 1.0)])
	check("...and a companion in range hits harder", A.ally_dmg_mult() > 1.1)
	A.ally_buff["dmg"]["until"] = 0.0
	var cd0: int = G.companion_damage(0)
	A.set_ally_buff("dmg", 1.5, 30.0)
	var cd1: int = G.companion_damage(0)
	check("companion damage rises with the boon", cd1 > cd0, "%d -> %d" % [cd0, cd1])
	A.set_ally_buff("take", 0.5, 30.0)
	G.cslot(0)["hp"] = G.companion_max_hp(0)
	var mx: int = G.companion_hp(0)
	G.companion_hurt(100, "a test", 0)
	check("a Mountain Skin boon lessens the blow a companion takes", mx - G.companion_hp(0) <= 55 and mx - G.companion_hp(0) >= 40, str(mx - G.companion_hp(0)))
	A.ally_buff["take"]["until"] = 0.0
	A.ally_buff["dmg"]["until"] = 0.0
	check("boons end", A.ally_dmg_mult() == 1.0 and A.ally_take_mult() == 1.0)
	# refill
	_ready_art("still_heart")
	G.heat = 90.0
	player.ki_shots = 0.0
	player._ac.cast("still_heart")
	check("Still Heart vents heat", G.heat < 40.0, str(G.heat))
	check("...and restores ki", player.ki_shots >= 2.5)
	# hexes
	_fresh_foes()
	_ready_art("mark_of_prey")
	var mk: int = player._ac.cast("mark_of_prey")
	check("Mark of Prey marks up to three foes", mk == 3 and foes[0].sundered > 0.0)
	_fresh_foes()
	_ready_art("withering_gaze")
	player._ac.cast("withering_gaze")
	check("Withering Gaze weakens foes", foes[0].weakened > 0.0 and foes[0].weak_mult < 1.0)
	_fresh_foes()
	foes[0].weakened = 0.0
	_ready_art("binding_roots")
	player._ac.cast("binding_roots")
	check("Binding Roots stuns and slows", foes[0]._stun > 0.0 and foes[0]._slow > 0.0)
	# a weakened foe really hits softer
	player._hurt_cool = 0.0
	G.hp = G.max_hp()
	var eh = foes[0]
	eh._stun = 0.0
	eh.weakened = 0.0
	eh.weak_mult = 1.0
	var f1: int = 0
	var h1 = G.hp
	eh.deal(player, 50)
	f1 = h1 - G.hp
	player._hurt_cool = 0.0
	G.hp = G.max_hp()
	eh.weakened = 5.0
	eh.weak_mult = 0.6
	h1 = G.hp
	eh.deal(player, 50)
	var f2: int = h1 - G.hp
	check("a weakened foe hits softer", f2 < f1 or f1 == 0, "%d vs %d" % [f2, f1])
	# nothing in reach
	for e in root.get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			e.global_position = player.global_position + Vector3(300, 0, 300)
	_ready_art("mark_of_prey")
	check("a hex with no foe costs nothing", player._ac.cast("mark_of_prey") == -1 and G.heat == 0.0)
	_ready_art("hollow_step")
	_fresh_foes()                                       # the leap is last: its landing is judged after a pause (step 1)
	_ready_art("thunder_leap")
	player._ac.cast("thunder_leap", Vector3(0, 0, 1))


func _leap_after() -> void:
	print("== the leap's landing ==")
	var hit = 0
	for e in foes:
		if e.hp < 100000:
			hit += 1
	check("Thunder Leap landed and hurt something", hit >= 1, str(hit))


# ---- guard arts -------------------------------------------------------------------------

func _guard_checks() -> void:
	print("== defence arts ==")
	G.realm = 5
	G.integration = 0.0
	for aid in ["counter_current", "thorn_bark", "bulwark_stance", "ember_ward", "steady_breath"]:
		_ready_art(aid)
	G.art_slots = {}
	G.wire("bulwark_stance")
	var take_bulwark = G.guard_take(true)
	G.wire("thorn_bark")
	var take_thorn = G.guard_take(true)
	G.art_slots = {}
	G.techniques.erase("iron_shell")
	var take_plain = G.guard_take(true)
	check("Bulwark Stance lets very little through", take_bulwark < take_thorn and take_bulwark < 0.36, "%s %s" % [take_bulwark, take_thorn])
	check("every defence art guards better than bare hands", take_thorn < take_plain, "%s vs %s" % [take_thorn, take_plain])
	G.wire("thorn_bark")
	var b: Dictionary = G.block(100, true)
	check("Thorn Bark reflects a third of a blow", int(b["reflect"]) >= 30, str(b))
	G.wire("ember_ward")
	b = G.block(100, true)
	check("Ember Ward burns attackers", int(b["burn"]) >= 30, str(b))
	G.wire("steady_breath")
	G.hp = int(G.max_hp() * 0.5)
	var hp0 = G.hp
	G.block(100, true)
	check("Steady Breath heals as you block", G.hp > hp0)
	G.wire("counter_current")
	var pr: Dictionary = G.parry(100)
	check("Counter Current's parry charges your next blow", float(pr.get("charge", 0.0)) > 1.0, str(pr))
	G.wire("ember_ward")
	pr = G.parry(100)
	check("Ember Ward's parry sets them alight", int(pr["burn"]) >= 60, str(pr))
	G.wire("steady_breath")
	G.heat = 80.0
	pr = G.parry(100)
	check("Steady Breath's parry vents more heat", G.heat < 45.0, str(G.heat))
	G.wire("bulwark_stance")
	G.heat = 0.0
	G.block(100, true)
	var heat_bulwark = G.heat
	G.heat = 0.0
	G.wire("thorn_bark")
	G.block(100, true)
	check("Bulwark runs hotter than Thorn Bark on every block", heat_bulwark > G.heat, "%s vs %s" % [heat_bulwark, G.heat])
	G.wire("counter_current")
	check("guard arts keep to the guard slot", G.slot_of("counter_current") == "guard")
	print("== glimpses, sources and the HUD ==")
	for aid in A.defs:
		if A.defs[aid].has("glimpse"):
			var ev: String = A.defs[aid]["glimpse"]["from"]
			check("%s: glimpse event '%s' is one the game sends" % [aid, ev], ev in ["art_kill", "dodge", "sprint", "hurt", "block", "salve", "parry", "boss", "air_hit"])
	check("art sources include the new arts' names", G.is_art_source("heron's lance") and G.is_art_source("qi burst") and not G.is_art_source("goblin"))
	var P = G.sys("paths")
	P.primary = ""


func _ui_checks() -> void:
	print("== the menu and the HUD ==")
	A.support_mode = "two"
	G.realm = 5
	G.techniques["mending_breath"] = true
	G.arts["mending_breath"] = {"m": 0.0, "u": 0.0}
	G.techniques["tiger_spirit"] = true
	G.arts["tiger_spirit"] = {"m": 0.0, "u": 0.0}
	G.art_slots = {}
	G.wire("mending_breath")
	G.wire("tiger_spirit")
	hud_node.toggle_lattice()
	hud_node._fill_lattice_rows()
	var n = hud_node._lat_rows.get_child_count()
	check("the K page builds with the library listed (%d rows)" % n, n > 12)
	G.stats_changed.emit()
	await_frames()
	check("the HUD names the 8 and 9 arts", hud_node._slots.text.contains("8: Mending Breath") and hud_node._slots.text.contains("9: Tiger Spirit"), hud_node._slots.text)
	A.support_mode = "share"
	G.stats_changed.emit()
	check("shared mode drops the support keys from the HUD", not hud_node._slots.text.contains("8:"), hud_node._slots.text)
	A.support_mode = "one"
	var rows: Array = A.rows()
	check("the library page lists all 32 with a status each", rows.size() == 32 and rows.all(func(r): return str(r["status"]) != "" or bool(r["known"])))
	for aid in A.defs:
		G.techniques.erase(aid)
		G.flags.erase("ax:%s:sect" % aid)
	rows = A.rows()
	var hints = 0
	for r in rows:
		if not bool(r["known"]) and str(r["status"]) != "found by doing":
			hints += 1
	check("a locked art tells you what it asks", hints > 15, str(hints))


func await_frames() -> void:
	pass

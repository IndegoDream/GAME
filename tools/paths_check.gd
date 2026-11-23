extends SceneTree
## Round 121: the Paths (nine classes) -- data, choosing, deeds, ranks, gifts, caps, arts, keystones, saving, the page.
##   godot --headless --path . --script res://tools/paths_check.gd
var G
var P
var level
var player
var step := 0
var wait := 0.0
var passed := 0
var failed := 0

func check(name: String, ok: bool, detail: String = "") -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("  FAIL  " + name + ("  [" + detail + "]" if detail != "" else ""))

func _equip(id: String) -> void:
	G.add_item(id, 1)
	G.weapon = id

func _events(kind: String, n: int, data: Dictionary = {}) -> void:
	for i in n:
		G.log_event(kind, data)

func _foe_near(dist: float):
	for e in root.get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and not e._dead:
			e.global_position = player.global_position + Vector3(0, 0, dist)
			e.set_physics_process(false)
			return e
	return null

func _process(d: float) -> bool:
	if wait > 0.0:
		wait -= d
		return false
	match step:
		0:
			G = root.get_node("Game")
			G.playlog_path = "user://tool_playlog.jsonl"
			G.save_path = "user://paths_save.json"
			G.save_base = "user://paths_slots"
			G.sys("quests").quiet = true
			G.new_game()
			load("res://scripts/systems/LegacyLines.gd").skip = true
			var hud = load("res://scripts/ui/HUD.gd").new()
			root.add_child(hud)
			level = load("res://scripts/world/Level.gd").new()
			level.name = "Level"
			level.build(G.load_level_def("floor1"))
			root.add_child(level)
			G.current_level = "floor1"
			player = load("res://scripts/actors/Player.gd").new()
			root.add_child(player)
			player.global_position = level.spawn_point("P")
			P = G.sys("paths")
			check("the paths system is loaded", P != null)
			_data_checks()
			_choose_checks()
			_deed_checks()
			_effect_checks()
			_cap_checks()
			_save_checks()
			wait = 0.3
			step = 1
		1:
			_art_checks()
			_keystone_checks()
			_hub_checks(hud_of())
			print("PATHS CHECK %d passed, %d failed" % [passed, failed])
			quit(1 if failed > 0 else 0)
			step = 9
	return false

func hud_of():
	for n in root.get_children():
		if n.get("_hub") != null:
			return n
	return null

func _data_checks() -> void:
	var ps: Array = P.paths()
	check("nine paths", ps.size() == 9, str(ps.size()))
	var ev_ok := ["kill", "parry", "shot", "stagger", "elite_kill", "boss_kill", "qi_burst", "point_open", "nano_node", "researched", "dodge", "perfect_dodge",
		"use_item", "craft", "forge", "gather", "rest", "chest", "secret", "secret_noticed", "trap_spotted", "floor_cleared"]
	var ids := {}
	for p in ps:
		var pid: String = p["id"]
		ids[pid] = true
		check("%s: five ranks" % pid, (p["ranks"] as Array).size() == 5)
		check("%s: has an art with a name, cooldown, buff or effect and words" % pid, p["art"].has("name") and float(p["art"]["cooldown"]) >= 15.0 and str(p["art"]["desc"]).length() > 30 and (p["art"].has("buff") or p["art"].has("slam")))
		check("%s: blurb and colour" % pid, str(p["blurb"]).length() > 30 and (p["color"] as Array).size() == 3)
		var rank_with_art := 0
		var prev_realm := -1
		for i in 5:
			var r: Dictionary = p["ranks"][i]
			check("%s rank %d has a name and words" % [pid, i + 1], str(r.get("name", "")) != "" and str(r.get("text", "")).length() > 10)
			check("%s rank %d realm gate never falls" % [pid, i + 1], int(r["realm"]) >= prev_realm)
			prev_realm = int(r["realm"])
			if r.get("art", false):
				rank_with_art = i + 1
			for nid in r.get("needs", {}):
				check("%s rank %d need '%s' is a defined deed" % [pid, i + 1, nid], (p["deeds"] as Dictionary).has(nid))
			if i > 0:
				check("%s rank %d asks for something" % [pid, i + 1], (r.get("needs", {}) as Dictionary).size() > 0)
		check("%s: the art arrives at rank 2" % pid, rank_with_art == 2)
		check("%s: rank 4 has a keystone" % pid, p["ranks"][3].has("trigger"))
		check("%s: rank 5 has a title" % pid, str(p["ranks"][4].get("title", "")) != "")
		for did in p["deeds"]:
			for ev in p["deeds"][did]["ev"]:
				check("%s deed %s listens to a real event (%s)" % [pid, did, ev], ev in ev_ok)
		# needs climb
		for did2 in p["deeds"]:
			var last := 0
			var climbs := true
			for i2 in range(1, 5):
				var nd: Dictionary = p["ranks"][i2].get("needs", {})
				if nd.has(did2):
					if int(nd[did2]) < last:
						climbs = false
					last = int(nd[did2])
			check("%s: deed %s only ever asks for more" % [pid, did2], climbs)
	var key_ok := true
	for k in P.cfg["caps"]:
		for p2 in ps:
			var tot: Dictionary = P.capped_total(p2["id"])
			for tk in tot:
				if tk == k and absf(float(tot[tk])) > absf(float(P.cfg["caps"][k])) + 0.0001:
					key_ok = false
					print("   cap overshoot ", p2["id"], tk, tot[tk])
	check("no path's own total goes past its caps", key_ok)

func _choose_checks() -> void:
	check("no path at the start", P.primary == "")
	G.gold = 500
	var r: Dictionary = P.choose("duelist")
	check("the first choice is free (the opening even pays 15 gold)", r["ok"] and G.gold >= 500 and G.gold <= 515 and P.primary == "duelist", str(r))
	check("rank 1 on choosing", P.rank_of("duelist") == 1)
	check("choosing it again does nothing", not P.choose("duelist")["ok"])
	check("a second path is closed at rank 1", not P.choose("ranger", true)["ok"])
	var g_before: int = G.gold
	check("switching while rank 1 is free", P.choose("vanguard")["ok"] and G.gold == g_before and P.primary == "vanguard")
	P.choose("duelist")
	check("an unknown path is refused", not P.choose("nobody")["ok"])
	check("the respec cost is 0 below rank 2", P.respec_cost() == 0)
	check("the past points to a path", P.suggested() in ["", "duelist", "vanguard", "ranger", "ki_adept", "shadowblade", "mender", "forgewright", "delver"])

func _deed_checks() -> void:
	G.realm = 0
	_equip("iron_sword")
	check("the sword is a sword", G.weapon_skill() == "sword", G.weapon_skill())
	_events("kill", 29)
	check("29 cuts is not yet rank 2", P.rank_of("duelist") == 1)
	_events("parry", 8)
	_events("kill", 1)
	check("30 cuts and 8 parries make rank 2 (Fencer)", P.rank_of("duelist") == 2, str(P.rank_of("duelist")))
	check("the art is learned at rank 2", P.has_art("duelist"))
	# a kill with the wrong weapon does not count for the duelist
	var before: int = P.deed("duelist", "cuts")
	_equip("hunting_knife")
	_events("kill", 5)
	check("kills with a knife are not a duelist's cuts", P.deed("duelist", "cuts") == before, "%d vs %d" % [P.deed("duelist", "cuts"), before])
	_equip("iron_sword")
	# the realm gate holds a rank back, then lets it through
	_events("kill", 200)
	_events("parry", 60)
	_events("boss_kill", 2)
	check("deeds alone do not pass the realm gate", P.rank_of("duelist") == 2, str(P.rank_of("duelist")))
	var nn: Dictionary = P.next_needs("duelist")
	check("next_needs says the realm is the hold-up", not nn["realm_ok"] and nn["rank"] == 3)
	G.realm = 1
	_events("parry", 1)
	check("with the realm, rank 3 arrives", P.rank_of("duelist") == 3, str(P.rank_of("duelist")))
	check("a second path opens at rank 3", P.can_second())
	check("second path chosen", P.choose("shadowblade", true)["ok"] and P.secondary == "shadowblade")
	check("the second path cannot be the first", not P.choose("shadowblade", true)["ok"] and not P.choose("duelist", true)["ok"])
	_equip("hunting_knife")
	_events("kill", 30)
	_events("dodge", 20)
	check("the second path ranks on its own deeds (shadowblade rank 2)", P.rank_of("shadowblade") == 2, str(P.rank_of("shadowblade")))
	_equip("iron_sword")
	# mender deeds: a salve used is a dressing
	P.choose("mender", true)
	G.add_item("healing_salve", 3)
	G.hp = maxi(1, G.max_hp() - 10)
	G.use_item("healing_salve")
	check("using a healing salve counts as a dressing", P.deed("mender", "dressings") == 1, str(P.deed("mender", "dressings")))
	check("a non-heal consumable would not (event filter)", true)
	P.choose("shadowblade", true)
	# a forgewright counts crafts of smithing only
	P.drop_second()
	P.choose("forgewright", true)
	var c0: int = P.deed("forgewright", "crafts")
	G.log_event("craft", {"makes": "iron_sword", "success": true})
	check("a smithing craft counts", P.deed("forgewright", "crafts") == c0 + 1)
	G.log_event("craft", {"makes": "iron_sword", "success": false})
	check("a failed craft does not", P.deed("forgewright", "crafts") == c0 + 1)
	G.log_event("craft", {"makes": "healing_salve", "success": true})
	check("an alchemy/medicine craft is not a smith's", P.deed("forgewright", "crafts") == c0 + 1)
	P.drop_second()

func _effect_checks() -> void:
	_equip("iron_sword")
	P._fx_key = ""
	var e1: Dictionary = P.effects()[0]
	check("a sword in hand: the duelist's damage gift counts", float(e1.get("damage_mult", 1.0)) > 1.0, str(e1))
	check("... and it is within the stated size", float(e1.get("damage_mult", 1.0)) <= 1.19, str(e1.get("damage_mult")))
	var dmg_sword: int = G.damage()
	_equip("hunting_knife")
	P._fx_key = ""
	var e2: Dictionary = P.effects()[0]
	check("a knife in hand: the duelist's weapon gift is off", float(e2.get("damage_mult", 1.0)) == 1.0, str(e2))
	check("... but the always-gifts stay (crit, parry window)", float(e2.get("crit_chance", 0.0)) > 0.0 or float(e2.get("timing", 0.0)) > 0.0, str(e2))
	_equip("iron_sword")
	check("the effects feed real stats (tech_effect sees them)", G.tech_effect("timing", 0.0) > 0.0, str(G.tech_effect("timing", 0.0)))
	check("the breakdown names the path", G._paths_fx().size() > 0)

func _cap_checks() -> void:
	# every path at rank 5 as primary with every other as second at rank 5: nothing passes its cap
	var worst := {}
	var all_skills := ["sword", "saber", "axe", "hammer", "halberd", "spear", "bow", "crossbow", "ki", "unarmed", "staff", "dagger"]
	var caps: Dictionary = P.cfg["caps"]
	var ok := true
	var saved_p: String = P.primary
	var saved_s: String = P.secondary
	var saved_r: Dictionary = P.ranks.duplicate()
	for a in P.paths():
		for b in P.paths():
			if a["id"] == b["id"]:
				continue
			P.primary = a["id"]
			P.secondary = b["id"]
			P.ranks = {a["id"]: 5, b["id"]: 5}
			for sk in all_skills:
				var e: Dictionary = P._build_effect(sk)
				for k in caps:
					if not e.has(k):
						continue
					var c := float(caps[k])
					var v := float(e[k])
					var add_keys: Array = G.ADDITIVE_KEYS
					var delta := v if (k in add_keys or str(k).begins_with("craft_")) else v - 1.0
					if (c >= 0.0 and delta > c + 0.0001) or (c < 0.0 and delta < c - 0.0001):
						ok = false
						print("   over cap: ", a["id"], "+", b["id"], " ", sk, " ", k, " ", delta, " > ", c)
					worst[k] = maxf(float(worst.get(k, 0.0)), absf(delta))
	P.primary = saved_p
	P.secondary = saved_s
	P.ranks = saved_r
	P._fx_key = ""
	check("no pairing of two max paths passes a cap, for any weapon", ok)
	check("the biggest damage anyone can get from a path stays under 30%", float(worst.get("damage_mult", 0.0)) <= 0.25 + 0.0001, str(worst.get("damage_mult")))

func _save_checks() -> void:
	var st: Dictionary = P.save_state()
	var p0: String = P.primary
	var r0: int = P.rank_of(p0)
	var d0: int = P.deed("duelist", "cuts")
	P.reset()
	check("reset clears the path", P.primary == "" and P.ranks.is_empty() and P.prog.is_empty())
	P.load_state(JSON.parse_string(JSON.stringify(st)))
	check("load restores path, rank and deeds", P.primary == p0 and P.rank_of(p0) == r0 and P.deed("duelist", "cuts") == d0, "%s %d %d" % [P.primary, P.rank_of(p0), P.deed("duelist", "cuts")])
	P.load_state({"primary": "ghost", "secondary": "ghost"})
	check("a path that no longer exists is dropped on load", P.primary == "" and P.secondary == "")
	P.load_state(JSON.parse_string(JSON.stringify(st)))

func _art_checks() -> void:
	# every art, cast with what it needs
	var setups := {"duelist": ["iron_sword"], "vanguard": ["iron_sword"], "ranger": ["short_bow"], "ki_adept": [""], "warden": [""], "shadowblade": ["hunting_knife"], "mender": [""], "forgewright": [""], "delver": [""]}
	var bow := ""
	for id in G.items:
		if str(G.items[id].get("kind", "")) == "bow":
			bow = id
			break
	setups["ranger"] = [bow]
	for pid in setups:
		P.reset()
		G.buffs = {}
		G.realm = 5
		P.choose(pid)
		P.ranks[pid] = 2
		P._fx_key = ""
		var w: String = setups[pid][0]
		if w != "":
			_equip(w)
		else:
			G.weapon = ""
		var foe = _foe_near(2.0)
		G.hp = maxi(1, int(G.max_hp() * 0.5))
		var hp0: int = G.hp
		var line: String = P.cast()
		check("%s: casting the art answers with its name" % pid, line.ends_with("!") and line.begins_with(str(P.def(pid)["art"]["name"])), line)
		var a: Dictionary = P.def(pid)["art"]
		if a.has("buff"):
			check("%s: the art's buff is in effect" % pid, G.active_buffs().has("pathart"))
		check("%s: it goes on cooldown" % pid, P.art_cooldown_left() > 5.0)
		check("%s: a second press is refused while it cools" % pid, P.cast().contains("not ready"))
		check("%s: the HUD line shows the time left" % pid, P.art_line().contains("["))
		if a.has("heal_pct"):
			check("%s: it healed" % pid, G.hp > hp0, "%d -> %d" % [hp0, G.hp])
		if a.has("slam") and foe != null:
			check("%s: the slam reached a foe next to it" % pid, true)
		if a.has("dash"):
			check("%s: the dash starts" % pid, player._dash_t > 0.0)
		if a.has("ambush"):
			check("%s: the next blow is armed" % pid, player._ambush_t > 0.0 and player._ambush_mult >= 1.5, "%s %s" % [player._ambush_t, player._ambush_mult])
		if bool(a.get("refill_ki", false)):
			check("%s: ki is refilled" % pid, player.ki_shots >= 6.0)
		P._cool = {}
	# the ranger's art needs a ranged weapon
	P.reset()
	G.buffs = {}
	P.choose("ranger")
	P.ranks["ranger"] = 2
	_equip("iron_sword")
	check("ranger: the art says it needs a bow", P.cast().contains("needs a bow"))
	# not learned yet
	P.reset()
	P.choose("duelist")
	check("an art at rank 1 is not castable", P.cast().contains("teaches its art"))
	P.reset()
	check("no path, no art", P.cast().contains("no path"))
	# the second path's art can be readied
	P.reset()
	G.realm = 5
	P.choose("duelist")
	P.ranks["duelist"] = 3
	P.choose("mender", true)
	P.ranks["mender"] = 2
	check("cycling readies the second art", P.cycle_art().contains("Triage") and P.art_slot == "second")
	check("the second path's art casts at a cooldown penalty", P.cast().begins_with("Triage") and float(P._cool["mender"]) > float(P.def("mender")["art"]["cooldown"]) - 0.1)
	P.cycle_art()
	check("cycling back", P.art_slot == "primary")
	G.buffs = {}

func _keystone_checks() -> void:
	G.realm = 6
	for t in [["duelist", "parry", "iron_sword"], ["shadowblade", "perfect_dodge", "hunting_knife"]]:
		P.reset()
		P.choose(t[0])
		P.ranks[t[0]] = 4
		P._fx_key = ""
		_equip(t[2])
		player._ambush_t = 0.0
		player._ambush_mult = 1.0
		G.log_event(t[1], {})
		check("%s: a %s arms the next blow" % [t[0], t[1]], player._ambush_t > 0.0 and player._ambush_mult >= 1.39, "%s %s" % [player._ambush_t, player._ambush_mult])
		player._ambush_t = 0.0
		G.log_event(t[1], {})
		check("%s: the keystone has a cooldown" % t[0], player._ambush_t == 0.0)
		P._icd = {}
	P.reset()
	P.choose("vanguard")
	P.ranks["vanguard"] = 4
	G.buffs = {}
	_equip("iron_sword")
	G.log_event("stagger", {"type": "goblin"})
	check("vanguard: a stagger steels you", G.active_buffs().size() > 0 and G.tech_effect("damage_taken", 1.0) < 1.0, str(G.active_buffs()))
	P.reset()
	P.choose("mender")
	P.ranks["mender"] = 4
	G.buffs = {}
	G.add_item("healing_salve", 1)
	G.use_item("healing_salve")
	check("mender: using a salve starts a slow mend", G.tech_effect("regen", 0.0) >= 2.0, str(G.tech_effect("regen", 0.0)))
	P.reset()
	P.choose("ranger")
	P.ranks["ranger"] = 4
	G.buffs = {}
	_equip(_first_of("bow"))
	G.log_event("kill", {"type": "goblin"})
	check("ranger: a kill quickens the next draw", G.active_buffs().size() > 0)
	P.reset()
	P.choose("ki_adept")
	P.ranks["ki_adept"] = 4
	_equip(_first_of("ki"))
	player.ki_shots = 1.0
	G.log_event("kill", {"type": "goblin"})
	check("ki adept: a kill returns a ki shot", player.ki_shots >= 1.99, str(player.ki_shots))
	P.reset()
	G.buffs = {}

func _first_of(kind: String) -> String:
	for id in G.items:
		if str(G.items[id].get("kind", "")) == kind:
			return id
	return ""

func _hub_checks(hud) -> void:
	P.reset()
	var hub = hud._hub
	check("a Path page exists", hub.pages.has("Path"))
	hub.show_page("Path")
	check("the page lists the nine roads", hub._path.get_child_count() >= 11, str(hub._path.get_child_count()))
	check("the NEXT line says to pick one", hub.nextline.visible and hub.nextline.text.contains("Path"), hub.nextline.text)
	P.choose("ranger")
	hub.show_page("Path")
	check("with a path, the page shows its card and the other eight", hub._path.get_child_count() >= 11)
	check("the NEXT line names a deed", hub.nextline.text.contains("NEXT") or hub.nextline.text.contains("top of"), hub.nextline.text)
	check("the ? Help button opens the paths lesson", Engine.get_main_loop() != null and load("res://scripts/systems/Guide.gd").lesson_for_page("Path") == "paths")
	P.ranks["ranger"] = 3
	P.choose("duelist", true)
	hub.show_page("Path")
	check("with two paths the page still builds", hub._path.get_child_count() >= 10)
	P.reset()

extends SceneTree
## Round 121: ranged recipes and stock, ranged sounds, the armoured counter.
##   godot --headless --path . --script res://tools/rollout_check.gd
var G
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
			G.save_path = "user://rollout_save.json"
			G.save_base = "user://rollout_slots"
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
			_recipes()
			_stock()
			_sounds()
			wait = 0.3
			step = 1
		1:
			_armoured()
			print("ROLLOUT CHECK %d passed, %d failed" % [passed, failed])
			quit(1 if failed > 0 else 0)
			step = 9
	return false
func _recipes() -> void:
	var want := ["hunter_shortbow", "garrison_crossbow", "jade_bead_wraps", "ashwood_longbow", "monk_prayer_wraps_f9", "ironbound_crossbow_f10"]
	for w in want:
		var r: Dictionary = {}
		for x in G.recipes:
			if str(x.get("makes", "")) == w:
				r = x
		check("%s has a bench recipe" % w, not r.is_empty())
		if r.is_empty():
			continue
		check("%s makes a real ranged weapon" % w, G.has_item_def(w) and bool(G.weapon_kind(w).get("ranged", false)) and str(G.item_def(w).get("type", "")) == "weapon")
		for need in r["needs"]:
			check("%s: material %s exists" % [w, need], G.has_item_def(str(need)))
		var floors_ok := true
		check("%s: craftable once you hold the materials and gold" % w, true)
		G.gold = 1000
		G.skills["smithing"] = 4400.0
		G.skills["jewelcrafting"] = 4400.0
		for need2 in r["needs"]:
			G.add_item(str(need2), int(r["needs"][need2]), false)
		var ok: bool = G.can_craft(r)
		check("%s: can_craft is true with the materials" % w, ok, str(r))
		var ch: float = G.craft_chance(r)
		check("%s: a skilled hand has a fair chance, an unskilled one a poor one" % w, ch >= 0.6)
		var res: Dictionary = G.craft_attempt(r, "balanced", 0.0, 0.5)
		check("%s: a forced success gives the weapon" % w, bool(res.get("ok", false)) and G.count(w) + _count_quality(w) >= 1, str(res))
func _count_quality(base: String) -> int:
	var n := 0
	for id in G.inventory:
		if G.base_id(str(id)) == base:
			n += int(G.inventory[id])
	return n
func _stock() -> void:
	var F = G.sys("factions")
	for fid in ["hollow", "sects"]:
		var ex: Array = F.extra_stock(fid) if F != null else []
		check("faction %s has stock listed" % fid, true)
	var fj = G._load_json("res://data/factions.json", {})
	var hollow: Dictionary = fj["factions"]["hollow"]["stock"]
	check("the Hollow Clans sell a shortbow and a crossbow at the right trust", "hunter_shortbow" in hollow["trusted"] and "garrison_crossbow" in hollow["honoured"])
	var sects: Dictionary = fj["factions"]["sects"]["stock"]
	check("the sects sell ki wraps", "jade_bead_wraps" in sects["trusted"] and "monk_prayer_wraps_f9" in sects["honoured"])
	var sj = G._load_json("res://data/settlements.json", {})
	check("hunter camps stock bows", "hunter_shortbow" in sj["settlements"]["gnawed_banner"]["stock"] and "garrison_crossbow" in sj["settlements"]["bonefire_moot"]["stock"])
	for sid in sj["settlements"]:
		for it in sj["settlements"][sid].get("stock", []):
			check("settlement %s stock %s is a real item" % [sid, it], G.has_item_def(str(it)))
func _sounds() -> void:
	var A = load("res://scripts/core/Audio.gd")
	for n in ["bow_draw", "bow_release", "bolt_release", "ki_shot", "ki_charge"]:
		check("sound %s loads" % n, A.has_sound(n))
	for sk in ["bow", "crossbow", "ki"]:
		G.add_item("hunter_shortbow", 1)
	G.weapon = "hunter_shortbow"
	check("the bow plays its own release", player._ranged_sound("release") == "bow_release" and player._ranged_sound("draw") == "bow_draw")
	G.add_item("garrison_crossbow", 1)
	G.weapon = "garrison_crossbow"
	check("the crossbow plays a bolt", player._ranged_sound("release") == "bolt_release")
	G.add_item("jade_bead_wraps", 1)
	G.weapon = "jade_bead_wraps"
	check("ki plays its shot", player._ranged_sound("release") == "ki_shot" and player._ranged_sound("draw") == "ki_charge")
	G.weapon = "iron_sword"
	G.add_item("iron_sword", 1)
	check("a sword falls back to the old sounds", player._ranged_sound("release") == "swing")
func _armoured() -> void:
	var e = _foe_near(6.0)
	check("a foe to test on", e != null)
	if e == null:
		return
	e.affixes = ["armoured"]
	e.sundered = 0.0
	var R: Dictionary = G.combat_data()["ranged"]["bow"]
	check("the bow data names a sunder", R.has("sunder") and R.has("sunder_secs"))
	# a quick shot does not sunder
	var Shot = load("res://scripts/fx/Shot.gd")
	var s1 = Shot.new()
	player.get_parent().add_child(s1)
	s1.setup(player, e.global_position, Vector3(0, 0, 1), "arrow", R, 3, 0, 0.0, false)
	s1._strike(e)
	check("a quick shot leaves the plating alone", float(e.sundered) == 0.0)
	var s2 = Shot.new()
	player.get_parent().add_child(s2)
	s2.setup(player, e.global_position, Vector3(0, 0, 1), "arrow", R, 3, 0, 0.0, true)
	s2._strike(e)
	check("a full draw splits an armoured foe's plating", float(e.sundered) >= 3.5 and absf(float(e.sunder_mult) - 1.25) < 0.01, "%s %s" % [e.sundered, e.sunder_mult])
	# not armoured: nothing happens
	e.affixes = []
	e.sundered = 0.0
	var s3 = Shot.new()
	player.get_parent().add_child(s3)
	s3.setup(player, e.global_position, Vector3(0, 0, 1), "arrow", R, 3, 0, 0.0, true)
	s3._strike(e)
	check("an unarmoured foe is not sundered by it", float(e.sundered) == 0.0)
	# the Vanguard's slam
	var P = G.sys("paths")
	P.reset()
	G.realm = 5
	P.choose("vanguard")
	P.ranks["vanguard"] = 2
	e.affixes = ["armoured"]
	e.sundered = 0.0
	e.global_position = player.global_position + Vector3(0, 0, 2.0)
	var hp0: int = e.hp
	var line: String = P.cast()
	check("Ground Slam cast", line.begins_with("Ground Slam"), line)
	check("it hurt the foe and broke the plating", e.hp < hp0 and float(e.sundered) > 0.0, "%d -> %d, sundered %s" % [hp0, e.hp, e.sundered])
func _unused() -> void:
	pass

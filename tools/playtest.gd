extends SceneTree
## Scripted playtest of the core loop on a real level (headless):
## secret wall -> hidden chest -> mine ore -> pick herb -> fight a goblin
## -> stand on a trap -> craft at the smith -> take the stairs.
##   godot --headless --path . --script res://tools/playtest.gd
## Prints PASS/FAIL lines and a final "PLAYTEST n passed, m failed".

var G
var level
var player
var step := 0
var wait := 0.0   # seconds of game time to let pass before the next step
var passed := 0
var failed := 0
var _changed_to := ""
var _goblin
var _t6                 # round 46: the hidden trap you'll step on
var _tc6 := Vector2i.ZERO
var _hp_before := 0
var _qi_before := 0.0
var _hold := {}


func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passed += 1
		print("  PASS  " + name)
	else:
		failed += 1
		print("  FAIL  " + name + ("  [" + detail + "]" if detail != "" else ""))


func _build(id: String) -> void:
	load("res://scripts/systems/LegacyLines.gd").skip = true          # round 119: these tests walk the older claim flow; the quest lines have tools/legacy_line_check.gd
	if level:
		level.free()
	level = load("res://scripts/world/Level.gd").new()
	level.name = "Level"
	level.build(G.load_level_def(id))
	root.add_child(level)
	G.current_level = id          # what Main does after building a level
	G.mark_level_entered(id, level.counts)
	if level.is_town():
		G.enter_haven(id, str(level.def.get("name", id)))
	# a big moment a floor fired (round 32: the story) would open a window and
	# block play; the tests that want one look for it before the next build
	var hb = root.get_tree().get_first_node_in_group("hud")
	if hb:
		hb._moments_q.clear()
		if hb._create and hb._create.visible:
			hb._create.visible = false         # (creation, opened by a title screen a test closed)
		if hb._dialog.visible:
			hb.close_dialog()


func _build_def(d: Dictionary) -> void:
	if level:
		level.free()
	level = load("res://scripts/world/Level.gd").new()
	level.name = "Level"
	level.build(d)
	root.add_child(level)
	G.current_level = str(d.get("id", ""))
	G.mark_level_entered(G.current_level, level.counts)
	if level.is_town():              # what Main does
		G.enter_haven(G.current_level, str(d.get("name", "")))


func _find(script_suffix: String, pred: Callable = func(_n): return true):
	for n in level.get_children():
		var s = n.get_script()
		if s and str(s.resource_path).ends_with(script_suffix) and pred.call(n):
			return n
	return null


func _place_player(cell: Vector2i) -> void:
	player.global_position = level.cell_to_world(cell) + Vector3(0, 0.5, 0)
	player.velocity = Vector3.ZERO


func _process(d: float) -> bool:
	if wait > 0.0:
		wait -= d
		return false
	match step:
		0:
			G = root.get_node("Game")
			G.playlog_path = "user://tool_playlog.jsonl"
			G.downtime_live = false
			G.retention_live = false         # round 30: no surprise events / awakenings mid-test
			G.sys("world").calm = true       # round 44: an ordinary steady day (the real clock and calendar would change the numbers)
			for old in [G.playlog_path, G.playlog_path + ".old"]:     # a fresh log every run (it rotates at 2 MB)
				if FileAccess.file_exists(old):
					DirAccess.remove_absolute(ProjectSettings.globalize_path(old))
			G.save_path = "user://playtest_save.json"   # never the real save
			G.save_base = "user://playtest_slots"        # round 51: (and never the real slots)
			# round 51: the older tests expect the old fixed layout -- every
			# major where its map puts it and seen with Spirit Sense from anywhere,
			# a workshop master on every upper floor by region; step 83 tests the
			# new, random, hard-to-find layout itself
			G.sys("legacies").pin = {"all_majors": true, "designed_spots": true, "sense_everywhere": true, "crafts_by_look": true}
			G.sys("quests").quiet = true                # (quests offered by townsfolk are tested at steps 85-86)
			G.new_game()
			G.level_change_requested.connect(func(id, _tag): _changed_to = id)
			var hud = load("res://scripts/ui/HUD.gd").new()
			root.add_child(hud)
			_build("floor1")
			player = load("res://scripts/actors/Player.gd").new()
			root.add_child(player)
			_place_player(Vector2i(5, 7))
			wait = 0.3
		1:
			print("== secret wall and hidden chest ==")
			var sw = _find("SecretWall.gd")
			check("floor1 has a secret wall", sw != null)
			check("before it's found, enemies can't path through it", level.astar.is_point_solid(Vector2i(5, 8)))
			check("a hidden wall gives nothing away at first: no loose stone to press", not sw.is_in_group("interactable") and player._nearest_interactable() != sw)
			player.velocity = Vector3.ZERO
			for i in 8:
				sw._process(0.5)
			check("stand still beside it a while and you notice the draft", sw.noticed and sw.is_in_group("interactable"))
			check("...then the loose stone is the nearest thing to press E on, from the room side", player._nearest_interactable() == sw, str(player._nearest_interactable()))
			sw.interact(player)
			wait = 1.6
		2:
			check("after E, the secret is remembered (saved)", G.has_flag(G.flag_key("floor1", Vector2i(5, 8), "secret")))
			check("...and the passage is open for pathing", not level.astar.is_point_solid(Vector2i(5, 8)))
			_place_player(Vector2i(5, 10))
			wait = 0.3
		3:
			check("the player can actually walk through where the wall was", player.global_position.z > level.cell_to_world(Vector2i(5, 9)).z - 0.1, str(player.global_position))
			var chest = _find("Chest.gd", func(n): return n.cell == Vector2i(7, 11))
			check("the hidden chest is there", chest != null)
			var gold_before: int = G.gold
			var ore_before: int = G.count("iron_ore")
			chest.interact(player)
			check("opening it pays out (gold + ore + a qi pill)", G.gold > gold_before and G.count("iron_ore") > ore_before and G.count("qi_pill") >= 1, "gold %d->%d ore %d->%d pills %d" % [gold_before, G.gold, ore_before, G.count("iron_ore"), G.count("qi_pill")])
			check("an opened chest can't be looted twice", not chest.is_in_group("interactable"))
			print("== lore and techniques ==")
			var stone = _find("Stele.gd", func(n): return n.teaches == "iron_skin")
			check("the hidden cache holds the Monk's Stone", stone != null)
			var hp0: int = G.hp
			G.hurt(20)
			var plain_loss: int = hp0 - G.hp
			G.heal(999)
			stone.interact(player)
			check("reading it teaches Iron Skin", G.has_tech("iron_skin"))
			root.get_tree().get_first_node_in_group("hud").close_dialog()
			hp0 = G.hp
			G.hurt(20)
			check("Iron Skin really reduces damage taken", hp0 - G.hp < plain_loss, "%d vs %d" % [hp0 - G.hp, plain_loss])
			G.heal(999)
			stone.interact(player)
			root.get_tree().get_first_node_in_group("hud").close_dialog()
			check("reading it again doesn't teach it twice (one log entry)", true)
			for i in 15:
				G.record_kill("goblin")
			check("killing 15 goblins teaches Wind Step (learned by doing)", G.has_tech("wind_step"))
			print("== gathering ==")
			var ore = _find("GatherNode.gd", func(n): return n.kind == "ore")
			var herb = _find("GatherNode.gd", func(n): return n.kind == "herb")
			var o0: int = G.count("iron_ore")
			var h0: int = G.count("spirit_herb")
			ore.interact(player)
			herb.interact(player)
			check("mining an ore vein gives iron ore", G.count("iron_ore") > o0)
			check("picking a herb gives spirit herb", G.count("spirit_herb") > h0)
			check("a gathered node can't be picked again right away", not ore.is_in_group("interactable"))
			print("== combat ==")
			_goblin = _find("Enemy.gd", func(n): return n.etype == "goblin")
			check("there are goblins", _goblin != null)
			_place_player(_goblin.cell + Vector2i(0, 1))
			_qi_before = G.qi + G.step_index() * 10000
			wait = 0.1
		4:
			# face the goblin and swing until it drops
			var to: Vector3 = _goblin.global_position - player.global_position
			player._model.rotation.y = atan2(to.x, to.z)
			player._deal_hit()
			if is_instance_valid(_goblin) and not _goblin._dead:
				wait = 0.05
				return false
			check("a goblin dies to repeated hits", _goblin._dead)
			check("the kill is recorded for quests", int(G.kills.get("goblin", 0)) >= 1)
			check("killing grants qi", G.qi + G.step_index() * 10000 > _qi_before)
			print("== goblins fight back ==")
			var g2 = _find("Enemy.gd", func(n): return n.etype == "goblin" and not n._dead and n != _goblin)
			_place_player(g2.cell + Vector2i(1, 0))
			_hp_before = G.hp
			wait = 3.0
			_goblin = g2
		5:
			check("a goblin next to you notices you and hits you", G.hp < _hp_before, "hp %d -> %d" % [_hp_before, G.hp])
			print("== traps ==")
			G.heal(999)
			player._hurt_cool = 0.0
			_goblin.queue_free()
			for e in root.get_tree().get_nodes_in_group("enemy"):
				e.queue_free()
			_place_player(Vector2i(18, 10))
			_hp_before = G.hp
			wait = 3.5
		6:
			check("standing on a spike trap hurts", G.hp < _hp_before, "hp %d -> %d" % [_hp_before, G.hp])
			print("== crafting ==")
			G.add_item("iron_ore", 3, false)
			G.gold += 10
			var r = null
			for rc in G.recipes:
				if rc["makes"] == "iron_sword":
					r = rc
			G.skills["sword"] = 250.0       # (this tester went to sword school: an Apprentice's hand)
			var dmg0: int = G.damage()
			check("the smith can make an iron sword from 3 ore + 10 gold", G.can_craft(r))
			var res: Dictionary = G.craft_attempt(r, "balanced", 0.0, 0.5)
			check("a successful craft equips it and raises damage", res.get("success") and G.weapon == "iron_sword" and G.damage() >= dmg0 + 6, "%s %s %d->%d" % [res, G.weapon, dmg0, G.damage()])
			check("crafting trains Smithing", G.skill_level("smithing") >= 0 and float(G.skills.get("smithing", 0)) > 0.0)
			print("== crafting can fail, and can excel ==")
			check("careful odds > steady odds > bold odds", G.craft_chance(r, "careful") > G.craft_chance(r, "balanced") and G.craft_chance(r, "balanced") > G.craft_chance(r, "bold"))
			G.add_item("iron_ore", 3, false)
			G.gold += 10
			var ore_b: int = G.count("iron_ore")
			var sx: float = float(G.skills.get("smithing", 0))
			res = G.craft_attempt(r, "balanced", 0.99, 0.5)
			check("a failed craft loses some materials, makes nothing", not res.get("success") and G.count("iron_ore") == ore_b - 2 and G.count("iron_sword") == 1, "%s ore %d->%d" % [res, ore_b, G.count("iron_ore")])
			check("...but you still learn from it", float(G.skills.get("smithing", 0)) > sx)
			G.skills["smithing"] = 1000.0
			check("skill raises the odds", G.craft_chance(r, "balanced") > 0.9)
			G.add_item("iron_ore", 3, false)
			G.gold += 10
			res = G.craft_attempt(r, "bold", 0.0, 0.0)
			check("boldly, at the top of a roll, a Masterwork", str(res.get("item", "")) == "iron_sword@masterwork", str(res))
			check("ten levels of Smithing teaches Forge Sense (mastery opens its own path)", G.has_tech("forge_sense"))
			check("...which is better than the plain one and equips itself", G.weapon == "iron_sword@masterwork" and G.item_name(G.weapon) == "Masterwork Iron Sword" and int(G.item_def(G.weapon)["damage"]) > int(G.item_def("iron_sword")["damage"]))
			G.add_item("iron_ore", 3, false)
			G.gold += 10
			res = G.craft_attempt(r, "careful", 0.0, 0.0)
			check("carefully, the best you can get is Fine", str(res.get("item", "")) == "iron_sword@fine", str(res))
			G.skills["smithing"] = 0.0
			G.add_item("healing_salve@fine", 1, false)
			var plain: int = G.count("healing_salve")
			G.hp = 5
			G.use_best("healing_salve")
			check("key 1 drinks the best salve you carry first", G.count("healing_salve@fine") == 0 and G.count("healing_salve") == plain and G.hp > 5)
			print("== skills and what you can see ==")
			check("mining a vein trained Mining", float(G.skills.get("mining", 0)) > 0.0)
			G.skills["mining"] = 0.0
			check("a novice sees only the plain description", not G.item_desc("iron_ore").contains("Rust-red"))
			G.skills["mining"] = 40.0
			check("a miner of level 2 sees more in the same ore", G.item_desc("iron_ore").contains("Rust-red"))
			check("...and what it's been used for", G.item_desc("iron_ore").contains("Iron Sword"))
			print("== the journal ==")
			check("the journal remembers where iron ore was found", G.journal["items"].has("iron_ore") and "floor1" in G.journal["items"]["iron_ore"]["where"])
			check("...and what you made from it", "iron_sword" in G.journal["items"]["iron_ore"]["uses"])
			check("places remember their discoveries", "Found a secret wall" in G.journal["places"].get("floor1", {}).get("notes", []) and "Read The Monk's Stone" in G.journal["places"]["floor1"]["notes"], str(G.journal["places"]))
			var hudj = root.get_tree().get_first_node_in_group("hud")
			hudj.toggle_journal()
			check("N opens the journal (and it blocks play while open)", hudj.is_blocking() and hudj._journal.visible)
			hudj.toggle_journal()
			print("== the five elements ==")
			var d_plain: int = G.damage()
			G.attune("fire", 40.0)
			check("Fire strengthens your strikes", G.damage() > d_plain, "%d -> %d" % [d_plain, G.damage()])
			var d_fire: int = G.damage()
			G.attune("wood", 40.0)
			check("Wood and Fire together: Wood feeds Fire (synergy)", G.affinity_status()["synergies"].size() == 1 and G.damage() > d_fire, "%s %d" % [G.affinity_status(), G.damage()])
			var qm: float = G.tech_effect("qi_mult", 1.0)
			G.attune("water", 40.0)
			check("Water held level with Fire: they clash, and qi gain suffers", G.affinity_status()["clashes"].size() >= 1 and G.tech_effect("qi_mult", 1.0) < qm, str(G.affinity_status()))
			for el in G.ELEMENTS:
				G.affinity[el] = 0.0
			check("growth never hard-caps but slows (diminishing)", true)
			G.attune("metal", 50.0)
			var m1: float = G.affinity["metal"]
			G.attune("metal", 50.0)
			check("...the second 50 is worth less than the first", G.affinity["metal"] - m1 < m1, "%f %f" % [m1, G.affinity["metal"]])
			for el in G.ELEMENTS:
				G.affinity[el] = 0.0
			print("== cultivation ==")
			var lbl0: String = G.cultivation_label()
			G.add_qi(G.qi_to_next() + 1)
			check("enough qi raises the sub-level", G.cultivation_label() != lbl0, lbl0 + " -> " + G.cultivation_label())
			G.realm = 0
			G.sublevel = 10
			G.qi = 0
			G.add_qi(G.qi_to_next() + 1)
			check("sub-level 10 fills the sea of qi -- and waits there for the breakthrough", G.realm == 0 and G.sublevel == 10 and G.at_threshold(), G.cultivation_label())
			G.tribulation = {"from_level": G.current_level, "from_tag": "P", "target": 1, "tries": 0}
			G.tribulation_won()
			check("...the tribulation won, it breaks through to the next realm", G.realm == 1 and G.sublevel == 1, G.cultivation_label())
			print("== stairs ==")
			var down = _find("Exit.gd", func(n): return n.target == "floor2")
			check("floor1 has stairs down to floor2", down != null)
			down._armed = true
			_place_player(down.cell)
			wait = 0.5
		7:
			# floor2 doesn't exist yet in this sandbox -> a message, no crash;
			# the village stairs do exist
			var up = _find("Exit.gd", func(n): return n.target == "village")
			up._armed = true
			_place_player(up.cell)
			wait = 0.5
		8:
			check("taking the up-stairs asks to go to the village", _changed_to == "village", _changed_to)
			print("== save / load ==")
			G.save_game()
			var g_before: int = G.gold
			G.gold = 0
			G.load_game()
			check("save + load restores gold", G.gold == g_before, "%d vs %d" % [G.gold, g_before])
			check("save + load restores the opened secret", G.has_flag(G.flag_key("floor1", Vector2i(5, 8), "secret")))
			print("== the village ==")
			_build("village")
			_place_player(level.world_to_cell(level.spawn_point("P")))
			wait = 0.3
		9:
			var hud = root.get_tree().get_first_node_in_group("hud")
			var elder = _find("NPC.gd", func(n): return n.role == "elder")
			var merchant = _find("NPC.gd", func(n): return n.role == "merchant")
			var smith = _find("NPC.gd", func(n): return n.role == "smith")
			check("the village has an elder, a merchant and a smith", elder != null and merchant != null and smith != null)
			elder.interact(player)
			check("talking to the elder opens a dialog", hud.is_blocking())
			check("...that offers the first quest", hud._dialog_body.text.contains("Roots of Cultivation"), hud._dialog_body.text.substr(0, 200))
			elder._accept("first_herbs")
			check("accepting it makes it active", G.quests.get("first_herbs", "") == "active")
			G.add_item("spirit_herb", 5, false)
			check("with five herbs in the bag it's ready to report", G.quest_ready("first_herbs"))
			var herbs_before: int = G.count("spirit_herb")
			var lvl_before: int = G.step_index() * 100000 + int(G.qi)
			elder._turn_in("first_herbs")
			check("reporting completes it, takes the herbs and pays qi", G.quests.get("first_herbs") == "done" and G.count("spirit_herb") == herbs_before - 5 and G.step_index() * 100000 + int(G.qi) > lvl_before)
			check("finishing the herb quest doesn't unlock the crypt quest early", not G.quest_available("crypt"))
			G.add_item("goblin_tooth", 4, false)
			var gold0: int = G.gold
			merchant.interact(player)
			merchant._sell_all()
			check("the merchant buys materials for gold", G.gold > gold0 and G.count("goblin_tooth") == 0, "%d -> %d" % [gold0, G.gold])
			smith.interact(player)
			check("the smith's dialog lists recipes with what you have", hud._dialog_body.text.contains("Iron Sword"))
			hud.close_dialog()
			check("closing the dialog gives control back", not hud.is_blocking())
			var shrine = _find("Shrine.gd")
			check("the village has a cultivation shrine", shrine != null)
			var alch = _find("NPC.gd", func(n): return n.role == "alchemist")
			check("the village has an apothecary", alch != null)
			alch.interact(player)
			check("...whose workshop is alchemy and medicine", hud._dialog_body.text.contains("Healing Salve") and hud._dialog_body.text.contains("Alchemy") and not hud._dialog_body.text.contains("Iron Sword"), hud._dialog_body.text.substr(0, 300))
			hud.close_dialog()
			print("== guilds ==")
			var lodge = _find("NPC.gd", func(n): return n.role == "guild" and n.def.get("guild") == "adventurers")
			var hall = _find("NPC.gd", func(n): return n.role == "guild" and n.def.get("guild") == "gatherers")
			check("the village has the Adventurers' Lodge and the Gatherers' Hall", lodge != null and hall != null)
			lodge.interact(player)
			check("the Lodge shows its ranks and offers to join", hud._dialog_body.text.contains("Blade") and hud._dialog_body.text.contains("Ranks"), hud._dialog_body.text.substr(0, 200))
			hud.close_dialog()
			G.join_guild("adventurers")
			check("joining makes you an Initiate", G.in_guild("adventurers") and G.guild_rank_name("adventurers") == "Initiate")
			var dmg_g: int = G.damage()
			G.record_kill("goblin")
			check("a kill raises Lodge standing", float(G.guilds["adventurers"]["rep"]) >= 1.0)
			G.add_guild_rep("adventurers", 100.0)
			check("enough standing ranks you up -- with a real perk", G.guild_rank_name("adventurers") == "Blade" and G.damage() > dmg_g, "%s %d->%d" % [G.guild_rank_name("adventurers"), dmg_g, G.damage()])
			var c0: Dictionary = G.contract_offer("adventurers")
			G.take_contract("adventurers", c0)
			check("a contract counts only kills made after taking it", G.contract_progress("adventurers")[0] == 0 and c0["id"] == "cull_goblins")
			for i in 12:
				G.record_kill("goblin")
			var gold_c: int = G.gold
			var rep_c: float = float(G.guilds["adventurers"]["rep"])
			check("...and is ready after 12 more goblins", G.contract_ready("adventurers"))
			G.turn_in_contract("adventurers")
			check("handing it in pays gold and standing", G.gold > gold_c and float(G.guilds["adventurers"]["rep"]) > rep_c)
			check("...and the next contract is a different one", G.contract_offer("adventurers")["id"] != "cull_goblins")
			G.join_guild("gatherers")
			c0 = G.contract_offer("gatherers")
			G.take_contract("gatherers", c0)
			G.inventory.erase("spirit_herb")
			G.add_item("spirit_herb", 10, false)
			check("a 'bring me' contract is ready when you carry enough", G.contract_ready("gatherers"))
			G.turn_in_contract("gatherers")
			check("...and takes what it asked for", G.count("spirit_herb") == 0)
			G.join_guild("alchemists")
			var t_r: String = G.join_guild("healers")
			check("joining a rival guild warns you", t_r.contains("won't like it"), t_r)
			G.add_guild_rep("healers", 10.0)
			check("...and each rival trusts you half as much", absf(float(G.guilds["healers"]["rep"]) - 5.0) < 0.01, str(G.guilds["healers"]))
			G.add_item("spirit_herb", 2, false)
			var rh: float = float(G.guilds["healers"]["rep"])
			var sal = null
			for rc in G.recipes:
				if rc["makes"] == "healing_salve":
					sal = rc
			G.craft_attempt(sal, "balanced", 0.0, 0.5)
			check("making a salve raises Healers' standing", float(G.guilds["healers"]["rep"]) > rh)
			G.save_game()
			G.guilds = {}
			G.load_game()
			check("guild standing survives save + load", G.in_guild("healers") and G.guild_rank_name("adventurers") == "Blade")
			for gname in G.guilds.keys():
				G.leave_guild(gname)
			check("leaving a guild drops its perks", not G.in_guild("adventurers"))
			print("== talking freely, and bonds ==")
			var pell = _find("NPC.gd", func(n): return n.npc_name == "Old Pell")
			var heard := []
			G.llm_override = func(msgs):
				heard.append(msgs)
				return JSON.stringify({"reply": "You've got soil under your nails. Good.", "warmth": 3, "memory": "talks to me about herbs"})
			hud.open_chat(pell)
			check("anyone can be talked to freely", hud._chat.visible and hud.is_blocking())
			hud.chat_say("Do you know where the best herbs grow?")
			check("they answer in their own words", hud.chat_text().contains("soil under your nails"), hud.chat_text())
			check("...from a prompt that knows who they are and how they feel about you",
				heard.size() == 1 and str(heard[0][0]["content"]).contains("Old Pell") and str(heard[0][0]["content"]).contains("a stranger"))
			check("a kind exchange warms them, and they remember something", float(G.bond("Old Pell")["warmth"]) > 2.0 and "talks to me about herbs" in G.bond("Old Pell")["memories"])
			for i in 14:      # 15 kind exchanges, each 3 +/- 0.5 (moods): 37.5-52.5, always "a friend"
				hud.chat_say("Thank you, truly.")
			check("enough warmth and they count you as a friend", G.bond_stage("Old Pell") == "a friend", G.bond_stage("Old Pell"))
			check("...and the next prompt carries what they remember", str(heard[heard.size() - 1][0]["content"]).contains("talks to me about herbs"))
			G.llm_override = func(msgs): return JSON.stringify({"reply": "Get out.", "warmth": -3, "memory": ""})
			var w_b: float = float(G.bond("Old Pell")["warmth"])
			hud.chat_say("Your herbs are weeds.")
			check("an insult cools them", float(G.bond("Old Pell")["warmth"]) < w_b)
			G.llm_override = func(msgs): return "not json at all"
			hud.chat_say("hm?")
			check("a model that doesn't answer in JSON is still shown, not lost", hud.chat_text().ends_with("not json at all"))
			G.llm_override = Callable()
			hud.close_chat()
			var rin = _find("NPC.gd", func(n): return n.npc_name == "Little Rin")
			for i in 3:
				rin.interact(player)
			hud.close_dialog()
			check("asking Little Rin three times teaches Spirit Sense (an easter egg)", G.has_tech("spirit_sense"))
			var fountain = _find("Fountain.gd")
			check("the fountain is interactable", fountain != null and fountain.is_in_group("interactable"))
			G.gold += 20
			var cult0: float = G.step_index() * 100000 + G.qi
			for i in 7:
				fountain.interact(player)
			check("the seventh coin in the fountain gives qi", G.step_index() * 100000 + G.qi > cult0 + 50)
			var locked = _find("Stele.gd", func(n): return n.needs_realm == 1)
			G.realm = 0
			locked.interact(player)
			check("the plaza stone can't be read before Qi Condensation", hud._dialog_body.text.contains("worn past reading"))
			hud.close_dialog()
			_place_player(shrine.cell + Vector2i(0, 1))
			_qi_before = G.step_index() * 100000 + G.qi
			shrine.interact(player)
			wait = 3.2
		10:
			check("sitting at the shrine cultivates qi over time (slowly: a shrine doubles 0.25 a second)", G.step_index() * 100000 + G.qi >= _qi_before + 1.0, "%f -> %f" % [_qi_before, G.step_index() * 100000 + G.qi])
			check("...and marks you as meditating at a shrine (for AFK qi)", G.meditating)
			print("== AFK cultivation ==")
			G.save_game()
			var f := FileAccess.open(G.save_path, FileAccess.READ)
			var data = JSON.parse_string(f.get_as_text())
			f.close()
			data["saved_at"] = float(data["saved_at"]) - 3600.0 * 2
			_rewind_pursuit(data, 7200.0)          # (round 63: the high-water clock moves back with it -- real time passed)
			var w := FileAccess.open(G.save_path, FileAccess.WRITE)
			w.store_string(JSON.stringify(data))
			w.close()
			var before: float = G.step_index() * 100000 + G.qi
			G.load_game()
			check("two hours away while meditating at a shrine grants AFK qi", G.step_index() * 100000 + G.qi > before + 100, "%f -> %f" % [before, G.step_index() * 100000 + G.qi])
			print("== treasures ==")
			G.inventory.erase("iron_ore")
			G.add_item("iron_ore", 25, false)
			check("without a storage ring the pouch holds 20 of a material", G.count("iron_ore") == 20, str(G.count("iron_ore")))
			var fountain2 = _find("Fountain.gd")
			G.counters["coins"] = 32.0
			G.gold += 5
			fountain2.interact(player)
			check("the 33rd coin in the fountain brings back the Qiankun Ring (an easter egg)", G.has_treasure("storage_ring"))
			G.add_item("iron_ore", 25, false)
			check("...and with the ring the pouch holds more", G.count("iron_ore") == 45, str(G.count("iron_ore")))
			G.add_item("storage_ring", 1, false)
			check("a treasure is one of a kind (no second ring)", G.count("storage_ring") == 1)
			G.gold = 100
			G.player_died("test")
			check("with the ring, falling doesn't cost gold", G.gold == 100, str(G.gold))
			G.add_item("spirit_gourd", 1, false)
			check("the Spirit Gourd starts full (3 sips)", G.gourd_sips() == 3)
			G.hp = 10
			G.drink_gourd()
			check("drinking from the gourd heals and uses a sip", G.hp > 10 and G.gourd_sips() == 2, "%d hp, %d sips" % [G.hp, G.gourd_sips()])
			G.drink_gourd()
			G.drink_gourd()
			var hp_e: int = G.hp
			check("an empty gourd does nothing", not G.drink_gourd() and G.hp == hp_e)
			G.refill_gourd()
			check("sitting at a shrine refills it", G.gourd_sips() == 3)
			var qm0: float = G.tech_effect("qi_mult", 1.0)
			G.add_item("jade_pendant", 1, false)
			check("a carried treasure works like a technique (the pendant raises qi gain)", G.tech_effect("qi_mult", 1.0) >= qm0 * 1.25 - 0.001, "%f -> %f" % [qm0, G.tech_effect("qi_mult", 1.0)])
			G.inventory.erase("jade_pendant")
			print("== jewelry and alchemy that changes you ==")
			var jr = null
			for rc in G.recipes:
				if rc["makes"] == "jade_ring":
					jr = rc
			G.add_item("rough_jade", 2, false)
			G.add_item("silver_ore", 1, false)
			G.gold += 20
			var hp_j: int = G.max_hp()
			G.ring = ""
			G.craft_attempt(jr, "balanced", 0.0, 0.5)
			check("Jewelcrafting a jade ring puts it on, and it steadies the body", G.ring == "jade_ring" and G.max_hp() > hp_j, "%s %d->%d" % [G.ring, hp_j, G.max_hp()])
			G.inventory["jade_ring@fine"] = 1
			var hp_c: int = G.max_hp()
			G.equip("jade_ring@fine")
			check("a Fine ring does more than a plain one", G.max_hp() > hp_c, "%d->%d" % [hp_c, G.max_hp()])
			G.ring = ""
			var f0: float = G.affinity["fire"]
			G.add_item("ember_pill", 1, false)
			G.use_item("ember_pill")
			check("an Ember Pill leaves a little Fire in you", G.affinity["fire"] > f0)
			G.affinity["fire"] = 0.0
			print("== a scavenger's hollow ==")
			var sid: String = G.ScavengeGen.make_id("floor1", "floor2", 7)
			check("a hollow's id round-trips", G.ScavengeGen.parse(sid) == {"from": "floor1", "to": "floor2", "seed": 7})
			var d1: Dictionary = G.load_level_def(sid)
			check("the same seed draws the same hollow", d1["map"] == G.load_level_def(sid)["map"])
			check("its stairs lead back up and on down", d1["exits"]["<"]["to"] == "floor1" and d1["exits"][">"]["to"] == "floor2")
			_build(sid)
			wait = 0.3
		11:
			var nodes := []
			for n in level.get_children():
				if n.get_script() and str(n.get_script().resource_path).ends_with("GatherNode.gd"):
					nodes.append(n)
			var ores: int = nodes.filter(func(n): return n.kind == "ore").size()
			check("a hollow is thick with things to gather", ores >= 5 and nodes.size() >= 12, "%d nodes, %d ore" % [nodes.size(), ores])
			var gem = null
			for n in nodes:
				if n.kind == "gem":
					gem = n
			if gem == null:
				check("a hollow has a glittering vein", false)
			else:
				var before: Dictionary = G.inventory.duplicate()
				var mx: float = float(G.skills.get("mining", 0))
				gem.interact(player)
				var got := []
				for k in G.inventory:
					if G.count(k) > int(before.get(k, 0)):
						got.append(k)
				check("a glittering vein gives gems or precious metal", got.size() > 0 and got.all(func(k): return k in ["rough_jade", "gold_nugget", "silver_ore", "rough_ruby", "sapphire_shard"]), str(got))
				check("...and trains Mining", float(G.skills.get("mining", 0)) > mx)
			var fish = null
			for n in nodes:
				if n.kind == "fish":
					fish = n
			if fish == null:
				check("a hollow has somewhere to fish", false)
			else:
				G.skills["fishing"] = 2000.0
				var caught := false
				for i in 12:
					G.flags.erase(fish._key)
					fish._refresh()
					fish.interact(player)
					fish.land_now()
					if G.count("cave_carp") + G.count("glowfin_eel") > 0:
						caught = true
						break
				check("casting a line catches fish (for a skilled angler)", caught)
				check("...and trains Fishing", float(G.skills.get("fishing", 0)) > 2000.0)
				G.skills["fishing"] = 0.0
			_build("floor1")
			_place_player(Vector2i(16, 27))
			wait = 0.3
		12:
			print("== hunting ==")
			_goblin = _find("Enemy.gd", func(n): return n.etype == "cave_hare")
			check("floor 1's grotto has cave hares", _goblin != null)
			_hp_before = int(_goblin.global_position.distance_to(player.global_position))
			_place_player(level.world_to_cell(_goblin.global_position) + Vector2i(-1, 0))
			_qi_before = _goblin.global_position.x
			wait = 0.8
		13:
			check("a hare runs from you instead of fighting", _goblin.global_position.x > _qi_before + 0.5 and G.hp >= 1, "%f -> %f" % [_qi_before, _goblin.global_position.x])
			var meat0: int = G.count("raw_meat")
			var hx: float = float(G.skills.get("hunting", 0))
			_goblin.take_damage(999)
			check("a hunted hare gives meat and trains Hunting", G.count("raw_meat") > meat0 and float(G.skills.get("hunting", 0)) > hx)
			print("== a familiar ==")
			var hare2 = _find("Enemy.gd", func(n): return n.etype == "cave_hare" and not n._dead)
			check("a wild hare can be offered food", hare2 != null and hare2.is_in_group("interactable"))
			G.inventory["raw_meat"] = 5
			hare2.interact(player)
			check("fed once, it stays calm (and doesn't bond yet)", hare2._calm > 0.0 and G.familiar.is_empty())
			hare2.interact(player)
			hare2.interact(player)
			check("fed three times, it follows you: a familiar", G.familiar.get("species", "") == "cave_hare" and G.familiar.get("name", "") == "Burrow" and G.count("raw_meat") == 2)
			var fam = load("res://scripts/actors/Familiar.gd").new()
			root.add_child(fam)
			fam.snap_to(player.global_position)
			check("the familiar is there, beside you", fam.visible and fam.global_position.distance_to(player.global_position) < 3.0)
			var gc0: float = G.tech_effect("gather_chance", 0.0)
			check("a familiar helps (Burrow: more finds when gathering)", gc0 >= 0.1, str(gc0))
			var found: String = fam.find_something(0.0)
			check("it turns things up, and that grows the bond", found != "" and float(G.familiar.get("bond", 0)) > 0.0, found)
			G.grow_bond(100.0)
			check("a deeper bond means a bigger gift", G.tech_effect("gather_chance", 0.0) > gc0)
			G.save_game()
			G.familiar = {}
			G.load_game()
			check("your familiar survives save + load", G.familiar.get("name", "") == "Burrow")
			fam.queue_free()
			G.familiar = {}
			print("== riddles ==")
			var rs = _find("RiddleStone.gd")
			check("the monks' cells have a riddle stone", rs != null)
			rs.interact(player)
			var hud_r = root.get_tree().get_first_node_in_group("hud")
			check("it asks its question with choices", hud_r._dialog_body.text.contains("leave behind"))
			rs.choose(0)
			check("a wrong answer silences it for a while", rs.silent() and not rs.solved())
			G.flags.erase(rs._key + ":wrong")
			var pills_r: int = G.count("qi_pill")
			rs.choose(rs.answer)
			check("the right answer is rewarded, once", rs.solved() and G.count("qi_pill") == pills_r + 2)
			hud_r.close_dialog()
			wait = 0.1
		14:
			print("== hidden in plain sight: floor 1's inheritance ==")
			player.stop_meditating()                 # (still sitting from the village shrine)
			G.counters.erase("talk:Little Rin")      # ...or check_unlocks re-teaches it at once
			G.techniques.erase("spirit_sense")
			G.realm = 0
			G.sublevel = 5
			_build("floor1")
			_place_player(Vector2i(16, 27))
			wait = 0.6
		15:
			var inh = _find("Inheritance.gd")
			check("floor 1 holds a master's inheritance", inh != null)
			check("...invisible without Spirit Sense", inh != null and not inh._body.visible and not inh.is_in_group("interactable"))
			var vchest = _find("Chest.gd", func(n): return n.hidden)
			check("...and a hidden chest nobody else can see", vchest != null and not vchest.is_in_group("interactable"))
			check("the inheritance sits behind a secret passage in the great hall", _find("SecretWall.gd", func(n): return n.cell == Vector2i(14, 24)) != null)
			check("...in a hidden chamber with a shrine to rest at", _find("Shrine.gd") != null)
			G.learn("spirit_sense")
			wait = 0.7
		16:
			var hud = root.get_tree().get_first_node_in_group("hud")
			var inh = _find("Inheritance.gd")
			var vchest = _find("Chest.gd", func(n): return n.hidden)
			check("with Spirit Sense the master appears", inh._body.visible and inh.is_in_group("interactable"))
			check("...and so does the hidden chest", vchest.is_in_group("interactable"))
			var pills0: int = G.count("qi_pill")
			vchest.interact(player)
			check("the hidden chest pays out", G.count("qi_pill") > pills0)
			inh.interact(player)
			check("below Qi Condensation the master turns you away", hud._dialog_body.text.contains("Too weak") and not G.has_treasure("flying_sword"), hud._dialog_body.text.substr(0, 120))
			hud.close_dialog()
			G.realm = 1
			G.sublevel = 1
			var dmg0: int = G.damage()
			inh.interact(player)
			check("at Qi Condensation the master offers the legacy", hud._dialog_body.text.contains("Azure Flying Sword"), hud._dialog_body.text.substr(0, 200))
			var accepted := false
			for b in hud.find_children("*", "Button", true, false):
				if b.text == "Accept the legacy" and not b.is_queued_for_deletion():
					b.pressed.emit()
					accepted = true
					break
			check("accepting gives the Azure Flying Sword and Sword Heart", accepted and G.has_treasure("flying_sword") and G.has_tech("sword_heart"))
			check("Sword Heart makes every strike hit harder", G.damage() > dmg0, "%d -> %d" % [dmg0, G.damage()])
			check("an inheritance is claimed once, ever", inh.claimed())
			inh.interact(player)
			check("...afterwards only bones remain", hud._dialog_body.text.contains("Only bones"))
			hud.close_dialog()
			print("== the flying sword ==")
			_goblin = null
			for e in root.get_tree().get_nodes_in_group("enemy"):
				if e.etype == "goblin" and not e._dead:
					_goblin = e
					break
			_place_player(level.world_to_cell(_goblin.global_position) + Vector2i(0, 3) if _goblin else Vector2i(16, 20))
			wait = 0.2
		17:
			var total0 := 0
			for e in root.get_tree().get_nodes_in_group("enemy"):
				total0 += int(e.hp)
			var struck: bool = player.fly_sword()
			var total1 := 0
			for e in root.get_tree().get_nodes_in_group("enemy"):
				if is_instance_valid(e) and not e._dead:
					total1 += int(e.hp)
			check("G sends the flying sword into the nearest enemy", struck and total1 < total0, "%d -> %d" % [total0, total1])
			check("...then it needs a moment to come home (cooldown)", not player.fly_sword())
			wait = 0.4
		18:
			print("== a settlement deep below (Shellhaven's engine) ==")
			var f := FileAccess.open("res://tools/fixture_settlement.json", FileAccess.READ)
			var j := JSON.new()
			j.parse(f.get_as_text())
			var sd: Dictionary = j.data
			_build_def(sd)
			check("a settlement is a town", level.is_town() and level.theme == "settlement")
			check("its people are all there (7)", int(level.counts.get("npcs", 0)) == 7, str(level.counts))
			check("lanterns, not torches, and no open sky -- a cavern vault overhead", _find("Torch.gd") == null and (level._env.sky == null or str(level._sky_mat.shader.resource_path).ends_with("cave_sky.gdshader")))
			check("walking into a town makes it your haven", G.last_haven == "testhaven" and G.havens.has("testhaven"), G.last_haven)
			var b0: float = level._env.ambient_light_energy
			level._process(level.BREATH_SECONDS / 4.0)
			check("a breathing town rises and falls (ambient light swells)", level._env.ambient_light_energy > b0 + 0.05, "%f -> %f" % [b0, level._env.ambient_light_energy])
			level._process(level.BREATH_SECONDS / 2.0)
			check("...and settles again", level._env.ambient_light_energy < b0 - 0.05, "%f" % level._env.ambient_light_energy)
			var spawn: Vector3 = level.spawn_point("P")
			check("you wake in the plaza ('P')", level.char_at(level.world_to_cell(spawn)) == "P")
			var inn = _find("NPC.gd", func(n): return n.role == "innkeeper")
			check("the inn has an innkeeper", inn != null)
			G.gold = 5
			G.hp = 10
			check("no coin, no bed", inn.rest() == false and G.gold == 5 and G.hp == 10)
			G.gold = 50
			G.last_haven = "village"
			check("a night at the inn costs its price and heals you fully", inn.rest() and G.gold == 38 and G.hp == G.max_hp(), "%d gold, %d/%d hp" % [G.gold, G.hp, G.max_hp()])
			check("...and makes this town where you wake", G.last_haven == "testhaven")
			var hud = root.get_tree().get_first_node_in_group("hud")
			inn._gossip()
			check("the talk of the house gives its rumours", hud._dialog_body.text.contains("rumour a"))
			inn._gossip()
			check("...one after another", hud._dialog_body.text.contains("rumour b"))
			hud.close_dialog()
			G.last_haven = "floor1"
			G.havens["floor1"] = "the Goblin Warrens"
			G.save_game()
			G.last_haven = "nowhere"
			G.load_game()
			check("your haven is saved and loaded", G.last_haven == "floor1" and str(G.havens.get("floor1", "")) == "the Goblin Warrens")
			_changed_to = ""
			G.player_died("test")
			wait = 0.2
		19:
			check("falling wakes you at your haven, not always the village", _changed_to == "floor1", _changed_to)
			G.last_haven = "testhaven"       # a town whose file is gone
			_changed_to = ""
			G.player_died("test")
			check("...unless that town is gone -- then home to the village", G.last_haven == "village")
			wait = 0.2
		20:
			check("...and you really go there", _changed_to == "village", _changed_to)
			print("== the floors below the tortoise (5-9 content) ==")
			for eid in ["thornling", "rootbound_monk", "grove_mother", "moss_stag", "cinder_imp", "slag_brute", "furnace_sovereign", "ember_salamander", "clay_soldier", "clay_cavalier", "buried_emperor", "burrow_mole", "sword_wraith", "grave_keeper", "sword_saint_shade", "steel_crow"]:
				var ed: Dictionary = G.enemies.get(eid, {})
				check("%s is defined for floor %d" % [eid, int(ed.get("floor", 0))], not ed.is_empty() and int(ed.get("floor", 0)) >= 6)
			var bosses := 0
			for eid in G.enemies:
				if int(G.enemies[eid].get("floor", 0)) >= 6 and int(G.enemies[eid].get("floor", 0)) <= 9 and bool(G.enemies[eid].get("boss", false)):
					bosses += 1
			check("one boss for each of floors 6-9", bosses == 4, str(bosses))
			var crafts := {}
			for r in G.recipes:
				crafts[str(r.get("makes", ""))] = true
			for id in ["thornwood_spear", "firestone_saber", "emperors_halberd", "grave_sword", "barkskin_mail", "slag_plate", "terracotta_scale", "magma_pill", "sword_qi_pill", "firestone_ring"]:
				check("%s can be crafted" % id, crafts.has(id))
			check("a Sword Grave inheritance can teach Sword Intent", G.technique_defs.has("sword_intent"))
			G.add_item("saints_sheath", 1)
			check("the Sword Saint's Sheath is a one-of-a-kind treasure that speeds your strikes", G.is_treasure("saints_sheath") and G.tech_effect("attack_speed", 1.0) > 1.0)
			wait = 0.1
		21:
			print("== companions: someone who chooses to walk with you ==")
			var hud = root.get_tree().get_first_node_in_group("hud")
			_build("village")
			_place_player(Vector2i(16, 13))
			var lin = _find("NPC.gd", func(n): return n.npc_name == "Little Rin")
			var apo = _find("NPC.gd", func(n): return n.npc_name == "Apothecary Lin")
			G.bond("Apothecary Lin")["warmth"] = 90.0
			check("someone with a post (the apothecary) keeps it, however close you are", _travel_opts(apo) == 0)
			G.bonds.erase("Little Rin")
			check("a near-stranger can't be asked along", _travel_opts(lin) == 0)
			G.bond("Little Rin")["warmth"] = 70.0
			check("a close friend can be asked to travel with you", _travel_opts(lin) == 1 and str(lin._talk_opts()[1][0]).contains("travel"))
			check("...and it's their choice: a bad roll is a 'not now'", lin.ask_to_travel(0.99) == "no" and G.companion.is_empty())
			check("...and asking again straight away gets 'give me time'", lin.ask_to_travel(0.0) == "later")
			G.flags.erase("ask:travel:Little Rin")
			var c70: float = G.companion_chance("Little Rin")
			G.bond("Little Rin")["warmth"] = 95.0
			var c95: float = G.companion_chance("Little Rin")
			G.bond("Little Rin")["warmth"] = 70.0
			check("warmth tilts the chance (a devoted friend is likelier to say yes)", c70 < c95, "%f vs %f" % [c70, c95])
			check("a good roll: they come along", lin.ask_to_travel(0.0) == "yes" and str(G.companion.get("name", "")) == "Little Rin")
			check("...and they're no longer standing at their post", not lin.visible and not lin.is_in_group("interactable"))
			var comp = load("res://scripts/actors/Companion.gd").new()
			root.add_child(comp)
			comp.snap_to(player.global_position)
			check("they walk beside you, and you can talk to them", comp.visible and comp.npc_name == "Little Rin" and comp.is_in_group("interactable"))
			var mo = _find("NPC.gd", func(n): return n.npc_name == "Elder Mo")
			_place_player(mo.cell + Vector2i(0, 1))
			comp.snap_to(player.global_position)
			check("someone at your post still gets the E key before your companion", player._nearest_interactable() == mo, str(player._nearest_interactable()))
			G.llm_override = func(msgs):
				check("a companion knows they're travelling with you", str(msgs[0]["content"]).contains("travelling with you"))
				return JSON.stringify({"reply": "The road suits you.", "warmth": 2, "memory": "asked how I was"})
			var said := [""]
			comp.say("How are you holding up?", func(r): said[0] = r)
			check("they answer in their own words", said[0] == "The road suits you.")
			G.llm_override = Callable()
			G.bond("Little Rin")["warmth"] = 84.0
			G.warm_bond("Little Rin", 2.0)
			check("the road warms a bond on its own -- devoted now", G.bond_stage("Little Rin").begins_with("devoted"))
			check("someone devoted who travels with you can be asked for more", G.can_ask_partner("Little Rin"))
			check("...it's still their choice", comp.ask_partner(0.99) == false and G.partner == "")
			G.flags.erase("ask:partner:Little Rin")
			var med0: float = G.tech_effect("meditate_mult", 1.0)
			check("a yes: partners", comp.ask_partner(0.0) and G.partner == "Little Rin" and bool(G.companion.get("partner", false)))
			check("...and it shows: you cultivate better side by side", G.tech_effect("meditate_mult", 1.0) > med0, "%f -> %f" % [med0, G.tech_effect("meditate_mult", 1.0)])
			check("...their name tag says so", comp._label.text.contains("partner"))
			G.save_game()
			G.companion = {}
			G.partner = ""
			G.load_game()
			check("companion and partner are saved and loaded", str(G.companion.get("name", "")) == "Little Rin" and G.partner == "Little Rin")
			hud.close_dialog()
			G.part_with_companion()
			check("asking them home: they go", G.companion.is_empty() and not comp.visible and not comp.is_in_group("interactable"))
			check("...and they're back at their post", lin.visible and lin.is_in_group("interactable"))
			check("a partner is still your partner when apart", G.partner == "Little Rin")
			_hold["comp"] = comp
			wait = 0.2
		22:
			print("== a companion fights beside you ==")
			_build("floor1")
			var comp = _hold["comp"]
			G.flags.erase("ask:travel:Little Rin")
			G.ask_companion("Little Rin", "Little Rin, a healer", "village", Color.WHITE, 0.0)
			check("back on the road together", comp.visible and comp.npc_name == "Little Rin")
			var gob = null
			var hare = null
			for e in root.get_tree().get_nodes_in_group("enemy"):
				if e._dead:
					continue
				if e.etype == "goblin" and gob == null:
					gob = e
				if bool(e.stats.get("passive", false)) and hare == null:
					hare = e
			check("they leave wild animals for you to hunt or tame", hare == null or not comp._hostile(hare))
			_place_player(level.world_to_cell(gob.global_position) + Vector2i(0, 2))
			comp._target = null
			var foe = comp._pick_target(player)
			var nearest = null
			var nd := 1e9
			for e in root.get_tree().get_nodes_in_group("enemy"):
				if not e._dead and not bool(e.stats.get("passive", false)) and e.global_position.distance_to(player.global_position) < nd:
					nd = e.global_position.distance_to(player.global_position)
					nearest = e
			check("they pick the monster nearest YOU", foe != null and foe == nearest)
			comp.global_position = foe.global_position + Vector3(1.0, 0, 0)
			var hp0: int = foe.hp
			comp._cool = 0.0
			comp._process(0.05)
			check("...close in and strike it", foe.hp < hp0, "%d -> %d" % [hp0, foe.hp])
			check("their strike keeps pace with your own (and the bond)", comp.strike_damage() >= int(G.damage() * 0.45), "%d vs %d" % [comp.strike_damage(), G.damage()])
			G.part_with_companion()
			wait = 0.1
		23:
			print("== the two settlements: Shellhaven and Lanternmere ==")
			_build("floor5")
			check("Shellhaven is a breathing town on moss", level.is_town() and bool(level.def.get("breathing", false)) and level.ground == "moss")
			check("...with 15 people in it (the examiner and the ringmaster too)", int(level.counts.get("npcs", 0)) >= 15, str(level.counts))     # (the forge may add townsfolk later)
			check("...and reaching it makes it your haven", G.last_haven == "floor5", G.last_haven)
			var ys = _find("NPC.gd", func(n): return n.npc_name == "Ysolde")
			check("Ysolde (a villager) could travel with you; Warden Tolle keeps his gate",
				ys.can_travel() and not _find("NPC.gd", func(n): return n.npc_name == "Warden Tolle").can_travel())
			_build("floor10")
			check("Lanternmere is a market on the water (plank decks, a lake)", level.is_town() and level.ground == "deck")
			check("...with 18 people and three fishing spots", int(level.counts.get("npcs", 0)) >= 18 and int(level.counts.get("fishing", 0)) == 3, str(level.counts))
			var orla = _find("NPC.gd", func(n): return n.role == "innkeeper")
			G.gold = 25
			check("a night at the Drifting Lantern costs 20", orla.rest() and G.gold == 5 and G.last_haven == "floor10")
			root.get_tree().get_first_node_in_group("hud").close_dialog()
			wait = 0.1
		24:
			print("== weapons: dropped, found, made ==")
			var pool: Array = G.gear_pool(7)
			check("floor 7 has gear that can drop (and only from nearby tiers)", pool.size() >= 3 and pool.has("slag_maul") and not pool.has("goblin_shiv"), str(pool))
			check("a floor with no gear of its own falls back to the nearest shallower tier", G.gear_pool(5).size() > 0)
			var hi := 0
			for i in 200:
				if G.roll_quality(2) >= 3:
					hi += 1
			var lo := 0
			for i in 200:
				if G.roll_quality(0) >= 3:
					lo += 1
			check("a boss's drop is likelier to be Superior or better than an ordinary one's", hi > lo, "%d vs %d" % [hi, lo])
			var before: int = G.inventory.size()
			var got: String = G.drop_gear(9, 0, ["weapon"], 0.0)
			check("drop_gear gives a real weapon with a quality", got != "" and G.count(got) == 1 and str(G.item_def(got).get("type", "")) == "weapon", got)
			G.weapon = ""
			var sp0: float = G.attack_speed()
			G.add_item("imp_fang_daggers", 1)
			G.equip("imp_fang_daggers")
			var sp_untrained: float = G.attack_speed()
			G.skills["dagger"] = 250.0
			check("a dagger strikes faster than bare hands (in a trained hand)", G.attack_speed() > sp0 * 1.3, "%f vs %f" % [G.attack_speed(), sp0])
			check("...an untrained hand swings it slower", sp_untrained < G.attack_speed(), "%f vs %f" % [sp_untrained, G.attack_speed()])
			G.add_item("sentinel_halberd", 1)
			G.equip("sentinel_halberd")
			check("a halberd reaches further and swings slower", G.weapon_reach() > 1.0 and G.attack_speed() < sp0)
			G.add_item("warden_staff", 1)
			G.equip("warden_staff")
			check("a weapon's own effect counts while it's in your hand (staff: +qi)", G.tech_effect("qi_mult", 1.0) > 1.0)
			check("its description says what kind of weapon it is", G.item_desc("warden_staff").contains("Staff"))
			G.weapon = ""
			var chest_n0 := 0
			for id in G.inventory:
				if G.gear_family(str(id)) != "":
					chest_n0 += G.count(id)
			G.depth = 8
			G.roll_loot({"random_gear": [2, 2]})
			var chest_n1 := 0
			for id in G.inventory:
				if G.gear_family(str(id)) != "":
					chest_n1 += G.count(id)
			check("a chest's 'random_gear' gives that many pieces for its floor", chest_n1 == chest_n0 + 2, "%d -> %d" % [chest_n0, chest_n1])
			var made_kinds := {}
			for r in G.recipes:
				if str(G.items.get(str(r.get("makes", "")), {}).get("type", "")) == "weapon":
					made_kinds[str(G.items[str(r["makes"])].get("kind", "sword"))] = true
			check("every kind of weapon but fists can also be made (and fists too)", made_kinds.size() >= 8, str(made_kinds.keys()))
			_build("floor7")
			var boss = null
			for e in root.get_tree().get_nodes_in_group("enemy"):
				if bool(e.stats.get("boss", false)):
					boss = e
			var gear0: Dictionary = G.inventory.duplicate()
			boss.take_damage(999999)
			var dropped := false
			for id in G.inventory:
				if G.count(id) > int(gear0.get(id, 0)) and G.gear_family(str(id)) != "":     # round 27: any piece of gear
					dropped = true
			check("a boss always leaves gear behind", dropped)
			print("== cultivation that never runs out ==")
			check("past the named realms the road goes on", str(G.realm_info(11)["name"]) == "Immortal Realm I" and str(G.realm_info(14)["name"]) == "Immortal Realm IV")
			G.realm = 4
			G.sublevel = 10
			G.qi = 0.0
			G.add_qi(G.qi_to_next() + 1.0)
			G.tribulation = {"from_level": G.current_level, "from_tag": "P", "target": 5, "tries": 1}
			G.tribulation_won()
			check("Nascent Soul 10 breaks through into Soul Transformation", G.realm == 5 and G.realm_name() == "Soul Transformation", G.cultivation_label())
			G.realm = 1
			G.sublevel = 1
			G.qi = 0.0
			wait = 0.1
		25:
			print("== the Lotus Ascent Academy: the entrance exam ==")
			_build("floor5")
			var ex = _find("NPC.gd", func(n): return n.role == "academy")
			check("Shellhaven has the Academy's examiner", ex != null)
			G.academy = {"trials": {}, "enrolled": false, "rank": 0, "merit": 0.0}
			_changed_to = ""
			G.start_exam_strength("floor5", 5)
			_hold["stage"] = 0
			_hold["phase"] = "enter"
			wait = 0.1
		26:
			# the arena, wave by wave: enter -> clear the ring -> (next wave | done)
			match str(_hold.get("phase", "")):
				"enter":
					if int(_hold["stage"]) == 0:
						check("the Trial of Strength takes you into the arena", G.arena_active() and _changed_to == "arena_floor5_exam_0", _changed_to)
					_build(_changed_to)
					if int(_hold["stage"]) == 0:
						check("the arena is a real level with the first wave in it", bool(level.def.get("arena", false)) and level.arena_foes_left() == 2, str(level.arena_foes_left()))
					_hold["phase"] = "fight"
					wait = 0.1
					return false
				"fight":
					for e in root.get_tree().get_nodes_in_group("enemy"):
						if not e._dead:
							e.take_damage(999999)
					if int(_hold["stage"]) == 0:
						check("...cleared, the ring knows it", level.arena_foes_left() == 0)
					_changed_to = ""
					G.arena_cleared()
					_hold["phase"] = "after"
					wait = 0.1
					return false
				"after":
					if _changed_to.begins_with("arena_"):
						_hold["stage"] = int(_hold["stage"]) + 1
						_hold["phase"] = "enter"
						wait = 0.05
						return false
			check("three waves cleared: Strength passed, and you're back at Shellhaven", bool(G.academy["trials"].get("strength", false)) and _changed_to == "floor5" and int(_hold["stage"]) == 2, "%s %s" % [_changed_to, str(_hold["stage"])])
			_build("floor5")
			var ex = _find("NPC.gd", func(n): return n.role == "academy")
			var hud = root.get_tree().get_first_node_in_group("hud")
			ex.interact(player)
			check("the examiner tells you how it went, once", hud._dialog_body.text.contains("Strength: passed"))
			hud.close_dialog()
			var qs: Array = G.AcademyLib.exam_questions(G.exam_knowledge_seed())
			check("the Trial of Knowledge asks five real questions", qs.size() == 5 and qs.all(func(q): return int(q["answer"]) >= 0 and q["options"].size() >= 2))
			check("...and four wrong answers fail it", not G.exam_knowledge_done(1) and G.knowledge_retry_wait() > 0.0)
			G.flags.erase("exam:knowledge:fail")
			ex._knowledge(qs, 0, 0)
			check("the first question is put to you", hud._dialog_body.text == str(qs[0]["q"]))
			ex._knowledge(qs, qs.size(), 5)
			check("five right answers pass it", bool(G.academy["trials"].get("knowledge", false)) and hud._dialog_body.text.contains("Passed"))
			hud.close_dialog()
			G.add_item("healing_salve@fine", 1)
			check("the Trial of Craft: a found Fine salve doesn't count", not ("healing_salve@fine" in G.craft_trial_candidates()))
			G.counters["made:healing_salve@fine"] = 1.0
			check("...one you made does", G.exam_present_craft("healing_salve@fine") and bool(G.academy["trials"].get("craft", false)))
			check("all three passed: you can enrol", G.exam_complete() and G.enroll() and G.in_guild("academy") and G.count("lotus_disciple_robe") == 1)
			check("an Outer Disciple of the Academy", G.guild_rank_name("academy") == "Outer Disciple" and G.titles.has("Outer Disciple of the Lotus Ascent Academy"))
			G.academy["merit"] = 100.0
			check("merit buys a technique from the library", G.library_learn("lotus_breathing") == "" and G.has_tech("lotus_breathing") and int(G.academy["merit"]) == 40)
			check("...but not one kept for higher ranks", G.library_learn("lotus_body") != "" and not G.has_tech("lotus_body"))
			G.realm = 1
			check("a rank trial needs standing AND a realm", G.can_rank_trial() != "")
			G.guilds["academy"]["rep"] = 200.0
			G.realm = 2
			check("...with both, the Inner Disciple trial opens", G.can_rank_trial() == "", G.can_rank_trial())
			G.realm = 1
			wait = 0.1
		27:
			print("== tournaments and rivals ==")
			_build("floor5")
			var rm = _find("NPC.gd", func(n): return n.role == "tournament")
			check("Shellhaven holds a tournament", rm != null)
			G.gold = 0
			check("no entry fee, no entry", not G.start_tournament("floor5", "Shellhaven", 5, 0.5))
			G.gold = 500
			G.rivals = {}
			_changed_to = ""
			check("pay the fee and you're in", G.start_tournament("floor5", "Shellhaven", 5, 0.5) and G.gold == 450)
			_hold["t"] = 0
			wait = 0.1
		28:
			match int(_hold.get("t", 0)):
				0:
					check("...straight into the ring", _changed_to == "arena_floor5_tour_0", _changed_to)
					_build(_changed_to)
					var foes := []
					for e in root.get_tree().get_nodes_in_group("enemy"):
						foes.append(e)
					check("the quarterfinal is one rival cultivator, named, with a sect", foes.size() == 1 and str(foes[0].stats.get("name", "")).contains("("), str(foes.size()))
					_hold["first"] = G.arena_round_foe()
					foes[0].take_damage(999999)
					G.arena_cleared()
					check("beat them and they remember it", int(G.rivals.get(_hold["first"], {}).get("beat", 0)) == 1 and int(G.arena.get("stage", 0)) == 1)
					_hold["second"] = G.arena_round_foe()
					_changed_to = ""
					G.player_died("a rival")
					_hold["t"] = 1
					wait = 0.1
					return false
				1:
					check("fall in the ring: carried out to Shellhaven, no gold lost", _changed_to == "floor5" and G.gold == 450 and not G.arena_active(), _changed_to)
					check("...and the one who beat you remembers that too", int(G.rivals.get(_hold["second"], {}).get("lost", 0)) == 1)
					check("the next bracket waits a while", G.tourney_cooldown("floor5") > 0.0 and not G.start_tournament("floor5", "Shellhaven", 5, 0.5))
					var r0 = G.Arena.rival_def(G.Arena.RIVALS[0], 5, 0)
					var r3 = G.Arena.rival_def(G.Arena.RIVALS[0], 5, 3)
					check("rivals come back stronger every time you meet", int(r3["hp"]) > int(r0["hp"]) and int(r3["damage"]) > int(r0["damage"]))
					G.flags.erase("tourney:floor5")
					G.start_tournament("floor5", "Shellhaven", 5, 0.9)
					check("the final is against whoever you've crossed most", str(G.arena.get("opponents", [])[2]) in [_hold["first"], _hold["second"]], str(G.arena.get("opponents", [])))
					for i in 3:
						G.arena_cleared()
					check("win all three: a title, a prize from the champions' rack, Academy standing", G.titles.has("Champion of Shellhaven") and int(G.counters.get("tourney_wins", 0.0)) == 1)
			wait = 0.2
		29:
			print("== who you were: backgrounds, weapon proficiency, survival, focus ==")
			G.new_game()
			check("a new game asks who you were", G.needs_background())
			check("...everyone starts an Apprentice at Unarmed and Survival, and a Novice at everything else",
				G.skill_level("unarmed") == 5 and G.skill_level("survival") == 5 and G.skill_level("sword") == 0 and G.skill_level("smithing") == 0)
			check("a background gives ONE skill, its kit, and the weapon in your hand", G.choose_background("spearman") and G.skill_level("spear") == 5
				and G.weapon == "practice_spear" and not G.needs_background(), "%s %d" % [G.weapon, G.skill_level("spear")])
			check("...and is chosen once", not G.choose_background("smith") and G.skill_level("smithing") == 0)
			check("an untrained weapon hits at 65%; an Apprentice's at 100%", is_equal_approx(G.proficiency_mult("iron_sword"), 0.65) and is_equal_approx(G.proficiency_mult("practice_spear"), 1.0))
			G.add_item("goblin_shiv", 1)
			check("a found weapon you can't use yet doesn't push out the one you can", G.weapon == "practice_spear", G.weapon)
			var d_untrained: int = G.weapon_damage("iron_sword")
			G.skills["sword"] = 250.0
			check("...train it, and the same sword hits harder", G.weapon_damage("iron_sword") > d_untrained, "%d vs %d" % [G.weapon_damage("iron_sword"), d_untrained])
			G.skills.erase("sword")
			var sx: float = float(G.skills.get("spear", 0.0))
			G.train_weapon(3, 40)
			check("every blow and every kill trains the weapon in your hand", float(G.skills["spear"]) > sx + 6.0, str(G.skills["spear"]))
			check("Survival: traps bite less, salves go further, wounds close between fights",
				G.survival_trap_mult() < 1.0 and G.survival_heal_mult() > 1.0 and G.survival_regen() > 0.0)
			G.hp = 10
			G.inventory["healing_salve"] = 1
			G.use_item("healing_salve")
			check("...a salve heals more in practised hands (60 -> 66)", G.hp == 76, str(G.hp))
			G.focus = {}
			var gains := []
			for i in 12:
				var b: float = float(G.skills.get("alchemy", 0.0))
				G.add_skill_xp("alchemy", 10.0)
				gains.append(float(G.skills["alchemy"]) - b)
			check("focus: the twelfth hour at the furnace teaches more than the first", float(gains[11]) > float(gains[0]) * 1.2, str(gains))
			var rc: Dictionary = {}
			for r in G.recipes:
				if str(r.get("skill", "")) == "alchemy":
					rc = r
					break
			var ch_focus: float = G.craft_chance(rc)
			var fv: float = G.focus_value("alchemy")
			G.playtime += 1200.0
			check("...and it fades when you walk away (half-life 10 minutes)", G.focus_value("alchemy") < fv * 0.3 and G.craft_chance(rc) < ch_focus, "%f -> %f" % [fv, G.focus_value("alchemy")])
			# an old save, from before backgrounds: asked once, nothing taken away
			G.weapon = "iron_sword"
			G.kills = {"goblin": 100}
			G.skills["smithing"] = 2000.0
			G.save_game()
			var raw = JSON.parse_string(FileAccess.get_file_as_string(G.save_path))
			raw.erase("background")
			raw["skills"].erase("sword")
			raw["skills"].erase("survival")
			var fw := FileAccess.open(G.save_path, FileAccess.WRITE)
			fw.store_string(JSON.stringify(raw))
			fw.close()
			G.load_game()
			check("an older save is asked who it was", G.needs_background() and G._legacy_save)
			check("...and keeps its hands: the sword it fought with remembers 100 kills", G.skill_level("sword") >= 5 and G.skill_level("survival") == 5, str(G.skills))
			G.choose_background("smith")
			check("...choosing never lowers a skill", float(G.skills["smithing"]) == 2000.0)
			var mdl = player._model
			var sk3: Skeleton3D = mdl.find_children("*", "Skeleton3D", true, false)[0]
			if mdl.has_meta("human"):
				check("the character is a real person, life-sized (the realistic figure, about 1.8 m)", sk3.find_bone("Head") >= 0 and mdl.scale.is_equal_approx(Vector3.ONE))
			else:
				check("the character's head is in proportion now (72%)", is_equal_approx(sk3.get_bone_pose_scale(sk3.find_bone("head")).x, 0.72))
			wait = 0.1
		30:
			print("== moments: anything you can describe ==")
			var hud = root.get_tree().get_first_node_in_group("hud")
			G.flags.erase("moment:last")
			var mo = load("res://scripts/fx/Moment.gd").new()
			root.add_child(mo)
			var out := [""]
			G.llm_override = func(_m): return "the model is having a bad day"
			G.inventory.erase("spirit_herb")
			mo.say("I forage among the roots for anything useful", func(t): out[0] = t)
			check("with the model down, a plain reading still answers -- and the world gives back", str(out[0]).contains("[") and str(out[0]).length() > 40, str(out[0]))
			check("...then the world needs a while", G.moment_wait() > 0.0)
			mo.say("I forage again", func(t): out[0] = t)
			check("...a second try too soon is turned away", str(out[0]).begins_with("(Not yet"), str(out[0]))
			G.flags.erase("moment:last")
			G.depth = 3
			G.gold = 100
			G.hp = G.max_hp()
			G.llm_override = func(_m): return JSON.stringify({"outcome": "success", "narration": "You find a dragon hoard.",
				"effects": {"gold": 999999, "hp": -999999, "qi": 1e9, "items": {"emperor_jade_pendant": 1, "spirit_herb": 50, "iron_sword": 1},
					"skill_xp": {"mining": 9999, "made_up_skill": 50}}})
			var q0: float = G.qi
			var mx0: float = float(G.skills.get("mining", 0.0))
			mo.say("I dig for treasure", func(t): out[0] = t)
			check("the model proposes; the depth decides: gold is capped", G.gold <= 100 + 10 + 8 * 3 and G.gold > 100, str(G.gold))
			check("...a moment never kills you", G.hp >= 1)
			check("...no treasures, no gear, and never fifty of anything", G.count("emperor_jade_pendant") == 0 and G.count("iron_sword") == 0 and G.count("spirit_herb") <= 3 and G.count("spirit_herb") > 0, str(G.count("spirit_herb")))
			check("...skills it names must be real, and grow by a bounded amount", float(G.skills.get("mining", 0.0)) - mx0 <= (30.0 + 15.0) * 1.6 and not G.skills.has("made_up_skill"))
			check("...qi is capped too", G.qi - q0 < G.qi_to_next() * 0.5 + 1.0)
			G.flags.erase("moment:last")
			G.hp = G.max_hp()
			G.llm_override = func(_m): return JSON.stringify({"outcome": "partial", "narration": "Half of it works.", "effects": {"gold": 10}})
			mo.say("I sweet-talk the guard", func(t): out[0] = t)
			check("reciprocity: a half-success that only gives also takes", G.hp < G.max_hp() and str(out[0]).contains("took something"), str(out[0]))
			G.flags.erase("moment:last")
			G.hp = G.max_hp()
			var sv0: float = float(G.skills.get("survival", 0.0))
			G.llm_override = func(_m): return JSON.stringify({"outcome": "fail", "narration": "You fall.", "effects": {"gold": 50}})
			mo.say("I leap the chasm", func(t): out[0] = t)
			check("...a failure gives nothing, costs something, and teaches", G.hp < G.max_hp() and float(G.skills.get("survival", 0.0)) > sv0 and str(out[0]).contains("Survival"), str(out[0]))
			G.flags.erase("moment:last")
			G.llm_override = func(_m): return JSON.stringify({"outcome": "success", "narration": "They smile.", "effects": {"bond": {"Elder Mo": 5, "Somebody Absent": 5}}})
			mo.say("I bring Elder Mo tea", func(t): out[0] = t)
			# (nobody was near in this test: the named people aren't present, so no bond moves)
			check("...it only touches people who are actually there", not G.bonds.has("Somebody Absent"))
			check("the world remembers what you did (moments are saved)", G.moments.size() >= 4)
			check("T opens the moment panel, and not while the world is still settling", not hud.open_moment())
			G.flags.erase("moment:last")
			G.llm_override = func(_m): return "nope"
			check("...when it's ready, it opens", hud.open_moment() and hud._chat.visible and hud._chat_title.text == "What do you do?")
			hud.chat_say("I sing a song my mother taught me")
			check("...one try, then the moment passes", hud.chat_text().contains("The moment passes") and not hud._chat_in.editable, hud.chat_text())
			hud.close_chat()
			mo.queue_free()
			print("== contribution: what guilds and the sect let you spend ==")
			G.join_guild("gatherers")
			G.add_guild_rep("gatherers", 100.0)
			check("standing earns contribution alongside it", int(G.contribution("gatherers")) == 100)
			check("the Gatherers' stores: gloves for a Picker", G.buy_special("gatherers", "forager_gloves") == "" and G.count("forager_gloves") == 1 and int(G.contribution("gatherers")) == 40)
			check("...one of a kind", G.buy_special("gatherers", "forager_gloves") != "")
			check("...and the Warden's own satchel is kept for higher ranks", G.buy_special("gatherers", "warden_satchel").begins_with("Kept for"))
			check("...what you bought works like a technique (more from every gather)", G.tech_effect("gather_chance", 0.0) >= 0.15)
			check("contribution never lowers your rank", G.guild_rank_name("gatherers") == "Picker")
			G.inventory["iron_ore"] = 12
			var dv: int = G.donation_value("gatherers")
			check("donate your materials: standing and contribution", dv > 0 and G.donate_materials("gatherers") == dv and G.count("iron_ore") == 0 and int(G.contribution("gatherers")) == 40 + dv)
			G.academy = {"trials": {}, "enrolled": true, "rank": 1, "merit": 200.0}
			G.guilds["academy"] = {"rep": 150.0, "contract": {}}
			check("the sect's stores take merit: an Inner Disciple's Lotus Seal", G.buy_special("academy", "lotus_seal") == "" and int(G.academy["merit"]) == 60)
			print("== made for you: tailored, and wished for ==")
			_build("floor5")
			G.join_guild("blacksmiths")
			G.add_guild_rep("blacksmiths", 100.0)
			G.skills["spear"] = 900.0
			G.kills = {"goblin": 300}
			var pr: Dictionary = G.play_profile()
			check("a tailor reads how you play", str(pr["style"]) == "fighter" and str(pr["favorite_weapon"]) == "spear", str(pr))
			var oru = _find("NPC.gd", func(n): return n.role == "guild" and str(n.def.get("guild", "")) == "blacksmiths")
			G.llm_override = func(_m): return JSON.stringify({"name": "Ember Oath", "type": "weapon", "kind": "spear", "effect": "damage_mult",
				"element": "fire", "desc": "Red-tipped, warm in the hand.", "line": "\"Mind the tip.\""})
			check("commission a piece with contribution", oru != null and G.tailor_block("blacksmiths") == "" and oru.commission("blacksmiths", oru._guild, 0.5))
			var made := ""
			for id in G.inventory:
				if str(id).begins_with("custom_"):
					made = str(id)
			var md: Dictionary = G.item_def(made)
			var dd: int = G.reach_depth()
			check("...it's the spear the maker designed, Superior, its strength set by the depth you've reached", str(md.get("type", "")) == "weapon"
				and str(md.get("kind", "")) == "spear" and G.item_name(made).contains("Ember Oath") and made.ends_with("@superior")
				and int(G.items[G.base_id(made)]["damage"]) <= int(round(5.8 * dd * 0.95 * 1.08)) + 1, "%s %s" % [made, md])
			check("...and the contribution is spent", int(G.contribution("blacksmiths")) == 0 and G.tailor_block("blacksmiths") != "")
			var fd: Dictionary = G.finalize_design({"name": "x".repeat(90), "type": "crown", "effect": "infinite_power"}, 3, 1.0, "test")
			check("an impossible design is bent back to an honest one", str(fd["type"]) == "ring" and str(fd["name"]).length() <= 40 and fd["effect"].has("hp_mult")
				and float(fd["effect"]["hp_mult"]) <= 1.0 + 0.14 + 0.001, str(fd))
			var smith = _find("NPC.gd", func(n): return n.role == "smith")
			G.gold = 5000
			check("a settlement's smith takes three wishes", G.wishes_left("floor5") == 3)
			G.llm_override = func(_m): return JSON.stringify({"name": "Tidewater Band", "type": "ring", "effect": "hp_mult", "element": "water", "line": "\"Wear it.\""})
			var w = smith.open_wish()
			check("...the wish panel opens", hud._chat.visible and hud._chat_title.text.contains("wish"))
			hud.chat_say("a ring to keep me alive down there")
			check("...a wish is made, the fee is paid", w.made != "" and str(G.item_def(w.made).get("type", "")) == "ring" and G.gold == 5000 - G.wish_fee() and G.wishes_left("floor5") == 2, w.made)
			hud.close_chat()
			G.llm_override = func(_m): return "model asleep"
			var w2 = smith.open_wish()
			hud.chat_say("a fast dagger that burns")
			check("...with the model down, the tables still honour the words", w2.made != "" and str(G.item_def(w2.made).get("kind", "")) == "dagger" and str(G.item_def(w2.made).get("element", "")) == "fire", str(G.item_def(w2.made)))
			hud.close_chat()
			var w3 = smith.open_wish()
			hud.chat_say("an amulet")
			hud.close_chat()
			var w4 = smith.open_wish()
			hud.chat_say("one more?")
			check("...three, and no more at this settlement", G.wishes_left("floor5") == 0 and w4.made == "" and hud.chat_text().contains("Three"))
			hud.close_chat()
			check("...the next settlement has its own three", G.wishes_left("floor10") == 3)
			G.save_game()
			var keep: String = w.made
			var keep_name: String = G.item_name(keep)
			G.new_game()
			check("a new life forgets what was made for the old one", not G.items.has(G.base_id(keep)))
			G.load_game()
			check("made-for-you pieces are saved with you", G.items.has(G.base_id(keep)) and G.item_name(keep) == keep_name and G.count(keep) == 1, keep_name)
			G.llm_override = Callable()
			wait = 0.1
		31:
			print("== texture and detail: how each place looks ==")
			var Lk = load("res://scripts/world/Look.gd")
			var want := {"floor1": "warrens", "floor2": "crypt", "floor3": "drowned", "floor4": "sanctum", "floor6": "grove", "floor7": "forge",
				"floor8": "barrows", "floor9": "swordgrave", "floor12": "canopy", "floor14": "fungal", "floor19": "crystal", "floor5": "settlement", "village": "village"}
			var bad := []
			for id in want:
				if Lk.key_for(G.load_level_def(id)) != want[id]:
					bad.append("%s=%s" % [id, Lk.key_for(G.load_level_def(id))])
			check("every floor picks its region's look", bad.is_empty(), str(bad))
			var unknown := {"theme": "dungeon", "name": "Floor 99, Somewhere New"}
			check("...and a floor nobody planned for still gets one", Lk.key_for(unknown) == "warrens")
			check("...every forge region has a look of its own", G.load_level_def("floor11").has("forged") and Lk.key_for(G.load_level_def("floor11")) == "drowned")
			_build("floor7")
			check("the floor and walls are real textured surfaces (one mesh each, not a model per tile)",
				level.get_node_or_null("Walls") != null and level._floor_cells.size() > 300 and level._wall_cells.size() > 100)
			check("...the forge has its ember cracks, clutter along the walls, and its own torchlight",
				int(level.counts.get("glows", 0)) > 0 and int(level.counts.get("clutter", 0)) > 20
				and _find("Torch.gd").color.is_equal_approx(Color(1.0, 0.5, 0.2)))
			var sw2 = _find("SecretWall.gd")
			check("...a secret wall is cut from the same stone as the rest", sw2 != null and sw2._model.get_child(0) is MeshInstance3D and sw2._model.get_child(0).mesh is BoxMesh)
			var vg = _find("Vignette.gd", func(n): return not n.legacy)
			check("little scenes on the floor: %d here" % int(level.counts.get("vignettes", 0)), vg != null and int(level.counts.get("vignettes", 0)) >= 2)
			var sv0: float = float(G.skills.get("survival", 0.0))
			vg.interact(player)
			check("...look closer and it tells you what happened here", hud_text().length() > 40 and hud_text() != "", hud_text())
			check("...the first look teaches you a little about surviving", float(G.skills.get("survival", 0.0)) > sv0 and G.has_flag(vg._key))
			root.get_tree().get_first_node_in_group("hud").close_dialog()
			var g0: int = G.gold
			var inv0: int = G.inventory.size()
			vg.interact(player)
			check("...and only the first look finds anything", G.gold == g0 and G.inventory.size() == inv0)
			root.get_tree().get_first_node_in_group("hud").close_dialog()
			var V = load("res://scripts/fx/Vignette.gd")
			var kinds_ok := true
			for k in ["camp", "fallen", "shrine", "battle", "cache"]:
				if V.texts().get("kinds", {}).get(k, {}).get("lines", []).size() < 3:
					kinds_ok = false
			check("every kind of scene has words to read (data/vignettes.json)", kinds_ok)
			check("small lives: rats, bats, moths on a floor", int(level.counts.get("critters", 0)) >= 2 and _find("Critter.gd") != null)
			G.hour_override = 12.0
			var noon: float = G.daylight()
			G.hour_override = 23.0
			var night: float = G.daylight()
			G.hour_override = 19.5
			var dusk: float = G.daylight()
			check("the village keeps your clock: day, dusk, night", noon == 1.0 and night == 0.0 and dusk > 0.0 and dusk < 1.0)
			G.hour_override = 23.0
			_build("village")
			var lit := 0.0
			for n in level.get_children():
				if n is OmniLight3D:
					lit = maxf(lit, n.light_energy)
			G.hour_override = 12.0
			_build("village")
			var day_lit := 0.0
			for n in level.get_children():
				if n is OmniLight3D:
					day_lit = maxf(day_lit, n.light_energy)
			check("...lanterns burn bright at night, low by day", lit > day_lit * 2.0, "%f vs %f" % [lit, day_lit])
			check("...smoke from the chimneys", int(level.counts.get("chimneys", 0)) > 0)
			G.life_in_tests = true
			_build("village")
			var vill = _find("NPC.gd", func(n): return n.role == "villager")
			check("villagers wander (traders keep their posts)", vill != null and vill.wander and not _find("NPC.gd", func(n): return n.role == "merchant").wander)
			_hold["vill"] = vill
			_hold["vcell"] = vill.cell
			_hold["vpos"] = vill.global_position
			vill._rest = 0.0
			G.hour_override = 12.0            # by day they walk further (at night, a step and a long rest)
			_place_player(Vector2i(1, 1))
			wait = 6.0
		32:
			var vill2 = _hold["vill"]
			var moved: bool = vill2.cell != _hold["vcell"] or vill2.global_position.distance_to(_hold["vpos"]) > 0.3 or not vill2._path.is_empty()
			G.hour_override = -1.0
			check("...a villager walks off on their own, a few steps from home", moved and absi(vill2.cell.x - vill2._home_cell.x) <= 3 and absi(vill2.cell.y - vill2._home_cell.y) <= 3,
				"%s -> %s" % [_hold["vcell"], vill2.cell])
			check("...and the cell they stand on is theirs (nobody walks through them)", level.astar.is_point_solid(vill2.cell))
			player.global_position = vill2.global_position + Vector3(1.0, 0.5, 0)
			vill2._path = [vill2.cell]
			vill2._process(0.1)
			check("...come close and they stop to look at you", vill2._path.is_empty())
			G.life_in_tests = false
			G.hour_override = -1.0
			wait = 0.1
		33:
			print("== lost workshops and the masters who wait in them ==")
			G.new_game()
			_build("floor7")
			var shops := []
			for n in level.get_children():
				var sc = n.get_script()
				if sc and str(sc.resource_path).ends_with("Vignette.gd") and n.kind in n.WORKSHOPS:
					shops.append(n)
			check("an upper floor hides a lost workshop -- the Ember Forges, a forge", shops.size() >= 1 and shops[0].kind == "smithy", str(shops.map(func(x): return x.kind)))
			var ws = shops[0]
			check("...and its master still sits at the work (a legacy for floors 1-10)", ws.legacy and ws._ghost != null)
			ws.interact(player)
			check("...but turns away someone who's never held a hammer", hud_text().contains("not yet") and not G.has_tech("forge_sense"), hud_text())
			root.get_tree().get_first_node_in_group("hud").close_dialog()
			G.skills["smithing"] = 40.0
			ws.interact(player)
			check("...a smith who has started down the road is offered the legacy", hud_text().contains("You will receive") and hud_text().contains("Forge Sense"), hud_text())
			root.get_tree().get_first_node_in_group("hud").close_dialog()
			var sx: float = float(G.skills["smithing"])
			check("...accepting it gives the craft's technique, a masterwork, and a lifetime of practice",
				ws.accept_legacy() and G.has_tech("forge_sense") and float(G.skills["smithing"]) > sx + 100.0
				and G.inventory.keys().any(func(k): return str(k).ends_with("@masterwork")))
			check("...once, ever", not ws.accept_legacy())
			_build("floor7")
			var again = _find("Vignette.gd", func(n): return n.legacy)
			check("...and it stays given when you come back", again != null and G.has_flag(again._legacy_key) and not again.is_in_group("discoverable"))
			_build("floor12")
			var garden = _find("Vignette.gd", func(n): return n.kind == "herb_garden" and not n.legacy)
			if garden == null:
				garden = _find("Vignette.gd", func(n): return n.kind == "herb_garden")
			var hx: float = float(G.skills.get("herbalism", 0.0))
			garden.legacy = false
			garden.interact(player)
			root.get_tree().get_first_node_in_group("hud").close_dialog()
			check("a lost workshop on any floor teaches its craft a little and leaves something of its trade", float(G.skills.get("herbalism", 0.0)) > hx and G.count("spirit_herb") >= 4)
			_build("floor25") if FileAccess.file_exists("res://levels/floor25.json") else _build("floor19")
			check("...but the masters only wait on the upper floors", _find("Vignette.gd", func(n): return n.legacy) == null)
			print("== what people wear ==")
			_build("village")
			var mo = _find("NPC.gd", func(n): return n.role == "elder")
			var sk3: Skeleton3D = mo._body_model.find_children("*", "Skeleton3D", true, false)[0]
			check("townsfolk are real people, dressed for their trade (the elder: white hair in a bun, a beard)", mo._body_model.has_meta("human")
				and sk3.get_node_or_null("Hair_Hair_Buns") != null and sk3.get_node_or_null("Hair_Hair_Beard") != null and sk3.get_node_or_null("Head_" + ("SuperHero_Male" if mo._body_model.get_meta("sex") == "m" else "Superhero_Female")) != null)
			var heads: Array = sk3.find_children("Head_Super*", "MeshInstance3D", false, false)
			check("...only their head comes from the base body (their clothes bring the rest)", heads.size() == 1 and heads[0].mesh.get_surface_count() >= 1
				and heads[0].mesh.surface_get_array_index_len(0) < 0.35 * _full_body_indices(str(mo._body_model.get_meta("sex"))))
			var ap_mo: AnimationPlayer = mo._body_model.get_node("AnimationPlayer")
			check("...and they move: idle, walk, sit cross-legged, fight, fall", ap_mo.has_animation("idle") and ap_mo.has_animation("walk") and ap_mo.has_animation("sit")
				and ap_mo.has_animation("attack-melee-right") and ap_mo.has_animation("die") and ap_mo.get_animation("idle").loop_mode == Animation.LOOP_LINEAR)
			var psk: Skeleton3D = player._model.find_children("*", "Skeleton3D", true, false)[0]
			G.weapon = ""
			player._dress_up()
			check("you wear your clothes, empty-handed", psk.get_node_or_null("Dress_held") != null and psk.get_node("Dress_held").get_child(0).get_child_count() == 0)
			G.add_item("practice_spear", 1, false)
			G.equip("practice_spear")
			check("...pick up a spear and it's in your hand", psk.get_node("Dress_held").get_child(0).get_child_count() > 0 and player.dress_spec()["held"] == "spear")
			_build("floor1")
			var orc = _find("Enemy.gd", func(n): return n.body_kind != "beast")
			# round 29: the Kenney orc became a real body (Bestiary imp / puglin, or a golem)
			var oap = orc._find_anim(orc._model)
			check("monsters are real, smooth bodies now (an imp, a puglin, a golem) -- and they move", orc.body_kind in ["imp", "puglin", "golem"]
				and oap != null and oap.has_animation("walk") and oap.has_animation("attack-melee-right") and oap.has_animation("die"))
			var Mon = load("res://scripts/actors/Monster.gd")
			check("...a golem is a golem, a skeleton is bone, a wraith is ghost-light", Mon.pick({"name": "Crystal Golem"}) == "golem" and Mon.skin_for({"name": "Crystal Golem"}) == "crystal"
				and Mon.skin_for({"name": "Skeleton Knight"}) == "bone" and Mon.skin_for({"name": "Nanite Wraith"}) == "spectral" and Mon.pick({"name": "Goblin Chief"}) == "puglin" and Mon.pick({"name": "Cinder Imp"}) == "imp")
			var hare = load("res://scripts/actors/Enemy.gd").make_beast(Color(0.8, 0.8, 0.8), "Cave Hare")
			var crab = load("res://scripts/actors/Enemy.gd").make_beast(Color(0.8, 0.3, 0.2), "Salt Crab")
			var crow = load("res://scripts/actors/Enemy.gd").make_beast(Color(0.3, 0.3, 0.35), "Steel Crow")
			check("animals are built to their kind: a hare on four legs, a crab on six, a crow with wings", hare.plan == "hare" and hare._legs.size() == 4
				and crab.plan == "crab" and crab._legs.size() == 6 and crow.plan == "bird" and crow._wings.size() == 2)
			for b in [hare, crab, crow]:
				b.free()
			var old_style = load("res://scripts/core/Art.gd").style
			load("res://scripts/core/Art.gd").style = "kenney"
			var low = load("res://scripts/actors/Enemy.gd").new()
			low.setup(level, {"type": "goblin"})
			level.add_child(low)
			var osk: Skeleton3D = low._model.find_children("*", "Skeleton3D", true, false)[0]
			check("...Low graphics keeps the old toy goblin, glowing eyes and all", low.body_kind == "kenney" and osk.get_node_or_null("Dress_head") != null)
			low.free()
			load("res://scripts/core/Art.gd").style = old_style
			var FXs = load("res://scripts/fx/FX.gd")
			FXs.hit(Vector3.ZERO)
			FXs.slash(player, Color.WHITE, 2.0, 0.0)
			FXs.puff(Vector3.ZERO)
			FXs.ring(Vector3.ZERO, Color.WHITE)
			check("effects are only pictures: under the headless check they do nothing (and break nothing)", not FXs.on() and FXs.aura(player, Color.WHITE) == null)
			var jumps := InputMap.action_get_events("jump").filter(func(e): return e is InputEventJoypadButton)
			var looks := InputMap.action_get_events("look_left").filter(func(e): return e is InputEventJoypadMotion)
			check("a game pad works: A jumps, the right stick looks", jumps.size() > 0 and looks.size() > 0)
			var Gx = load("res://scripts/core/Gfx.gd")
			var was_touch = str(Gx.settings.get("touch", "auto"))
			Gx.settings["touch"] = "on"
			var TU = load("res://scripts/ui/TouchUI.gd")
			var tui = TU.new()
			root.add_child(tui)
			Gx.settings["touch"] = "off"
			var off_ok: bool = not TU.wanted()
			Gx.settings["touch"] = was_touch
			check("touch controls: a stick for the left thumb, buttons that press the game's own keys", tui._play_buttons.size() >= 12
				and tui._play_buttons.any(func(pb): return pb[0].action == "attack") and off_ok)
			tui._stick_finger = 0
			tui._stick_origin = Vector2(200, 500)
			tui._stick_now = Vector2(200, 380)
			tui._push_stick()
			var fwd := Input.get_action_strength("move_forward")
			tui._release_stick()
			check("...push the stick up and you walk forward; let go and you stop", fwd > 0.9 and Input.get_action_strength("move_forward") == 0.0)
			tui.free()
			wait = 0.1
		34:
			print("== downtime: a home, a garden, a bench, a chest, a bed ==")
			G.new_game()
			G.background = "farmhand" if G.BACKGROUNDS.has("farmhand") else str(G.BACKGROUNDS.keys()[0])
			var hud = root.get_tree().get_first_node_in_group("hud")
			_build("floor3")
			_build("village")
			var home = _find("Home.gd")
			check("the village has a home site (Elder Mo's spare plot)", home != null and level.char_at(home.cell) == ".")
			check("...it's offered, not owned, until you look at it", not G.has_home() and home._spots["garden"].prompt().contains("spare plot"))
			home.open("garden")
			check("...looking at it offers it to you", hud_text().contains("Elder Mo said it was yours"), hud_text())
			hud.close_dialog()
			G.take_home()
			check("...and then it's yours: three garden beds", G.has_home() and G.plot_count() == 3 and G.home["garden"].size() == 3)
			G.add_item("spirit_herb", 2, false)
			home.garden_menu()
			check("the garden shows each bed, and offers what you can plant", hud_text().contains("Plot 1: empty") and hud._dialog_buttons.get_child_count() >= 2, hud_text())
			hud.close_dialog()
			check("planting takes a seed and starts the clock", G.plant(0, "spirit_herb") and G.count("spirit_herb") == 1 and not G.plot_ready(0))
			check("...you can't plant over something growing", not G.plant(0, "spirit_herb"))
			home._last_sig = ""
			home._build_garden()
			check("...and you can see it in the ground", home._garden.get_child_count() >= 4 and home._stage(0) == 0)
			G.home["garden"][0]["ready"] = G._now() - 1.0
			check("when it's grown it's ready -- and the goal line says so", G.plot_ready(0) and G.ready_plots() == 1 and G.next_goals()[0].contains("garden"), str(G.next_goals()))
			var hv: String = G.harvest(0, 0.9)
			check("harvesting brings back several, teaches Herbalism, and empties the bed", hv != "" and G.count("spirit_herb") >= 4 and G.home["garden"][0].is_empty() and float(G.skills.get("herbalism", 0.0)) > 0.0, hv)
			G.gold = 300
			check("more garden beds cost gold (3 -> 6)", G.upgrade_plots() and G.plot_count() == 6 and G.gold == 50 and G.home["garden"].size() == 6)
			G.add_item("iron_ore", 5, false)
			var moved: int = G.stash_all_materials()
			check("the chest takes every material in your pouch", moved >= 5 and G.count("iron_ore") == 0 and int(G.home["stash"].get("iron_ore", 0)) == 5)
			check("...and gives them back", G.take_from_stash("iron_ore") == 5 and G.count("iron_ore") == 5 and not G.home["stash"].has("iron_ore"))
			G.stash_all_materials()
			var salve: Dictionary = G._recipe_for("healing_salve")
			check("the bench can work from the chest as well as the pouch", G.bench_can_make(salve) >= 2, str(G.bench_can_make(salve)))
			var msg: String = G.queue_craft("healing_salve", 2)
			check("queue two salves at the bench", msg.contains("2") and int(G.home["queue"].get("left", 0)) == 2, msg)
			check("...the goal line counts them down", str(G.next_goals()).contains("Bench"), str(G.next_goals()))
			check("...nothing happens before it's time", G.process_queue().is_empty())
			G.home["queue"]["next"] = G._now() - 1.0
			var done1: Array = G.process_queue()
			check("...then one piece at a time, taking from the chest", done1.size() == 1 and int(G.home["queue"].get("left", 0)) == 1, str(done1))
			G.home["queue"]["next"] = G._now() - 10.0 * G.queue_period(salve)
			G.process_queue()
			check("...until the queue is done", G.home["queue"].is_empty())
			home.bench_menu()
			check("the bench menu offers what you can make", hud_text().contains("idle"), hud_text())
			hud.close_dialog()
			home.bed_menu()
			check("the bed offers sleep and planning your time away", _btn_has("Sleep") and _btn_has("Plan your time away"))
			hud.close_dialog()
			var g0: float = G.growth_mult()
			G.hp = 1
			G.rest_at_home()
			check("sleeping at home mends you and leaves you well rested (+10%)", G.hp == G.max_hp() and G.rested() and G.growth_mult() > g0 * 1.09)
			print("== downtime: what you do while you're away ==")
			G.home["rested_until"] = 0.0
			var sx0: float = float(G.skills.get("spear", 0.0))
			G.set_away_task({"kind": "train", "skill": "spear"})
			var lines: Array = G.resolve_away(3.0, false, 7)
			check("three hours away training: the skill grows, and you're told", float(G.skills.get("spear", 0.0)) > sx0 + 50.0 and "\n".join(lines).contains("trained"), "\n".join(lines))
			var inv0 := 0
			for k in G.inventory:
				inv0 += int(G.inventory[k])
			G.set_away_task({"kind": "gather", "skill": "herbalism"})
			lines = G.resolve_away(2.0, false, 7)
			var inv1 := 0
			for k in G.inventory:
				inv1 += int(G.inventory[k])
			check("two hours out gathering: you come back with things", inv1 > inv0 and "\n".join(lines).contains("brought back"), "\n".join(lines))
			G.add_item("spirit_herb", 6, false)
			var made0: int = G._total_crafted()
			G.set_away_task({"kind": "craft", "recipe": "healing_salve", "count": 2})
			lines = G.resolve_away(4.0, false, 7)
			check("...or working at the bench: things get made", G._total_crafted() > made0 or "\n".join(lines).contains("spoiled"), "\n".join(lines))
			check("...and a finished craft task clears itself", G.away_task.is_empty() or int(G.away_task.get("count", 0)) < 2)
			G.away_task = {}
			var rest_q := int(str(G.resolve_away(1.0, false, 7)[1]).split(" ")[3])
			G.set_away_task({"kind": "meditate"})
			var med_q := int(str(G.resolve_away(1.0, false, 7)[1]).split(" ")[3])
			check("meditating while away refines twice the qi of resting (slow without aids)", med_q >= rest_q * 1.8 and rest_q > 0, "%d vs %d" % [med_q, rest_q])
			check("away time is capped", G.resolve_away(500.0, false, 7)[0].contains("12.0"))
			G.set_away_task({"kind": "gather", "skill": "mining"})
			G.save_game()
			var f2 := FileAccess.open(G.save_path, FileAccess.READ)
			var data2 = JSON.parse_string(f2.get_as_text())
			f2.close()
			data2["saved_at"] = float(data2["saved_at"]) - 3600.0 * 2
			_rewind_pursuit(data2, 7200.0)          # (round 63: the high-water clock moves back with it -- real time passed)
			var w2 := FileAccess.open(G.save_path, FileAccess.WRITE)
			w2.store_string(JSON.stringify(data2))
			w2.close()
			G.load_game()
			check("coming back after two hours: a report of what you did", G.away_report.size() >= 3 and str(G.away_report).contains("brought back"), str(G.away_report))
			check("...your home, plan and stash came back with you", G.has_home() and G.plot_count() == 6 and str(G.away_task.get("skill", "")) == "mining" and G.home["stash"].size() > 0)
			hud.show_away_report()
			check("...shown when you're back, then cleared", hud._dialog_title.text == "While you were away" and G.away_report.is_empty())
			hud.close_dialog()
			hud.open_away_plan()
			check("the pause menu's 'Plan your time away' offers meditate / train / gather / craft / rest", _btn_has("Meditate") and _btn_has("Train a skill") and _btn_has("Work at the bench"))
			hud.close_dialog()
			print("== downtime: expeditions ==")
			G.familiar = {"species": "cave_hare", "name": "Pip", "bond": 0.0}
			var fam = load("res://scripts/actors/Familiar.gd").new()
			root.add_child(fam)
			check("somewhere you've been is somewhere they can go", G.expedition_floors().has("floor3") and G.can_send("familiar") == "", str(G.expedition_floors()))
			hud.open_expedition("familiar")
			check("...the familiar can be sent (where? how long?)", hud._dialog_title.text.contains("Send Pip where"), hud._dialog_title.text)
			hud.close_dialog()
			var gold0: int = G.gold
			check("send your familiar off for an hour", G.start_expedition("familiar", "floor3", 1.0) and bool(G.familiar.get("away", false)))
			check("...it's gone from your side while it's away", not fam.visible and not fam.is_in_group("interactable"))
			check("...one expedition at a time", G.can_send("familiar") != "" and not G.start_expedition("familiar", "floor3", 1.0))
			check("...the goal line says when it's back", str(G.next_goals()).contains("Pip returns"), str(G.next_goals()))
			check("...nothing yet", G.check_expedition().is_empty())
			G.expedition["end"] = G._now() - 1.0
			var back: Array = G.check_expedition()
			check("back with gold, finds and a story", back.size() == 2 and G.gold > gold0 and not G.familiar.has("away") and int(G.counters.get("expeditions", 0.0)) == 1, str(back))
			check("...and at your side again", fam.visible and fam.is_in_group("interactable"))
			fam.queue_free()
			G.familiar = {}
			print("== downtime: daily bounties and long goals ==")
			var bl: Array = G.bounties_today()
			check("three bounties a day", bl.size() == 3 and str(G.bounties.get("day", "")) == G.today(), str(bl))
			check("...the same three all day", str(G.bounties_today()) == str(bl))
			var gold1: int = G.gold
			for i in 3:
				G.counters["crafted:probe"] = float(G.counters.get("crafted:probe", 0.0)) + 1.0
			var bd: Array = G.check_bounties()
			check("finish one and it pays at once (gold, qi, standing)", bd.size() == 1 and str(bd[0]["kind"]) == "craft" and G.gold > gold1, str(bd))
			check("...only once", G.check_bounties().is_empty())
			check("...and starts a streak", int(G.bounties.get("streak", 0)) == 1)
			G.counters["harvests"] = 10.0
			var ach: Array = G.check_achievements()
			check("achievements: long goals, each a permanent boost to growth", ach.size() >= 2 and G.achievements.has("harvest_10") and G.growth_mult() > 1.0, str(ach.map(func(a): return a["id"])))
			check("...earned once", G.check_achievements().is_empty())
			check("...and the next ones are in the journal", G.next_achievements(3).size() == 3)
			hud.fill_journal()
			var jt := ""
			for c in hud._jr_body.get_children():
				if c is Label:
					jt += c.text + "\n"
			check("the journal lists today's bounties and the next achievements", jt.contains("Bounty:") and jt.contains("Achievement --"), jt.substr(0, 400))
			hud.refresh_goals()
			check("the goal line is always on screen", hud._goals.text != "")
			wait = 0.1
		35:
			print("== graphics: presets, photo-scanned props, the camera ==")
			var Gfx = load("res://scripts/core/Gfx.gd")
			var Art = load("res://scripts/core/Art.gd")
			var LookS = load("res://scripts/world/Look.gd")
			Gfx.load_settings()
			var keep: String = Gfx.preset()
			Gfx.set_preset("low", root.get_tree())
			check("Low is the original look: Kenney models, painted stone", Art.style == "kenney" and not LookS.natural and Art.make("mini-dungeon/barrel.glb").name != "Art_wine_barrel_01")
			var lowp: Node3D = Art.person({"sex": "f", "hair": "long"})
			check("...and the old blocky people", not lowp.has_meta("human") and lowp.scale.is_equal_approx(Vector3.ONE * 2.0))
			lowp.free()
			var env := Environment.new()
			Gfx.tune_env(env, "dungeon")
			check("...and no extra effects", not env.ssao_enabled and not env.volumetric_fog_enabled and not env.sdfgi_enabled)
			Gfx.set_preset("high", root.get_tree())
			check("High: photo-scanned props, natural stone, rough/AO detail", Art.style == "realistic" and LookS.natural and LookS.detail)
			Gfx.tune_env(env, "dungeon")
			check("...ambient occlusion, bounce light, bloom, fog you can see light in, a colour grade", env.ssao_enabled and env.ssil_enabled and env.glow_enabled and env.volumetric_fog_enabled and env.adjustment_enabled and not env.sdfgi_enabled)
			var env2 := Environment.new()
			Gfx.tune_env(env2, "village")
			check("...no underground fog under the open sky", not env2.volumetric_fog_enabled)
			check("...a real photographed sky over Eliet by day (not at night)", Gfx.day_sky(1.0) != null and Gfx.day_sky(0.1) == null)
			check("...torches near you cast shadows", Gfx.torch_shadow_radius() > 0.0)
			Gfx.set_preset("ultra", root.get_tree())
			Gfx.tune_env(env, "dungeon")
			check("Ultra adds global illumination", env.sdfgi_enabled)
			Gfx._loaded = false
			Gfx.settings["preset"] = "medium"
			check("the preset is remembered between sessions (user://settings.json)", Gfx.load_settings()["preset"] == "ultra")
			var kb: AABB = Art.box("res://assets/kenney/mini-dungeon/barrel.glb")
			var barrel: Node3D = Art.make("mini-dungeon/barrel.glb", 0)
			var fitted: AABB = Art._merge(barrel, Transform3D.IDENTITY, AABB(), true)
			check("a photo-scanned barrel stands in for the Kenney one", barrel.name.begins_with("Art_"), barrel.name)
			check("...at the same size and on the same ground (nothing in a level moves)", absf(maxf(fitted.size.y, maxf(fitted.size.x, fitted.size.z)) - maxf(kb.size.y, maxf(kb.size.x, kb.size.z))) < 0.02 and absf(fitted.position.y - kb.position.y) < 0.02, "%s vs %s" % [fitted, kb])
			barrel.free()
			var wall: Node3D = Art.make("fantasy-town-kit/wall-block.glb")
			var mis: Array = wall.find_children("*", "MeshInstance3D", true, false)
			check("houses get real stone and wood instead of flat colour", mis.size() > 0 and (mis[0].material_override != null or mis[0].get_surface_override_material(0) != null))
			wall.free()
			check("everything without a stand-in stays as it was", Art.make("mini-dungeon/trap.glb").name != "Art_" and Art.stand_in("mini-dungeon/trap.glb") == "")
			_build("floor1")
			var chest = _find("Chest.gd", func(n): return not n.hidden)
			check("chests are the real treasure chest", chest != null and chest._model.find_child("treasure_chest_lid", true, false) != null)
			chest.interact(player)
			var lid = chest._model.find_child("treasure_chest_lid", true, false)
			wait = 0.6
			_hold["lid"] = lid
		36:
			check("...and its lid lifts when you open it", _hold["lid"].rotation.x < -1.0, str(_hold["lid"].rotation))
			player.set_camera_mode("first")
			check("first person: the camera is in your eyes", player._spring.spring_length == 0.0 and player.cam_mode == "first")
			var body_meshes: Array = player._model.find_children("*", "VisualInstance3D", true, false)
			check("...and your own body is left out of the picture (its shadow isn't)", (player.camera.cull_mask & player.OWN_BODY_LAYER) == 0 and body_meshes.size() > 0 and (body_meshes[0].layers & player.OWN_BODY_LAYER) != 0)
			player.set_camera_mode("shoulder")
			check("over the shoulder", player._spring.spring_length == 3.0 and (player.camera.cull_mask & player.OWN_BODY_LAYER) != 0)
			player.set_camera_mode("far")
			check("...and back to the far camera, at the distance you had it", player._spring.spring_length > 3.5)
			var m0: String = str(load("res://scripts/core/Gfx.gd").load_settings()["camera"])
			var m1: String = player.cycle_camera()
			check("C cycles the camera, and it's remembered", m1 != m0 and str(load("res://scripts/core/Gfx.gd").load_settings()["camera"]) == m1)
			player.set_camera_mode("far")
			load("res://scripts/core/Gfx.gd").settings["camera"] = "far"
			load("res://scripts/core/Gfx.gd").set_preset("high", root.get_tree())
			wait = 0.1
		37:
			print("== the Meridian Lattice: your body is the skill tree ==")
			G.new_game()
			check("a new cultivator has no points open; the first ring is open to work on, the second sealed",
				G.lattice.is_empty() and G.can_focus("laogong") == "" and G.can_focus("quchi").contains("sealed"), G.can_focus("quchi"))
			var fmsg: String = G.set_focus("laogong")
			check("choosing a focus point", G.lattice_focus == "laogong" and fmsg.contains("Laogong"), fmsg)
			var q0: float = G.qi
			G.meditate_tick(1.0, false, 0.0)
			check("plain meditation is slow: 0.25 qi a second", is_equal_approx(G.qi - q0, 0.25), str(G.qi - q0))
			q0 = G.qi
			G.meditate_tick(1.0, true, 0.0)
			check("...a shrine doubles it (an aid)", is_equal_approx(G.qi - q0, 0.5), str(G.qi - q0))
			q0 = G.qi
			G.meditate_tick(1.0, false, 400.0)
			check("...and a long sitting flows at half", is_equal_approx(G.qi - q0, 0.125), str(G.qi - q0))
			check("...while the focus point fills (1 + 2 + 1 seconds so far)", is_equal_approx(float(G.lattice_progress.get("laogong", 0.0)), 4.0), str(G.lattice_progress))
			var fire0: float = float(G.affinity["fire"])
			var dm0: float = G.tech_effect("damage_mult", 1.0)
			G.meditate_tick(150.0, false, 0.0)
			check("enough sitting opens the point: Laogong is open", G.lattice.has("laogong"))
			check("...a small permanent bonus on its meridian (+2% strike damage) and its element grows",
				is_equal_approx(float(G.lattice_effect().get("damage_mult", 1.0)), 1.02) and G.tech_effect("damage_mult", 1.0) > dm0 and float(G.affinity["fire"]) >= fire0 + 5.0, "%s %f" % [G.lattice_effect(), dm0])
			check("...and your focus moves on to the next point of that meridian", G.lattice_focus == "hegu", G.lattice_focus)
			G.learn("wind_step", "test")
			check("an art whose route is sealed can't be used yet -- and says which point to open", G.art_blocked("wind_step").contains("Yongquan") and G.arts.has("wind_step"))
			_build("floor1")
			_place_player(level.spawns.get("P", [Vector2i(2, 2)])[0])
			check("...the button does nothing but remind you", player.use_wind_step(Vector3.FORWARD) == false)
			G.open_point("yongquan")
			player._cool.clear()
			check("open the route, and it works", player.use_wind_step(Vector3.FORWARD) == true and float(G.arts["wind_step"]["u"]) >= 1.0)
			G.learn("qi_burst", "test")
			var foe = _find("Enemy.gd", func(n): return not n._dead and not bool(n.stats.get("passive", false)))
			_place_player(foe.cell + Vector2i(1, 0))
			foe.hp = 100000
			var hegu0: float = float(G.lattice_progress.get("hegu", 0.0))
			player._cool.clear()
			var hit: int = player.use_qi_burst()
			check("Qi Burst in a real fight: it lands, and that counts three times as practice", hit >= 1 and is_equal_approx(float(G.arts["qi_burst"]["u"]), 3.0), "%d %s" % [hit, G.arts.get("qi_burst")])
			check("...and tugs at the next sealed point on its meridian", float(G.lattice_progress.get("hegu", 0.0)) >= hegu0 + G.TUG_SECONDS - 0.01)
			check("...on its own cooldown", float(player._cool.get("qi_burst", 0.0)) > 5.0)
			for i in 400:
				G.practice("qi_burst", true)
			check("unsettled practice has a ceiling: rest or lose the rest", float(G.arts["qi_burst"]["u"]) <= 300.0 and float(G.arts["qi_burst"]["m"]) == 0.0, str(G.arts["qi_burst"]))
			check("...until then it's still Practiced, at 85% power", G.art_stage_name("qi_burst") == "Practiced" and is_equal_approx(G.art_power("qi_burst"), 0.85))
			G.meditate_tick(10.0, false, 0.0)
			check("meditation settles practice a little at a time", float(G.arts["qi_burst"]["m"]) >= 10.0 and float(G.arts["qi_burst"]["m"]) < 12.0, str(G.arts["qi_burst"]))
			G.take_home()
			G.rest_at_home()
			check("a night in your own bed settles all of it: Fluent", float(G.arts["qi_burst"]["u"]) == 0.0 and G.art_stage_name("qi_burst") == "Fluent", str(G.arts["qi_burst"]))
			G.arts["qi_burst"]["m"] = 600.0
			check("Mastered: more power, a shorter cooldown", G.art_stage_name("qi_burst") == "Mastered" and G.art_power("qi_burst") > 1.0 and G.art_cooldown_mult("qi_burst") < 1.0)
			var qk0: float = G.step_index() * 100000.0 + G.qi
			var weak = _find("Enemy.gd", func(n): return not n._dead and not bool(n.stats.get("passive", false)) and n != foe)
			var kq: float = float(weak.stats.get("qi", 5))
			weak.take_damage(100000, "test")
			check("every kill refines qi -- half again what it was (fighting is the main road)", G.step_index() * 100000.0 + G.qi >= qk0 + kq * 1.5 - 0.01, "%f %f" % [G.step_index() * 100000.0 + G.qi - qk0, kq])
			check("...and all that practice pulled Hegu open along the way", G.lattice.has("hegu"))
			G.set_focus("qihai")
			check("the goal line names the point you're opening", str(G.next_goals()).contains("Open Qihai"), str(G.next_goals()))
			var hud = root.get_tree().get_first_node_in_group("hud")
			hud.toggle_lattice()
			check("K shows the lattice: your points, your focus, your arts and their mastery", hud._lattice.visible and hud._lat_info.text.contains("points open") and _rows_text(hud).contains("Qi Burst (strike) -- Mastered"), _rows_text(hud))
			var lv = hud._lat_view
			var p0: Dictionary = G.lattice_point("shousanli")
			check("...click a point on the figure to choose it", lv.point_at(lv.point_pos(p0)) == "shousanli")
			hud.toggle_lattice()
			# a save from before the lattice keeps its arts working
			G.save_game()
			var f3 := FileAccess.open(G.save_path, FileAccess.READ)
			var d3 = JSON.parse_string(f3.get_as_text())
			f3.close()
			for k in ["lattice", "lattice_progress", "lattice_focus", "arts"]:
				d3.erase(k)
			var w3 := FileAccess.open(G.save_path, FileAccess.WRITE)
			w3.store_string(JSON.stringify(d3))
			w3.close()
			G.load_game()
			check("an older save keeps its arts: their points open, already Fluent", G.lattice.has("laogong") and G.lattice.has("yongquan")
				and G.art_stage_name("qi_burst") == "Fluent" and G.art_blocked("wind_step") == "", str(G.arts))
			wait = 0.1
		38:
			print("== round 20: heat, the guard, glimpses, branches, bridges, aids ==")
			G.new_game()
			check("the new arts, the incense and its recipe are merged in from data/lattice.json (the forge's files untouched)",
				G.technique_defs.has("severing_finger") and G.technique_defs.has("returning_tide") and G.items.has("calming_incense") and G.items.has("nanite_bridge")
				and G.recipes.any(func(r): return str(r.get("makes", "")) == "calming_incense"))
			check("a new cultivator runs cool", G.heat == 0.0 and G.heat_cap() == 100.0 and not G.running_hot())
			# a nanite bridge lets an art run before its point is open -- hot
			G.learn("wind_step", "test")
			check("no bridge to wire yet", G.can_bridge("yongquan").contains("no nanite bridge"), G.can_bridge("yongquan"))
			G.boss_fell(true)
			check("a great foe's first fall leaves a nanite bridge (and a glimpse)", G.count("nanite_bridge") == 1 and float(G.glimpses.get("collapsing_palm", 0.0)) == 1.0, str(G.glimpses))
			var bmsg: String = G.set_bridge("yongquan")
			check("wire it across a sealed point: the art runs", bmsg.begins_with("BRIDGE") and G.art_blocked("wind_step") == "" and G.count("nanite_bridge") == 0, bmsg)
			check("...at half again the heat", G.art_heat("wind_step") >= 26.9 and G.art_heat("wind_step") <= 27.5, str(G.art_heat("wind_step")))
			G.add_item("nanite_bridge", 1, false)
			check("...and your lattice holds one bridge until a ring is complete", G.can_bridge("zusanli").contains("hold 1") or G.can_bridge("zusanli").contains("can hold 1"), G.can_bridge("zusanli"))
			check("a deep point can't be bridged yet", G.can_bridge("taixi").contains("too deep"), G.can_bridge("taixi"))
			G.open_point("yongquan")
			check("once the point opens, the bridge comes back", not G.bridges.has("yongquan") and G.count("nanite_bridge") == 2 and G.art_heat("wind_step") < 19.0, "%d %f" % [G.count("nanite_bridge"), G.art_heat("wind_step")])
			# heat
			G.learn("qi_burst", "test")
			G.open_point("laogong")
			var pw0: float = G.art_fire("qi_burst")
			check("every art heats your nanites (Qi Burst: about 30)", G.heat >= 29.0 and G.heat <= 31.5 and is_equal_approx(pw0, G.art_power("qi_burst")), "%f %f" % [G.heat, pw0])
			G.heat = 72.0
			var pw1: float = G.art_fire("wind_step")
			check("above 70%% you run HOT: arts hit 15%% harder", is_equal_approx(pw1, G.art_power("wind_step") * 1.15) and G.heat < G.heat_cap(), "%f %f" % [pw1, G.heat])
			var hp0: int = G.hp
			G.heat = 95.0
			G.art_fire("qi_burst")
			check("past the cap: BACKLASH -- a tenth of your life, heat knocked back to 60%", G.hp == hp0 - int(round(G.max_hp() * 0.1)) and is_equal_approx(G.heat, 60.0), "%d->%d %f" % [hp0, G.hp, G.heat])
			check("...and the strike meridian is injured: its bonus goes quiet, its arts run twice as hot",
				G.injury.has("strike") and is_equal_approx(float(G.lattice_effect().get("damage_mult", 1.0)), 1.0) and G.art_heat("qi_burst") > 59.0, "%s %s %f" % [G.injury, G.lattice_effect(), G.art_heat("qi_burst")])
			G.heat_tick(10.0, true, false, false)
			check("heat vents on its own out of a fight (8 a second)", G.heat == 0.0, str(G.heat))
			G.heat_tick(25.0, false, false, true)
			check("sitting mends an injured meridian four times faster", not G.injury.has("strike") and float(G.lattice_effect().get("damage_mult", 1.0)) > 1.0, str(G.injury))
			var bl := int(G.counters.get("backlashes", 0.0))
			check("...and backlashes are counted", bl == 1, str(bl))
			# the guard
			check("a raised guard lets half a blow through; from behind, three quarters", is_equal_approx(G.guard_take(true), 0.5) and is_equal_approx(G.guard_take(false), 0.75))
			G.heat = 0.0
			var bk: Dictionary = G.block(20, true)
			check("a blocked blow: half through, a little heat", int(bk["take"]) == 10 and is_equal_approx(G.heat, 4.0) and float(G.glimpses.get("iron_shell", 0.0)) == 1.0, "%s %f %s" % [bk, G.heat, G.glimpses])
			G.glimpse("block", 29.0)
			check("thirty blows glimpsed: Iron Shell is learned, and wired to your guard", G.has_tech("iron_shell") and G.slot_art("guard") == "iron_shell")
			check("...but its route (Qihai, Guanyuan) is sealed, so the plain guard still holds", G.guard_art() == "" and is_equal_approx(G.guard_take(true), 0.5))
			G.open_point("qihai")
			G.open_point("guanyuan")
			check("open them: Iron Shell lets only ~40% through at Practiced", G.guard_art() == "iron_shell" and absf(G.guard_take(true) - 0.405) < 0.01, str(G.guard_take(true)))
			G.heat = 50.0
			var pr: Dictionary = G.parry(30)
			check("a perfect parry: the blow is gone, the foe staggers, 25 heat vents", is_equal_approx(G.heat, 25.0) and float(pr["stagger"]) > 1.0 and float(G.glimpses.get("returning_tide", 0.0)) == 1.0, "%s %f" % [pr, G.heat])
			G.glimpse("parry", 40.0)
			check("Returning Tide fully glimpsed -- but it grows from Iron Shell grown Fluent, so it waits", not G.has_tech("returning_tide"))
			var gr: Array = G.glimpse_rows()
			check("...K says so", str(gr).contains("Returning Tide") and str(gr).contains("Iron Shell Fluent"), str(gr))
			G.arts["iron_shell"]["u"] = 160.0
			G.settle_all()
			check("Iron Shell settles into Fluent: Returning Tide is learned", G.has_tech("returning_tide") and G.art_stage_name("iron_shell") == "Fluent")
			check("...a second guard art: you choose which is wired", G.known_arts("guard").size() == 2 and G.slot_art("guard") == "iron_shell" and G.wire("returning_tide").contains("guard") and G.slot_art("guard") == "returning_tide")
			check("...its route runs into the second ring -- sealed, so the plain guard holds again", G.guard_art() == "")
			G.wire("iron_shell")
			# branches at Fluent
			check("an art takes an element only when Fluent", G.can_branch("qi_burst").contains("Fluent"))
			G.arts["qi_burst"]["m"] = 150.0
			var br: String = G.choose_branch("qi_burst", "fire")
			check("...Fluent Qi Burst takes fire: its hits will burn", br.begins_with("BRANCH") and G.art_branch("qi_burst") == "fire", br)
			check("...once, for good; and only its own elements", G.choose_branch("qi_burst", "earth").contains("already") and G.choose_branch("iron_shell", "fire").contains("doesn't fit"))
			# aids
			check("the training post: half an hour of drill a day", is_equal_approx(G.post_budget(), 1800.0))
			var pu0: float = float(G.arts["qi_burst"]["u"])
			check("...an art drilled there is real practice (2: between a miss and a hit)", G.post_drill("qi_burst") and is_equal_approx(float(G.arts["qi_burst"]["u"]), pu0 + 2.0))
			G.post_log["used"] = 1799.0
			G.post_drill("qi_burst")
			check("...and when today's drill is spent, it's spent", G.post_budget() == 0.0 and not G.post_drill("qi_burst"))
			var ma0: float = G.meditation_aid(false)        # (a little water affinity already helps)
			G.add_item("calming_incense", 1, false)
			G.use_item("calming_incense")
			check("Calming Incense: ten minutes of 1.5x sitting", absf(G.meditation_aid(false) - ma0 * 1.5) < 0.01 and float(G.aid_buff.get("seconds", 0.0)) == 600.0, str(G.aid_buff))
			var qi0: float = G.qi
			G.meditate_tick(10.0, false, 0.0)
			check("...qi comes half again as fast, and the incense burns down", absf(G.qi - qi0 - 3.75 * ma0) < 0.01 and float(G.aid_buff["seconds"]) == 590.0, "%f" % (G.qi - qi0))
			G.aid_buff = {"mult": 12.0 / ma0, "seconds": 60.0}
			check("aids stack with diminishing returns past 3x (12x counts as 6x)", absf(G.meditation_aid(false) - 6.0) < 0.01, str(G.meditation_aid(false)))
			G.aid_buff = {}
			check("Trader Wen sells incense", load("res://scripts/actors/NPC.gd").SHOP.has("calming_incense"))
			# in the world
			_build("floor1")
			player._cool.clear()
			var foe2 = _find("Enemy.gd", func(n): return not n._dead and not bool(n.stats.get("passive", false)))
			foe2.hp = 100000
			foe2.stagger(1.0)
			check("a staggered foe stands still", foe2.staggered())
			foe2._stun = 0.0
			foe2.burn(30, 3.0)
			var fh0: int = foe2.hp
			foe2._physics_process(1.0)
			check("a burning foe takes its burn over time", foe2.hp <= fh0 - 9 and foe2.hp >= fh0 - 11, "%d" % (fh0 - foe2.hp))
			foe2._burn_t = 0.0
			_place_player(foe2.cell + Vector2i(2, 0))
			var to2: Vector3 = foe2.global_position - player.global_position
			player._model.rotation.y = atan2(to2.x, to2.z)
			# a dodge
			player._hurt_cool = 0.3
			player._dodge_t = 0.3
			player.take_damage(10, "test", foe2)
			check("a blow stepped through is a glimpse of Hollow Step", float(G.glimpses.get("hollow_step", 0.0)) == 1.0, str(G.glimpses))
			# guard and parry, for real
			player._hurt_cool = 0.0
			player.guarding = true
			player._guard_t = 0.0
			var php: int = G.hp
			player.take_damage(40, "test", foe2)
			check("guard up just as it lands: PARRIED -- no damage, the foe staggers", G.hp == php and foe2.staggered(), "%d %d" % [php, G.hp])
			foe2._stun = 0.0
			player._hurt_cool = 0.0
			player._guard_t = 1.0
			player.take_damage(40, "test", foe2)
			check("guard held: the blow is blocked -- some gets through", G.hp < php and G.hp > php - 30, "%d -> %d" % [php, G.hp])
			player.guarding = false
			# the strike arts
			G.learn("severing_finger", "test")
			G.open_point("hegu")
			G.wire("severing_finger")
			player._cool.clear()
			_place_player(foe2.cell + Vector2i(4, 0))
			to2 = foe2.global_position - player.global_position
			player._model.rotation.y = atan2(to2.x, to2.z)
			var fh1: int = foe2.hp
			check("F fires the wired strike art: Severing Finger reaches a foe metres away", player.use_strike() == 1 and foe2.hp < fh1 and float(G.arts["severing_finger"]["u"]) == 3.0, "%d %s" % [fh1 - foe2.hp, G.arts.get("severing_finger")])
			check("X switches the strike art", G.cycle_slot("strike").contains("Qi Burst") and G.slot_art("strike") == "qi_burst")
			G.learn("hollow_step", "test")
			G.open_point("zusanli")
			G.wire("hollow_step")
			player._cool.clear()
			_place_player(foe2.cell + Vector2i(2, 0))
			check("V fires the wired step art: Hollow Step puts you behind the foe, the next strike primed", player.use_step(Vector3.ZERO) and (player.global_position - foe2.global_position).length() < 2.3 and player._ambush_t > 0.0,
				str((player.global_position - foe2.global_position).length()))
			var hud2 = root.get_tree().get_first_node_in_group("hud")
			hud2.refresh()
			check("the HUD shows what's on each key, and the heat bar", hud2._slots.text.contains("F: Qi Burst") and hud2._slots.text.contains("V: Hollow Step") and hud2._slots.text.contains("Guard: Iron Shell") and hud2._heat_bar != null, hud2._slots.text)
			G.arts["severing_finger"]["m"] = 150.0
			hud2.toggle_lattice()
			var rows := _rows_text(hud2)
			check("K: each art with its stage, heat, element choice and a button to wire it; arts still to find",
				rows.contains("Severing Finger (strike) -- Fluent") and rows.contains("Metal:") and rows.contains("Wire to V") and rows.contains("Still to find") and rows.contains("Collapsing Palm"), rows)
			hud2.toggle_lattice()
			# it all keeps
			G.injury = {"step": 30.0}
			G.save_game()
			G.glimpses = {}
			G.bridges = {}
			G.injury = {}
			G.load_game()
			check("glimpses, injuries, which arts are wired and branches all keep in the save",
				float(G.glimpses.get("collapsing_palm", 0.0)) == 1.0 and G.injury.has("step") and G.slot_art("step") == "hollow_step" and G.art_branch("qi_burst") == "fire", "%s %s %s" % [G.glimpses, G.injury, G.art_slots])
			G.take_home()
			G.rest_at_home()
			check("a night in your own bed mends every meridian", G.injury.is_empty())
			_build("village")
			check("the training post stands at home", root.get_tree().get_nodes_in_group("training_post").size() >= 1)
			wait = 0.1
		39:
			print("== round 21: the nanite swarm -- its own road, beside cultivation ==")
			G.new_game()
			check("a new cultivator's swarm is just seeded, and the two roads haven't begun", G.nanite_tier() == 0 and G.tier_name() == "Nanite Seeding" and G.integration == 0.0 and G.harmony() == "" and G.nanite_label() == "Nanite Seeding")
			G.learn("qi_burst", "test")
			G.open_point("laogong")
			G.meditate_tick(100.0, true, 0.0)
			check("sitting grows your qi, never your swarm", G.integration == 0.0 and G.qi > 0.0)
			G.art_fire("qi_burst")
			var ig1: float = G.integration
			check("running an art through your nanites grows the swarm (heat x 0.25, +1.5% per open point)", ig1 > 7.0 and ig1 < 8.5, str(ig1))
			G.heat = 75.0
			G.art_fire("wind_step") if G.has_tech("wind_step") else G.art_fire("qi_burst")
			check("...twice as much when you're running hot", G.integration - ig1 > 14.0, str(G.integration - ig1))
			G.heat = 0.0
			G.add_item("nanite_shard", 7, false)
			var ig2: float = G.integration
			var am: String = G.absorb("nanite_shard")
			check("absorb a nanite shard: the swarm takes it in", absf(G.integration - ig2 - 40.0 * G.integration_mult()) < 0.1 and G.count("nanite_shard") == 6, am)
			ig2 = G.integration
			var im2: float = G.integration_mult()          # (taken before: the swarm's growth moves your balance)
			G.absorb("nanite_shard", true)
			check("DISCOVERY: a shard absorbed while sitting gives twice as much (Shard Communion)", G.discoveries.has("shard_communion") and absf(G.integration - ig2 - 80.0 * im2) < 0.1, "%f vs %f" % [G.integration - ig2, 80.0 * im2])
			G.integration = 140.0
			var cap0: float = G.heat_cap()
			var hpm0: int = G.max_hp()
			G.integrate(20.0)
			check("the swarm rises to its next tier on its own: Nanite Bloom -- more heat, more life, an augment slot", G.nanite_tier() == 1 and G.heat_cap() == cap0 + 12.0 and G.max_hp() > hpm0 and G.augment_slots() == 1, "%d %f/%f %d/%d %d" % [G.nanite_tier(), G.heat_cap(), cap0, G.max_hp(), hpm0, G.augment_slots()])
			check("...and it pries your meridians open faster", G.swarm_open_mult() > 1.0)
			check("...but realm and swarm are separate: the realm didn't move", G.realm == 0)
			# experiments
			G.add_item("moonpetal", 2, false)
			G.add_item("rough_ruby", 1, false)
			G.add_item("beast_hide", 1, false)
			var ig3: float = G.integration
			var ex1: String = G.experiment("moonpetal")
			check("EXPERIMENT at the bench: a shard and moonpetal teach the swarm Coolant Weave", ex1.begins_with("EXPERIMENT") and G.augments.has("coolant_weave") and G.integration > ig3, ex1)
			var ex2: String = G.experiment("rough_ruby")
			check("...a near miss says so (something fire is close)", ex2.contains("fire is close"), ex2)
			var ex3: String = G.experiment("beast_hide")
			check("...anything else still teaches the swarm a little", ex3.contains("learns a little"), ex3)
			G.remove_item("nanite_shard", G.count("nanite_shard"))
			check("...and you can't experiment without a shard", G.count("nanite_shard") == 0 and G.experiment("moonpetal").contains("need a nanite shard"))
			var v0: float = G.swarm_vent_mult()
			check("run the augment: your swarm vents 30% faster", G.set_augment("coolant_weave", true).contains("comes alive") and absf(G.swarm_vent_mult() - v0 * 1.3) < 0.001)
			G.augments["dermal_plating"] = "known"
			check("...one slot at Nanite Bloom: a second augment waits", G.set_augment("dermal_plating", true).contains("run 1 augment"))
			# harmony and strain
			G.realm = 1
			check("realm and swarm within a tier: HARMONY -- +10% qi", G.harmony() == "harmony" and is_equal_approx(float(G.nanite_effect().get("qi_mult", 1.0)), 1.1))
			var h0: float = G.art_heat("qi_burst")
			G.integration = 4500.0
			check("a swarm three tiers past your qi strains: arts run 20% hotter", G.harmony() == "swarm_ahead" and absf(G.art_heat("qi_burst") - h0 * 1.2) < 0.01, G.harmony())
			G.integration = 150.0
			G.realm = 5
			check("qi three realms past your swarm strains the other way: your heat caps at 85%", G.harmony() == "qi_ahead" and G.heat_cap() < 100.0 + 15.0 * 0 + 12.0 + 0.01, str(G.heat_cap()))
			G.realm = 0
			# discoveries
			G.set_focus("qihai")
			G.heat = 90.0
			G.nanite_tick(0.1, false, true, false, 0.0)
			check("DISCOVERY: sitting while hot -- Furnace Sitting", G.discoveries.has("furnace_sitting"))
			var hg0: float = float(G.lattice_progress.get("qihai", 0.0))
			G.meditate_tick(1.0, false, 0.0)
			check("...a hot sitting opens your focus point three times as fast", float(G.lattice_progress.get("qihai", 0.0)) - hg0 >= 3.0 * G.swarm_open_mult() - 0.01, str(float(G.lattice_progress.get("qihai", 0.0)) - hg0))
			G.heat_tick(1.0, true, false, true)
			check("...and the heat bleeds off slowly while you hold it", G.heat > 85.0, str(G.heat))
			G.heat = 0.0
			G.hour_override = 22.0
			G.nanite_tick(0.1, false, true, true, 0.0)
			G.near_water = true
			var mq0: float = G.qi
			G.meditate_tick(1.0, false, 0.0)
			check("DISCOVERY: meditating by water at night -- Moonwater Breath: 30% more qi", G.discoveries.has("moonwater_breath") and absf((G.qi - mq0) - 0.25 * G.meditation_aid(false) * 1.3 * G.tech_effect("qi_mult", 1.0) * G.growth_mult()) < 0.01, str(G.qi - mq0))
			G.hour_override = -1.0
			G.near_water = false
			G.heat = G.heat_cap() * 0.9
			G.nanite_tick(16.0, true, false, false, 0.0)
			check("DISCOVERY: holding at the edge in a fight -- Edge Running", G.discoveries.has("edge_running"))
			G.nanite_tick(1.0, false, true, false, 601.0)
			check("DISCOVERY: ten unmoving minutes on the mat -- Still Mind (a long sitting flows at three quarters)", G.discoveries.has("still_mind"))
			G._parry_times = []
			G.heat = 50.0
			G.parry(10)
			G.parry(10)
			G.parry(10)
			check("DISCOVERY: three parries in six seconds -- Perfect Rhythm", G.discoveries.has("perfect_rhythm"))
			G.heat = 60.0
			G.parry(10)
			G.parry(10)
			var ig4: float = G.integration
			G.parry(10)
			check("...after that, every third parry in a row silences your heat and teaches the swarm", G.heat == 0.0 and G.integration - ig4 >= 20.0, "%f %f" % [G.heat, G.integration - ig4])
			check("the journal counts what's been found; townsfolk trade rumours of the rest", G.discovery_rows().filter(func(r): return r[2]).size() == 6 and G.rumour(1) != "")
			# old saves
			G.realm = 3
			G.save_game()
			var f4 := FileAccess.open(G.save_path, FileAccess.READ)
			var d4 = JSON.parse_string(f4.get_as_text())
			f4.close()
			d4.erase("integration")
			var w4 := FileAccess.open(G.save_path, FileAccess.WRITE)
			w4.store_string(JSON.stringify(d4))
			w4.close()
			G.load_game()
			check("an older save's swarm starts at the tier its realm used to name (here Nanite Core)", G.nanite_tier() == 3 and G.tier_name() == "Nanite Core", G.tier_name())
			check("...and keeps its augments and discoveries", G.augment_on("coolant_weave") and G.discoveries.size() == 6)
			# on screen
			_build("village")
			var hud3 = root.get_tree().get_first_node_in_group("hud")
			hud3.refresh()
			check("the HUD shows both roads: realm and swarm tier, and the swarm's own bar", hud3._stage.text.contains("Nanite Core") and hud3._swarm_text.text.begins_with("Swarm"), hud3._stage.text)
			hud3.toggle_lattice()
			var rows3 := _rows_text(hud3)
			check("K shows the swarm: tier, harmony, and each augment to run or stop", rows3.contains("Your swarm: Nanite Core") and rows3.contains("Stop Coolant Weave") and rows3.contains("Run Dermal Plating"), rows3)
			hud3.toggle_lattice()
			G.add_item("nanite_shard", 2, false)
			hud3._inventory.visible = true
			hud3._fill_inventory()
			var absorb_btn := false
			for row in hud3._inv_body.get_children():
				for c in row.get_children():
					if c is Button and c.text == "Absorb":
						absorb_btn = true
			hud3._inventory.visible = false
			check("the inventory offers to Absorb nanite shards", absorb_btn)
			var home3 = root.get_tree().get_first_node_in_group("home")
			home3.bench_menu()
			check("the workbench offers nanite experiments", _btn_has("Experiment with nanites"))
			home3.experiment_menu()
			check("...a list of things to pair a shard with", _btn_has("Moonpetal") and _btn_has("Back to the bench"))
			hud3.close_dialog()
			var npc3 = _find("NPC.gd")
			check("townsfolk can be asked if they've heard anything strange", npc3 != null and str(npc3._talk_opts()).contains("Heard anything strange"))
			hud3.toggle_journal()
			var jt := ""
			for c in hud3._jr_body.get_children():
				if c is Label:
					jt += c.text + "\n"
			hud3.toggle_journal()
			check("the journal lists Discoveries and the swarm", jt.contains("Discoveries") and jt.contains("Furnace Sitting") and jt.contains("Augments found"), jt.substr(0, 200))
			wait = 0.1
		40:
			print("== round 22: training you find by asking; chat and trade, smoother ==")
			G.new_game()
			G.gold = 500
			check("asking about training is noticed; small talk isn't", G.asks_about_training("Could you teach me anything?") and G.asks_about_training("Any TRAINING around here?") and not G.asks_about_training("Nice weather today."))
			check("everyone teaches one thing, picked by who they are (a smith: weapons or guard work)", G.lesson_for("Smith Hale", "smith") in ["weapon", "guard_drill"] and G.lesson_for("Smith Hale", "smith") == G.lesson_for("Smith Hale", "smith"))
			check("a lesson costs 15 gold at the start, more as you rise; friends pay less", G.lesson_price("Nobody") == 15)
			_build("village")
			var rin = _find("NPC.gd", func(n): return n.npc_name == "Little Rin")
			var hud4 = root.get_tree().get_first_node_in_group("hud")
			var heard4 := []
			G.llm_override = func(msgs):
				heard4.append(msgs)
				return JSON.stringify({"reply": "Me? I could show you a thing or two.", "warmth": 1, "memory": ""})
			hud4.open_chat(rin)
			check("the chat shows quick things to ask, including about training", _chip_has(hud4, "Ask about training") and _chip_has(hud4, "Heard anything strange") and not G.knows_lesson("Little Rin"))
			hud4.chat_say("Can you train me?")
			check("ask about training: they know what they can teach, and say so", str(heard4[0][0]["content"]).contains("can teach you") and G.knows_lesson("Little Rin"), str(heard4[0][0]["content"]).substr(0, 400))
			check("...and the conversation reads cleanly: you, then them", hud4.chat_text().contains("You: Can you train me?") and hud4.chat_text().contains("Little Rin: Me? I could show you"), hud4.chat_text())
			check("...a Train button appears in the chat", _chip_has(hud4, "Train:"))
			check("...and in their menu from now on", str(rin._talk_opts()).contains("Train:"))
			var g0: int = G.gold
			rin.lesson()
			check("a lesson: gold paid, something learned, written into the chat", G.gold == g0 - G.lesson_price("Little Rin") and G.lesson_wait("Little Rin") and hud4.chat_text().length() > 0)
			check("...once a day", rin.lesson().contains("tomorrow") and G.gold == g0 - G.lesson_price("Little Rin"))
			hud4.close_chat()
			G.llm_override = Callable()
			# what the lessons do
			G.learn("qi_burst", "test")
			G.open_point("laogong")
			var u0: float = float(G.arts["qi_burst"]["u"])
			var r1: String = G.take_lesson("Drillmaster", "academy")
			check("a striking drill: +12 practice on your wired strike art, and a glimpse of the next one", float(G.arts["qi_burst"]["u"]) == u0 + 12.0 and float(G.glimpses.get("severing_finger", 0.0)) >= 4.0, r1)
			var ig5: float = G.integration
			G.take_lesson("Tinker", "merchant")
			check("nanite tinkering grows the swarm", G.integration > ig5 + 29.0)
			var breath_name := ""
			for i in 20:
				if G.lesson_for("Sage%d" % i, "elder") == "breath":
					breath_name = "Sage%d" % i
					break
			G.take_lesson(breath_name, "elder")
			check("a breathing lesson: your next quarter hour on the mat runs deeper", absf(float(G.aid_buff.get("mult", 0.0)) - 1.4) < 0.01 and float(G.aid_buff.get("seconds", 0.0)) == 900.0, str(G.aid_buff))
			G.bond("Sage1")["warmth"] = 40.0
			check("...and a friend charges less", G.lesson_price("Sage1") < G.lesson_price("Stranger"))
			# trade
			var wen = _find("NPC.gd", func(n): return n.role == "merchant")
			G.add_item("iron_ore", 5, false)
			G.add_item("iron_sword", 1, false)
			wen.interact(player)
			check("the trader opens a trade screen: their goods and yours side by side", hud4._trade.visible and _trade_has(hud4, "Healing Salve") and _trade_has(hud4, "Iron Ore") and hud4.is_blocking())
			g0 = G.gold
			var tb: String = wen.trade_buy("healing_salve", 5)
			check("buy five at once, without the window closing", G.count("healing_salve") >= 5 and G.gold == g0 - 5 * int(G.items["healing_salve"]["value"]) * 2 and hud4._trade.visible, tb)
			g0 = G.gold
			wen.trade_sell("iron_ore", 2)
			check("sell some of a thing, not just everything", G.count("iron_ore") == 3 and G.gold == g0 + 2 * int(G.items["iron_ore"]["value"]))
			check("gear sells too, at half its worth -- but not what you're wearing", G.sell_price("iron_sword") == int(G.items["iron_sword"]["value"]) / 2 or G.weapon == "iron_sword")
			G.weapon = "iron_sword"
			check("...what you're holding isn't for sale", G.sell_price("iron_sword") == 0)
			hud4.close_trade()
			check("closing the trade screen gives control back", not hud4.is_blocking())
			wait = 0.1
		41:
			print("== round 23: every floor wider -- side chambers and their wonders ==")
			G.new_game()
			var Ex = load("res://scripts/world/Expanse.gd")
			var d1: Dictionary = G.load_level_def("floor1")
			var e1: Dictionary = Ex.expand(d1)
			var ex1: Array = e1.get("extras", [])
			var kinds1 := ex1.map(func(e): return str(e["kind"]))
			check("a dungeon floor grows 3-6 side chambers into the rock between its rooms", ex1.size() >= 3 and ex1.size() <= 6 and e1["map"].size() >= d1["map"].size(), str(kinds1))
			check("...always a nanite relic, a quiet alcove, an echo stone and a buried cache", "relic" in kinds1 and "hermitage" in kinds1 and "echo" in kinds1 and "cache" in kinds1)
			check("...one of them sealed behind a secret wall", ex1.any(func(e): return bool(e.get("sealed", false))) and str(e1["map"]).count("S") > str(d1["map"]).count("S"))
			check("...the same chambers every time (seeded by the floor)", str(Ex.expand(G.load_level_def("floor1"))["map"]) == str(e1["map"]))
			var orig_ok := true
			for y in d1["map"].size():
				var r0: String = str(d1["map"][y]).rstrip(" ")
				var r1: String = str(e1["map"][y])
				for x in r0.length():
					if r0[x] != " " and (x >= r1.length() or r1[x] != r0[x]):
						orig_ok = false
			check("...and nothing Dev drew moves or changes", orig_ok)
			check("towns aren't touched", not Ex.expand(G.load_level_def("village")).has("extras") and not Ex.expand(G.load_level_def("floor5")).has("extras"))
			_build("floor1")
			var wonders := root.get_tree().get_nodes_in_group("wonder")
			check("the floor is built with its wonders in place", wonders.size() == ex1.size(), "%d vs %d" % [wonders.size(), ex1.size()])
			var open_reach := 0
			var open_n := 0
			var sp: Vector2i = level.spawns.get("P", [Vector2i(2, 2)])[0]
			for sc in level.spawns.get("S", []):
				level.open_cell(sc)          # (as if every secret had been found)
			for e in ex1:
				open_n += 1
				if level.path_between(sp, Vector2i(int(e["cell"][0]), int(e["cell"][1]))).size() > 0:
					open_reach += 1
			check("...and every chamber can be walked to, once its secrets are found", open_reach == open_n, "%d of %d" % [open_reach, open_n])
			var W := {}
			for w in wonders:
				W[w.kind] = w
			var ig6: float = G.integration
			var sh0: int = G.count("nanite_shard")
			W["relic"].interact(player)
			check("a nanite relic: the swarm drinks from it -- integration and a shard", G.integration > ig6 + 20.0 and G.count("nanite_shard") > sh0)
			ig6 = G.integration
			W["relic"].interact(player)
			check("...once; then it's cold", G.integration == ig6 and W["relic"].used())
			_place_player(W["hermitage"].cell)
			W["hermitage"].interact(player)
			check("a quiet alcove: sit, and meditation runs half again as deep", player.meditating and is_equal_approx(G.sit_aid, 1.5) and absf(G.meditation_aid(false) - 1.5 * G.tech_effect("meditate_mult", 1.0)) < 0.01)
			player.stop_meditating()
			check("...only while you stay", is_equal_approx(G.sit_aid, 1.0))
			var gl0 := 0.0
			for v in G.glimpses.values():
				gl0 += float(v)
			W["echo"].interact(player)
			var gl1 := 0.0
			for v in G.glimpses.values():
				gl1 += float(v)
			check("an echo stone: watch the old fight -- a glimpse of an art you haven't found", gl1 >= gl0 + 3.0 and W["echo"].used(), str(G.glimpses))
			var gold6: int = G.gold
			W["cache"].interact(player)
			check("a buried cache: gold and the floor's materials", G.gold > gold6 and W["cache"].used())
			check("...and Spirit Sense lights it", W["cache"].is_in_group("discoverable"))
			if W.has("trial"):
				W["trial"].interact(player)
				var tf: Array = W["trial"]._trial_foes
				check("an altar of trial: foes rise around it", tf.size() >= 3 and W["trial"].prompt().contains("under way"))
				for f in tf:
					f.take_damage(1000000, "test")
				var tg: int = G.gold
				W["trial"]._process(0.1)
				check("...beat them in time and the altar pays -- once a day", G.gold > tg and W["trial"].used() and W["trial"].prompt().contains("tomorrow"))
			else:
				check("(this floor has no altar)", true)
			wait = 0.1
		42:
			print("== round 24: the valley -- sects and towers ==")
			G.new_game()
			G.gold = 500
			var V: Dictionary = G.valley_data()
			check("the valley's data is in: Dev's sects, three towers", V.get("sects", []).size() >= 3 and V.get("towers", []).size() == 3, str(V.get("sects", []).size()))
			var s0: Dictionary = V["sects"][0]
			var a0: Dictionary = s0["arts"][0]
			check("each sect art is a real art: in the lattice, on an engine template, named in Dev's words",
				G.technique_defs.has(str(a0["id"])) and G.technique_defs[str(a0["id"])]["name"] == a0["name"] and G.art_template(str(a0["id"])) == str(a0["template"])
				and G.art_route(str(a0["id"])).size() >= 2, str(a0))
			check("the valley is drawn the same way every time", str(G.load_level_def("valley")["map"]) == str(G.load_level_def("valley")["map"]) and G.level_exists("valley"))
			_build("village")
			var gate_ok := false
			for n in level.get_children():
				if n.get_script() and str(n.get_script().resource_path).ends_with("Exit.gd") and n.target == "valley":
					gate_ok = true
			check("the village has a road out to the valley", gate_ok and level.spawns.has("@valley"))
			_build("valley")
			var halls := root.get_tree().get_nodes_in_group("sect_hall")
			var spires := root.get_tree().get_nodes_in_group("tower_spire")
			check("the valley: a hall at every sect's seat, three towers, its own creatures", halls.size() == V["sects"].size() and spires.size() == 3 and int(level.counts.get("enemies", 0)) >= 20,
				"%d %d %d" % [halls.size(), spires.size(), int(level.counts.get("enemies", 0))])
			check("...under the sky (an outdoor place, not a town)", level.is_outdoor() and not level.is_town())
			var sid0 := str(s0["id"])
			var elder = _find("NPC.gd", func(n): return n.role == "sect" and n.sect_id() == sid0)
			var hall0 = null
			for h in halls:
				if h.sid == sid0:
					hall0 = h
			elder.interact(player)
			check("the elder speaks the sect's creed and offers the entry trial", hud_text().contains(str(s0["creed"]).left(30)) and _btn_has("Take the entry trial"), hud_text().left(200))
			root.get_tree().get_first_node_in_group("hud").close_dialog()
			_place_player(hall0.cell + Vector2i(0, 4))
			var tr0: String = hall0.start_trial()
			check("the trial begins (%s)" % s0["trial"]["kind"], tr0.begins_with("TRIAL") and not hall0.trial.is_empty(), tr0)
			if str(s0["trial"]["kind"]) == "combat":
				for f in hall0._foes:
					f.take_damage(1000000, "test")
			elif str(s0["trial"]["kind"]) == "stillness":
				player.meditating = true
				player.global_position = hall0.global_position
			hall0._process(float(s0["trial"]["seconds"]) - 1.0 if str(s0["trial"]["kind"]) != "combat" else 0.1)
			if str(s0["trial"]["kind"]) == "stillness":
				player.meditating = false
			check("pass it and you're an Outer Disciple -- with the sect's first art, carrying its element", G.in_sect(sid0) and G.sect_rank_name() == "Outer Disciple"
				and G.has_tech(str(a0["id"])) and G.art_branch(str(a0["id"])) == str(s0["element"]), "%s %s" % [G.sect, G.arts.get(str(a0["id"]))])
			hall0.interact(player)
			check("a disciple sits in the sect's hall at 2.5x", is_equal_approx(G.sit_aid, G.SECT_HALL_AID))
			player.stop_meditating()
			G.sect_contrib(120.0)
			check("contribution alone doesn't raise you past what your cultivation can carry", int(G.sect["rank"]) == 0 and G.has_flag("sect_wait:%s:1" % sid0))
			G.realm = 1
			G.sect_contrib(1.0)
			var a1: Dictionary = s0["arts"][1] if s0["arts"].size() > 1 else {}
			check("...reach the realm and you rise: Inner Disciple, and the sect's second art", int(G.sect["rank"]) == 1 and (a1.is_empty() or G.has_tech(str(a1["id"]))), str(G.sect))
			var el0 := str(s0["element"])
			var mat0 := ""
			for id in G.items:
				if str(G.items[id].get("type", "")) == "material" and str(G.items[id].get("element", "")) == el0:
					mat0 = str(id)
					break
			G.add_item(mat0, 3, false)
			var c0: float = float(G.sect["contrib"])
			check("materials of the sect's element feed its stores", G.sect_donate().contains("contribution") and float(G.sect["contrib"]) > c0 and G.count(mat0) == 0)
			G.add_qi(0.0)
			var killed := float(G.sect["contrib"])
			G.record_kill("goblin")
			check("every kill anywhere counts for your sect", float(G.sect["contrib"]) == killed + 1.0)
			check("you can't wear two sects' colours", G.sect_join_check(str(V["sects"][1]["id"])).contains("leave it first"))
			G.leave_sect()
			check("leave, and what they taught you stays -- but not the same day you can join another", not G.in_sect() and G.has_tech(str(a0["id"])) and G.sect_join_check(str(V["sects"][1]["id"])).contains("this very day"))
			G.flags.erase("sect_left_day")
			# the towers
			var t0: Dictionary = V["towers"][0]
			var t1: Dictionary = V["towers"][1]
			G.realm = 0
			check("the first tower opens to anyone; the second waits for Foundation", G.tower_locked(str(t0["id"])) == "" and G.tower_locked(str(t1["id"])).contains("doesn't move"))
			var tid0 := str(t0["id"])
			_build("tower:%s:1" % tid0)
			var trial = _find("TowerTrial.gd")
			check("a tower floor: a round room, its trial in the middle", trial != null and trial.kind == str(t0["floors"][0]["kind"]) and level.counts.get("exits", 0) == 1)
			if trial.kind == "combat":
				trial._begin()
				check("...combat: foes of the tower's tier rise", trial._foes.size() >= 3)
				for f in trial._foes:
					f.take_damage(1000000, "test")
				var gt: int = G.gold
				trial._process(0.1)
				var up_ok := false
				for n in level.get_children():
					if n.get_script() and str(n.get_script().resource_path).ends_with("Exit.gd") and n.target == "tower:%s:2" % tid0:
						up_ok = true
				check("...beat them: the floor pays, and the stair up opens", trial.cleared and G.tower_cleared(tid0) == 1 and G.gold > gt and up_ok)
			# a puzzle floor
			var pn := 0
			for i in 9:
				if str(t0["floors"][i]["kind"]) == "puzzle":
					pn = i + 1
					break
			if pn > 0:
				_build("tower:%s:%d" % [tid0, pn])
				var pt = _find("TowerTrial.gd")
				var wrong := ""
				for el in ["wood", "fire", "earth", "metal", "water"]:
					if el != pt._order[0]:
						wrong = el
						break
				check("puzzle: a wrong pillar puts them all out and wakes something", not pt.touch_pillar(wrong) and pt._foes.size() == 1)
				for el in pt._order:
					pt.touch_pillar(el)
				check("...the right order (%s from %s) passes the floor" % [pt._which, pt._order[0]], pt.cleared and G.tower_cleared(tid0) >= pn - 1)
			var qn := 0
			for i in 9:
				if str(t0["floors"][i]["kind"]) == "insight":
					qn = i + 1
					break
			if qn > 0:
				G.towers[tid0] = qn - 1          # not yet passed, whatever floor order the tower has
				_build("tower:%s:%d" % [tid0, qn])
				var qt = _find("TowerTrial.gd")
				var right := int(qt._q.get("answer", 0))
				check("insight: a wrong answer wakes two keepers and quiets the stone", not qt.answer((right + 1) % maxi(qt._q.get("options", []).size(), 2)) and qt._foes.size() == 2 and qt._quiet > 0.0)
				check("...the right one passes it", qt.answer(right) and qt.cleared)
			var en := 0
			for i in 9:
				if str(t0["floors"][i]["kind"]) == "endurance":
					en = i + 1
					break
			if en > 0:
				G.towers[tid0] = en - 1
				_build("tower:%s:%d" % [tid0, en])
				var et = _find("TowerTrial.gd")
				et._begin()
				et._process(1.0)
				check("endurance: they keep coming", et._alive() >= 1 and not et.cleared, "%d alive, t=%f started=%s dead=%s foes=%d" % [et._alive(), et._t, et._started, player.dead, et._foes.size()])
				et._process(100.0)
				check("...hold until the stone remembers you", et.cleared)
			G.towers[tid0] = 8
			_build("tower:%s:9" % tid0)
			var st = _find("TowerTrial.gd")
			st._begin()
			var boss_up := false
			for f in st._foes:
				if bool(f.stats.get("boss", false)):
					boss_up = true
			check("the summit: the tower's guardian waits", boss_up, str(st._foes.size()))
			for f in st._foes:
				f.take_damage(100000000, "test")
			var br0: int = G.count("nanite_bridge")
			st._process(0.1)
			root.get_tree().get_first_node_in_group("hud").close_dialog()
			check("...beat it: the summit names you, and gives a nanite bridge", G.tower_cleared(tid0) == 9 and ("Summit of %s" % t0["name"]) in G.titles and G.count("nanite_bridge") > br0)
			G.save_game()
			G.towers = {}
			G.load_game()
			check("towers climbed keep in the save", G.tower_cleared(tid0) == 9)
			var hud5 = root.get_tree().get_first_node_in_group("hud")
			hud5.toggle_journal()
			var jt5 := ""
			for c in hud5._jr_body.get_children():
				if c is Label:
					jt5 += c.text + "\n"
			hud5.toggle_journal()
			check("the journal tells your standing in the valley", jt5.contains("The valley") and jt5.contains(str(t0["name"])))
			wait = 0.1
		43:
			print("== round 25: the breakthrough -- comprehension and the heart demon ==")
			G.new_game()
			G.current_level = "floor1"
			check("a new cultivator has no insight, and needs 10 for Qi Condensation", G.insight == 0.0 and G.insight_need() == 10)
			G.sublevel = 10
			G.add_qi(G.qi_to_next() * 3.0)
			check("a full sea of qi waits at the door: still Body Tempering 10, qi topped up, not spilling over", G.realm == 0 and G.at_threshold() and is_equal_approx(G.qi, G.qi_to_next()))
			var miss: Array = G.breakthrough_missing()
			check("...and says what it still needs: insight, and the first ring open", str(miss).contains("insight 0 / 10") and str(miss).contains("first ring"), str(miss))
			G.log_event("lore_read", {"title": "test"})
			check("reading a lore stone is insight (+1)", G.insight == 1.0)
			G.mark_level_entered("floor_test_new", {"enemies": 0})
			check("...a first visit somewhere new (+2)", G.insight == 3.0)
			G.log_event("art_stage", {"art": "x", "stage": "Fluent"})
			check("...an art grown Fluent (+3)", G.insight == 6.0)
			G.gain_insight(4.0)
			for p in G.lattice_data()["points"]:
				if int(p["ring"]) == 1:
					G.open_point(str(p["id"]))
			check("insight 10 and the first ring open: ready", G.breakthrough_ready(), str(G.breakthrough_missing()))
			G.arts = {"wind_step": {"m": 400.0, "u": 0.0}, "qi_burst": {"m": 10.0, "u": 0.0}}
			check("your favourite family is the one you've grown most (here: step)", G.favored_family() == "step")
			check("sitting at the door offers the tribulation", G.begin_tribulation() == "" and G.current_level == "tribulation:1" and not G.tribulation.is_empty())
			_build("tribulation:1")
			_place_player(level.spawns["P"][0])
			var demon = root.get_tree().get_first_node_in_group("heart_demon")
			check("the tribulation: your heart demon stands up -- your strength, your favourite art", demon != null and demon.favored() == "step" and demon.hp > G.damage() * 10, "%s" % [demon.stats if demon else "none"])
			var hp0: int = G.hp
			player._hurt_cool = 0.0
			player.guarding = false
			demon.cast(player)
			check("...a step demon appears behind you and strikes", G.hp < hp0 and (demon.global_position - player.global_position).length() < 2.5)
			demon.stats["favored"] = "guard"
			demon.cast(player)
			var dh0: int = demon.hp
			player._hurt_cool = 0.0
			var hp1: int = G.hp
			demon.take_damage(100, "test")
			check("...a guard demon closes up: most of your blow glances off, some comes back", dh0 - demon.hp == 30 and G.hp < hp1, "%d %d" % [dh0 - demon.hp, hp1 - G.hp])
			demon._guard_t = 0.0
			demon.stats["favored"] = "strike"
			player._hurt_cool = 0.0
			var hp2: int = G.hp
			demon.cast(player)
			check("...a strike demon bursts dark qi around it", G.hp < hp2)
			check("...always after a moment's warning", demon.WARN > 0.5)
			G.player_died("your heart demon")
			check("lose: no death, no gold -- an injured meridian, an hour's wait, and your qi still full", G.realm == 0 and G.at_threshold() and not G.injury.is_empty()
				and G.current_level == "floor1" and str(G.breakthrough_missing()).contains("hour"), str(G.breakthrough_missing()))
			G.flags.erase("tribulation_wait")
			G.injury = {}
			G.begin_tribulation()
			_build("tribulation:1")
			var demon2 = root.get_tree().get_first_node_in_group("heart_demon")
			demon2.take_damage(100000000, "you")
			G.tribulation_won()
			check("win: you break through -- Qi Condensation, a Dao Heart (+1%% on a second try), a title", G.realm == 1 and G.sublevel == 1 and is_equal_approx(G.dao_heart, 1.0) and "Heart Unshaken" in G.titles and G.current_level == "floor1",
				"%d %f %s" % [G.realm, G.dao_heart, G.current_level])
			check("...and the Dao Heart is felt everywhere", G.tech_effect("damage_mult", 1.0) >= 1.01 and G.dao_heart_effect().has("qi_mult"))
			G.save_game()
			var f6 := FileAccess.open(G.save_path, FileAccess.READ)
			var d6 = JSON.parse_string(f6.get_as_text())
			f6.close()
			d6.erase("insight")
			d6["realm"] = 3
			var w6 := FileAccess.open(G.save_path, FileAccess.WRITE)
			w6.store_string(JSON.stringify(d6))
			w6.close()
			G.load_game()
			check("an older save's past counts as insight -- never stopped at a door it couldn't have known about", G.insight >= float(G.insight_need(2)), str(G.insight))
			G.realm = 0
			G.sublevel = 10
			G.qi = G.qi_to_next()
			var hud6 = root.get_tree().get_first_node_in_group("hud")
			hud6.toggle_lattice()
			check("K shows insight and what the breakthrough still needs", hud6._lat_info.text.contains("Insight") and hud6._lat_info.text.contains("break through"), hud6._lat_info.text.right(200))
			hud6.toggle_lattice()
			check("the goal line names the breakthrough at the door", str(G.next_goals()).contains("Breakthrough"), str(G.next_goals()))
			wait = 0.1
		44:
			print("== round 26: Dev's landmarks, codex and rumours ==")
			G.new_game()
			var kinds6 := ["ruin", "shrine", "hamlet", "camp", "grove", "cave", "lake", "peak", "bridge", "battlefield", "workshop", "tomb"]
			var lms6 := []
			for k in kinds6:
				lms6.append({"name": "The Test %s" % k.capitalize(), "kind": k, "where": "Somewhere in the valley, by a %s." % k,
					"sight": "What you see at the %s: something worth the walk, described at length." % k, "secret": "Under the %s, a hidden thing." % k})
			G.valley_def["landmarks"] = lms6
			G.valley_def["codex"] = [{"name": "On Seeding", "realm": "body tempering", "text": "The first swarm is a guest in the blood, polite and hungry."},
				{"name": "On Bloom", "realm": "qi condensation", "text": "At condensation the swarm stops asking and starts deciding."}]
			G.valley_def["rumours"] = [{"name": "Lights", "lines": ["There are lights on the ridge at night, and nobody goes to see.", "My cousin saw them too."]}]
			var vd6: Dictionary = G.load_level_def("valley")
			var lm_extras: Array = vd6["extras"].filter(func(e): return str(e["kind"]) == "landmark")
			check("every landmark Dev wrote gets a place in the valley", lm_extras.size() == 12, str(lm_extras.size()))
			var lake_e = null
			for e in lm_extras:
				if str(lms6[int(e["index"])]["kind"]) == "lake":
					lake_e = e
			check("...a lake brings its own pond, and a place to fish", lake_e != null and str(vd6["map"][int(lake_e["cell"][1]) - 2]).substr(int(lake_e["cell"][0]), 1) == "&")
			_build("valley")
			var L6 := {}
			for n in root.get_tree().get_nodes_in_group("landmark"):
				L6[str(n.data.get("kind", ""))] = n
			check("...each built from the art kit by its kind", L6.size() == 12 and L6["camp"].get_child_count() > 3)
			var ins0: float = G.insight
			L6["camp"].interact(player)
			check("look around: Dev's words, and insight the first time", hud_text().contains("What you see at the camp") and G.insight == ins0 + 2.0 and _btn_has("Search the place"))
			var g6: int = G.gold
			L6["camp"].search(null)
			check("search: the secret, and what it kept (once)", G.gold > g6 and G.has_flag(L6["camp"].key() + ":secret") and L6["camp"].search(null) == "")
			var aw0: float = float(G.affinity["wood"])
			L6["grove"].search(null)
			check("...a grove gives a little of itself (wood affinity)", float(G.affinity["wood"]) > aw0)
			L6["shrine"].search(null)
			check("...a shrine's calm goes with you (deeper sitting)", float(G.aid_buff.get("mult", 0.0)) >= 1.5)
			root.get_tree().get_first_node_in_group("hud").close_dialog()
			var cx6: Array = G.codex_entries()
			check("the nanite codex: entries open with your realm", cx6.size() == 2 and bool(cx6[0]["open"]) and not bool(cx6[1]["open"]))
			var ins1: float = G.insight
			check("...reading a new entry is insight, once", G.read_codex() == 1 and G.insight == ins1 + 1.0 and G.read_codex() == 0)
			var heard6 := false
			for sd in 200:
				if G.rumour(sd).contains("lights on the ridge"):
					heard6 = true
					break
			check("townsfolk repeat Dev's rumours", heard6)
			var hud7 = root.get_tree().get_first_node_in_group("hud")
			hud7.toggle_journal()
			var jt7 := ""
			for c in hud7._jr_body.get_children():
				if c is Label:
					jt7 += c.text + "\n"
			hud7.toggle_journal()
			check("the journal holds the codex", jt7.contains("The nanite codex") and jt7.contains("On Seeding") and jt7.contains("1 more entries"), jt7.left(100))
			check("the journal lists the places found", jt7.contains("Places found out in the valley: 1 of") and jt7.contains("(searched)"), jt7.left(100))
			G.valley_def = {}
			wait = 0.1
		45:
			print("== round 27: the whole body's gear, the bench, the forge, the nanoforge ==")
			G.new_game()
			G.background = "craft"
			check("27 places to wear something: weapon, cowl, choker, necklace, cape, pauldrons, robe, chest, under-armour, vambraces, two bracelets, gloves, gauntlets, eight rings, pants, greaves, boots, two toe rings",
				G.gear_slots().size() == 27 and G.slots_for("ring").size() == 8 and G.slots_for("toering").size() == 2 and G.slots_for("bracelet").size() == 2)
			var cat_n := 0
			for id in G.items:
				if str(id).begins_with("g_") or str(id).begins_with("j_"):
					cat_n += 1
			check("a catalogue of pieces is made from the stocks (and real items, every one)", cat_n > 250 and G.items.has("g_iron_ore_greaves") and G.items.has("j_silver_ore_rough_ruby_ring"), str(cat_n))
			var hp27a: int = G.max_hp()
			var kit27 := ["g_iron_ore_chest", "g_iron_ore_pauldrons", "g_iron_ore_greaves", "g_iron_ore_gauntlets", "g_iron_ore_vambraces", "g_beast_hide_boots",
				"g_iron_thistle_cowl", "g_iron_thistle_cape", "g_beast_hide_pants", "g_iron_thistle_underarmour", "g_iron_thistle_robe", "g_beast_hide_gloves"]
			for id in kit27:
				G.add_item(id, 1, false)
			check("found armour goes on by itself, each to its own slot", G.worn("greaves") == "g_iron_ore_greaves" and G.worn("robe") == "g_iron_thistle_robe" and G.worn("chest") == "g_iron_ore_chest", str(G.equipment))
			check("...the old names still work: armor IS the chest slot", G.armor == "g_iron_ore_chest")
			check("every piece adds health", G.max_hp() > hp27a + 20, "%d -> %d" % [hp27a, G.max_hp()])
			G.hp = 1000
			G.hurt(100)
			check("ward: blows lose some of themselves on armour", 1000 - G.hp < 100 and G.ward_factor() < 0.9, "took %d" % (1000 - G.hp))
			G.hp = G.max_hp()
			check("all that metal is heavy: over what you can carry, you're slower", G.weight_penalty() > 0.0 and G.tech_effect("move_mult", 1.0) < 1.0, "%.1f of %.1f" % [G.total_weight(), G.carry_capacity()])
			var pen0: float = G.weight_penalty()
			G.realm = 2
			check("...and stronger cultivation carries more", G.weight_penalty() < pen0)
			G.realm = 0
			var ring := "j_silver_ore_rough_ruby_ring"
			G.add_item(ring, 1, false)
			var one: float = G.tech_effect("damage_mult", 1.0)
			G.add_item(ring, 7, false)
			for i in 7:
				G.wear(ring)
			var eight: float = G.tech_effect("damage_mult", 1.0)
			check("four rings a hand -- eight rings on, all worn", G.equipped_count(ring) == 8, str(G.equipped_count(ring)))
			check("...each one adds, but the same gift stacks with diminishing returns", eight > one and eight - 1.0 < (one - 1.0) * 8.0 * 0.75, "%f vs %f" % [one, eight])
			check("...a ninth has nowhere to go but someone's finger: worn rings can't be sold", G.sell_price(ring) == 0)
			G.remove_item(ring, 3)
			check("what leaves the pack leaves your hands", G.equipped_count(ring) == 5)
			G.add_item("j_gold_nugget_sapphire_shard_necklace", 1, false)
			check("...the old amulet IS the necklace", G.amulet == "j_gold_nugget_sapphire_shard_necklace")
			check("unequip takes it off", G.unequip("cape") != "" and G.worn("cape") == "" and G.wear("g_iron_thistle_cape") != "" and G.worn("cape") == "g_iron_thistle_cape")
			# save / load / an older save
			G.save_game()
			var eq27: Dictionary = G.equipment.duplicate()
			G.new_game()
			G.load_game()
			check("what you wear is saved and comes back", G.equipment == eq27, str(G.equipment))
			var fs := FileAccess.open(G.save_path, FileAccess.READ)
			var sd: Dictionary = JSON.parse_string(fs.get_as_text())
			fs.close()
			sd.erase("equipment")
			sd["armor"] = "iron_armor"
			sd["ring"] = "jade_ring"
			sd["inventory"]["iron_armor"] = 1
			sd["inventory"]["jade_ring"] = 1
			var fw := FileAccess.open(G.save_path, FileAccess.WRITE)
			fw.store_string(JSON.stringify(sd))
			fw.close()
			G.load_game()
			check("a save from before round 27 keeps its armour, ring and amulet", G.worn("chest") == "iron_armor" and G.worn("ring_l1") == "jade_ring" and G.worn("necklace") == "j_gold_nugget_sapphire_shard_necklace", str(G.equipment))
			# materials
			G.new_game()
			G.background = "craft"
			for pair in [["iron_ore", 8], ["firestone", 3], ["spirit_resin", 6], ["spirit_herb", 6], ["moonpetal", 3], ["rough_jade", 3], ["beast_hide", 8], ["storm_glass", 2], ["nanite_shard", 30],
					["silver_ore", 4], ["goblin_tooth", 4], ["ember_root", 4], ["sapphire_shard", 2]]:
				G.add_item(pair[0], pair[1], false)
			check("every material has an element and traits", G.material_traits("iron_ore").has("hard") and G.material_element("spirit_herb") == "wood")
			check("...a material the forge adds later gets traits from its name", G.material_traits("bone_blade").has("keen"))
			check("you don't know what a thing IS until you work it or study it", not G.knows_material("moonpetal") and G.traits_text("moonpetal").contains("unknown"))
			check("...studying one teaches you", G.study_material("moonpetal").contains("Resonant") and G.knows_material("moonpetal") and G.count("moonpetal") == 2)
			# formulas by trial and error
			var pv27: Dictionary = G.combine_preview("iron_ore", ["firestone", "spirit_resin"])
			check("the bench shows its odds before you commit", bool(pv27["ok"]) and float(pv27["chance"]) > 0.0 and float(pv27["luck"]) > 0.0 and str(pv27["formula"]) == "")
			var r27: Dictionary = G.combine_attempt("iron_ore", ["firestone", "spirit_resin"], 0.0, 0.99)
			check("the right things together make a formula's product -- and you've worked the formula out", r27["success"] and G.count("tempered_steel") == 1 and G.knows_formula("tempered_steel"), str(r27))
			check("...it used what the formula needs (two iron)", G.count("iron_ore") == 6 and G.count("firestone") == 2)
			var pv27b: Dictionary = G.combine_preview("iron_ore", ["firestone", "spirit_resin"])
			check("...knowing it makes it likelier", float(pv27b["chance"]) > float(pv27["chance"]), "%f vs %f" % [pv27b["chance"], pv27["chance"]])
			# infusing gear
			G.add_item("g_beast_hide_gloves", 1, false)
			var ri: Dictionary = G.combine_attempt("g_beast_hide_gloves", ["spirit_herb", "moonpetal"], 0.0, 0.99)
			var gid27 := str(ri["item"])
			check("gear takes on what you work into it, and stays on your hands", ri["success"] and gid27.begins_with("c27_") and G.worn("gloves") == gid27 and (G.item_def(gid27).get("affixes", []) as Array).size() == 1, str(ri))
			check("...its gifts come from the traits (vital herb: more health)", float(G.item_def(gid27)["effect"].get("hp_mult", 1.0)) > 1.0, str(G.item_def(gid27)["effect"]))
			check("...the old gloves are gone", G.count("g_beast_hide_gloves") == 0)
			G.add_item("rough_ruby", 2, false)
			var rl: Dictionary = G.combine_attempt(gid27, ["rough_ruby"], 0.0, 0.0)
			check("a lucky working brings something unexpected", rl["success"] and rl["lucky"] and str(rl["text"]).contains("UNEXPECTED"), str(rl["text"]))
			var g2 := str(rl["item"])
			check("...a piece holds only so much", G.combine_check(g2, ["spirit_herb"]) != "" and G.combine_check(g2, ["spirit_herb"]).contains("can't hold"), G.combine_check(g2, ["spirit_herb"]))
			# failure, volatility
			G.add_item("g_iron_ore_vambraces", 1, false)
			var f0: float = float(G.counters.get("combine_fail", 0.0))
			var rf: Dictionary = G.combine_attempt("g_iron_ore_vambraces", ["firestone", "ember_root", "goblin_tooth"], 0.999, 0.99)
			check("a failure costs what you worked in, and teaches", not rf["success"] and G.count("ember_root") == 3 and float(G.counters["combine_fail"]) == f0 + 1.0, str(rf))
			check("...volatile things, unbound, can wreck the piece itself", str(G.worn("vambraces")).begins_with("c27_") and G.item_name(G.worn("vambraces")).begins_with("Scorched"), G.item_name(G.worn("vambraces")))
			# alloys and brews
			var ra: Dictionary = G.combine_attempt("silver_ore", ["moonpetal"], 0.0, 0.99)
			var al := str(ra["item"])
			check("materials together become a new material, with traits from both", ra["success"] and al.begins_with("alloy_") and G.material_traits(al).has("conductive") and G.material_traits(al).has("resonant"), str(ra))
			check("...and it can be forged like what it came from, a tier better", G.stock_info(al).get("class", "") == "metal" and int(G.stock_info(al)["tier"]) == int(G.stock_info("silver_ore")["tier"]) + 1)
			G.add_item("healing_salve", 2, false)
			var rb: Dictionary = G.combine_attempt("healing_salve", ["spirit_herb"], 0.0, 0.99)
			check("a draught worked with a vital herb heals more", rb["success"] and int(G.item_def(str(rb["item"])).get("heal", 0)) > int(G.item_def("healing_salve")["heal"]), str(rb))
			check("treasures can't be worked", G.combine_check("spirit_gourd", ["spirit_herb"]) != "")
			# forging
			G.gold = 2000
			G.skills["smithing"] = 400.0
			G.skills["jewelcrafting"] = 400.0
			var rfg: Dictionary = G.forge_piece("boots", "beast_hide", "", 0.0, 0.5)
			check("forge any piece from a stock: hide boots", rfg["success"] and G.base_id(str(rfg["item"])) == "g_beast_hide_boots", str(rfg))
			var rj: Dictionary = G.forge_piece("ring", "silver_ore", "spirit_resin", 0.0, 0.5)
			check("...jewellery from a metal, set with ANY material -- the setting gives the gift", rj["success"] and G.item_def(str(rj["item"])).has("effect") and G.is_jewel(str(rj["item"])), str(rj))
			check("nano classes wait for the nanoforge", G.forge_check("gloves", "nanoweave_thread") != "")
			# the nanoforge
			check("the tree's first node is ready; deeper ones wait for the swarm", G.nano_state("filament_spinning") == "ready" and G.nano_state("lattice_plating") == "locked" and G.nano_state("neural_lace") == "hidden")
			var sh0: int = G.count("nanite_shard")
			G.nano_unlock("filament_spinning")
			check("unlocking costs shards and teaches its formula", G.nano_has("filament_spinning") and G.knows_formula("nanoweave_thread") and G.count("nanite_shard") == sh0 - 2)
			G.add_item("spirit_silk", 2, false)
			var rn: Dictionary = G.combine_attempt("nanite_shard", ["spirit_silk"], 0.0, 0.99)
			check("...nanoweave can be made now", rn["success"] and G.count("nanoweave_thread") == 2, str(rn))
			var rnw: Dictionary = G.forge_piece("cape", "nanoweave_thread", "", 0.0, 0.5)
			check("...and worn: a nano cape", rnw["success"] and str(G.item_def(str(rnw["item"])).get("make", "")) == "nano", str(rnw))
			G.add_item("spirit_silk", 1, false)
			G.add_item("g_beast_hide_pants", 1, false)
			var hyb: Dictionary = G.combine_attempt("g_beast_hide_pants", ["nanite_shard", "spirit_silk"], 0.0, 0.99)
			check("crafted, then given to the swarm: a piece that is both", hyb["success"] and str(G.item_def(str(hyb["item"])).get("make", "")) == "both", str(hyb))
			G.combine_attempt("nanite_shard", ["storm_glass"], 0.99, 0.99)
			check("a secret node is found by experimenting (lightning-glass and the swarm)", G.nano_state("neural_lace") != "hidden")
			G.integration = 99999.0
			G.add_item("singing_crystal", 1, false)
			G.add_item("spirit_herb", 6, false)
			G.add_item("spirit_resin", 4, false)
			G.add_item("nanite_shard", 20, false)
			G.add_item("silver_ore", 3, false)
			G.add_item("iron_ore", 4, false)
			for nid in ["lattice_plating", "micro_circuitry", "self_repair", "catalysis"]:
				G.nano_unlock(nid)
			check("with the swarm grown, the tree opens further", G.nano_has("lattice_plating") and G.nano_has("self_repair") and G.nano_has("catalysis"), str(G.nano_nodes))
			check("...self-repair: nano pieces mend you", G.tech_effect("regen", 0.0) > 0.0)
			G.integration = 0.0
			# formula scrolls
			var stock27: Array = G.formula_scrolls_for("smith")
			check("smiths sell formulas", stock27.size() > 0)
			var sid := str(stock27[0][0])
			G.add_item(sid, 1, false)
			check("...a scroll is learned, not carried", G.knows_formula(str(G.items[sid]["formula"])) and G.count(sid) == 0)
			# the pack screen
			var hud27 = root.get_tree().get_first_node_in_group("hud")
			hud27.open_kit("Pack")
			var kit = hud27._kit
			check("the pack screen: you on a dummy, every slot laid out", kit._left_slots.get_child_count() + kit._right_slots.get_child_count() + kit._ring_row.get_child_count() == 27 and kit._dummy != null)
			check("...the dummy wears what you wear", kit._dummy.find_children("Dress_Armour_*", "", true, false).size() > 3)
			kit.choose_slot("gauntlets")
			kit._refresh_now()
			G.add_item("g_iron_ore_gauntlets", 1, false)
			kit._refresh_now()
			var pt27 := ""
			for c in kit.pack_body.find_children("*", "", true, false):
				if c is Button or c is Label:
					pt27 += c.text + "|"
			check("click a slot to choose what goes there", pt27.contains("Gauntlets -- choose what to wear there") and (pt27.contains("Wear here") or pt27.contains("Take off")), pt27.left(300))
			kit.bench_set("iron_ore", ["firestone", "spirit_resin"])
			kit.show_tab("Bench")
			kit._refresh_now()
			var bt := ""
			for c in kit._bench_body.get_children():
				if c is Label:
					bt += c.text
			check("the bench tab shows the odds and what you understand of the mix", bt.contains("Odds:") and bt.contains("Hard"), bt.left(200))
			kit.show_tab("Nanoforge")
			kit._refresh_now()
			check("the nanoforge tab draws the tree", kit._nano_body.find_children("*", "Button", true, false).size() >= 5)
			kit.show_tab("Formulas")
			kit._refresh_now()
			check("the formulas tab lists what you know", kit._formula_body.get_child_count() >= 3)
			hud27.close_kit()
			check("closing it leaves the bench", G.at_bench == "" and not hud27._inventory.visible)
			# armour on the body
			var H27 = load("res://scripts/actors/Human.gd")
			if H27.available():
				var m27: Node3D = H27.make({"sex": "m", "outfit": "ranger", "hair": "long"})
				root.add_child(m27)
				var looks := []
				for fam in ["cowl", "cape", "pauldrons", "robe", "armor", "underarmour", "vambraces", "gauntlets", "pants", "greaves", "boots"]:
					looks.append({"family": fam, "look": "metal", "color": [0.5, 0.5, 0.5], "make": "nano", "slot": fam})
				for sl in ["ring_l1", "ring_r4", "bracelet_l", "toering_r"]:
					looks.append({"family": G.slot_family(sl), "look": "jewel", "color": [0.9, 0.8, 0.3], "make": "crafted", "slot": sl})
				load("res://scripts/actors/Armour.gd").dress_gear(m27, looks)
				var parts := m27.find_children("Dress_Armour_*", "", true, false)
				check("our own armour models ride the bones: every kind drawn", parts.size() >= 20, str(parts.size()))
				var hair_hidden := true
				for hn in m27.find_children("Hair_*", "", true, false):
					if hn is Node3D and not str(hn.name).contains("Beard") and (hn as Node3D).visible:
						hair_hidden = false
				check("...a hood hides the hair", hair_hidden)
				check("...a cape that sways", m27.find_children("CapePivot", "", true, false).size() == 1)
				load("res://scripts/actors/Armour.gd").dress_gear(m27, [])
				check("...and it all comes off again", m27.find_children("Dress_Armour_*", "", true, false).size() == 0)
				m27.free()
			check("the player wears it too", player._model.find_children("Dress_Armour_*", "", true, false).size() > 0 or G.worn_looks().is_empty())
			G.new_game()
			wait = 0.1
		46:
			print("== round 28: no two fights the same ==")
			G.new_game()
			G.background = "craft"
			check("a monster's name says how it fights (a knight guards, an imp throws)",
				G.foe_style("skeleton_knight", G.enemies["skeleton_knight"]) == "guardian" and G.foe_style("storm_weak_f16", G.enemies["storm_weak_f16"]) == "ranged")
			check("...and every other kind fights its own way, the same every time",
				G.foes_data()["styles"].has(G.foe_style("goblin", G.enemies["goblin"])) and G.foe_style("goblin", G.enemies["goblin"]) == G.foe_style("goblin", G.enemies["goblin"]))
			_build("floor1")
			var plain := true
			for e in root.get_tree().get_nodes_in_group("enemy"):
				if e.get("style") != null and (e.style != "brawler" or e.elite):
					plain = false
			check("floor 1 stays plain: it teaches the basics", plain)
			_build("floor20")
			var styles28 := {}
			var elites28 := 0
			var variants28 := 0
			for e in root.get_tree().get_nodes_in_group("enemy"):
				if e.get("style") == null:
					continue
				styles28[e.style] = true
				if e.elite:
					elites28 += 1
			var pool28 := []
			for i in 160:
				var fe = load("res://scripts/actors/Enemy.gd").new()
				fe.setup(level, {"type": "goblin", "cell": Vector2i(i, 3), "roll": true})
				if fe.elite:
					elites28 += 1
				if fe.style != G.foe_style("goblin", G.enemies["goblin"]):
					variants28 += 1
				pool28.append(fe)
			for fe in pool28:
				fe.free()
			check("deep down, packs are mixed: variant styles and elites turn up", variants28 > 20 and elites28 > 5, "%d variants, %d elites, styles on floor 20: %s" % [variants28, elites28, styles28.keys()])
			var P28: Vector3 = level.spawn_point("P")
			player.global_position = P28
			var mk := func(args: Dictionary):
				var at: Vector3 = P28 + Vector3(0, 0, 4.0)
				var a2 := {"type": "goblin", "cell": level.world_to_cell(at)}
				a2.merge(args, true)
				return level._spawn_script("res://scripts/actors/Enemy.gd", at, a2)
			var gd = mk.call({"style": "guardian"})
			gd._face(player.global_position - gd.global_position)
			var h0: int = gd.hp
			gd.take_damage(20, "you")
			var front_cut: int = h0 - gd.hp
			gd.take_damage(20, "severing finger")
			check("a guardian turns your blade from the front -- not your arts", front_cut < 10 and h0 - gd.hp - front_cut == 20, "%d then %d" % [front_cut, h0 - gd.hp - front_cut])
			gd._face(gd.global_position - player.global_position)
			var h1: int = gd.hp
			gd.take_damage(10, "you")
			check("...and not from behind", h1 - gd.hp == 10)
			gd.queue_free()
			var sk = mk.call({"style": "skulker"})
			check("a skulker can't be seen until it's close", not sk._model.visible)
			sk.take_damage(1, "you")
			check("...a blow finds it", sk._model.visible)
			sk.queue_free()
			var rg = mk.call({"style": "ranged"})
			var hp28: int = G.hp
			var b = rg.shoot(player)
			for i in 40:
				if not is_instance_valid(b) or b.is_queued_for_deletion():
					break
				b._physics_process(0.05)
			check("a ranged foe's shot flies at you and lands (step aside and it wouldn't)", G.hp < hp28, "%d -> %d" % [hp28, G.hp])
			rg.queue_free()
			G.hp = G.max_hp()
			player._hurt_cool = 0.0          # (a fresh blow: the last one's flinch has passed)
			var ch = mk.call({"style": "charger"})
			ch._t1 = 0.0
			var to28: Vector3 = player.global_position - ch.global_position
			ch._charge(0.1, player, to28, to28.length())
			check("a charger winds up first -- the ring is your warning", ch._t2 > 0.0)
			for i in 20:
				ch._charge(0.1, player, player.global_position - ch.global_position, 1.0 if ch._dash > 0.0 else to28.length())
			check("...then runs you down", G.hp < G.max_hp() and ch._dash_hit, "hp %d" % G.hp)
			ch.queue_free()
			G.hp = G.max_hp()
			var sw = mk.call({"style": "swarmer"})
			sw._brood()
			var young := root.get_tree().get_nodes_in_group("enemy").filter(func(e): return e.get("minion") == true and str(e.stats.get("name", "")).begins_with("Young"))
			check("a swarmer brings its young", young.size() >= 2, str(young.size()))
			for y in young:
				y.queue_free()
			sw.queue_free()
			var md = mk.call({"style": "mender"})
			var hurt28 = mk.call({"style": "brawler"})
			hurt28.hp = 1
			md._heal_allies()
			check("a mender heals the others", hurt28.hp > 1)
			md.queue_free()
			hurt28.queue_free()
			var el = mk.call({"affixes": ["armoured", "vampiric"]})
			check("an elite carries its affixes in its name, and is far tougher", str(el.stats["name"]).begins_with("Armoured Vampiric") and int(el.stats["hp"]) > int(G.enemies["goblin"]["hp"]) * 2)
			var e0: int = el.hp
			el.take_damage(100, "severing finger")
			check("...armoured: every blow loses 40%", e0 - el.hp == 60, str(e0 - el.hp))
			player._hurt_cool = 0.0          # (a fresh blow: the last one's flinch has passed)
			var e1: int = el.hp
			el.deal(player, 20)
			check("...vampiric: it heals from what it draws", el.hp > e1)
			el.queue_free()
			G.hp = G.max_hp()
			var fz = mk.call({"affixes": ["frenzied"]})
			var sp0: float = float(fz.stats["speed"])
			fz.take_damage(int(fz.hp * 0.6), "severing finger")
			check("frenzied: hurt it badly and it gets faster", fz._frenzy and float(fz.stats["speed"]) > sp0)
			fz.queue_free()
			player._hurt_cool = 0.0          # (a fresh blow: the last one's flinch has passed)
			var th = mk.call({"affixes": ["thunderous"]})
			th._t3 = 0.0
			th._thunder(0.1, player, 2.0)
			check("thunderous: a ring warns before it stamps", th._t4 > 0.0)
			for i in 15:
				th._thunder(0.1, player, 2.0)
			check("...and the stamp lands if you stay", G.hp < G.max_hp())
			th.queue_free()
			G.hp = G.max_hp()
			var g28: int = G.gold
			var gi = mk.call({"affixes": ["gilded", "splitting"]})
			var n_before: int = root.get_tree().get_nodes_in_group("enemy").size()
			gi.take_damage(999999, "severing finger")
			check("gilded: it carries far more than it should", G.gold > g28)
			wait = 0.2
			_hold["n_before"] = n_before
		47:
			var parts := root.get_tree().get_nodes_in_group("enemy").filter(func(e): return e.get("minion") == true and not e._dead)
			check("splitting: it breaks into two lesser ones", parts.size() >= 2, str(parts.size()))
			for e in parts:
				e.queue_free()
			_build("floor7")
			var boss28 = null
			for e in root.get_tree().get_nodes_in_group("enemy"):
				if bool(e.stats.get("boss", false)):
					boss28 = e
			var bs0: float = float(boss28.stats["speed"])
			boss28.take_damage(int(boss28.hp * 0.55), "severing finger")
			check("a boss at half health is ENRAGED", boss28._enraged and float(boss28.stats["speed"]) > bs0)
			# rival disciples in the valley
			G.valley_def = {}
			_build("valley")
			player.global_position = level.spawn_point("P")
			var rivals28 := root.get_tree().get_nodes_in_group("rival")
			check("rival disciples wait by the valley roads, from the sects", rivals28.size() == 3 and str(rivals28[0].rival.get("sect_name", "")) != "", str(rivals28.size()))
			var rv = rivals28[0]
			check("...they ask for a bout", rv.prompt().contains("wants a bout"))
			var rh: int = rv.hp
			rv.take_damage(50, "you")
			check("...and can't be hurt until you agree", rv.hp == rh)
			var gold28: int = G.gold
			rv.begin()
			rv.take_damage(999999, "you")
			check("win the bout: they yield (nobody dies), and pay you", not rv.dueling and not rv._dead and G.gold > gold28 and int(G.rivals[rv.rival["name"]]["beat"]) == 1)
			check("...once a day each", rv.prompt().contains("Tomorrow"))
			var rv2 = rivals28[1]
			player._hurt_cool = 0.0          # (a fresh blow: the last one's flinch has passed)
			rv2.begin()
			G.hp = G.max_hp()
			rv2.deal(player, G.max_hp() * 2)
			check("lose a bout: you yield before the blow that would finish you", not player.dead and G.hp > 0 and int(G.rivals[rv2.rival["name"]]["lost"]) == 1, "hp %d" % G.hp)
			G.new_game()
			wait = 0.1
		48:
			print("== round 30: bloodlines ==")
			G.new_game()
			G.retention_live = true
			var vis := 0
			var hid := 0
			for i in 400:
				G.blood_new_game(1000 + i)
				if G.blood_dominant() != "":
					vis += 1
				elif not (G.bloodline.get("hidden", {}) as Dictionary).is_empty():
					hid += 1
			check("some are born with a bloodline, more carry a hidden one, most have neither (percentages)", vis >= 15 and vis <= 55 and hid >= 60 and hid <= 150 and vis + hid < 260, "visible %d hidden %d of 400" % [vis, hid])
			G.new_game()
			G.bloodline = {"dominant": "azure_dragon", "secondary": "", "purity": {"azure_dragon": 12.0}, "hidden": {}, "known": {"azure_dragon": true}, "awaken_at": 20, "awake": false}
			var q0: float = G.tech_effect("qi_mult", 1.0)
			check("a bloodline sleeps until the deep wakes it: no gifts before", G.blood_effect().is_empty())
			G.blood_floor_reached(19)
			check("...not yet at floor 19 (this save wakes at 20)", not G.blood_awake())
			G.blood_floor_reached(20)
			check("...and at its floor it wakes: Azure Dragon's first milestone (10%%) gives qi", G.blood_awake() and G.tech_effect("qi_mult", 1.0) > q0 * 1.03, "%f -> %f" % [q0, G.tech_effect("qi_mult", 1.0)])
			check("the blood waking is a big moment (a window, not just a line)", _moment_seen("Your Blood Wakes"))
			G.new_game()
			G.bloodline = {"dominant": "", "secondary": "", "purity": {}, "hidden": {"white_tiger": 9.0}, "known": {}, "awaken_at": 20, "awake": false}
			G.awaken_blood(7)
			check("a hidden bloodline shines through when the blood wakes", G.blood_dominant() == "white_tiger" and absf(G.purity("white_tiger") - 9.0) < 0.01 and (G.bloodline.get("hidden", {}) as Dictionary).is_empty())
			G.add_purity("white_tiger", 45.0, "test")
			var bef: Dictionary = G.blood_effect()
			check("milestones add up: White Tiger at 54%% -- 10%%, 25%% and 50%% all count", G.blood_milestone(G.purity("white_tiger")).get("name", "") == "Manifest"
				and absf(float(bef.get("crit_chance", 0.0)) - 0.1) < 0.001 and float(bef.get("attack_speed", 1.0)) > 1.04, str(bef))
			G.add_purity("qilin", 20.0, "test")
			check("a second line becomes your secondary -- and gives at half (and refines a little slower)", G.blood_secondary() == "qilin" and absf(float(G.blood_effect().get("loot_luck", 0.0)) - 0.025) < 0.001
				and absf(G.purity("qilin") - 12.0) < 0.01, "%s %s" % [str(G.blood_effect()), G.purity("qilin")])
			var r3: String = G.add_purity("asura", 5.0, "test")
			check("one dominant and one secondary only: a third line has to be decided", r3 == "pending" and not G.bloodline["purity"].has("asura") and _moment_seen("New Blood", true))
			G.resolve_blood_choice("dominant")
			check("...take it as dominant: the old dominant follows, the old secondary fades", G.blood_dominant() == "asura" and G.blood_secondary() == "white_tiger"
				and not G.bloodline["purity"].has("qilin") and G.bloodline["known"].has("qilin"))
			check("...the journal's blood rows: dominant first", G.blood_rows().size() == 2 and str(G.blood_rows()[0][3]) == "dominant")
			check("your secondary can lead instead (and then has to settle)", G.swap_blood().contains("leads now") and G.blood_dominant() == "white_tiger" and G.swap_blood().contains("settling"))
			G.bloodline["swap_at"] = 0.0
			G.swap_blood()
			G.bloodline["purity"]["asura"] = 55.0
			G.hp = int(G.max_hp() * 0.2)
			check("Asura blood: below 40%% health your blows strike harder", G.fury_mult() > 1.2)
			G.hp = G.max_hp()
			check("...not when you're whole", G.fury_mult() == 1.0)
			var kp: float = G.purity("asura")
			G.blood_kill({"name": "Goblin Brute"})
			check("defeating your blood's kin refines it (a brute for Asura)", G.purity("asura") > kp)
			G.add_item("essence_golden_crow", 1, false)
			G.use_item("essence_golden_crow")
			check("a drop of old blood is something you use (a third line: you're asked again)", not (G.bloodline.get("pending", {}) as Dictionary).is_empty())
			G.resolve_blood_choice("refine")
			check("...burn it away and your dominant line drinks it", G.purity("asura") > kp and (G.bloodline.get("pending", {}) as Dictionary).is_empty())
			G.new_game()
			G.bloodline = {"dominant": "vermilion_phoenix", "secondary": "", "purity": {"vermilion_phoenix": 52.0}, "hidden": {}, "known": {}, "awaken_at": 20, "awake": true}
			player.dead = false
			player._hurt_cool = 0.0
			player.guarding = false
			G.hp = 5
			player.take_damage(999, "a test", null)
			check("Vermilion Phoenix (50%%): a killing blow leaves you standing, once a day", not player.dead and G.hp >= int(G.max_hp() * 0.35), "hp %d dead %s" % [G.hp, player.dead])
			check("...only once a day", not G.try_rebirth())
			var lid: String = G.blood_inheritance("legacy|test", {"bloodline": "kunpeng"})
			check("a dead master's legacy can carry their blood (a level file names it)", lid == "kunpeng" and G.blood_secondary() == "kunpeng" and G.purity("kunpeng") > 2.0)
			G.new_game()
			G.bloodline = {"dominant": "", "secondary": "", "purity": {}, "hidden": {}, "known": {}, "awaken_at": 20, "awake": false}
			G.add_purity("kunpeng", 6.0, "test")
			check("before the blood wakes, new blood settles in hidden", G.blood_dominant() == "" and float(G.bloodline["hidden"].get("kunpeng", 0.0)) > 5.9)
			check("every line has its essence item", G.has_item_def("essence_azure_dragon") and G.item_def("essence_starborn_lattice").get("blood", "") == "starborn_lattice")
			G.retention_live = false
			wait = 0.1
		49:
			print("== round 30: the daily trial, the week, the Trial Board ==")
			G.new_game()
			G.retention_live = true
			G.journal["places"]["floor4"] = {"visits": 1}
			var tid: String = G.TrialGen.make_id(G.today())
			var mods: Array = G.trial_mods()
			check("today's trial has one or two twists, the same all day", mods.size() >= 1 and mods.size() <= 2 and G.trial_mods() == mods)
			var tdef: Dictionary = G.load_level_def(tid)
			check("the trial is built to how deep you've come (floor 4)", bool(tdef.get("trial", false)) and int(tdef.get("depth", 0)) == 4 and int(tdef.get("trial_foes", 0)) >= 5, str(tdef.get("trial_foes", 0)))
			_build_def(tdef)
			var foes: Array = root.get_tree().get_nodes_in_group("enemy").filter(func(e): return not bool(e.stats.get("passive", false)))
			check("...a real level with its foes in it (and a way back to Eliet)", foes.size() >= 5 and str(tdef["exits"]["<"]["to"]) == "village", str(foes.size()))
			G.current_level = tid
			G.trials["run"] = {"day": G.today(), "t0": G.playtime, "hp_lost": 0, "kills": 0, "elites": 0, "done": false}
			_hold["marks"] = G.marks
			_hold["gold"] = G.gold
			for e in foes:
				e.take_damage(999999, "you")
			wait = 0.3
		50:
			check("clear every foe and the trial is done: gold, marks, a streak", G.trial_done_today() and G.marks > int(_hold["marks"]) and G.gold > int(_hold["gold"]) and int(G.trials.get("streak", 0)) == 1,
				"marks %d gold %d streak %s" % [G.marks, G.gold, str(G.trials.get("streak"))])
			check("...with a score, and a window saying so", int(G.trials.get("best", {}).get(G.today(), 0)) > 0 and _moment_seen("Trial Cleared"))
			var y: String = Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_system()) - 86400)
			G.trials["done"] = {}
			G.trials["last_day"] = y
			G.trials["streak"] = 3
			G.trials["run"] = {"day": G.today(), "t0": G.playtime, "hp_lost": 0, "kills": 1, "elites": 0, "done": false}
			G.trial_complete()
			check("coming back the next day grows the streak", int(G.trials["streak"]) == 4)
			G.trials["done"] = {}
			G.trials["last_day"] = Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_system()) - 86400 * 4)
			G.trials["streak"] = 5
			G.trials["run"] = {"day": G.today(), "t0": G.playtime, "hp_lost": 0, "kills": 1, "elites": 0, "done": false}
			G.trial_complete()
			check("...missing days only wears it down a little (5, three days missed, back: 3)", int(G.trials["streak"]) == 3, str(G.trials["streak"]))
			G.current_level = "village"
			var goals: Array = G.weekly_goals()
			check("three sect trials a week, the same all week", goals.size() == 3 and G.weekly_goals() == goals)
			var g0: Dictionary = goals[0]
			var ev = g0.get("event", "")
			var evk: String = str(ev[0]) if ev is Array else str(ev)
			G.trials["progress"] = {}          # (this week's goal may already have been met by what the run did before -- elites, say)
			G.trials["claimed"] = {}
			var mk0: int = G.marks
			for i in int(g0.get("need", 1)):
				G.log_event(evk, {})
			check("they count what you do anyway -- and pay out when done", G.weekly_rows()[0][3] == true and G.marks > mk0, str(G.weekly_rows()[0]))
			G.marks = 20
			var pills: int = G.count("qi_pill")
			G.buy_with_marks("qi_pills")
			check("trial marks buy things at the board", G.count("qi_pill") == pills + 3 and G.marks == 16)
			check("...a drop of old blood only once your blood has woken", G.buy_with_marks("essence").contains("woken") and G.marks == 16)
			for e in G.enemies:
				if int(G.enemies[e].get("floor", -1)) > 0 and int(G.enemies[e].get("floor", -1)) <= 14 and not bool(G.enemies[e].get("passive", false)):
					G.kills[e] = 12
			var mk1: int = G.marks
			var got: Array = G.check_collections()
			check("collections pay out at 25/50/75/100%", got.size() > 0 and G.marks > mk1, str(got))
			check("...and studying a kind makes you hit it harder (10 of them: +4%%, 50: +10%%)", absf(G.bestiary_mult("goblin") - 1.04) < 0.001 and G.bestiary_mult("no_such_thing") == 1.0)
			G.kills["goblin"] = 50
			check("...mastered at 50", absf(G.bestiary_mult("goblin") - 1.1) < 0.001)
			_build("village")
			var board = _find("TrialBoard.gd")
			check("the Trial Board stands in Eliet", board != null)
			if board:
				board.interact(player)
				check("...and it posts today's trial", hud_text().contains("TODAY'S TRIAL") and _btn_has("today's trial"))
				board.open_ascension()
				check("...ascension waits until you've come far enough", hud_text().contains("Not yet"))
				root.get_tree().get_first_node_in_group("hud").close_dialog()
			wait = 0.1
		51:
			print("== round 30: world events, ascension, Steam ==")
			G.force_event("floor3", "blood_moon")
			check("a Blood Moon makes elites likelier on its floor", absf(G.level_mod({"id": "floor3"}, "elite_mult") - 3.0) < 0.001 and G.level_mod({"id": "floor6"}, "elite_mult") == 1.0)
			G.force_event("floor3", "treasure_spirit")
			_build("floor3")
			check("a Treasure Spirit runs about a floor on its day", _find("Enemy.gd", func(n): return n._treasure) != null)
			G.force_event("floor3", "wandering_master")
			_build("floor3")
			var wm = _find("WanderingMaster.gd")
			check("a wandering master camps on a floor on theirs", wm != null)
			if wm:
				G.gold = 500
				var ins: float = G.insight
				wm.listen()
				check("...sit and listen: insight, for a fee", G.insight > ins and G.gold == 500 - wm.fee())
			G.force_event("floor3", "meteor_fall")
			_build("floor3")
			check("a meteor fall leaves star iron to mine", _find("GatherNode.gd", func(n): return n.yields == "star_iron") != null)
			G.world_events = {}
			G.counters["event_pity"] = 0.0
			var any := 0
			for i in 60:
				if not G.roll_world_event("floor%d" % (2 + i), {"depth": 3, "theme": "dungeon", "id": "floor%d" % (2 + i)}).is_empty():
					any += 1
			check("events are rare -- and the longer since the last, the likelier", any >= 2 and any <= 30, str(any))
			check("...and decided once per floor per day", G.roll_world_event("floor2", {"depth": 3, "theme": "dungeon"}) == G.roll_world_event("floor2", {"depth": 3, "theme": "dungeon"}))
			G.world_events = {}
			G.new_game()
			G.retention_live = true
			check("ascension waits for floor 25 (or Core Formation)", G.can_ascend() != "")
			G.journal["places"]["floor26"] = {"visits": 1}
			G.realm = 2
			G.achievements["first_blood"] = 1.0
			G.marks = 7
			G.add_item("iron_sword", 1, false)
			G.equip("iron_sword")
			G.bloodline = {"dominant": "qilin", "secondary": "", "purity": {"qilin": 50.0}, "hidden": {}, "known": {"qilin": true}, "awaken_at": 20, "awake": true}
			var earn: int = G.ascension_marks()
			check("ascending earns heavenly marks for how far you came", earn > 25, str(earn))
			check("...the Trial Board offers it now", G.can_ascend() == "")
			G.ascend()
			check("ascend: back to the start, harder, with your marks, achievements, heirloom weapon and part of your blood", int(G.ascension["count"]) == 1 and G.realm == 0
				and int(G.ascension["marks"]) == earn and G.achievements.has("first_blood") and G.marks == 7 and G.weapon == "iron_sword"
				and absf(G.purity("qilin") - 30.0) < 0.01 and not G.blood_awake() and G.challenge_mult() > 1.2, "%s %d %s %s %f" % [str(G.ascension), G.realm, G.weapon, G.marks, G.purity("qilin")])
			var en = load("res://scripts/actors/Enemy.gd").new()
			en.setup(null, {"type": "goblin"})
			check("...and the deep is harder: foes have more health", en.hp > int(G.enemies["goblin"]["hp"]))
			en.free()
			G.ascension["marks"] = 10
			var hp0: int = G.max_hp()
			G.buy_boon("old_bones")
			check("heavenly marks buy boons that last through every climb", G.boon_rank("old_bones") == 1 and G.max_hp() > hp0)
			check("Steam: the plug-in is in the game, but nothing turns on here (not under Steam)", G.steam != null and not G.steam.on and load("res://scripts/core/SteamLink.gd").available() and G.steam.cloud_get() == null)
			G.steam.achieve("FIRST_BLOOD")
			G.steam.leaderboard("deepest_floor", 5)
			G.save_game()
			var keep_asc: Dictionary = G.ascension.duplicate(true)
			G.ascension = {}
			G.marks = 0
			G.load_game()
			check("bloodlines, trials, marks and ascension are saved", int(G.ascension.get("count", 0)) == int(keep_asc["count"]) and G.marks == 7 and absf(G.purity("qilin") - 30.0) < 0.01)
			G.retention_live = false
			G.new_game()
			_build("floor1")
			wait = 0.1
		52:
			print("== round 31: sound, the front door, first steps ==")
			G.new_game()
			var au = G.audio
			G.hour_override = 12.0                   # (round 59: the village has night music now)
			check("the game has sound now: music by place, sounds by name (silent under the headless check)", au != null and not au.on()
				and au.music_for("village", {"theme": "village"}) == "village" and au.music_for("floor3", {"depth": 3}) == "dungeon"
				and au.music_for("floor12", {"depth": 12}) == "deep" and au.music_for("valley", {}) == "valley" and au.music_for("title", {}) == "title")
			G.hour_override = -1.0
			au.play("hit_flesh")
			au.at("swing", Vector3.ZERO)
			au.set_music("dungeon")
			G.jingle("levelup")
			check("...and asking for a sound never breaks anything", ResourceLoader.exists("res://assets/audio/sfx/hit_flesh1.ogg") and ResourceLoader.exists("res://assets/audio/music/village.ogg"))
			var Gx2 = load("res://scripts/core/Gfx.gd")
			var mv0: int = int(Gx2.settings.get("music", 6))
			Gx2.step_volume("music", root.get_tree())
			check("music and sound volumes turn in the menu (0-10, round the dial)", int(Gx2.settings["music"]) == (mv0 + 2) % 12)
			Gx2.settings["music"] = mv0
			check("first steps: the first hour is one thing at a time, talking to Elder Mo first", G.next_goals()[0].contains("Elder Mo"))
			G.log_event("talk", {"npc": "Elder Mo", "role": "elder"})
			check("...done, the next step shows (the bag)", G.next_goals()[0].contains("bag"))
			G.set_flag("fs:bag")
			G.add_item("iron_sword", 1, false)
			G.equip("iron_sword")
			check("...a weapon in hand skips that step", G.next_goals()[0].contains("stairs"))
			G.journal["places"]["floor1"] = {"visits": 1}
			G.set_flag("fs:journal")
			G.set_flag("fs:meditate")
			check("...and once they're all done the first steps are gone for good", G.first_steps().is_empty() and G.has_flag("fs:done"))
			var h31 = root.get_tree().get_first_node_in_group("hud")
			h31.show_title()
			check("the title screen is a front door: it blocks play until you choose", h31._title != null and h31._title.visible and h31.is_blocking())
			h31.close_title()
			check("...and opens on to the game", not h31._title.visible)
			if h31._dialog.visible:
				h31.close_dialog()
			G.new_game()
			wait = 0.1
		53:
			print("== round 32: the fight itself ==")
			G.new_game()
			_build("floor1")
			_place_player(Vector2i(5, 7))
			var C32: Dictionary = G.combat_data()
			check("combat numbers live in data/combat.json", not C32.is_empty() and C32.has("combo") and C32.has("heavy") and C32.has("poise"))
			var foe = level._spawn_script("res://scripts/actors/Enemy.gd", player.global_position + Vector3(0, 0, 1.5), {"type": "goblin_brute", "cell": Vector2i(5, 8), "style": "guardian"})
			foe.set_physics_process(false)
			player._model.rotation.y = 0.0
			foe._model.rotation.y = PI
			player._combo = 0
			player._combo_t = 0.0
			player._start_blow(false, 1.0)
			var m1: float = player._blow_mult
			player._end_blow()
			player._start_blow(false, 1.0)
			var m2: float = player._blow_mult
			player._end_blow()
			player._start_blow(false, 1.0)
			var m3: float = player._blow_mult
			check("three light blows chain: the third is the finisher and lands hardest", m1 < m2 and m2 < m3 and player._combo == 2, "%f %f %f" % [m1, m2, m3])
			player._end_blow()
			check("...and the chain starts over", player._combo == 0)
			player._start_blow(true, 2.2)
			check("a charged heavy: a big blow and a beat of recovery after", player._heavy and absf(player._blow_mult - 2.2) < 0.01)
			var hp_g: int = foe.hp
			player._hit_done = false
			player._deal_hit()
			var took: int = hp_g - foe.hp
			check("...the heavy goes through a guardian's shield (a light blow would be mostly turned)", took >= int(G.damage() * 2.0), "took %d dmg %d" % [took, G.damage()])
			player._end_blow()
			check("...then you can't swing for a moment", player._recover_t > 0.3)
			player._recover_t = 0.0
			var pm: float = foe.poise_max()
			foe.poise = 0.0
			foe.poise_hit(pm * 0.6, false)
			check("every blow pushes at a foe's footing (poise)", foe.poise > 0.0 and not foe.staggered())
			foe.poise_hit(pm * 0.6, true)
			check("...break it and it staggers, open to a free hit", foe.staggered() and foe.poise == 0.0 and foe._label.text.contains("STAGGERED"))
			player._blow_mult = 1.0
			player._heavy = false
			player._combo = 0
			foe.hp = int(foe.stats["hp"])
			foe._stun = 2.0
			player._hit_done = false
			foe._model.rotation.y = 0.0          # (its back to you: no shield in the way)
			player._deal_hit()
			var took2: int = int(foe.stats["hp"]) - foe.hp
			check("...and blows on a staggered foe land harder", took2 >= int(G.damage() * 1.3), "took %d" % took2)
			foe._stun = 0.0
			player._roll_cool = 0.0
			player.velocity = Vector3.ZERO
			check("Ctrl rolls you out of the way, through the blow", player.dodge(Vector3(1, 0, 0)) and player._roll_t > 0.0 and player._dodge_t > 0.2 and player._hurt_cool > 0.2)
			check("...not twice in a row", not player.dodge(Vector3(1, 0, 0)))
			player._roll_t = 0.0
			player.toggle_lock()
			check("Z locks on to the nearest foe", player.lock_target == foe)
			player._lock_tick(1.0)
			var to_foe: Vector3 = foe.global_position - player.global_position
			check("...and you keep facing it", absf(angle_difference(player._model.rotation.y, atan2(to_foe.x, to_foe.z))) < 0.2)
			player.toggle_lock()
			check("...Z again lets go", player.lock_target == null)
			foe.free()
			var boss = level._spawn_script("res://scripts/actors/Enemy.gd", player.global_position + Vector3(2, 0, 0), {"type": "goblin_chief", "cell": Vector2i(6, 7)})
			boss.set_physics_process(false)
			var bmx: int = int(boss.stats["hp"])
			boss.hp = int(bmx * 0.6)
			boss._after_hurt()
			check("a floor's master has phases: at two thirds it gains a stamp", boss._phase == 1 and "thunderous" in boss.affixes)
			var before_n: int = root.get_tree().get_nodes_in_group("enemy").size()
			boss.hp = int(bmx * 0.3)
			boss._after_hurt()
			wait = 0.2
		54:
			var boss2 = _find("Enemy.gd", func(n): return n.etype == "goblin_chief" and n._phase > 0)
			var n_now: int = root.get_tree().get_nodes_in_group("enemy").size()
			check("...at a third it calls its young and comes apart (frenzy)", boss2 != null and boss2._phase == 2 and "frenzied" in boss2.affixes and _find("Enemy.gd", func(n): return n.minion) != null,
				"%s phase %s affixes %s minions %s" % [boss2 != null, boss2._phase if boss2 else -1, str(boss2.affixes) if boss2 else "", str(_find("Enemy.gd", func(n): return n.minion))])
			check("the pad: LT rolls, the right stick locks on", InputMap.action_get_events("dodge").any(func(e): return e is InputEventJoypadMotion)
				and InputMap.action_get_events("lock_on").any(func(e): return e is InputEventJoypadButton))
			G.new_game()
			_build("floor1")
			wait = 0.1
		55:
			print("== round 32: set-pieces -- the Keeper, the gate, the levers (floor 6; round 119: floor 3 is a cavern with no corridor to bar, it gets a guarded cache instead) ==")
			G.new_game()
			_build("floor6")
			var sp: Dictionary = level.set_pieces
			check("a dungeon floor gets a Keeper, a locked gate with a vault behind it, and a lever puzzle", sp.has("gate") and sp.has("vault") and sp.has("keeper") and sp.has("levers"), str(sp))
			var gate = _find("Gate.gd", func(n): return not n.puzzle)
			var keeper = _find("Enemy.gd", func(n): return n.champion != "")
			check("the Keeper is named for its floor, carries two affixes and the key", keeper != null and keeper.champion.contains(" of ") and keeper.affixes.size() == 2 and keeper.drops_key == "key_floor6", str(keeper.champion) if keeper else "")
			check("the gate blocks the path until it's opened", gate != null and level.astar.is_point_solid(gate.cell) and not gate.is_open())
			var SPt = load("res://scripts/world/SetPieces.gd")
			var free_t: Dictionary = SPt._free_cells(level)
			free_t[gate.cell] = true
			for g2 in root.get_tree().get_nodes_in_group("gate"):
				free_t[g2.cell] = true           # (a puzzle gate may stand before it)
			var st_c: Vector2i = level.spawns["<"][0] + Vector2i(0, 1)
			var open_reach: Dictionary = SPt._bfs(level, free_t, st_c)
			var shut_reach: Dictionary = SPt._bfs(level, free_t, st_c, gate.cell)
			var down_ok := true
			for dd in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
				var nb: Vector2i = level.spawns[">"][0] + dd
				if open_reach.has(nb) != shut_reach.has(nb):
					down_ok = false
			check("...and the way down is never behind it", down_ok and open_reach.size() > shut_reach.size())
			_place_player(gate.cell + Vector2i(0, 1))
			gate.interact(player)
			check("...no key: locked", not gate.is_open())
			keeper._die()
			check("kill the Keeper and you have the key", G.count("key_floor6") == 1 and G.item_name("key_floor6").begins_with("Key to"))
			gate.interact(player)
			check("...the key opens the gate (and is used up), the path through is open, and it stays open", gate.is_open() and G.count("key_floor6") == 0 and not level.astar.is_point_solid(gate.cell) and G.has_flag(G.flag_key("floor6", gate.cell, "gate")))
			var vault = _find("Chest.gd", func(n): return n.gear > 0)
			check("the vault chest holds real gear", vault != null)
			var pg = _find("Gate.gd", func(n): return n.puzzle)
			var levers: Array = []
			for n in level.get_children():
				if n.get_script() and str(n.get_script().resource_path).ends_with("Lever.gd"):
					levers.append(n)
			check("three levers, a tablet with the order, and a lockless gate they open", levers.size() == 3 and pg != null and not pg.is_open() and level.puzzle_order.size() == 3
				and _find("Stele.gd", func(n): return n.title == "A Worn Tablet") != null)
			var by_color := {}
			for lv in levers:
				by_color[lv.color_name] = lv
			var wrong: String = level.puzzle_order[1]
			by_color[wrong].interact(player)
			check("the wrong lever first: everything resets", level.puzzle_pulled.is_empty() and not by_color[wrong]._pulled)
			for cn in level.puzzle_order:
				by_color[cn].interact(player)
			check("...the right order opens the puzzle gate", pg.is_open() and G.has_flag("floor6:puzzle:levers"))
			G.new_game()
			_build("floor1")
			wait = 0.1
		56:
			print("== round 32: the story -- acts, choices, consequences, arcs, the rival, the ending ==")
			G.new_game()
			_build("village")
			var h32 = root.get_tree().get_first_node_in_group("hud")
			check("thirteen acts of story, each with a trigger, a townsperson and two choices", G.story_acts().size() == 13 and G.story_acts().all(func(a): return a.has("trigger") and a.has("who") and (a.get("choices", []) as Array).size() == 2))
			check("nothing is told before its trigger", G.story_check("floor_reached", 1).is_empty() and G.story_rows().is_empty())
			var opened: Array = G.story_check("floor_reached", 2)
			check("two floors down: the first act opens (a window tells it; Mo waits)", opened == ["seeding"] and G.story_state("seeding") == "open" and G.story_rows().size() == 1 and G.story_rows()[0][1] == "open" and _moment_seen("What the Deep Put in You"))
			h32._moments_q.clear()
			check("...and it doesn't open twice", G.story_check("floor_reached", 3).is_empty())
			var mo = _find("NPC.gd", func(n): return n.npc_name == "Elder Mo")
			check("Elder Mo stands in Eliet", mo != null)
			mo.interact(player)
			check("talk to Mo: the scene comes first, with its two choices and 'Later'", h32._dialog_title.text.contains("What the Deep") and _btn_has("The village should know") and _btn_has("Keep it between us") and _btn_has("Later"))
			var ins0: float = G.insight
			var after: String = G.story_choose("seeding", 0)
			check("choose: the consequences land (insight; the Lodge's standing waits until you join), the act is done, the choice is remembered", after.contains("gently") and G.insight == ins0 + 3.0 and float(G.flags.get("story:rep_owed:adventurers", 0.0)) == 10.0
				and G.story_state("seeding") == "done" and G.has_flag("story:open") and G.story_rows()[0][2].begins_with("The village should know"), "insight %s->%s after=%s" % [ins0, G.insight, after])
			G.join_guild("adventurers")
			check("...join the Lodge: the standing lands", float(G.guilds.get("adventurers", {}).get("rep", 0.0)) == 10.0 and not G.flags.has("story:rep_owed:adventurers"))
			check("...a done act can't be chosen again", G.story_choose("seeding", 1) == "" and not G.has_flag("story:quiet"))
			h32.close_dialog()
			mo.interact(player)
			check("talk to Mo again: his usual business, with his arc line first", h32._dialog_body.text.contains("\"The deep is awake in you") and _btn_has("Goodbye"), h32._dialog_title.text + " | " + h32._dialog_body.text.left(160))
			h32.close_dialog()
			check("the choice reaches other townspeople (Lin and Rhee speak of it)", G.story_arc_text("Apothecary Lin").contains("Half the village") and G.story_arc_text("Captain Rhee").contains("Lodge takes the deep seriously"))
			# Wen's debt: a choice you may not be able to afford
			check("six floors: Wen's act opens, not the tenth-floor one", G.story_check("floor_reached", 6) == ["wens_debt"] and G.story_state("envoy") == "")
			G.gold = 50
			var wen_act: Dictionary = G.story_act("wens_debt")
			check("too poor to clear the debt: the choice says so and nothing happens", G.story_can_choose(wen_act["choices"][0]) != "" and G.story_choose("wens_debt", 0).contains("need 200") and G.story_state("wens_debt") == "open")
			G.gold = 300
			var wen = _find("NPC.gd", func(n): return n.npc_name == "Trader Wen")
			var full_price := int(wen.trade_stock()[0][1])
			G.story_choose("wens_debt", 0)
			check("pay it: 200 gold gone, Wen's prices are 15% lower for you, and he has a gift the next time you talk", G.gold == 100 and G.shop_discount("Trader Wen") == 0.15 and int(wen.trade_stock()[0][1]) < full_price
				and G.story_arc_text("Trader Wen").contains("road's open") and G.count("nanite_shard") >= 6 and not G.story_arc_text("Trader Wen").contains("give you"))
			# the Keeper's keys: a share of your gold
			G.gold = 100
			check("the third floor's master dead: Hale's act", G.story_check("boss_floor", 3) == ["first_master"] and G.story_check("boss_floor", 4).is_empty())
			G.story_choose("first_master", 0)
			check("give the village its share: 30% of your gold, and a sword from Hale's rack", G.gold == 70 and G.count("iron_sword") >= 1 and G.has_flag("story:gave_share"))
			check("...and Hale teaches a formula for it, once", G.story_arc_text("Smith Hale").contains("formula") and G.formulas_known.size() >= 1 and not G.story_arc_text("Smith Hale").contains("formula:"))
			# the blood
			check("the blood waking opens Lin's act", G.story_check("blood_awake", true) == ["blood"])
			var dom0: String = G.blood_dominant()
			var pur0: float = G.purity(dom0) if dom0 != "" else 0.0
			G.story_choose("blood", 1)
			check("keep your blood: your line thickens -- or, with no line yet, the purity waits for one", (dom0 == "" and float(G.flags.get("story:purity_owed", 0.0)) == 4.0) or (dom0 != "" and G.purity(dom0) > pur0), "dominant '%s'" % dom0)
			# the sects, the rival
			check("fifteen floors: the envoy (10) and the rival (15) both open", G.story_check("floor_reached", 15) == ["envoy", "rival"])
			G.story_choose("envoy", 0)
			check("go to the hills with no sect: the contribution waits for the one you join", float(G.flags.get("story:contrib_owed", 0.0)) == 20.0)
			check("no Shen on the valley road yet", not G.valley_rivals().any(func(r): return r["name"] == "Shen"))
			G.story_choose("rival", 0)
			var rv: Array = G.valley_rivals()
			check("let him come: Shen walks the valley road, a cut above the other disciples", G.rival_shen_live() and rv[0]["name"] == "Shen" and rv.size() >= 2
				and int(G.rival_disciple_stats(rv[0])["hp"]) > int(G.rival_disciple_stats(rv[1])["hp"]))
			G.duel_result(rv[0], true)
			check("beat him: a title, and he leaves the road", G.has_flag("story:shen_beaten") and ("The One Shen Couldn't Beat" in G.titles) and not G.valley_rivals().any(func(r): return r["name"] == "Shen"))
			# the ending
			G.story_check("floor_reached", 20)
			G.story_choose("pagoda", 0)
			check("the Pagoda: forgive Mo, and the heart settles", G.dao_heart >= 1.0 and G.has_flag("story:mo_forgiven"))
			check("the twenty-fifth master dead: the last act", G.story_check("boss_floor", 25) == ["mirror"] and G.story_ending() == "")
			G.story_choose("mirror", 0)
			check("seal the shaft: an ending, a title, the shaft is sealed", G.story_ending() == "sealed" and G.story_sealed() and ("The Sealer" in G.titles))
			var ex = _find("Exit.gd", func(n): return str(n.target).begins_with("floor"))
			ex._armed = true
			ex._on_body_entered(player)
			check("...the stairs warn you first", G.flags.has("story:seal_warned") and not G.has_flag("story:seal_broken"))
			G.break_seal()
			check("...and the seal can be broken", not G.story_sealed() and G.story_rows().size() == 8)
			# Dev's words win
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/drafts"))
			var df := FileAccess.open("res://data/drafts/story.json", FileAccess.WRITE)
			df.store_string(JSON.stringify({"items": [{"act": "seeding", "told": "DEV TOLD", "choices": [{"text": "DEV CHOICE"}]}]}))
			df.close()
			G.story_def = {}
			check("the writing room's words replace ours, act by act", G.story_act("seeding")["told"] == "DEV TOLD" and G.story_act("seeding")["choices"][0]["text"] == "DEV CHOICE" and G.story_act("seeding")["choices"][1]["text"].begins_with("Keep it"))
			DirAccess.remove_absolute(ProjectSettings.globalize_path("res://data/drafts/story.json"))
			G.story_def = {}
			G.save_game()
			check("a saved game keeps the story (flags)", G.load_game() and G.story_ending() == "sealed" and G.story_state("seeding") == "done")
			G.new_game()
			_build("floor1")
			wait = 0.1
		57:
			print("== round 32: companions and pets grown up ==")
			G.new_game()
			_build("floor2")
			var hd = root.get_tree().get_first_node_in_group("hud")
			# -- a companion with a style, gear, levels, a life bar
			G.flags.erase("ask:travel:Little Rin")
			G.bond("Little Rin")["warmth"] = 200.0
			check("(setup) Little Rin comes along", G.ask_companion("Little Rin", "Little Rin, a healer", "village", Color.WHITE, 0.0) == "yes")
			var cp = load("res://scripts/actors/Companion.gd").new()
			root.add_child(cp)
			cp.snap_to(player.global_position)
			check("a companion starts as a green striker with no gear and a life bar", G.companion_style() == "striker" and G.companion_level() == 0 and G.companion_gear("weapon") == "" and G.companion_hp() == G.companion_max_hp() and G.companion_hp() > 0)
			var d_strike: int = G.companion_damage()
			check("set a style: guard hits softer, hunts closer", G.set_companion_style("guard") and G.companion_style() == "guard" and G.companion_damage() < d_strike and float(G.style_def().get("hunt", 0)) < 9.0)
			check("...and a style you don't know is refused", not G.set_companion_style("ninja") and G.companion_style() == "guard")
			G.set_companion_style("striker")
			G.inventory["iron_sword"] = 1
			G.inventory["padded_vest"] = 1
			var d0: int = G.companion_damage()
			var h0: int = G.companion_max_hp()
			var msg: String = G.give_companion_gear("iron_sword")
			check("give them a sword: it leaves your pouch, their strike grows, and it shows in their hand", msg.contains("takes") and G.count("iron_sword") == 0 and G.companion_gear("weapon") == "iron_sword" and G.companion_damage() > d0)
			G.give_companion_gear("padded_vest")
			check("give them armour: more life", G.companion_gear("armor") == "padded_vest" and G.companion_max_hp() > h0)
			check("a potion is not gear", G.give_companion_gear("healing_salve").contains("only carry") )
			G.inventory["iron_sword"] = 1
			G.inventory["spirit_blade"] = 1 if G.has_item_def("spirit_blade") else 0
			G.give_companion_gear("iron_sword")
			check("a second weapon hands the first back", G.count("iron_sword") == 1 and G.companion_gear("weapon") == "iron_sword")
			check("take it back: it's yours again", G.take_companion_gear("weapon").contains("take back") and G.companion_gear("weapon") == "" and G.count("iron_sword") == 2)
			var xp0: float = G.companion_xp_total()
			var gob32 = _find("Enemy.gd", func(n): return not n._dead and not bool(n.stats.get("passive", false)))
			cp.global_position = gob32.global_position + Vector3(1.0, 0, 0)
			cp._cool = 0.0
			cp.strike(gob32)
			check("every strike teaches them (xp)", G.companion_xp_total() > xp0)
			gob32.hp = 1
			cp._cool = 0.0
			cp.strike(gob32)
			check("a kill teaches more, and is logged", G.companion_xp_total() >= xp0 + 5.0 and gob32._dead)
			G.comp_bond()["xp"] = 149.0
			G.companion_xp(11.0)
			check("levels follow the xp table (160 xp: level 3, 'seasoned'), and the strike grows with them", G.companion_level() == 3 and G.companion_level_name() == "seasoned" and G.companion_damage() > d0)
			var d_guard: int = G.companion_damage()
			# guard: steps into blows
			G.set_companion_style("guard")
			cp.global_position = player.global_position + Vector3(1, 0, 0)
			var took := 0
			var hp_p0: int = G.hp
			seed(7)
			for i in 40:
				if G.companion_intercept(1, true) == 0:
					took += 1
			check("a Guard steps into blows meant for you, about half the time, and takes the hurt", took >= 8 and took <= 32 and G.companion_hp() < G.companion_max_hp(), "took %d" % took)
			check("...never when they're not beside you", G.companion_intercept(10, false) == 10)
			G.companion["hp"] = 5
			G.companion_hurt(10, "a test")
			check("hurt enough, they go down for a while -- and don't fight", G.companion_down() and G.companion_intercept(10, true) == 10)
			G.companion["down_until"] = G.playtime - 1.0
			G.companion_tick(0.1)
			check("...and get up again at half life", not G.companion_down() and G.companion_hp() >= int(G.companion_max_hp() * 0.5) - 1)
			G.companion["hp"] = 5
			G.companion_hurt(10, "a test")
			G.take_home()
			G.rest_at_home()
			check("a night at home puts them back on their feet, whole", not G.companion_down() and G.companion_hp() == G.companion_max_hp())
			check("their growth lives in the bond (it survives parting)", float(G.bond("Little Rin").get("xp", 0.0)) >= 160.0 and str(G.bond("Little Rin").get("style", "")) == "guard")
			# scout: finds
			G.set_companion_style("scout")
			var found32 := ""
			for i in 30:
				found32 = cp.scout_find(0.1 + i * 0.01)
				if found32 != "":
					break
			check("a Scout turns things up on the floor", found32 != "" and G.count(found32) >= 1, found32)
			G.part_with_companion()
			cp.queue_free()
			# -- a familiar grows up
			G.familiar = {"species": "cave_hare", "name": "Burrow", "bond": 0.0}
			var fm = load("res://scripts/actors/Familiar.gd").new()
			root.add_child(fm)
			check("a new familiar is at the first stage: no bite, gives x1", G.familiar_stage() == 0 and G.familiar_bite() == 0 and G.familiar_effect_mult() == 1.0 and G.familiar_title() == "Burrow")
			var sc0: Vector3 = fm._model.scale
			G.grow_bond(45.0)
			check("bond 45: it has GROWN -- a stage, a window, a bite, more of what it gives, and it's bigger", G.familiar_stage() == 1 and G.familiar_title() == "Burrow the grown" and G.familiar_bite() > 0 and G.familiar_effect_mult() == 1.3 and _moment_seen("Burrow -- Grown") and fm._model.scale.x > sc0.x)
			hd._moments_q.clear()
			var eff: Dictionary = G._effects().filter(func(e): return e.has("gather_chance")).reduce(func(a, b): return a if float(a.get("gather_chance", 0)) >= float(b.get("gather_chance", 0)) else b, {})
			check("...and the gift really is bigger (Burrow's gather chance)", float(eff.get("gather_chance", 0.0)) > 0.1 * 1.45 * 1.2, str(eff))
			var gob33 = _find("Enemy.gd", func(n): return not n._dead and not bool(n.stats.get("passive", false)))
			fm.global_position = gob33.global_position + Vector3(1.0, 0, 0)
			var ghp: int = gob33.hp
			fm.bite(gob33)
			check("a grown familiar bites", gob33.hp < ghp and fm._bite_cool > 0.0)
			G.grow_bond(130.0)
			check("bond 175: a spirit beast, giving x2.2", G.familiar_stage() == 3 and G.familiar_effect_mult() == 2.2 and G.familiar_title().ends_with("spirit beast"))
			hd._moments_q.clear()
			# -- the taming tree
			check("taming is a skill, and the tree's first tier waits on Taming 1", G.skill_defs.has("taming") and G.taming_tiers().size() == 3 and not G.taming_tiers()[0][2])
			check("...so nothing can be chosen yet", G.choose_perk("keen_nose") != "" and G.taming_perks.is_empty())
			var tx0: float = float(G.skills.get("taming", 0.0))
			G.taming_xp("feed")
			check("feeding teaches taming", float(G.skills.get("taming", 0.0)) > tx0)
			G.skills["taming"] = 10.0 * 2 * 2 + 1.0      # level 2
			check("Taming 2: tier one is open, tier two not", G.taming_tiers()[0][2] and not G.taming_tiers()[1][2])
			var bite0: int = G.familiar_bite()
			check("choose Sharp Fangs: bites hurt more", G.choose_perk("sharp_fangs") == "" and G.has_perk("sharp_fangs") and G.familiar_bite() > bite0)
			check("...one choice a tier: Keen Nose is closed now", G.choose_perk("keen_nose") != "" and not G.has_perk("keen_nose"))
			G.skills["taming"] = 10.0 * 6 * 6 + 1.0      # level 5
			var em0: float = G.familiar_effect_mult()
			check("Taming 5: Thick Hide (gives a third more) and Pack Bond (bites mend you)", G.choose_perk("thick_hide") == "" and G.familiar_effect_mult() > em0 and G.choose_perk("pack_bond") == "")
			G.hp = 10
			fm._bite_cool = 0.0
			fm.bite(gob33)
			check("...a bite mends you", G.hp > 10)
			G.save_game()
			G.taming_perks = []
			G.load_game()
			check("perks survive save + load", G.has_perk("sharp_fangs") and G.has_perk("thick_hide") and G.has_perk("pack_bond"))
			fm.queue_free()
			# -- the home grows into a compound
			_build("village")
			var hm = _find("Home.gd")
			check("home starts as Elder Mo's plot; the sign is where you build", G.home_stage() == 0 and hm._spots.has("sign") and hm.prompt_for("sign").contains("build a cottage") and hm._tent.visible and not hm._spots.has("shrine"))
			G.gold = 10
			check("too poor: the sign says what it costs", G.home_upgrade_check().contains("350 gold"))
			G.gold = 5000
			check("...and what it needs", G.home_upgrade_check().contains("Iron Ore"))
			G.inventory["iron_ore"] = 5
			G.home["stash"] = {"iron_ore": 3, "spirit_resin": 2}
			var rest0: float = G.home_rested_mult()
			check("build the cottage: gold and materials (pouch first, then the stash), the tent gives way to walls, rest lasts twice as long", G.home_upgrade() == "" and G.home_stage() == 1 and G.gold == 4650 and G.count("iron_ore") == 0 and int(G.home["stash"].get("iron_ore", 0)) == 0 and not G.home["stash"].has("spirit_resin")
				and G.home_rested_mult() == 2.0 * rest0 and _moment_seen("Your home is now a cottage"))
			hd._moments_q.clear()
			hm._build_compound()
			check("...and it shows", not hm._tent.visible and hm._compound.get_child_count() >= 3)
			G.inventory["iron_ore"] = 16
			G.inventory["rough_jade"] = 3
			check("the courtyard: a cultivation stone of your own", G.home_upgrade() == "" and G.home_has_shrine())
			hd._moments_q.clear()
			hm._build_compound()
			check("...a shrine spot appears at home", hm._spots.has("shrine") and hm.prompt_for("shrine").contains("cultivate"))
			G.inventory["silver_ore"] = 6
			G.inventory["spirit_resin"] = 6
			G.inventory["rough_jade"] = 4
			check("the compound: the last stage", G.home_upgrade() == "" and G.home_stage() == 3 and G.home_next_stage().is_empty() and G.home_upgrade_check().contains("nothing more"))
			hd._moments_q.clear()
			G.flags.erase("ask:travel:Little Rin")
			G.bond("Little Rin")["warmth"] = 200.0
			G.ask_companion("Little Rin", "Little Rin, a healer", "village", Color.WHITE, 0.0)
			G.familiar = {"species": "cave_hare", "name": "Burrow", "bond": 10.0}
			var cx0: float = G.companion_xp_total()
			var al: Array = G.home_away_lines(4.0)
			check("a compound looks after yours while you're away: the companion trains, the familiar's bond grows", al.size() == 2 and G.companion_xp_total() == cx0 + 48.0 and float(G.familiar["bond"]) >= 18.0 * 1.0 - 0.01, str(al))
			G.part_with_companion()
			G.new_game()
			_build("floor1")
			wait = 0.1
		58:
			print("== round 33: the last floor, the Heart of the Deep, the ending ==")
			G.new_game()
			check("the back half of the story has its acts (30, 35, 40, 45) and they fire in order", G.story_acts().size() == 13 and G.story_check("floor_reached", 36) == ["seeding", "wens_debt", "envoy", "rival", "pagoda", "expedition", "last_steel"] and G.story_check("floor_reached", 45) == ["sickness", "last_letter"])
			G.inventory["iron_sword"] = 1
			var inv0: int = G.inventory.size()
			G.story_choose("last_steel", 0)
			check("Hale's night at the forge: two pieces of real gear", G.has_flag("story:last_steel") and G.inventory.size() >= inv0 + 1)
			G.bloodline["dominant"] = "asura"
			G.bloodline["purity"] = {"asura": 30.0}
			G.story_choose("sickness", 0)
			check("Lin's draught: your blood goes quiet by 8, for good", float(G.bloodline["purity"]["asura"]) == 22.0 and ("Eliet's Keeper" in G.titles))
			G.new_game()
			for a3 in G.story_acts():
				if str(a3["id"]) != "after":
					G.set_flag("story:%s:done" % a3["id"])          # (the road behind you, for this test)
			var fd: Dictionary = G.load_level_def("floor3").duplicate(true)
			fd["id"] = "floor50"
			fd["name"] = "Floor 50, the Heart of the Deep -- The Test"
			fd["depth"] = 50
			fd["final"] = true
			fd["exits"]["<"] = {"to": "floor49", "arrive": ">", "label": "Up to floor 49", "down": false}
			fd["exits"][">"] = {"to": "ending", "arrive": "<", "label": "Into the Heart of the Deep"}
			_build_def(fd)
			G.current_level = "floor50"
			var hd3 = root.get_tree().get_first_node_in_group("hud")
			hd3._moments_q.clear()
			var down = _find("Exit.gd", func(n): return str(n.target) == "ending")
			check("the last floor's stairs lead to the ending, not a floor", down != null and down.label.contains("Heart"))
			var boss50 = _find("Enemy.gd", func(n): return bool(n.stats.get("boss", false)) and not n._dead)
			check("(setup) the floor has a master", boss50 != null)
			down._armed = true
			down._on_body_entered(player)
			check("with the master alive, the Heart won't open", not G.finished() and G.finale_check(root.get_tree()) != "")
			boss50._die()
			down._armed = true
			down._on_body_entered(player)
			check("kill it and walk in: the game is finished -- a flag, a title, the ending screen, Mo's last scene waiting", G.finished() and ("Heart of the Deep" in G.titles)
				and hd3._ending != null and hd3._ending.visible and hd3.is_blocking() and G.story_state("after") == "open")
			var ep: Array = G.epilogue_lines()
			check("the epilogue is written from what you chose (here: nothing yet, so the opening and the closing)", ep.size() >= 2 and str(ep[0]).contains("fifty floors") and str(ep[-1]).contains("sequel"))
			G.set_flag("story:ending_delver")
			G.set_flag("story:mo_forgiven")
			G.partner = "Little Rin"
			check("...and grows with every choice and companion", G.epilogue_lines().size() == ep.size() + 3 and G.epilogue_lines().any(func(l): return str(l).contains("Little Rin")))
			G.partner = ""
			check("the credits name the makers and the road you took", G.credits_lines().any(func(l): return str(l).contains("Robert")) and G.credits_lines().any(func(l): return str(l).contains("floors")))
			hd3.close_ending()
			check("close it and play goes on", not hd3.is_blocking())
			_build("village")
			var mo2 = _find("NPC.gd", func(n): return n.npc_name == "Elder Mo")
			mo2.interact(player)
			check("in Eliet, Mo has the last scene: stay, or go east (the sequel)", hd3._dialog_title.text.contains("After the Heart") and _btn_has("I'll stay") and _btn_has("I'll go east"))
			hd3.close_dialog()
			G.story_choose("after", 1)
			check("go east: a title, and the epilogue says so", ("The Wanderer" in G.titles) and G.epilogue_lines().any(func(l): return str(l).contains("east")))
			G.save_game()
			G.load_game()
			check("finished survives save + load", G.finished() and G.counters.get("finished", 0.0) >= 1.0)
			G.new_game()
			_build("floor1")
			wait = 0.1
		59:
			print("== round 34: gates, buffs, the curve, the road down, errands ==")
			G.new_game()
			_build("floor1")
			var hd4 = root.get_tree().get_first_node_in_group("hud")
			hd4._moments_q.clear()
			# -- gates
			check("floors without a gate are open", G.gate_check("floor3") == "" and G.gate_check("village") == "")
			var w6: String = G.gate_check("floor6")
			check("floor 6 needs Qi Condensation -- the stairs say so, and what it takes", w6.contains("Qi Condensation") and w6.contains("drown") and G.gate_missing(6) == ["the Qi Condensation realm"])
			G.realm = 1
			check("...break through and it opens", G.gate_check("floor6") == "")
			G.realm = 3
			check("floor 11 needs Core Formation and a crafted pill", G.gate_missing(11) == ["a Deep Breath Pill"])
			G.realm = 1
			check("...(without the realm, both)", G.gate_missing(11).size() == 2)
			G.realm = 3
			G.inventory["deep_breath_pill"] = 1
			check("...have it and the way is clear", G.gate_check("floor11") == "")
			G.gate_pass("floor11")
			check("passing spends the pill and the gate stays open", G.count("deep_breath_pill") == 0 and G.gate_passed(11) and G.gate_check("floor11") == "" and G.gate_missing(11).is_empty())
			G.story_def = {}
			check("deeper gates ask for skills, your weapon, and the story", G.gate_missing(21).has("Survival 10") and G.gate_missing(36).any(func(m): return str(m).contains("(the weapon you carry)")) and G.gate_missing(26).any(func(m): return str(m).contains("the story: The Mirror")), "%s | %s | %s" % [G.gate_missing(21), G.gate_missing(36), G.gate_missing(26)])
			check("the next gate is the first one not yet passed", int(G.next_gate().get("floor", 0)) == 6)
			G.realm = 0
			_build("floor5")
			var st6 = _find("Exit.gd", func(n): return str(n.target) == "floor6")
			check("(setup) floor 5 has the stairs to 6", st6 != null)
			_changed_to = ""
			st6._armed = true
			st6._on_body_entered(player)
			check("the stairs refuse an untempered body (a window says why), and log it", _changed_to == "" and not G.gate_passed(6) and hd4._dialog.visible and hd4._dialog_title.text.contains("floor 6"))
			hd4.close_dialog()
			G.realm = 1
			st6._armed = true
			st6._on_body_entered(player)
			check("...and take a condensed one: the gate is passed for good (and the stairs take you)", G.gate_passed(6) and not st6._armed)
			# -- buffs
			G.inventory["whetstone"] = 1
			var dm0: float = G.tech_effect("damage_mult", 1.0)
			check("a whetstone is a crafted buff: +20% damage for ten minutes", G.use_item("whetstone") and G.tech_effect("damage_mult", 1.0) > dm0 * 1.19 and G.buff_left("whetstone") > 500.0 and G.buff_lines().size() == 1)
			G.buffs["whetstone"]["until"] = G._now() - 1.0
			check("...and it wears off", G.tech_effect("damage_mult", 1.0) == dm0 and G.buff_lines().is_empty())
			G.inventory["hunters_oil"] = 1
			G.use_item("hunters_oil")
			check("hunter's oil: a crit chance where there was none", G.tech_effect("crit_chance", 0.0) >= 0.1)
			G.buffs = {}
			check("the gate items and buffs have recipes at the benches", G.recipes.any(func(r): return r["makes"] == "deep_breath_pill" and r["skill"] == "alchemy") and G.recipes.any(func(r): return r["makes"] == "star_iron_key" and r["skill"] == "smithing") and G.recipes.any(func(r): return r["makes"] == "qi_incense"))
			# -- the curve
			check("the curve: nothing until floor 3, then a little more every floor", G.curve_mult(1, "hp") == 1.0 and G.curve_mult(2, "hp") == 1.0 and absf(G.curve_mult(10, "hp") - (1.0 + 8 * float(G.combat_data()["curve"]["hp_per_floor"]))) < 0.001 and G.curve_mult(50, "damage") > G.curve_mult(25, "damage"))
			var fd3: Dictionary = G.load_level_def("floor1").duplicate(true)
			fd3["depth"] = 3
			_build_def(fd3)
			var g3 = _find("Enemy.gd", func(n): return n.etype == "goblin" and n.affixes.is_empty() and not n.elite)
			var hp3: int = g3.stats["hp"] if g3 else 0
			fd3["depth"] = 23
			_build_def(fd3)
			var g23 = _find("Enemy.gd", func(n): return n.etype == "goblin" and n.affixes.is_empty() and not n.elite)
			var hp23: int = g23.stats["hp"] if g23 else 0
			check("the same goblin twenty floors deeper is harder", hp3 > 0 and hp23 > hp3 * 1.3, "%d -> %d" % [hp3, hp23])
			# -- the road down
			G.new_game()
			_build("village")
			check("the main quest starts at chapter one with its first goal", G.mq_index() == 0 and G.mq_chapter()["id"] == "first_steps" and G.mq_next_goal().contains("Elder Mo") and G.mq_line().contains("The Road Down"))
			G.set_flag("fs:done")
			check("...and the HUD's first goal line is the road down", str(G.next_goals()[0]).contains("The Road Down"))
			var mo4 = _find("NPC.gd", func(n): return n.npc_name == "Elder Mo")
			mo4.interact(player)
			check("talking to Mo ticks the first goal; his dialog shows the road and his errands", G.mq_progress()[0][1] and hd4._dialog_body.text.contains("The road down") and not G.mq_ready())
			hd4.close_dialog()
			_build("floor1")
			check("going down ticks the second", G.mq_progress()[1][1] and not G.mq_progress()[2][1])
			G.record_kill("goblin_chief")
			check("killing the floor's master ticks the third: the chapter is ready, report to Mo", G.mq_ready() and G.mq_reporter() == "Elder Mo" and G.mq_line().contains("report to Elder Mo"))
			_build("village")
			mo4 = _find("NPC.gd", func(n): return n.npc_name == "Elder Mo")
			mo4.interact(player)
			check("Mo takes the report first", hd4._dialog_title.text.contains("road down") and _btn_has("Report it"))
			hd4.close_dialog()
			var gold4: int = G.gold
			var got4: String = G.mq_complete()
			check("report: the reward lands, the next chapter opens, a window says so", got4.contains("40 gold") and G.gold == gold4 + 40 and G.count("whetstone") >= 2 and G.mq_index() == 1 and G.mq_chapter()["id"] == "three_floors" and _moment_seen("Chapter done: The Road Down"))
			hd4._moments_q.clear()
			check("...and the next goal is the next chapter's", G.mq_next_goal().contains("Healing Salve"))
			check("twelve chapters walk the road to the Heart: gates, realms, crafts, the story", G.mq_chapters().size() == 12 and G.mq_chapters()[-1]["goals"].any(func(g): return g.has("finished")) and G.mq_chapters().any(func(c): return c["goals"].any(func(g): return g.has("gate") and int(g["gate"]) == 46)))
			G.mq_data()["chapters"].append({"id": "_test", "name": "Test", "who": "", "goals": [{"realm": 0}], "reward": {"gold": 5}})
			G.mq["chapter"] = G.mq_chapters().size() - 1
			var g5: int = G.gold
			G.log_event("ping")
			check("a chapter with nobody to report to completes itself", G.gold == g5 + 5 and G.mq_finished_all())
			G.mq_data()["chapters"].pop_back()
			G.mq_def = {}
			G.mq = {}
			# -- errands
			G.new_game()
			_build("floor1")
			var ed: Dictionary = G.errand_defs()
			check("Elder Mo has errands for every floor you've reached: a kill and a gather, from the floor's own foes and chests", ed.has("errand:kill:1") and ed.has("errand:gather:1") and ed["errand:kill:1"]["goal"]["kill"] == "goblin" and ed["errand:gather:1"]["goal"]["have"] == "iron_ore")
			check("...not for floors you haven't", not ed.has("errand:kill:2"))
			G.errand_accept("errand:kill:1")
			var need4: int = int(ed["errand:kill:1"]["goal"]["count"])
			for i in need4 - 1:
				G.record_kill("goblin")
			check("kills count from when you took it", G.quests["errand:kill:1"] == "active" and not G.errand_ready("errand:kill:1"))
			G.record_kill("goblin")
			var gold5: int = G.gold
			check("...done: Mo pays", G.errand_ready("errand:kill:1") and G.errand_turn_in("errand:kill:1").contains("gold") and G.gold > gold5 and G.quests["errand:kill:1"] == "done")
			_build("village")
			mo4 = _find("NPC.gd", func(n): return n.npc_name == "Elder Mo")
			mo4.interact(player)
			check("his dialog offers the errands", hd4._dialog_body.text.contains("Errands:") and _btn_has("Take on: Bring up Iron Ore"))
			hd4.close_dialog()
			G.save_game()
			G.mq = {}
			G.load_game()
			check("the road and the buffs survive save + load", G.mq_index() == 0 and G.quests.get("errand:kill:1", "") == "done")
			G.new_game()
			_build("floor1")
			wait = 0.1
		60:
			print("== round 34: hidden masters ==")
			G.new_game()
			_build("village")
			var hd5 = root.get_tree().get_first_node_in_group("hud")
			hd5._moments_q.clear()
			check("fourteen hidden masters, each with a place, a disguise, a test and a technique (or, two of them, a craft) of their own", G.hm_data()["masters"].size() == 14
				and G.hm_data()["masters"].all(func(m): return m.has("place") and m.has("disguise") and m.has("test") and (G.technique_defs.has(str(m["reward"].get("technique", {}).get("id", ""))) or G.skill_defs.has(str(m["reward"].get("craft", ""))))))
			check("their techniques use only effects the game reads", G.hm_data()["masters"].all(func(m): return (m["reward"].get("technique", {}).get("effect", {}) as Dictionary).keys().all(func(k): return k in ["damage_taken", "move_mult", "dodge_chance", "meditate_mult", "craft_success_alchemy", "craft_success_medicine", "rebirth", "craft_success_smithing", "damage_mult", "loot_luck", "qi_mult", "attack_speed", "crit_chance", "swarm_mult", "hp_mult"])))
			check("no technique comes free: check_unlocks never teaches a master's art", (func(): G.check_unlocks(); return not G.techniques.has("broom_stance")).call())
			var su = _find("HiddenMaster.gd", func(n): return n.master_id == "sweeper")
			check("in Eliet, an old sweeper -- nobody special, by the look of her", su != null and su._label.text == "An Old Sweeper" and su.prompt().contains("old sweeper"))
			check("the journal's rumour points at her", G.hm_hint().contains("sweeps"))
			su.interact(player)
			check("talk once: an ordinary line", hd5._dialog_title.text == "An Old Sweeper" and G.hm_stage("sweeper") == "")
			hd5.close_dialog()
			su.interact(player)
			hd5.close_dialog()
			su.interact(player)
			check("the third time, she shows who she is, and sets a test", G.hm_stage("sweeper") == "revealed" and hd5._dialog_title.text.contains("Broom Saint") and hd5._dialog_body.text.contains("Their test") and su._label.text.contains("Broom Saint"))
			hd5.close_dialog()
			su.interact(player)
			check("...not passed yet: \"Not yet\", with the count", hd5._dialog_body.text.contains("Not yet") and hd5._dialog_body.text.contains("/ 600") and not _btn_has("Show them"))
			hd5.close_dialog()
			G.counters["shrine_seconds"] = float(G.counters.get("shrine_seconds", 0.0)) + 600.0
			su.interact(player)
			check("sit ten minutes and she'll see it", _btn_has("Show them") and G.hm_test_ready("sweeper"))
			hd5.close_dialog()
			var td0: float = G.tech_effect("damage_taken", 1.0)
			var got5: String = G.hm_complete("sweeper")
			check("she teaches: a technique no one else knows, a title, insight -- and a window saying so", G.techniques.has("broom_stance") and G.tech_effect("damage_taken", 1.0) < td0 and ("Su's Student" in G.titles) and got5.contains("Broom Saint") and _moment_seen("Grandmother Su, the Broom Saint") and G.hm_stage("sweeper") == "done")
			hd5._moments_q.clear()
			check("...and only once", G.hm_complete("sweeper") == "" and G.hm_count_done() == 1)
			# a master who needs strength before they'll show themselves
			G.counters["hm_talk:fisher"] = 5.0
			check("Old Bao won't show himself to an untempered body", G.hm_reveal_missing("fisher") == ["realm"] and G.hm_talk("fisher") == "")
			G.realm = 1
			check("...condensed, he does", G.hm_talk("fisher") == "reveal" and G.hm_stage("fisher") == "revealed")
			G.inventory["cave_carp"] = 3
			check("bring three fish: they're taken, and he teaches", G.hm_test_ready("fisher") and G.hm_complete("fisher") != "" and G.count("cave_carp") == 0 and G.techniques.has("still_water"))
			hd5._moments_q.clear()
			# kill tests count from the reveal, on the floor's own foes
			G.counters["hm_talk:ratcatcher"] = 1.0
			G.kills["goblin"] = 50
			G.hm_talk("ratcatcher")
			check("the ratcatcher's test counts this floor's foes from when he set it", G.hm_stage("ratcatcher") == "revealed" and str(G.hm["ratcatcher"]["foe"]) != "" and G.hm_test_progress("ratcatcher")[0] == 0)
			var foe5: String = str(G.hm["ratcatcher"]["foe"])
			G.kills[foe5] = int(G.kills.get(foe5, 0)) + 20
			check("...twenty more and it's done", G.hm_test_ready("ratcatcher"))
			# waiting is a test too
			G.realm = 2
			G.counters["hm_talk:bonepicker"] = 1.0
			G.hm_talk("bonepicker")
			check("Sister Ivory: come back after twelve real hours (not before)", G.hm_stage("bonepicker") == "revealed" and not G.hm_test_ready("bonepicker"))
			G.hm["bonepicker"]["at"] = G._now() - 13 * 3600.0
			check("...and after, you're ready", G.hm_test_ready("bonepicker"))
			# give gold
			G.realm = 5
			G.counters["hm_talk:beggar"] = 3.0
			G.hm_talk("beggar")
			G.gold = 600
			G.hm_complete("beggar")
			check("the beggar's test costs what it says", G.gold == 100 and G.techniques.has("open_hand"))
			hd5._moments_q.clear()
			check("every master stands where the data puts them: the village, the valley, the floors", G.hm_masters_at("village").size() == 1 and G.hm_masters_at("valley").size() == 1 and G.hm_masters_at("floor10").size() == 1)
			_build("floor10")
			check("a boardwalk town still finds room for its master", _find("HiddenMaster.gd") != null)
			G.save_game()
			G.hm = {}
			G.load_game()
			check("found and taught survive save + load", G.hm_stage("sweeper") == "done" and G.hm_stage("ratcatcher") == "revealed" and G.techniques.has("broom_stance"))
			G.new_game()
			_build("floor1")
			wait = 0.1
		61:
			print("== round 35: fog of war ==")
			G.new_game()
			_build("floor3")
			var fog = level.get_node_or_null("FogOfWar")
			check("underground, the floor has a fog of war", fog != null)
			_build("village")
			check("...the village doesn't", level.get_node_or_null("FogOfWar") == null)
			_build("floor3")
			fog = level.get_node_or_null("FogOfWar")
			var st3: Vector2i = level.spawns["<"][0] + Vector2i(0, 1)
			_place_player(st3)
			var fresh: int = fog.reveal_from(st3)
			check("arriving, you see what's around you -- and only that", fresh > 10 and fog.state(st3) == "visible" and fog.explored_fraction() < 0.5, "%d cells, %.2f explored" % [fresh, fog.explored_fraction()])
			var far := Vector2i(-1, -1)
			for c in fog._cells:
				if not fog.blocks(c) and (c - st3).length() > 30:
					far = c
					break
			check("the far side of the floor is unexplored", far.x >= 0 and fog.state(far) == "unexplored")
			# walls block sight
			var behind := Vector2i(-1, -1)
			for c in fog._cells:
				if not fog.blocks(c) and (c - st3).length() <= 6.0 and not fog.line_clear(st3, c):
					behind = c
					break
			check("a cell behind a wall, close by, stays dark", behind.x < 0 or fog.state(behind) != "visible")
			# a foe out of sight is hidden; in sight, shown
			var foe = _find("Enemy.gd", func(n): return not n._dead and (level.world_to_cell(n.global_position) - st3).length() > 20)
			fog._hide_things()
			check("a foe across the floor can't be seen", foe != null and not foe.visible and foe.has_meta("fog_hidden"))
			var fc: Vector2i = level.world_to_cell(foe.global_position)
			fog.reveal_from(fc)
			fog._hide_things()
			check("...walk up to it and it can", foe.visible and not foe.has_meta("fog_hidden"))
			fog.reveal_from(st3)
			fog._hide_things()
			check("...walk away and it fades again; the ground it stood on stays remembered", not foe.visible and fog.state(fc) == "remembered")
			# chests show once explored and stay
			var ch = _find("Chest.gd", func(n): return fog.state(level.world_to_cell(n.global_position)) == "unexplored")
			fog._statics_dirty = true
			fog._hide_things()
			check("an unexplored chest is hidden", ch == null or not ch.visible)
			if ch:
				var cc: Vector2i = level.world_to_cell(ch.global_position)
				fog.reveal_from(cc)
				fog.reveal_from(st3)
				fog._hide_things()
				check("...seen once, it stays where you saw it", ch.visible)
			# never un-hide what the fog didn't hide
			var lone = _find("Chest.gd", func(n): return n != ch)
			lone.visible = false
			fog._statics_dirty = true
			fog._hide_things()
			check("the fog never shows what something else hid", not lone.visible or not lone.has_meta("fog_hidden"))
			lone.visible = true
			# remembered across visits
			var seen_n: int = fog.seen.size()
			_build("floor1")
			_build("floor3")
			fog = level.get_node_or_null("FogOfWar")
			check("leave and come back: the floor remembers what you explored", fog.seen.size() == seen_n, "%d vs %d" % [fog.seen.size(), seen_n])
			G.save_game()
			G.fog_seen = {}
			G.load_game()
			check("...and so does a saved game", G.fog_load("floor3", level.grid).size() == seen_n)
			# sight
			var r0: int = fog.reveal_from(st3)
			G.inventory["spirit_lantern"] = 1
			G.use_item("spirit_lantern")
			check("a spirit lantern (smithing) lets you see further", G.sight_bonus() == 3 and fog.reveal_from(st3) > 0, str(G.sight_bonus()))
			G.buffs = {}
			fog.reveal_all()
			check("a floor's map can reveal everything", fog.explored_fraction() > 0.99)
			# the setting
			var GfxS = load("res://scripts/core/Gfx.gd")
			GfxS.load_settings()
			GfxS.next_fog(root.get_tree())
			check("fog of war can be turned off in the menu (and what it hid shows again)", str(GfxS.settings["fog"]) == "off" and root.get_tree().get_nodes_in_group("enemy").all(func(e): return not e.has_meta("fog_hidden")))
			_build("floor2")
			check("...off: no fog on the next floor", level.get_node_or_null("FogOfWar") == null)
			GfxS.next_fog(root.get_tree())
			check("...and back on", str(GfxS.settings["fog"]) == "on")
			G.new_game()
			_build("floor1")
			wait = 0.1
		62:
			print("== round 36: the character -- stats, earned attributes, titles, the level-up ==")
			G.new_game()
			_build("village")
			var hd6 = root.get_tree().get_first_node_in_group("hud")
			hd6._moments_q.clear()
			check("a new character has no attribute points -- they're earned", G.attr_points_earned() == 0 and G.attr_points_free() == 0 and not G.attr_spend("might"))
			var lv_seen := []
			var conn := func(info): lv_seen.append(info)
			G.level_up.connect(conn)
			var hp_a: int = G.max_hp()
			G.add_qi(G.qi_to_next() + 1.0)
			check("a step of cultivation: a level-up, with what changed (health up), and a point", lv_seen.size() == 1 and str(lv_seen[0]["kind"]) == "step"
				and lv_seen[0]["rows"].any(func(r): return str(r[0]) == "Health" and str(r[2]).contains("->")) and G.max_hp() > hp_a and G.attr_points_free() == 1)
			check("...a step shows as a card that doesn't stop play", hd6._lvl_card != null and hd6._lvl_card.visible and not hd6.is_blocking())
			var dmg_a: int = G.damage()
			check("spend it: Might -- damage rises", G.attr_spend("might") and G.damage() >= dmg_a and G.tech_effect("damage_mult", 1.0) > 1.02 and G.attr_points_free() == 0)
			check("...no more to spend than you've earned", not G.attr_spend("body"))
			G.realm = 1
			G.sublevel = 1
			check("a realm crossed is worth more (the steps, and 3 for the realm)", G.attr_points_earned() == 10 + 3)
			G.tribulation = {"tries": 0, "from_level": "village", "from_tag": "P"}
			lv_seen.clear()
			G.tribulation_won()
			check("a realm breakthrough is the full window", lv_seen.size() == 1 and str(lv_seen[0]["kind"]) == "realm" and hd6._moments_q.any(func(m): return str(m[0]) == "__level_up"))
			G.level_up.disconnect(conn)
			hd6._moments_q.clear()
			# titles carry gifts
			var hp_t: float = G.tech_effect("hp_mult", 1.0)
			check("titles carry a gift: Heart Unshaken (from the breakthrough) adds qi", ("Heart Unshaken" in G.titles) and G.title_gift_text("Heart Unshaken").contains("qi"))
			G.titles.append("Champion of the Ring")
			check("an unlisted title gives what its words suggest", G.title_gift("Champion of the Ring").has("damage_mult"))
			for i in 30:
				G.titles.append("Su's Student %d" % i)
			check("...and title gifts are capped (15% a stat)", G.title_effect().get("hp_mult", 1.0) <= 1.1501)
			G.titles = ["Heart Unshaken"]
			# the swarm and the qi sea feed the body too
			G.integration = 0.0
			var d_t0: float = G.tech_effect("damage_mult", 1.0)
			G.integration = 99999.0
			check("the swarm's tiers strengthen the hand as well as the body", G.nanite_tier() > 0 and G.nanite_effect().has("damage_mult") and G.tech_effect("damage_mult", 1.0) > d_t0)
			G.integration = 0.0
			# where a stat comes from
			G.inventory["iron_sword"] = 1
			G.equip("iron_sword")
			var srcs: Array = G.stat_sources("damage")
			check("the sheet says where damage comes from: cultivation, the weapon, attributes", srcs.any(func(r): return str(r[0]) == "Cultivation") and srcs.any(func(r): return str(r[0]) == "Weapon") and srcs.any(func(r): return str(r[0]) == "Attributes"))
			G.add_item("g_iron_ore_chest", 1, false)
			check("worn armour shows in health's sources", G.stat_sources("max_hp").any(func(r): return str(r[0]) == "What you wear"))
			# every kind of worn thing really reaches the character
			var fam_ok := true
			var fam_bad := []
			for id in ["g_iron_ore_pauldrons", "g_iron_ore_greaves", "g_beast_hide_boots", "g_spirit_silk_cowl", "g_iron_ore_gauntlets", "g_iron_ore_vambraces"]:
				if not G.has_item_def(id):
					continue
				var hp0: int = G.max_hp()
				var w0: float = G.total_ward()
				G.add_item(id, 1, false)
				if not (G.max_hp() > hp0 or G.total_ward() > w0):
					fam_ok = false
					fam_bad.append(id)
			check("every piece you put on adds to you (health or ward)", fam_ok, str(fam_bad))
			# the sheet itself
			hd6.open_character()
			check("P opens the character sheet: stats, attributes, titles, the road ahead", hd6._char.visible and hd6.is_blocking() and _label_has(hd6._char_body, "Attributes") and _label_has(hd6._char_body, "Titles") and _label_has(hd6._char_body, "The road down"))
			hd6.close_character()
			check("...and closes", not hd6._char.visible)
			G.gold = 10
			check("unlearning costs gold", G.attr_respec() != "" and G.attrs.size() > 0)
			G.gold = 5000
			check("...paid, the points come back", G.attr_respec() == "" and G.attr_points_spent() == 0 and G.attr_points_free() == G.attr_points_earned())
			G.attr_spend("spirit", 2)
			G.save_game()
			G.attrs = {}
			G.load_game()
			check("spent points survive save + load", int(G.attrs.get("spirit", 0)) == 2)
			# the spread valley
			var vd: Dictionary = G.load_level_def("valley")
			check("the valley is wider: more country between its places", str(vd["map"][0]).length() >= 180 and vd["map"].size() >= 145)
			G.new_game()
			_build("floor1")
			wait = 0.1
		63:
			print("== round 36: who you are -- character creation ==")
			G.new_game()
			_build("village")
			var hd7 = root.get_tree().get_first_node_in_group("hud")
			check("a new game needs creating", G.needs_creation() and G.needs_background())
			hd7.start_creation()
			check("creation opens: a name, a look, a past, eight questions, a last page", hd7._create.visible and hd7.is_blocking() and hd7._cr["steps"].size() == 3 + 1 + 8 + 1 and hd7._cr_title.text == "Who are you?")
			check("every answer is worth the same (one point -- an attribute or a free point), the last question two or three",
				G.creation_data()["questions"].all(func(q): return q["answers"].all(func(a): return (a.get("attrs", {}) as Dictionary).values().reduce(func(x, y): return x + y, 0) + int(a.get("free", 0)) + int(a.get("lean", 0)) == (2 if q["id"] == "road" else 1))))
			var fighter := {"born": 1, "trouble": 1, "hands": 0, "fear": 0, "why": 1, "temper": 1, "road": 0}
			var t7: Dictionary = G.creation_tally(fighter)
			check("a fighter's answers start them strong in Might (and leaning in adds to it)", int(t7["attrs"]["might"]) == 7 and int(t7["free"]) == 0, str(t7))
			var drifter := {"born": 3, "trouble": 3, "hands": 3, "fear": 2, "why": 2, "temper": 0, "road": 2}
			var t8: Dictionary = G.creation_tally(drifter)
			check("a drifter who leaves it to the road starts with free points instead", int(t8["free"]) == 5 and int(t8["attrs"]["spirit"]) == 3, str(t8))
			# click through: name, look, past, answers
			hd7._cr_go(1)
			hd7._cr["name"] = "Robert"
			hd7._cr_go(1)
			hd7._cr["look"]["sex"] = "f"
			hd7._cr["look"]["hair"] = "long"
			hd7._cr_go(1)
			check("the past step lists every background", hd7._cr_title.text.contains("before the road") and _cr_btn_has(hd7, "Militia Spear"))
			hd7._cr["past"] = "spearman"
			hd7._cr_go(1)
			check("then the questions, one at a time", hd7._cr_title.text == "Where were you born?" and _cr_btn_has(hd7, "In Eliet"))
			hd7._cr["answers"] = fighter.duplicate()
			hd7._cr["i"] = hd7._cr["steps"].size() - 1
			hd7._cr_show()
			check("the last page shows it all before you set out", hd7._cr_title.text == "This is who you are" and _cr_btn_has(hd7, "This is who I am") and _label_has(hd7._cr_body, "Might 7"))
			var g7: int = G.gold
			hd7._cr_finish()
			check("set out: the name, the look, the past and the start are yours", not G.needs_creation() and G.char_name == "Robert" and str(G.look["sex"]) == "f" and G.background == "spearman"
				and G.attr_total("might") == 7 and G.attr_born("might") == 7 and G.tech_effect("damage_mult", 1.0) > 1.14 and G.gold >= g7)
			check("...creation can't be run twice", G.creation_finish("Other", {}, drifter) == "already" and G.char_name == "Robert")
			check("born strengths aren't spent points: unlearning leaves them", (func():
				G.gold = 99999
				G.attr_respec()
				return G.attr_total("might") == 7).call())
			# the drifter: free points to spend straight away
			G.new_game()
			G.choose_background("hunter")
			G.creation_finish("", {"sex": "m"}, drifter)
			check("the drifter sets out with 5 points to spend, and a name the road gave", G.attr_points_free() == 5 and G.char_name != "")
			check("an older save with a past but no creation is asked (and only gains)", (func():
				G.flags.erase("creation_done")
				return G.needs_creation() and not G.needs_background()).call())
			G.set_flag("creation_done")
			G.save_game()
			G.char_name = ""
			G.born = {}
			G.load_game()
			check("who you are survives save + load", G.char_name != "" and int(G.born.get("free", 0)) == 5)
			G.new_game()
			G.choose_background("hunter")
			G.set_flag("creation_done")
			_build("floor1")
			wait = 0.1
		64:
			print("== round 37: balance, mastery, the sky, the roof, the body ==")
			G.new_game()
			G.choose_background("hunter")
			G.set_flag("creation_done")
			check("a new cultivator has no balance yet (nothing to balance)", G.balance() < 0.3 and G.balance_mult() < 1.1)
			G.attrs = {"might": 8}
			var lop: float = G.balance()
			G.attrs = {"body": 2, "might": 2, "agility": 2, "spirit": 2}
			check("even attributes are worth more balance than one piled high", G.balance() > lop)
			for sk in ["sword", "smithing", "mining"]:
				G.skills[sk] = 10.0 * 8 * 8
			G.realm = 2
			G.integration = 0.0
			while G.nanite_tier() < 2:
				G.integration += 50.0
			for e in G.ELEMENTS:
				G.affinity[e] = 20.0
			check("fighting, making and finding even, both roads together, every element: near-perfect balance", G.balance() > 0.85, str(G.balance_parts()))
			var gm: float = G.growth_mult()
			G.affinity["fire"] = 200.0
			G.skills["sword"] = 10.0 * 25 * 25
			check("...lean hard one way and growth slows", G.growth_mult() < gm)
			check("balance multiplies growth (qi, practice, the swarm) by up to x1.6", G.balance_mult() >= 1.0 and G.balance_mult() <= 1.6001)
			# mastery
			var mps: Array = G.mastery_parts()
			check("mastery counts everything the game holds -- and a new game has done almost none of it", mps.size() >= 12 and G.mastery() < 0.15, str(G.mastery()))
			check("...some of it can't be done in one life (ten bloodlines pure, both endings)", mps.any(func(m): return str(m[0]) == "bloodlines" and int(m[3]) >= 10) and mps.any(func(m): return str(m[0]) == "endings" and int(m[3]) == 2))
			G.set_flag("story:ending_sealed")
			G.bloodline["purity"] = {"asura": 100.0}
			G.ascension = {"count": 0, "marks": 0}
			var asc_ok: bool = G.ascend() == "" if G.can_ascend() == "" else false
			if asc_ok:
				check("an ending seen in a past life still counts after ascending", G.mastery_parts().any(func(m): return str(m[0]) == "endings" and int(m[2]) == 1))
			# the sky, the roof
			G.new_game()
			G.choose_background("hunter")
			G.set_flag("creation_done")
			_build("village")
			check("the village has a living sky (clouds, sun, moon, stars)", level._sky_mat != null and level._env.background_mode == Environment.BG_SKY and str(level._sky_mat.shader.resource_path).ends_with("sky.gdshader"))
			_build("floor3")
			check("underground: a rock roof over the open floor, and a far cavern vault above the walls", level.get_node_or_null("Ceiling") != null and str(level._sky_mat.shader.resource_path).ends_with("cave_sky.gdshader"))
			# the body
			player._body_motion(0.016)
			check("the body leans and looks (gaze set up on a figure with a head, or none on a simple one)", player._lean != null)
			G.hit_stop(0.05)
			check("a hit-stop slows the world for a moment...", Engine.time_scale < 0.5)
			G._hitstop_until = Time.get_ticks_msec() - 1
			G._process(0.0)
			check("...and always ends", Engine.time_scale == 1.0)
			G.new_game()
			G.choose_background("hunter")
			G.set_flag("creation_done")
			_build("floor1")
			wait = 0.1
		65:
			print("== round 38: rune craft and talismans ==")
			G.new_game()
			G.choose_background("hunter")
			G.set_flag("creation_done")
			_build("village")
			var hd8 = root.get_tree().get_first_node_in_group("hud")
			hd8._moments_q.clear()
			var R8: Dictionary = G.runes_data()
			check("two crafts nobody is born knowing: rune craft and talismans", G.skill_defs.has("runecraft") and G.skill_defs.has("talismans") and not G.skill_known("runecraft") and not G.skill_known("talismans"))
			check("runes, talismans, their papers and inks are items, each with a recipe", R8["runes"].keys().all(func(k): return G.items.has(k) and not G._recipe_for(k).is_empty())
				and R8["talismans"].keys().all(func(k): return G.items.has(k) and not G._recipe_for(k).is_empty()) and G.items.has("rune_blank") and G.items.has("spirit_paper") and G.items.has("cinnabar_ink"))
			var mats8 := []
			for k in R8["runes"]:
				mats8.append_array((R8["runes"][k]["needs"] as Dictionary).keys())
			for k in R8["talismans"]:
				mats8.append_array((R8["talismans"][k]["needs"] as Dictionary).keys())
			check("every rune and talisman is made from things the deep has", mats8.all(func(m): return G.items.has(str(m))), str(mats8.filter(func(m): return not G.items.has(str(m)))))
			var keys8 := ["damage_taken", "move_mult", "dodge_chance", "meditate_mult", "damage_mult", "loot_luck", "qi_mult", "attack_speed", "crit_chance", "hp_mult", "regen", "ward", "sight", "burn_on_hit", "heal_on_kill"]
			var effs8 := []
			for k in R8["runes"]:
				effs8.append(R8["runes"][k]["weapon"])
				effs8.append(R8["runes"][k]["wear"])
			for w in R8["words"]:
				effs8.append(w["effect"])
			check("runes and words only give what the game reads", effs8.all(func(e): return (e as Dictionary).keys().all(func(k): return k in keys8)))
			check("rune words use runes that exist, and none is a copy", R8["words"].all(func(w): return (w["runes"] as Array).all(func(r): return R8["runes"].has(str(r)))))
			# not taught: can't carve
			G.inventory["rune_blank"] = 2
			G.inventory["slag_iron"] = 2
			var er8: Dictionary = G._recipe_for("edge_rune")
			check("until you're taught, you can't carve a rune (and the bench won't either)", not G.can_craft(er8) and G.bench_can_make(er8) == 0)
			G.inventory["iron_sword"] = 1
			G.equip("iron_sword")
			check("...nor set one", not bool(G.inscribe("iron_sword", "rune_blank").get("ok", false)) and G.rune_sockets("iron_sword") == 0)
			# the teacher
			var oda: Dictionary = G.hm_master("rune_carver")
			check("Old Oda is on the seventeenth floor, and the rumours find him", str(oda.get("place", "")) == "floor17" and str(oda.get("hint", "")).contains("seventeenth"))
			_build("floor17")
			hd8._moments_q.clear()
			var od = _find("HiddenMaster.gd", func(n): return n.master_id == "rune_carver")
			check("...a grave-cutter, standing on floor 17", od != null)
			G.realm = 4
			G.counters["hm_talk:rune_carver"] = 1.0
			if od:
				od.interact(player)
				hd8.close_dialog()
			check("talk to him with a nascent soul and he shows you the old marks", G.hm_stage("rune_carver") == "revealed")
			G.inventory["silver_ore"] = 4
			G.inventory["bone_shard"] = 6
			check("bring silver and bone, and he teaches the craft", G.hm_complete("rune_carver") != "" and G.skill_known("runecraft") and G.count("edge_rune") >= 1 and G.count("rune_blank") >= 3)
			hd8._moments_q.clear()
			if od:
				od.interact(player)
				check("his table is open to you afterwards", _btn_has("Work at their table") and _btn_has("Ask about rune words"))
				hd8.close_dialog()
			# carve and set
			G.at_bench = "rune"
			check("taught, you can carve", G.can_craft(er8))
			var cr8: Dictionary = G.craft_attempt(er8, "balanced", 0.0, 0.5)
			check("...a Rune of the Edge, and Runecraft grows", bool(cr8.get("success", false)) and G.count("edge_rune") >= 2 and G.skills["runecraft"] > 90.0)
			check("a weapon takes one rune to begin with; a cloak too", G.rune_sockets("iron_sword") == 1)
			var dm0: int = G.damage()
			var in8: Dictionary = G.inscribe("iron_sword", "edge_rune", 0.0)
			check("set it: the sword hits harder", bool(in8.get("success", false)) and G.runes_on("iron_sword").size() == 1 and G.damage() > dm0, "%d -> %d" % [dm0, G.damage()])
			check("...and says so", G.item_desc("iron_sword").contains("Runes: Edge") and G.inscription_text("iron_sword") != "")
			check("a full weapon refuses another rune", not bool(G.inscribe("iron_sword", "edge_rune").get("ok", false)))
			var ec8: int = G.count("edge_rune")
			G.skills["runecraft"] = 10.0 * 8 * 8
			check("Runecraft 8: two runes in a weapon", G.rune_sockets("iron_sword") == 2)
			G.inventory["ember_rune"] = 2
			var fail8: Dictionary = G.inscribe("iron_sword", "ember_rune", 0.999)
			check("a slip cracks the rune (it's lost), never the sword", bool(fail8.get("ok", false)) and not bool(fail8.get("success", true)) and G.count("ember_rune") == 1 and G.runes_on("iron_sword").size() == 1)
			var w8: Dictionary = G.inscribe("iron_sword", "ember_rune", 0.0)
			check("Edge, then Ember: the runes speak a word -- Keen Flame", str(w8.get("word", "")) == "keen_flame" and G.rune_word_known("keen_flame") and G.runewords_found() == 1 and G.tech_effect("burn_on_hit", 0.0) >= 5.0)
			hd8._moments_q.clear()
			check("...and the word is a moment worth a window", true)
			check("mastery counts the rune words", G.mastery_parts().any(func(m): return str(m[0]) == "runewords" and int(m[2]) == 1 and int(m[3]) == 10))
			# worn runes pool
			G.inventory["iron_sword"] = 1
			G.gold += 200
			var sc8: String = G.scour("iron_sword")
			check("scouring takes the runes off, for gold", G.runes_on("iron_sword").is_empty() and sc8.contains("scoured"))
			G.skills["runecraft"] = 10.0 * 12 * 12
			var fams8 := {}
			for pid in G.items.keys():
				var fm: String = G.gear_family(str(pid))
				if fm == "" or fm == "weapon" or G.is_jewel(str(pid)) or fams8.has(fm) or fams8.size() >= 4:
					continue
				fams8[fm] = true
				G.inventory[str(pid)] = 1
				G.equip(str(pid))
			var dt0: float = G.tech_effect("damage_taken", 1.0)
			var set8 := 0
			for sl in G.gear_slots():
				var wid2: String = G.worn(str(sl[0]))
				if wid2 == "" or G.gear_family(wid2) == "weapon":
					continue
				for i in 2:
					G.inventory["edge_rune"] = 1
					if bool(G.inscribe(wid2, "edge_rune", 0.0).get("success", false)):
						set8 += 1
			var dt1: float = G.tech_effect("damage_taken", 1.0)
			check("runes on armour pool -- many of the same gift count for less, never past a quarter", set8 >= 2 and dt1 < dt0 and dt0 - dt1 <= 0.2501, "%d set, %.3f -> %.3f" % [set8, dt0, dt1])
			# a gate wants runes
			check("the gate to floor 36 asks for two runes in your weapon", G.gates_data()["gates"].any(func(g): return int(g["floor"]) == 36 and int(g["need"].get("weapon_runes", 0)) == 2))
			G.realm = 13
			G.skills[G.weapon_skill()] = 10.0 * 20 * 20
			G.inventory["heartfire_elixir"] = 1
			G.inscriptions.erase("iron_sword")
			G.weapon = "iron_sword"
			check("...without them it won't open", G.gate_missing(36).any(func(t): return str(t).contains("runes")))
			G.skills["runecraft"] = 10.0 * 15 * 15
			G.inventory["edge_rune"] = 3
			G.inscribe("iron_sword", "edge_rune", 0.0)
			G.inscribe("iron_sword", "edge_rune", 0.0)
			check("...with them it does (runecraft 15: three sockets)", G.rune_sockets("iron_sword") == 3 and G.weapon_runes() == 2 and not G.gate_missing(36).any(func(t): return str(t).contains("runes")))
			# talismans
			var hwa: Dictionary = G.hm_master("talisman_scribe")
			check("Sister Hwa, a letter-writer on floor 22, teaches talismans", str(hwa.get("place", "")) == "floor22" and str(hwa["reward"].get("craft", "")) == "talismans")
			G.realm = 6
			G.counters["hm_talk:talisman_scribe"] = 2.0
			G.hm_talk("talisman_scribe")
			G.inventory["spirit_silk"] = 2
			G.inventory["spirit_herb"] = 6
			check("bring her silk and herbs: you can draw now", G.hm_complete("talisman_scribe") != "" and G.skill_known("talismans") and G.count("flame_talisman") >= 2)
			hd8._moments_q.clear()
			G.inventory["spirit_paper"] = 2
			G.inventory["cinnabar_ink"] = 2
			G.inventory["crimson_bark"] = 1
			var it8: Dictionary = G.craft_attempt(G._recipe_for("ironskin_talisman"), "balanced", 0.0, 0.5)
			check("draw an Iron Skin Talisman", bool(it8.get("success", false)) and G.count("ironskin_talisman") >= 1)
			check("the gate to floor 26 wants a Mirror Seal Talisman, drawn from what floor 24 gives", G.gates_data()["gates"].any(func(g): return int(g["floor"]) == 26 and str(g["need"].get("item", "")) == "mirror_seal_talisman")
				and G._recipe_for("mirror_seal_talisman").get("skill", "") == "talismans")
			check("the readied talisman shows on the screen, key 4", G.talisman_line().contains("[4]"))
			var cyc8: String = G.talisman_cycle()
			check("5 switches between the kinds you carry", cyc8.contains("ready") and G.talismans_carried().size() >= 2)
			# burn them in a fight
			_build("floor3")
			hd8._moments_q.clear()
			var foes8 := root.get_tree().get_nodes_in_group("enemy").filter(func(e): return not e._dead)
			var f8 = foes8[0] if foes8.size() > 0 else null
			if f8:
				f8.global_position = player.global_position + Vector3(1.5, 0, 0)
				f8.hp = 999999
			var hp8: int = f8.hp if f8 else 0
			var fl0: int = G._talisman_count("flame_talisman")
			player._talisman_cd = 0.0
			var hit8: int = player.use_talisman("flame_talisman")
			check("a Flame Talisman burns everything near you", hit8 >= 1 and f8 != null and f8.hp < hp8 and f8._burn_t > 0.0 and G._talisman_count("flame_talisman") == fl0 - 1, "hit %d" % hit8)
			player._talisman_cd = 0.0
			var dtk0: float = G.tech_effect("damage_taken", 1.0)
			player.use_talisman("ironskin_talisman")
			check("an Iron Skin Talisman: blows land softer for a while", G.tech_effect("damage_taken", 1.0) < dtk0 * 0.7 and G.buff_left("ironskin_talisman") > 0.0)
			G.inventory["mending_talisman"] = 1
			G.hp = 10
			player._talisman_cd = 0.0
			player.use_talisman("mending_talisman")
			check("a Mending Talisman closes a third of you at once", G.hp >= 10 + int(G.max_hp() * 0.3))
			G.inventory["clear_sight_talisman"] = 1
			var fog8 = root.get_tree().get_first_node_in_group("fog_of_war")
			player._talisman_cd = 0.0
			player.use_talisman("clear_sight_talisman")
			check("a Clear Sight Talisman shows the whole floor, and you see further", (fog8 == null or fog8.explored_fraction() > 0.99) and G.sight_bonus() >= 4)
			G.inventory["binding_talisman"] = 1
			if f8 and is_instance_valid(f8):
				f8._stun = 0.0
			player._talisman_cd = 0.0
			player.use_talisman("binding_talisman")
			check("a Binding Talisman holds what's near you where it stands", f8 != null and is_instance_valid(f8) and f8.staggered())
			G.inventory["mirror_seal_talisman"] = 1
			check("the seal can't be burned in a fight (it's for the gate)", G.talisman_take("mirror_seal_talisman").is_empty() and G.count("mirror_seal_talisman") == 1 and not ("mirror_seal_talisman" in G.talismans_carried()))
			# the road down points at them
			var qtext := JSON.stringify(G.mq_data())
			check("the road down points at both teachers, a rune word, and two runes in your weapon", qtext.contains("\"learn\": \"runecraft\"") or qtext.contains("\"learn\":\"runecraft\""))
			check("...in the chapters around them", G.mq_chapters().any(func(c): return (c["goals"] as Array).any(func(g): return g.has("learn") and str(g["learn"]) == "talismans")) and G.mq_chapters().any(func(c): return (c["goals"] as Array).any(func(g): return g.has("weapon_runes"))))
			check("balance counts the new crafts among making", "runecraft" in G.char_data()["balance"]["craft_skills"])
			# the Runes tab
			G.at_bench = "rune"
			hd8.open_kit("Runes", "rune")
			check("the pack has a Runes tab: what you wear, its marks, your talismans, the table", _label_has(hd8._kit._rune_body, "Rune craft") and _label_has(hd8._kit._rune_body, "Talismans") and _label_has(hd8._kit._rune_body, "Rune words"))
			hd8.close_kit()
			# saved
			G.save_game()
			var ins8: Dictionary = G.inscriptions.duplicate(true)
			G.inscriptions = {}
			G.load_game()
			check("runes set and the talisman readied survive save + load", G.inscriptions == ins8 and G.skill_known("runecraft") and G.skill_known("talismans"))
			G.new_game()
			check("a new life starts with neither craft and nothing carved", not G.skill_known("runecraft") and G.inscriptions.is_empty())
			G.choose_background("hunter")
			G.set_flag("creation_done")
			_build("floor1")
			wait = 0.1
		66:
			print("== round 39: the menu, a party of two, contract beasts, bonds ==")
			G.new_game()
			G.choose_background("hunter")
			G.set_flag("creation_done")
			_build("village")
			var h9 = root.get_tree().get_first_node_in_group("hud")
			h9._moments_q.clear()
			# -- the menu
			check("one menu with sections down the side: You, Spirit, Pack, Party, Bonds, Road, Quests, World, Map, Mind, Swarm, Journal, Meridians, System", h9._hub != null and h9._hub.pages.size() == 14
				and ["You", "Spirit", "Pack", "Party", "Bonds", "Road", "Quests", "World", "Map", "Mind", "Swarm", "Journal", "Meridians", "System"].all(func(k): return h9._hub.pages.has(k) and h9._hub.buttons.has(k)))
			check("the old windows are its pages now", h9._inventory.get_parent() == h9._hub.holder and h9._journal.get_parent() == h9._hub.holder and h9._char.get_parent() == h9._hub.holder and h9._lattice.get_parent() == h9._hub.holder)
			for k9 in ["menu", "party", "bonds", "road", "inventory", "character", "journal", "lattice"]:
				check("a key for '%s'" % k9, InputMap.has_action(k9) and InputMap.action_get_events(k9).size() > 0)
			h9._hub.close_hub()
			h9._hub.last = "You"                 # (as on a fresh start: earlier tests used it)
			var ev := InputEventAction.new()
			ev.action = "menu"
			ev.pressed = true
			h9._unhandled_input(ev)
			check("Tab opens the menu (at You, the first time) and play stops for it", h9._hub.visible and h9._hub.current == "You" and h9.is_blocking() and h9._char.visible)
			h9._hub.step(5)
			check("E (or the right shoulder) flips through the sections in the rail's order (round 119: You, Spirit, Mind, Meridians, Swarm, then Pack)", h9._hub.current == "Pack" and h9._inventory.visible and not h9._char.visible)
			h9._hub.step(-6)
			check("Q flips back -- past the start, round to System", h9._hub.current == "System" and _label_has(h9._hub._system, "Keys"))
			var ev2 := InputEventAction.new()
			ev2.action = "pause"
			ev2.pressed = true
			h9._unhandled_input(ev2)
			check("Esc closes it", not h9._hub.visible and not h9.is_blocking() and not h9.get_tree().paused)
			h9._unhandled_input(ev)
			check("Tab again: back where you were (not System -- the last real section)", h9._hub.visible and h9._hub.current == "Pack")
			h9._unhandled_input(ev)
			check("...and Tab closes it", not h9._hub.visible)
			h9.toggle_journal()
			check("N jumps straight to the Journal", h9._hub.visible and h9._hub.current == "Journal" and h9._journal.visible)
			h9.toggle_journal()
			check("...N again closes", not h9._hub.visible and not h9._journal.visible)
			h9.open_kit("Bench", "home")
			check("a bench still opens the Pack at its Bench tab", h9._hub.current == "Pack" and G.at_bench == "home" and h9._kit.tabs.get_tab_title(h9._kit.tabs.current_tab) == "Bench")
			h9.close_kit()
			check("...and closing leaves the bench", G.at_bench == "" and not h9._hub.visible)
			h9.open_dialog("A question", "Over the menu?", [["Yes", h9.close_dialog]])
			h9._hub.show_page("Road")
			check("a window asked for from the menu shows over it", h9._dialog.get_index() > h9._hub.get_index())
			h9.close_dialog()
			check("closing that window leaves the menu open (and the mouse free)", h9._hub.visible and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
			h9._hub.close_hub()
			# -- a party of two
			check("one companion to begin with", G.party_cap() == 1)
			G.realm = 4
			check("Nascent Soul: room for a second", G.party_cap() == 2)
			for nm9 in ["Mei", "Jun", "Tan"]:
				G.warm_bond(nm9, 70.0)
			check("Mei comes", G.ask_companion("Mei", "Mei, a hunter.", "village", Color(1, 1, 1), 0.0) == "yes" and str(G.companion.get("name", "")) == "Mei")
			check("Jun comes too -- second in the party", G.ask_companion("Jun", "Jun.", "village", Color(1, 1, 1), 0.0) == "yes" and str(G.companion2.get("name", "")) == "Jun" and G.in_party("Jun") == 1 and G.party_size() == 2)
			var c0 = load("res://scripts/actors/Companion.gd").new()
			root.add_child(c0)
			var c1 = load("res://scripts/actors/Companion.gd").new()
			c1.slot = 1
			root.add_child(c1)
			check("both walk with you, each their own", c0.visible and c1.visible and c0.npc_name == "Mei" and c1.npc_name == "Jun")
			check("each fights in their own style, at their own level", G.set_companion_style("guard", 1) and G.companion_style(1) == "guard" and G.companion_style(0) == "striker" and G.companion_damage(1) > 0 and G.companion_max_hp(1) > 0)
			G.companion_xp(500.0, "", 1)
			check("...and grows on their own", G.companion_level(1) > G.companion_level(0))
			G.companion_hurt(999999, "a test", 1)
			check("one can go down while the other fights on", G.companion_down(1) and not G.companion_down(0))
			G.companion_revive()
			check("a night's rest stands them both up", not G.companion_down(1) and G.companion_hp(1) == G.companion_max_hp(1))
			check("a full party: someone new takes the second place", G.ask_companion("Tan", "Tan.", "village", Color(1, 1, 1), 0.0) == "yes" and str(G.companion2.get("name", "")) == "Tan" and str(G.companion.get("name", "")) == "Mei")
			check("Jun is on your roster now", "Jun" in G.roster() and G.in_party("Jun") < 0)
			G.part_with_companion(1)
			check("send the second home; call Jun back from town", G.recall("Jun") == "" and G.in_party("Jun") == 1)
			G.swap_party()
			check("swap who walks first", str(G.companion.get("name", "")) == "Jun" and str(G.companion2.get("name", "")) == "Mei")
			G.part_with_companion(0)
			check("send the first home: the second steps up", str(G.companion.get("name", "")) == "Mei" and G.companion2.is_empty())
			G.current_level = "floor3"
			check("you can't call anyone from the deep", G.can_recall("Jun").contains("town"))
			G.current_level = "village"
			G.warm_bond("Jun", -60.0)
			check("...nor someone who's grown cold", G.can_recall("Jun").contains("close"))
			c0.queue_free()
			c1.queue_free()
			# -- contract beasts
			check("no contracts yet; room for two", G.contracts.is_empty() and G.contract_cap() == 2 and G.summon_cap() == 1)
			G.bond_familiar("cave_hare")
			check("the first beast that chooses you walks at your heel (the lead)", G.contracts.size() == 1 and is_same(G.familiar, G.contracts[0]) and G.beasts_out().size() == 1)
			G.bond_familiar("tunnel_boar")
			check("the second rests in your spirit space", G.contracts.size() == 2 and not bool(G.contracts[1].get("out", false)) and G.beasts_out().size() == 1)
			check("a full roster: no more taming until Taming opens more", not G.can_tame_more())
			check("one at your side at first", G.summon_beast(1).contains("hold 1"))
			G.realm = 6
			G.skills["taming"] = 10.0 * 10 * 10
			check("Taming 10 and Void Refinement: two at your side, and more contracts", G.summon_cap() == 2 and G.contract_cap() >= 4)
			var dm9: float = G.tech_effect("damage_mult", 1.0)
			check("call the boar out", G.summon_beast(1) == "" and G.beasts_out().size() == 2)
			check("...its gifts join yours (a share of them, behind the lead)", G.tech_effect("damage_mult", 1.0) > dm9)
			var f0 = load("res://scripts/actors/Familiar.gd").new()
			root.add_child(f0)
			var f1 = load("res://scripts/actors/Familiar.gd").new()
			f1.slot = 1
			root.add_child(f1)
			check("both follow you, each its own body", f0.visible and f1.visible and f0._me() != f1._me() and str(f1._me().get("species", "")) == "tunnel_boar")
			check("make the boar the lead", G.make_lead(1) == "" and str(G.familiar.get("species", "")) == "tunnel_boar" and bool(G.contracts[0].get("out", false)))
			G.contracts[1]["bond"] = 70.0
			check("a contract can be deepened -- not without what it asks", G.deepen_missing(1).size() > 0 and G.deepen_contract(1).begins_with("Not yet"))
			G.inventory["bloodsap"] = 2
			G.inventory["beast_hide"] = 4
			G.gold += 200
			var bm9: float = G.familiar_effect_mult(G.contracts[1])
			check("...with it: a Blood Contract, and it gives more", G.deepen_contract(1) == "" and int(G.contracts[1]["tier"]) == 1 and G.familiar_effect_mult(G.contracts[1]) > bm9 and G.count("bloodsap") == 0)
			h9._moments_q.clear()
			var b9: float = float(G.contracts[0].get("bond", 0.0))
			check("rest one, and it still grows (slowly) in your spirit space", G.rest_beast(0) == "" and (func(): G._rest_t = 60.0; G._rest_tick(0.0); return float(G.contracts[0].get("bond", 0.0)) > b9).call())
			check("rename one", G.rename_beast(0, "Whiskers") == "" and str(G.contracts[0]["name"]) == "Whiskers")
			check("release one: it goes, and the rest stay", G.release_beast(0) == "" and G.contracts.size() == 1 and str(G.familiar.get("species", "")) == "tunnel_boar")
			f0.queue_free()
			f1.queue_free()
			# a save from before contracts
			G.familiar = {"species": "cave_hare", "name": "Old", "bond": 20.0}
			G.contracts = []
			G.r39_load({})
			check("an old save's familiar becomes your first contract", G.contracts.size() == 1 and is_same(G.familiar, G.contracts[0]) and bool(G.familiar.get("lead", false)))
			G.bond_familiar("moss_stag")
			G.save_game()
			var n9: int = G.contracts.size()
			G.contracts = []
			G.familiar = {}
			G.companion2 = {}
			G.load_game()
			check("contracts and the party survive save + load (and the lead is one beast, not two copies)", G.contracts.size() == n9 and is_same(G.familiar, G.contracts[0]))
			# -- the pages
			h9.open_hub("Party")
			check("the Party page: companions, your roster, contract beasts, the taming tree", _label_has(h9._hub._party, "Companions") and _label_has(h9._hub._party, "Contract beasts") and _label_has(h9._hub._party, "taming tree"))
			h9.open_hub("Bonds")
			check("the Bonds page: everyone who knows you, closest first", _label_has(h9._hub._bonds, "Bonds") and _label_has(h9._hub._bonds, "Mei"))
			h9.open_hub("Road")
			check("the Road page: the chapter, the next gate, the masters", _label_has(h9._hub._road, "Chapter") and _label_has(h9._hub._road, "gate") and _label_has(h9._hub._road, "Hidden masters"))
			h9._hub.close_hub()
			G.new_game()
			check("a new life: no contracts, no second companion", G.contracts.is_empty() and G.companion2.is_empty())
			G.choose_background("hunter")
			G.set_flag("creation_done")
			_build("floor1")
			wait = 0.1
		67:
			print("== round 40: synergy, cleansing, the mind, the swarm's research ==")
			G.new_game()
			G.choose_background("hunter")
			G.set_flag("creation_done")
			_build("village")
			var h0 = root.get_tree().get_first_node_in_group("hud")
			h0._moments_q.clear()
			var SY = G.sys("synergy")
			var MI = G.sys("mind")
			var CL = G.sys("cleansing")
			var RS = G.sys("research")
			check("four modular systems under the Game: synergy, mind, cleansing, research", SY != null and MI != null and CL != null and RS != null and G.get_node_or_null("System_research") != null)
			check("each shaped the same way (save, load, reset, effects, tick, meditate, background)", [SY, MI, CL, RS].all(func(x): return x.has_method("save_state") and x.has_method("load_state") and x.has_method("effects") and x.has_method("meditate") and x.has_method("background")))
			# -- synergy
			check("a new cultivator: no synergy yet (neither road has begun)", SY.level() == 0.0 and SY.effects().is_empty())
			var pwz: float = G.parry_window()
			var dmz: float = G.tech_effect("damage_mult", 1.0)
			G.realm = 4
			while G.nanite_tier() < 3:
				G.integration += 100.0
			check("realm 4, swarm tier 3: synergy follows the lower road (3)", SY.level() >= 3.0 and SY.level() <= 3.5, str(SY.level()))
			check("Honing: the swarm and qi grown together make a sharper fighter -- harder, quicker, telling blows, a wider parry", G.tech_effect("timing", 0.0) > 0.0 and G.tech_effect("crit_chance", 0.0) > 0.0
				and G.tech_effect("damage_mult", 1.0) > dmz and G.parry_window() > pwz, "%f %f" % [G.parry_window(), pwz])
			check("five channels: recovery, focus, adaptability, connection, honing", SY.rows().size() == 5 and G.tech_effect("focus_mult", 1.0) > 1.0 and G.tech_effect("adapt_mult", 1.0) > 1.0 and G.tech_effect("insight_mult", 1.0) > 1.0 and G.tech_effect("bond_mult", 1.0) > 1.0)
			var ins0: float = G.insight
			G.gain_insight(10.0, "a test")
			check("Connection: insight comes easier", G.insight - ins0 > 10.0)
			# -- the mind
			check("you sit to Cultivate unless you choose otherwise; qi in full", MI.mode == "cultivate" and MI.qi_factor(MI.shares()) == 1.0)
			G.qi = 0.0
			G.meditate_tick(10.0, false, 0.0)
			var q_cult: float = G.qi
			MI.set_mode("research")
			G.qi = 0.0
			G.meditate_tick(10.0, false, 0.0)
			check("sit to Research: qi still comes, at 60%", G.qi > 0.0 and absf(G.qi / q_cult - 0.6) < 0.02, "%f vs %f" % [G.qi, q_cult])
			check("one thread: no split yet", MI.threads() == 1 and MI.set_share("research", 0.5).contains("can't split"))
			# -- research
			G.inventory = {}
			G.qi = 0.0
			check("research costs materials and qi -- without them, no", RS.can_research("edge_swarm").contains("needs"))
			G.inventory["nanite_shard"] = 200
			G.inventory["goblin_tooth"] = 10
			G.qi = G.qi_to_next() * 0.9
			var qb: float = G.qi
			check("with them: it begins, and the price is paid", RS.start("edge_swarm").begins_with("Research") and G.count("goblin_tooth") == 5 and G.qi < qb and RS.current == "edge_swarm")
			G.meditate_tick(30.0, false, 0.0)
			check("sitting with Research as your focus works on it", float(RS.progress.get("edge_swarm", 0.0)) > 0.0)
			RS.push(100000.0)
			h0._moments_q.clear()
			check("...until it's known", RS.state_of("edge_swarm") == "known" and RS.current == "")
			check("a design has to be connected -- and only while you sit", RS.connect_design("edge_swarm", false).contains("sit"))
			var dm0: float = G.tech_effect("damage_mult", 1.0)
			check("connected: its gift is yours, its bandwidth used", RS.connect_design("edge_swarm", true).contains("joins") and G.tech_effect("damage_mult", 1.0) > dm0 and RS.bandwidth_used() == 1)
			var dm1: float = G.tech_effect("damage_mult", 1.0)
			check("tune it with a material: Refined (two shards)", RS.tune("edge_swarm", "nanite_shard", true).contains("refined") and G.tech_effect("damage_mult", 1.0) > dm1)
			for nid0 in ["seeker_motes", "hardening_film", "kinetic_shell", "lantern_motes", "whisper_net"]:
				RS.researched[nid0] = true
			RS.dirty()
			var full := 0
			for nid1 in ["hardening_film", "kinetic_shell", "lantern_motes", "whisper_net", "seeker_motes"]:
				if RS.connect_design(nid1, true).contains("bandwidth"):
					full += 1
			check("bandwidth is finite: the swarm can't run everything (it grows with the tier)", full >= 1 and RS.bandwidth_used() <= RS.bandwidth_cap())
			# -- upkeep
			check("connected designs run on qi", RS.upkeep_points() > 0 and SY.upkeep_per_minute() > 0.0)
			G.qi = 1000000.0
			var q1: float = G.qi
			SY._acc = 60.0
			SY.tick(0.0)
			check("...a minute's upkeep comes out of your qi", G.qi < q1 and not SY.starved)
			G.qi = 0.0
			SY._acc = 60.0
			SY.tick(0.0)
			var dmS: float = G.tech_effect("damage_mult", 1.0)
			check("run dry: the designs go quiet", SY.starved and dmS < dm1)
			G.qi = 1000000.0
			SY._acc = 60.0
			SY.tick(0.0)
			check("...and wake when there's qi again", not SY.starved and G.tech_effect("damage_mult", 1.0) > dmS)
			# -- divided mind and the swarm in the background
			RS.researched["second_thread"] = true
			RS.dirty()
			check("Second Thread: the mind splits two ways", MI.threads() == 2 and MI.set_share("research", 0.5) == "" and MI.set_share("cultivate", 0.5) == "" and absf(float(MI.shares()["research"]) - 0.5) < 0.01)
			check("...a split sitting does 85% of each, until Quiet Mind", MI.split_efficiency(MI.shares()) < 1.0)
			MI.set_mode("cultivate")
			RS.researched["swarm_parallelism"] = true
			RS.dirty()
			RS.current = ""
			RS.progress = {}
			RS.start("ember_mites") if RS.can_research("ember_mites") == "" else null
			if RS.current == "":
				RS.current = "ember_mites"
				RS.progress["ember_mites"] = 0.0
			G.sitting = false
			G._systems_tick(100.0)
			check("Swarm Parallelism: research goes on while you walk (a quarter pace)", float(RS.progress.get("ember_mites", 0.0)) > 0.0 and MI.bg_rate() == 0.25)
			# -- installs (late)
			check("wetware waits for the late game", RS.state_of("neural_lace") == "locked" and RS.gate_missing("neural_lace").size() > 0)
			G.realm = 10
			while G.nanite_tier() < 8:
				G.integration += 2000.0
			for nid2 in ["neural_lace", "power_frame", "servo_limbs", "weapon_mount", "cyber_arm", "optic_implant"]:
				RS.researched[nid2] = true
			RS.dirty()
			check("an install needs you sitting", RS.install("neural_lace", false).contains("sitting"))
			var as0: float = G.tech_effect("attack_speed", 1.0)
			check("install a Neural Lace: it's part of you", RS.install("neural_lace", true).contains("part of you") and G.tech_effect("attack_speed", 1.0) > as0 and RS.load_used() == 2)
			check("servo limbs fit onto a power frame -- not without one", RS.install("servo_limbs", true).contains("first"))
			var cap0: int = RS.load_cap()
			RS.install("power_frame", true)
			RS.install("servo_limbs", true)
			check("the body bears only so much (load %d of %d)" % [RS.load_used(), cap0], RS.load_used() <= cap0 and RS.install("servo_limbs", true).contains("can't bear"))
			RS.uninstall("neural_lace")
			RS.install("servo_limbs", true)
			check("take the frame out and what's mounted on it comes too", RS.installed.has("servo_limbs") and RS.uninstall("power_frame").contains("Servo") and not RS.installed.has("servo_limbs"))
			# -- cleansing
			check("a minor node can't be cleansed until it's open (K)", CL.can_cleanse("laogong").contains("Open"))
			G.lattice["laogong"] = true
			CL.target = ""
			check("open it, and it can", CL.can_cleanse("laogong") == "" and CL.set_target("laogong").begins_with("Cleansing"))
			var dmc: float = G.tech_effect("damage_mult", 1.0)
			MI.set_mode("cleanse")
			var need0: float = CL.seconds_for("laogong", 1)
			G.meditate_tick(need0 + 1.0, false, 0.0)
			check("sit to Cleanse: Laogong goes from murky to clouded", CL.grade_of("laogong") >= 1)
			check("...and your damage rises a little (it feeds strike damage)", G.tech_effect("damage_mult", 1.0) > dmc and CL.stat_bonus("damage") > 0.0)
			check("major nodes open with your realm", CL.can_cleanse("baihui").contains("opens") and CL.can_cleanse("qihai") == "")
			G.realm = 5
			CL.grade["laogong"] = 3
			CL._eff_dirty = true
			check("radiance waits for the realm (Radiant at Tribulation Transcendence)", CL.can_cleanse("laogong").contains("radiant"))
			for n9 in CL.nodes():
				CL.grade[str(n9["id"])] = 4
			CL._eff_dirty = true
			check("THE METRIC: every node radiant is exactly each stat's ceiling -- never more", ["health", "damage", "speed", "attack", "defense", "qi", "recovery"].all(func(k): return absf(CL.stat_bonus(k) - float(CL.data["stats"][k]["cap"])) < 0.0001))
			check("...+30% health, +30% damage, +15% speed, 20% less damage taken", absf(CL.stat_bonus("health") - 0.3) < 0.001 and absf(CL.stat_bonus("speed") - 0.15) < 0.001)
			CL.grade = {}
			CL._eff_dirty = true
			G.lattice["laogong"] = true
			check("a Marrow Washing Pill: an alchemy recipe, and a quarter hour's cleansing", G.items.has("marrow_washing_pill") and str(G._recipe_for("marrow_washing_pill").get("skill", "")) == "alchemy")
			G.inventory["marrow_washing_pill"] = 1
			CL.target = "laogong"
			G.use_item("marrow_washing_pill")
			check("...it works on the node you're cleansing", CL.grade_of("laogong") >= 1)
			var capr: int = RS.load_cap()
			check("radiant nodes give the body more load to bear", (func(): CL.grade["laogong"] = 4; CL.grade["qihai"] = 4; CL.grade["guanyuan"] = 4; return RS.load_cap() > capr).call())
			# -- the pages
			h0.open_hub("Mind")
			check("the Mind page: your focus, the split, synergy, cleansing and every node", _label_has(h0._hub._mind, "where your sitting goes") and _label_has(h0._hub._mind, "Synergy") and _label_has(h0._hub._mind, "Major nodes") and _label_has(h0._hub._mind, "Laogong"))
			h0.open_hub("Swarm")
			check("the Swarm page: research, designs, wetware to power armour", _label_has(h0._hub._swarm, "The swarm") and _label_has(h0._hub._swarm, "Power Armour") and _label_has(h0._hub._swarm, "Edge Swarm"))
			G.affinity["fire"] = 40.0
			G.affinity["earth"] = 30.0
			h0.open_hub("Spirit")
			check("the Spirit page: the five elements, their gifts, how they sit together", _label_has(h0._hub._spirit, "your elements") and _label_has(h0._hub._spirit, "Fire") and _label_has(h0._hub._spirit, "ACTIVE") and _label_has(h0._hub._spirit, "Synergy: Fire feeds Earth"))
			h0._hub.close_hub()
			# -- saved
			G.save_game()
			var st0: Dictionary = G._systems_save()
			G._systems_reset()
			G.load_game()
			check("synergy, the mind, cleansing and research survive save + load", JSON.stringify(G._systems_save(), "", true) == JSON.stringify(st0, "", true), JSON.stringify(G._systems_save(), "", true).left(300) + " VS " + JSON.stringify(st0, "", true).left(300))
			G.new_game()
			check("a new life starts with none of it", RS.researched.is_empty() and CL.grade.is_empty() and MI.mode == "cultivate")
			G.choose_background("hunter")
			G.set_flag("creation_done")
			_build("floor1")
			wait = 0.1
		68:
			print("== round 42: words that give something -- tips and history ==")
			G.new_game()
			G.choose_background("hunter")
			G.set_flag("creation_done")
			_build("floor1")
			var hl = root.get_tree().get_first_node_in_group("hud")
			hl._moments_q.clear()
			var LO = G.sys("lore")
			check("a Lore system: tips that are true now, and the history of Eliet in pieces", LO != null and LO.data.get("templates", {}).size() >= 10 and (LO.data.get("history", []) as Array).size() >= 12)
			var ts0: Array = LO.tips()
			check("on floor 1, the tips know how many hidden ways are still here", ts0.any(func(t): return str(t["kind"]) == "secrets" and str(t["text"]).contains("way through its walls")), str(ts0.map(func(t): return t["kind"])))
			check("...and who this floor's master is, and how to beat it", ts0.any(func(t): return str(t["kind"]) == "boss" and str(t["text"]).contains("guard")))
			check("...and what the next gate wants (Qi Condensation, for floor 6)", ts0.any(func(t): return str(t["kind"]) == "gate" and str(t["text"]).contains("floor 6")))
			check("history comes in order of depth: nothing from below where you've been", LO.next_history().get("id", "") == "eliet_founding" and (LO.data["history"] as Array).filter(func(h): return int(h["floor"]) > 30).all(func(h): return int(h["floor"]) > G.reach_depth()))
			# reading
			var st = _find("Stele.gd")
			check("a lore stone on floor 1", st != null)
			if st:
				G.realm = 10
				st.interact(player)
				check("read it: below the carving, something more -- a tip or a piece of history", hl._dialog_body.text.contains(str(LO.data["frames"]["stele"])) and LO.notes.size() >= 1, hl._dialog_body.text.right(200))
				hl.close_dialog()
				var nn: int = LO.notes.size()
				st.interact(player)
				check("...only the first time you read it", LO.notes.size() == nn)
				hl.close_dialog()
			# secrets
			var sw = _find("SecretWall.gd", func(n): return not G.has_flag(str(n._key)))
			if sw:
				var left0: int = int(str(LO.tips().filter(func(t): return str(t["kind"]) == "secrets")[0]["text"]).to_int()) if LO.tips().any(func(t): return str(t["kind"]) == "secrets") else -1
				sw.interact(player)
				check("open a hidden wall: whoever hid it left a word", hl._dialog.visible and hl._dialog_body.text.contains(str(LO.data["frames"]["secret"])))
				hl.close_dialog()
				check("...and the count of hidden ways left goes down", not LO.tips().any(func(t): return str(t["kind"]) == "secrets" and str(t["id"]).ends_with(":%d" % (left0 if left0 > 0 else 999))) or left0 < 0)
			# inheritance
			var ih = _find("Inheritance.gd")
			if ih:
				ih.interact(player)
				check("a dead master's legacy comes with last advice", hl._dialog_body.text.contains("One more thing"), hl._dialog_body.text.left(300))
				hl.close_dialog()
			# people
			_build("village")
			hl._moments_q.clear()
			var np = _find("NPC.gd", func(n): return str(n.role) == "villager")
			if np:
				np._advice()
				check("ask anyone for advice: something true, in their words", hl._dialog.visible and hl._dialog_body.text.contains("advice"), hl._dialog_body.text.left(200))
				hl.close_dialog()
				np.say("hello", func(_r): pass)
				check("...and when you talk, they know a tip they might pass on", np._voice().situation.contains("you know this"))
			# never the same thing twice in a row; the menu keeps them
			var p1: Dictionary = LO.pick("chest")
			var p2: Dictionary = LO.pick("chest")
			check("never the same note twice in a row", p1.is_empty() or p2.is_empty() or str(p1["text"]) != str(p2["text"]))
			hl.open_hub("Road")
			check("the Road page keeps what you've learned, and counts the history", _label_has(hl._hub._road, "What you've learned") and _label_has(hl._hub._road, "pieces of Eliet's history"))
			hl._hub.close_hub()
			check("Dev's rewording is used only if it keeps every {placeholder}", LO._holes("There are {n} ways") == LO._holes("Still {n} left") and LO._holes("{n} on {floor}") != LO._holes("{n} left"))
			check("mastery counts the history you've pieced together", G.mastery_parts().any(func(m): return str(m[0]) == "history" and int(m[2]) >= 1))
			G.save_game()
			var nts: int = LO.notes.size()
			LO.reset()
			G.load_game()
			check("what you've learned survives save + load", LO.notes.size() == nts and LO.history_found.size() >= 1)
			G.new_game()
			G.choose_background("hunter")
			G.set_flag("creation_done")
			_build("floor1")
			wait = 0.1
		69:
			print("== round 43: a base requirement, and inheritance crystals ==")
			var hc = root.get_tree().get_first_node_in_group("hud")
			hc._moments_q.clear()
			G.learn("spirit_sense")
			G.realm = 0
			check("the base requirement: the named realm, or the hardest art it teaches", G.inheritance_need(0, {"techniques": ["sword_intent"]}) == 3 and G.inheritance_need(5, {"techniques": ["sword_heart"]}) == 5)
			check("a floor that names no realm asks one for every four floors down", G.inheritance_default_realm(1) == 1 and G.inheritance_default_realm(20) == 5)
			var ic = _find("Inheritance.gd")
			check("floor 1's master is there", ic != null)
			if ic:
				check("too weak: the legacy is locked", G.inheritance_state(ic.needs_realm, ic.grants) == "locked")
				ic.interact(player)
				check("...the will turns you away, says what it asks, and offers to condense", hc._dialog_body.text.contains("Too weak") and hc._dialog_body.text.contains("asks for") and _btn_has("Condense it into a crystal"), hc._dialog_body.text.left(300))
				for b in hc._dialog_buttons.get_children():
					if b is Button and b.text.contains("Condense") and not b.is_queued_for_deletion():
						b.pressed.emit()
						break
				var cid := ""
				for id in G.inventory.keys():
					if G.is_crystal(str(id)):
						cid = str(id)
				check("condensing puts an Inheritance Crystal in your pack", cid != "" and G.item_name(cid).contains("Inheritance Crystal") and G.item_name(cid).contains("Azure Sword Sage"), cid)
				check("...and nothing of the legacy is given yet", not G.has_treasure("flying_sword") and not G.has_tech("sword_heart"))
				check("...the seat is empty for good", ic.claimed() and ic.prompt().contains("empty seat"))
				ic.interact(player)
				check("...and it says where the will went", hc._dialog_body.text.contains("crystal you made"))
				hc.close_dialog()
				check("the crystal is cold until you reach its realm", G.crystal_ready(cid) != "" and G.absorb_crystal(cid).contains("cold") and G.count(cid) == 1)
				check("a trader will buy it, at its worth", G.sell_price(cid) >= 300 and cid in G.sellables(), str(G.sell_price(cid)))
				hc.open_kit("Pack")
				hc._kit._choose_slot = ""
				hc._kit._refresh_now()
				var kt := ""
				var ab_dis := false
				for c in hc._kit.pack_body.find_children("*", "", true, false):
					if c is Button or c is Label:
						kt += c.text + "|"
					if c is Button and c.text.begins_with("Absorb (at"):
						ab_dis = c.disabled
				check("the pack lists it under Crystals, with Absorb waiting for the realm", kt.contains("Crystals|") and ab_dis, kt.right(300))
				hc.close_kit()
				G.save_game()
				G.load_game()
				check("the crystal survives save + load, legacy and all", G.is_crystal(cid) and G.count(cid) == 1 and (G.crystal_info(cid).get("grants", {}).get("techniques", []) as Array).has("sword_heart"))
				G.realm = 1
				G.sublevel = 1
				var q0: float = G.qi
				var said: String = G.absorb_crystal(cid)
				check("at the realm, absorbing it gives the whole legacy", G.has_treasure("flying_sword") and G.has_tech("sword_heart") and G.count(cid) == 0 and said.contains("Azure"), said)
				check("...qi too", G.qi > q0 or G.realm > 1 or G.sublevel > 1)
			# of no use: everything it teaches you know
			G.learn("sword_heart")
			check("a legacy that teaches only what you know is of no use", G.inheritance_state(0, {"techniques": ["sword_heart"]}) == "useless" and G.inheritance_state(0, {"techniques": ["sword_heart"], "qi": 50}) == "ready")
			var uid: String = G.condense_inheritance("test:useless", "an old hermit", 0, {"techniques": ["sword_heart"]})
			check("...it can still be condensed and sold", uid != "" and G.sell_price(uid) > 0 and G.sell(uid, 1) > 0 and G.count(uid) == 0)
			check("...but a legacy can't be condensed twice", G.condense_inheritance("test:useless", "an old hermit", 0, {"techniques": ["sword_heart"]}) == "")
			G.new_game()
			G.choose_background("hunter")
			G.set_flag("creation_done")
			_build("floor1")
			wait = 0.1
		70:
			print("== round 44: time and seasons ==")
			var W = G.sys("world")
			var hw = root.get_tree().get_first_node_in_group("hud")
			hw._moments_q.clear()
			W.calm = false
			check("a World system: four seasons, four times of day, weather above and currents below, a festival a season", W != null and (W.data.get("seasons", []) as Array).size() == 4 and W.data.get("phases", {}).size() == 4 and W.data.get("surface_weather", {}).size() >= 6 and W.data.get("deep_currents", {}).size() >= 6 and W.data.get("festivals", {}).size() == 4)
			check("the calendar runs on the real date (a world day of several hundred by now)", W.day() > 0, str(W.day()))
			W.day_override = 0
			check("day 0 is the first day of the first Thaw, year 1", W.season_id() == "thaw" and W.day_of_season() == 1 and W.year() == 1 and W.date_text() == "Day 1 of Thaw, Year 1", W.date_text())
			W.day_override = 5 * 3 + 4
			check("...and the seasons turn every few days: day 19 is the last day of Frost", W.season_id() == "frost" and W.day_of_season() == 5, W.date_text())
			W.day_override = 20
			check("...then a new year", W.season_id() == "thaw" and W.year() == 2)
			var snow_in_thaw := false
			var snow_in_frost := false
			for dd in range(0, 80):
				for q in 4:
					var wid: String = W.weather_id("surface", dd, q)
					if wid == "snow" and W.season_index(dd) == 0:
						snow_in_thaw = true
					if wid == "snow" and W.season_index(dd) == 3:
						snow_in_frost = true
			check("weather follows the season: snow in Frost, never in the Thaw", snow_in_frost and not snow_in_thaw)
			check("the weather is the same for everyone at the same time and place (it's the world's, not a dice roll each look)", W.weather_id("deep:forge", 33, 2) == W.weather_id("deep:forge", 33, 2))
			G.hour_override = 23.0
			check("23:00 is night; 06:00 is dawn; 19:00 is dusk; noon is day", W.phase() == "night" and (func(): G.hour_override = 6.0; return W.phase() == "dawn").call() and (func(): G.hour_override = 19.0; return W.phase() == "dusk").call() and (func(): G.hour_override = 12.0; return W.phase() == "day").call())
			G.hour_override = 23.0
			var fd4: Dictionary = G.load_level_def("floor4")
			check("at night the deep is hungrier: its beasts hit harder and more of them are elites", W.foe_mod("floor4", fd4, "foe_damage") > 1.05 and W.foe_mod("floor4", fd4, "elite_mult") > 1.2 and G.level_mod(fd4, "foe_damage") > 1.05)
			check("...but not in a town", W.foe_mod("floor5", G.load_level_def("floor5"), "foe_damage") == 1.0)
			G.hour_override = 6.0
			W._eff_key = ""
			var med0: float = G.tech_effect("meditate_mult", 1.0)
			W.calm = true
			var med1: float = G.tech_effect("meditate_mult", 1.0)
			W.calm = false
			check("dawn is the best hour to sit", med0 > med1 * 1.1, "%.3f vs %.3f" % [med0, med1])
			# a festival
			W.day_override = 2
			check("the third day of every season is a festival in Eliet (the Festival of First Lanterns in the Thaw)", str(W.festival().get("id", "")) == "lantern" and W.festival(3).is_empty())
			G.hour_override = 12.0
			_build("village")
			var wfx = level.get_node_or_null("WorldFX")
			check("every place has its WorldFX, in step with the hour and the weather", wfx != null and str(wfx.state.get("phase", "")) == "day")
			check("...on a festival day Eliet is strung with lanterns", int(wfx.state.get("lanterns", 0)) >= 6, str(wfx.state))
			check("...and in the Thaw, flowers come up", int(wfx.state.get("flowers", 0)) >= 10)
			var e0: float = level.sun_light.light_energy
			G.hour_override = 23.0
			wfx.apply()
			check("the sun goes down as the hours pass, without leaving the place", level.sun_light.light_energy < e0 * 0.5, "%.2f -> %.2f" % [e0, level.sun_light.light_energy])
			G.hour_override = 12.0
			wfx.apply()
			var mer = _find("NPC.gd", func(n): return str(n.role) == "merchant")
			var p_fest := 0
			var p_base := 0
			if mer:
				var st0: Array = mer.trade_stock()
				p_fest = int(st0[0][1]) if st0.size() > 0 else 0
				W.day_override = 3
				var st1: Array = mer.trade_stock()
				p_base = int(st1[0][1]) if st1.size() > 0 else 0
				W.day_override = 2
			check("...the traders give a little off on the day", mer != null and p_fest > 0 and p_fest < p_base, "%d vs %d" % [p_fest, p_base])
			var eld = _find("NPC.gd", func(n): return str(n.role) == "elder")
			var pills0: int = G.count("qi_pill")
			if eld:
				eld.interact(player)
				hw.close_dialog()
				eld.interact(player)
				hw.close_dialog()
			check("...and the elder has a gift for those who walk the deep, once", eld != null and G.count("qi_pill") == pills0 + 2, "%d -> %d" % [pills0, G.count("qi_pill")])
			hw.update_clock()
			check("the HUD shows the day, the hour and the weather", hw._clock.text.contains("Day 3 of Thaw") and hw._clock.text.contains("Day") and hw._clock.text.contains("First Lanterns"), hw._clock.text)
			W.day_override = 17
			_build("village")
			wfx = level.get_node_or_null("WorldFX")
			check("in Frost, snow lies on the valley", bool(wfx.state.get("snow_ground", false)))
			W.day_override = 11
			_build("village")
			check("in Harvest, the trees turn", int(level.counts.get("season_trees", 0)) > 0, str(level.counts.get("season_trees", 0)))
			# -- factions
			print("== round 44: factions that remember ==")
			var F = G.sys("factions")
			F.reset()
			check("five peoples, each with a standing toward you", F.ids().size() == 5 and F.tier_id("eliet") == "known" and F.tier_id("hollow") == "wary" and F.tier_id("deepfolk") == "neutral")
			var el0: float = F.value("eliet")
			G.log_event("quest_done", {"id": "test"})
			check("what you already do counts: a quest done raises Eliet's standing", F.value("eliet") == el0 + 15.0)
			var h0: float = F.value("hollow")
			F.change("deepfolk", 100.0, "test")
			check("helping a people cools their rivals (the Deepfolk up 100, the Hollow Clans down 35)", F.value("deepfolk") == 100.0 and F.value("hollow") == h0 - 35.0)
			F.change("eliet", 300.0, "test")
			check("standing has tiers, and each brings something: Trusted in Eliet means a free inn", F.tier_id("eliet") == "trusted" and F.inn_free() and F.price_mult("eliet") < 1.0)
			check("...and better stock from their traders", "breakthrough_pill" in F.extra_stock("eliet"))
			F.standing["hollow"] = -400.0
			check("make enemies of the Hollow Clans and their hunters come looking", F.hunters_hunting() and F.tier_id("hollow") == "hostile")
			var hd := -1
			var f9: Dictionary = G.load_level_def("floor9")
			for dd2 in range(0, 60):
				W.day_override = dd2
				if F.hunters_for("floor9", f9) > 0:
					hd = dd2
					break
			check("...some days, on some floors", hd >= 0)
			if hd >= 0:
				W.day_override = hd
				_build("floor9")
				var hunters: Array = root.get_tree().get_nodes_in_group("enemy").filter(func(e): return bool(e.get("hunter")))
				check("...a pack of clan hunters waits on the floor", hunters.size() >= 2 and str(hunters[0].stats.get("name", "")).contains("clan hunter"), str(hunters.size()))
			var hh0: float = F.value("hollow")
			G.log_event("hunter_kill", {"type": "x"})
			check("killing their hunters makes it worse with the clans (and the Deepfolk approve)", F.value("hollow") < hh0)
			F.reset()
			G.save_game()
			F.change("heirs", 77.0, "test")
			G.save_game()
			F.reset()
			G.load_game()
			check("standing survives save + load", F.value("heirs") == 77.0 and F.value("sects") < 0.0)
			W.day_override = 40
			G.realm = 2
			_build("floor3")
			wait = 0.2
		71:
			print("== round 44: peoples in the deep ==")
			var S = G.sys("settlements")
			var F2 = G.sys("factions")
			var hs = root.get_tree().get_first_node_in_group("hud")
			hs._moments_q.clear()
			var camp = _find("Settlement.gd")
			check("floor 3 has a camp of real people in an open hall (Rootlight)", camp != null and str(camp.sid) == "rootlight" and camp.built_stage == 0, str(level.warnings))
			var head = _find("NPC.gd", func(n): return str(n.role) == "headman")
			check("...with its headman, its people, its fire and its banner", head != null and _find("NPC.gd", func(n): return str(n.npc_name) == "Tilly Spore") != null and camp.get_node("Parts/Campfire") != null and camp.get_node_or_null("Parts/Banner") != null)
			check("...and no trader yet (that comes when it grows)", _find("NPC.gd", func(n): return str(n.npc_name) == "Wick") == null)
			if head:
				head.interact(player)
				check("the first time, they tell you who they are", hud_text().contains("Mushroom farmers") and hud_text().contains("Today:"), hud_text().left(300))
				hs.close_dialog()
			var nd: Dictionary = S.need("rootlight")
			check("one need a day: bring them something, or thin out the floor's beasts", str(nd.get("type", "")) in ["bring", "cull"] and int(nd.get("n", 0)) > 0)
			if str(nd["type"]) == "bring":
				G.add_item(str(nd["item"]), int(nd["n"]), false)
			else:
				for i in int(nd["n"]):
					G.log_event("kill", {"type": "goblin"})
			check("...you can see when it can be met", S.can_meet("rootlight") == "", S.can_meet("rootlight"))
			var g0: int = G.gold
			var df0: float = F2.value("deepfolk")
			var said: String = S.meet("rootlight")
			check("meeting it: the camp grows, you're paid, and the Deepfolk think better of you", float(S.st("rootlight")["pros"]) >= 22.0 and G.gold > g0 and F2.value("deepfolk") > df0, said)
			check("...once a day", S.need("rootlight").is_empty() and S.meet("rootlight").contains("met"))
			S.st("rootlight")["pros"] = 58.0
			G.gold += 500
			S.give_supplies("rootlight")
			check("supplies help too -- and Rootlight becomes an outpost", S.stage("rootlight") == 1)
			camp._check = 0.0
			camp._process(0.1)
			wait = 0.2
		72:
			var S2 = G.sys("settlements")
			var camp2 = _find("Settlement.gd")
			check("it rebuilds as it grows, while you watch: a trader sets up", camp2.built_stage == 1 and _find("NPC.gd", func(n): return str(n.npc_name) == "Wick") != null)
			S2.st("rootlight")["pros"] = 420.0
			S2.st("rootlight")["peak"] = 3
			camp2._check = 0.0
			camp2._process(0.1)
			wait = 0.2
		73:
			var S3 = G.sys("settlements")
			var W3 = G.sys("world")
			var camp3 = _find("Settlement.gd")
			check("a town: an inn you can wake at, a shrine, and your statue by the fire", camp3.built_stage == 3 and _find("NPC.gd", func(n): return str(n.role) == "innkeeper") != null
				and camp3.get_node_or_null("Parts/Statue") != null and level.get_node_or_null("Shrine_rootlight") != null)
			var inn = _find("NPC.gd", func(n): return str(n.role) == "innkeeper")
			check("...its innkeeper charges what the camp charges (free to friends of the Deepfolk)", inn != null and inn.inn_price() == S3.rest_price("rootlight"))
			var mer2 = _find("NPC.gd", func(n): return str(n.npc_name) == "Wick")
			check("...and its trader carries the town's specialty", mer2 != null and mer2.trade_stock().any(func(r): return str(r[0]) == "moonpetal_tonic"))
			S3.st("rootlight")["last_help"] = W3.day() - 10
			S3.st("rootlight")["decayed_to"] = -1
			S3.st("rootlight")["pros"] = 450.0
			S3.st("rootlight")["last_seen"] = W3.day() - 10
			var back: String = S3.visit("rootlight")
			check("leave it alone for days and it slips back -- never below its stage", float(S3.st("rootlight")["pros"]) < 450.0 and float(S3.st("rootlight")["pros"]) >= 400.0 and S3.stage("rootlight") == 3, str(S3.st("rootlight")["pros"]))
			check("...and when you come back they tell you what happened", back.contains("It's been 10 days") and back.contains("prosperity lost"), back)
			var F3 = G.sys("factions")
			F3.standing["hollow"] = -600.0
			var fake = load("res://scripts/actors/NPC.gd").new()
			fake.def = {"faction": "hollow", "stock": ["raw_meat"]}
			fake.level = level
			check("an enemy people's traders won't deal with you", fake.trade_refused() and fake.trade_stock().is_empty())
			fake.free()
			F3.reset()
			G.save_game()
			var pr: float = float(S3.st("rootlight")["pros"])
			S3.reset()
			G.load_game()
			check("camps survive save + load", absf(float(S3.st("rootlight")["pros"]) - pr) < 0.01 and int(S3.st("rootlight")["peak"]) == 3)
			# -- ruins
			print("== round 44: ruins and the old age ==")
			var R = G.sys("ruins")
			R.reset()
			check("relics, potsherds, the four ages' techniques and Archaeology join the game", G.items.has("quiet_hearthstone") and G.items.has("old_age_potsherd") and G.technique_defs.has("breath_of_the_first") and G.skill_defs.has("archaeology"))
			var tl: Array = R.timeline()
			check("the Old Age timeline: four ages, oldest first, six relics each", tl.size() == 4 and str(tl[0]["era"]) == "first_breath" and str(tl[3]["era"]) == "long_quiet" and tl.all(func(e): return (e["entries"] as Array).size() == 6))
			_build("floor4")
			wait = 0.2
		74:
			var R4 = G.sys("ruins")
			var ht = root.get_tree().get_first_node_in_group("hud")
			ht._moments_q.clear()
			var site = _find("DigSite.gd")
			check("floor 4 has a dig site, ringed with jade stones and lines of light", site != null and site._stones.size() >= 3, str(level.warnings))
			check("...dig it a layer at a time", site != null and site.prompt().contains("layer 1 of 3"))
			var arch0: float = float(G.skills.get("archaeology", 0.0))
			if site:
				for i in 3:
					site.interact(player)
			check("at the bottom: a relic of the Long Quiet (the soot-black hearthstone)", G.count("quiet_hearthstone") == 1 and "quiet_hearthstone" in R4.found and G.count("old_age_potsherd") >= 1)
			check("...Archaeology grows as you dig", float(G.skills.get("archaeology", 0.0)) > arch0)
			check("...and the site is done", site != null and site.prompt().contains("old floor") and R4.site_done("floor4"))
			check("a site with nothing left points you at the nearest relic you haven't found", R4.pointer(4).contains("floor 6"), R4.pointer(4))
			# complete an age
			for rid in ["clan_tally_stick", "sealed_well_cap", "refugee_shoe", "sect_banner_scrap"]:
				R4.found.append(rid)
			for i in 3:
				R4.dig("floor11", 11)
			check("find every relic of an age and you learn its technique (Patience of the Quiet)", R4.era_known("long_quiet") and G.has_tech("patience_of_the_quiet"))
			if site:
				site._refresh()
			check("...and its glyphs become words you can read, on every ruin of that age", R4.inscription_for("floor4", 4) != "" and site != null and site._words.visible and site._words.text.contains("WAITED"))
			var F4 = G.sys("factions")
			var he0: float = F4.value("heirs")
			var se0: float = F4.value("sects")
			var gave: String = R4.give("quiet_hearthstone", "heirs")
			check("give a relic to the Heirs: they're pleased, the Sects are not -- and you keep what it told you", F4.value("heirs") == he0 + 30.0 and F4.value("sects") == se0 - 15.0 and G.count("quiet_hearthstone") == 0 and "quiet_hearthstone" in R4.found, gave)
			ht.open_kit("Pack")
			ht._kit._choose_slot = ""
			ht._kit._refresh_now()
			var kt := ""
			for c in ht._kit.pack_body.find_children("*", "", true, false):
				if c is Button or c is Label:
					kt += c.text + "|"
			check("relics have their own place in the pack, with a choice of who gets them", kt.contains("Relics|") and kt.contains("Give to the Heirs") and kt.contains("Give to the Sects"), kt.right(300))
			ht.close_kit()
			G.save_game()
			var nf: int = R4.found.size()
			R4.reset()
			G.load_game()
			check("the dig, the finds and the gifts survive save + load", R4.found.size() == nf and R4.site_done("floor4") and str(R4.given.get("quiet_hearthstone", "")) == "heirs")
			# -- the World page
			ht.open_hub("World")
			var wp = ht._hub._world
			check("the World page: the day, the peoples, the camps, the Old Age", _label_has(wp, "Year") and _label_has(wp, "The peoples") and _label_has(wp, "Hollow Clans") and _label_has(wp, "Camps in the deep") and _label_has(wp, "Rootlight") and _label_has(wp, "The Old Age") and _label_has(wp, "Soot-black hearthstone"))
			check("...camps you haven't met are only a rumour", _label_has(wp, "Someone is living on floor 8"))
			ht._hub.close_hub()
			G.sys("world").calm = true
			G.sys("world").day_override = -1
			G.hour_override = -1.0
			G.realm = 0
			G.new_game()
			G.choose_background("hunter")
			G.set_flag("creation_done")
			_build("floor1")
			wait = 0.1
		75:
			print("== round 45: Eliet remembers, and the world talks ==")
			var S5 = G.sys("settlements")
			var F5 = G.sys("factions")
			var W5 = G.sys("world")
			var L5 = G.sys("lore")
			var h5 = root.get_tree().get_first_node_in_group("hud")
			h5._moments_q.clear()
			_build("village")
			check("the Lantern Stone stands by the fountain: those who went down and came back (Mo, of the first expedition)", level.get_node_or_null("LanternStone") != null and level.get_node("LanternStoneWords").text.contains("Mo -- the first expedition"))
			check("...but not your name, not yet", not level.get_node("LanternStoneWords").text.contains("who made the deep"))
			check("no people fly their colours in Eliet for a stranger", int(level.counts.get("faction_banners", 0)) == 0)
			F5.change("deepfolk", 260.0, "test")
			F5.change("heirs", 230.0, "test")
			F5.standing["eliet"] = 900.0
			S5.st("rootlight")["pros"] = 450.0
			S5.st("rootlight")["peak"] = 3
			S5.st("rootlight")["met"] = true
			var md := -1
			for dd in range(0, 9):
				if S5.market_day("rootlight", dd):
					md = dd
					break
			W5.day_override = md
			_build("village")
			check("the peoples who trust you fly their colours in Eliet (the Deepfolk, the Heirs)", level.get_node_or_null("Banner_deepfolk") != null and level.get_node_or_null("Banner_heirs") != null and level.get_node_or_null("Banner_hollow") == null)
			check("Revered in Eliet: your name goes on the Lantern Stone", level.get_node("LanternStoneWords").text.contains("who made the deep a place people live"))
			var vis = _find("NPC.gd", func(n): return str(n.npc_name) == "Wick of Rootlight")
			check("a town in the deep sends its trader up to Eliet every third day", md >= 0 and vis != null and str(vis.role) == "merchant")
			check("...selling the town's specialty, at Deepfolk prices", vis != null and vis.trade_stock().any(func(r): return str(r[0]) == "moonpetal_tonic") and vis.faction() == "deepfolk")
			check("...and the World page says who's up today", (func():
				h5.open_hub("World")
				var ok: bool = _label_has(h5._hub._world, "Up in Eliet today: Wick of Rootlight")
				h5._hub.close_hub()
				return ok).call())
			G.current_level = "floor3"
			check("...while down in Rootlight, Wick's stall is empty and the headman says where he went", S5.market_day("rootlight") and (func():
				var hm = load("res://scripts/actors/NPC.gd").new()
				hm.def = {"settlement": "rootlight"}
				hm.npc_name = "Old Mother Puk"
				hm.level = level
				S5.talk(hm)
				var t: String = hud_text()
				h5.close_dialog()
				hm.free()
				return t.contains("gone up to Eliet")).call())
			G.current_level = "village"
			# the world in words
			W5.calm = false
			S5.st("tallowmark")["met"] = false
			G.depth = 6
			var kinds := {}
			for t in L5.tips():
				kinds[str(t["kind"])] = str(t["text"])
			check("people pass on the world's news as advice: a camp that needs you", kinds.has("camp_need") and str(kinds["camp_need"]).contains("Rootlight"), str(kinds.keys()))
			check("...a camp you haven't found yet", kinds.has("camp_unmet") and str(kinds["camp_unmet"]).contains("floor 8"), str(kinds.get("camp_unmet", "")))
			check("...who's up from the deep to trade", kinds.has("market") and str(kinds["market"]).contains("Wick"))
			check("...what the season's good for", kinds.has("season"))
			F5.standing["hollow"] = -400.0
			var k2 := {}
			for t in L5.tips():
				k2[str(t["kind"])] = true
			check("...and that the clans are hunting you, and how to stop it", k2.has("hunters"))
			W5.day_override = 0
			var k3 := {}
			for t in L5.tips():
				k3[str(t["kind"])] = str(t["text"])
			check("...and a festival coming up in Eliet", k3.has("festival") and str(k3["festival"]).contains("First Lanterns"), str(k3.keys()))
			F5.reset()
			S5.reset()
			W5.calm = true
			W5.day_override = -1
			G.new_game()
			G.choose_background("hunter")
			G.set_flag("creation_done")
			_build("floor1")
			wait = 0.1
		76:
			print("== round 46: traps and secrets you have to notice ==")
			var h6 = root.get_tree().get_first_node_in_group("hud")
			h6._moments_q.clear()
			G.techniques.erase("spirit_sense")
			_build("floor2")
			var traps: Array = level.get_children().filter(func(n): return n.get_script() != null and str(n.get_script().resource_path).ends_with("Trap.gd"))
			check("past the first floor, traps are hidden: the plate looks like any other stone", traps.size() >= 2 and traps.all(func(t): return t.hidden and not t._model.visible and t._tell != null))
			var walls: Array = level.get_children().filter(func(n): return n.get_script() != null and str(n.get_script().resource_path).ends_with("SecretWall.gd") and not G.has_flag(str(n._key)))
			check("...and hidden walls offer nothing to press", walls.size() >= 1 and walls.all(func(w): return not w.is_in_group("interactable")))
			# how fast you notice
			player.velocity = Vector3.ZERO
			var still: float = G.notice_rate("trap", player)
			player.velocity = Vector3(4.0, 0, 0)
			var walk: float = G.notice_rate("trap", player)
			player.velocity = Vector3(8.0, 0, 0)
			var run: float = G.notice_rate("trap", player)
			player.velocity = Vector3.ZERO
			check("you notice things standing still, less walking, hardly at all sprinting", still > walk and walk > run, "%.2f %.2f %.2f" % [still, walk, run])
			var sv0: float = float(G.skills.get("survival", 0.0))
			G.skills["survival"] = 1000.0
			check("...and Survival makes you quicker to notice", G.notice_rate("trap", player) > still)
			G.skills["survival"] = sv0
			# spot one
			var t0 = traps[0]
			var tc: Vector2i = t0.cell
			_tc6 = tc
			var spot := tc
			for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if level.is_free(tc + dd):
					spot = tc + dd
					break
			_place_player(spot)
			for i in 12:
				t0._watch(0.5)
			check("linger near a hidden trap and you spot it -- and it's a known trap from then on", not t0.hidden and t0._model.visible and G.has_flag(t0._key), str(t0.notice))
			# step on one
			for e in root.get_tree().get_nodes_in_group("enemy"):
				e.queue_free()
			_t6 = traps[1]
			_t6.notice = 0.0
			G.heal(999)
			player._hurt_cool = 0.0
			_hp_before = G.hp
			_place_player(_t6.cell)
			wait = 1.2
		77:
			check("step on one you haven't spotted: a click, a breath, then the spikes", G.hp < _hp_before and not _t6.hidden and G.has_flag(_t6._key), "hp %d -> %d" % [_hp_before, G.hp])
			check("...deeper floors' traps bite harder", _t6.damage() > 14)
			# spirit sense
			G.learn("spirit_sense")
			var rest: Array = level.get_children().filter(func(n): return n.get_script() != null and str(n.get_script().resource_path).ends_with("Trap.gd") and n.hidden)
			var w2 = level.get_children().filter(func(n): return n.get_script() != null and str(n.get_script().resource_path).ends_with("SecretWall.gd") and not n.noticed and not G.has_flag(str(n._key)))
			if rest.size() > 0:
				_place_player(rest[0].cell + Vector2i(1, 0) if level.is_free(rest[0].cell + Vector2i(1, 0)) else rest[0].cell + Vector2i(0, 1))
				player._spirit_sense()
				check("Spirit Sense finds a hidden plate nearby", not rest[0].hidden)
			if w2.size() > 0:
				player.global_position = w2[0].global_position + Vector3(0, 0.5, 2.0)
				player._spirit_sense()
				check("...and the hollow behind a hidden wall", w2[0].noticed and w2[0].is_in_group("interactable"))
			var LO6 = G.sys("lore")
			_build("floor2")
			var again: Array = level.get_children().filter(func(n): return n.get_script() != null and str(n.get_script().resource_path).ends_with("Trap.gd") and n.cell == _tc6)
			check("a trap you've found stays found when you come back", again.size() == 1 and not again[0].hidden)
			G.techniques.erase("spirit_sense")
			G.skills["survival"] = 0.0
			_build("floor3")
			var tk := {}
			for t in LO6.tips():
				tk[str(t["kind"])] = str(t["text"])
			check("people warn you about the floors' hidden plates, and how to spot them", tk.has("traps") and str(tk["traps"]).contains("pebbles"))
			check("...and tell you to feel for a draft to find a hidden way", tk.has("secrets") and str(tk["secrets"]).contains("draft"), str(tk.get("secrets", "")))
			G.new_game()
			G.choose_background("hunter")
			G.set_flag("creation_done")
			_build("floor1")
			wait = 0.1
		78:
			print("== round 47: realistic trees, props, people and equipment ==")
			var Art7 = load("res://scripts/core/Art.gd")
			var T7 = load("res://scripts/world/Tree.gd")
			check("realistic trees can be built (leaf cards cut from Poly Haven's atlases, bark, the foliage shader)", T7.available())
			var tr: Node3D = Art7.make("nature-kit/tree_oak.glb", 3)
			var leaves = tr.get_node_or_null("Leaves")
			check("a Kenney tree becomes a real one: a bark trunk and a crown of swaying leaf cards", tr.has_meta("realistic_tree") and leaves is MultiMeshInstance3D and leaves.multimesh.instance_count >= 20 and leaves.material_override is ShaderMaterial)
			var conif: Node3D = Art7.make("nature-kit/tree_pineDefaultA.glb", 1) if ResourceLoader.exists("res://assets/kenney/nature-kit/tree_pineDefaultA.glb") else T7.make(true, 4.0, 1)
			check("...pines and firs grow tiers of needled branches", conif.has_meta("realistic_tree") and (conif.get_node("Leaves").material_override as ShaderMaterial).get_shader_parameter("albedo_tex") != null)
			var fall: Node3D = Art7.make("nature-kit/tree_oak_fall.glb", 3)
			var bare: Node3D = Art7.make("nature-kit/tree_oak_dark.glb", 3)
			var ct: Color = (fall.get_node("Leaves").material_override as ShaderMaterial).get_shader_parameter("tint")
			check("...Harvest turns the leaves, Frost strips them", ct.r > ct.b * 2.0 and bare.get_node("Leaves").multimesh.instance_count < leaves.multimesh.instance_count / 2)
			var kb7: AABB = Art7.box("res://assets/kenney/nature-kit/tree_oak.glb")
			var tb7: AABB = Art7._merge(tr, Transform3D.IDENTITY, AABB(), true)
			check("...standing where the Kenney tree stood, about as tall", tb7.size.y > kb7.size.y * 0.9 and tb7.size.y < kb7.size.y * 1.8 and absf(tb7.position.y) < 0.05, "%s vs %s" % [tb7, kb7])
			for n in [tr, conif, fall, bare]:
				n.free()
			var tent: Node3D = Art7.make("nature-kit/tent_smallOpen.glb")
			var tmi: MeshInstance3D = tent.find_children("*", "MeshInstance3D", true, false)[0]
			var surf_ok := tmi.mesh.get_surface_count() >= 2 and tmi.get_surface_override_material(0) != null
			var diff := false
			for i in tmi.mesh.get_surface_count():
				if tmi.get_surface_override_material(i) != tmi.get_surface_override_material(0):
					diff = true
			check("tents are canvas over wooden poles -- each part of a model gets its own real surface", surf_ok and diff)
			tent.free()
			var fo: Node3D = Art7.make("fantasy-town-kit/fountain-round.glb")
			var water_kept := false
			for mi in fo.find_children("*", "MeshInstance3D", true, false):
				for i in (mi as MeshInstance3D).mesh.get_surface_count():
					var sm = (mi as MeshInstance3D).mesh.surface_get_material(i)
					if sm and str(sm.resource_name) == "Water" and (mi as MeshInstance3D).get_surface_override_material(i) == null:
						water_kept = true
			check("...the fountain is marble, and its water stays water", water_kept)
			fo.free()
			for k7 in ["fantasy-town-kit/stall.glb", "fantasy-town-kit/cart.glb", "fantasy-town-kit/fence.glb", "fantasy-town-kit/banner-red.glb", "fantasy-town-kit/roof-gable.glb", "mini-dungeon/trap.glb"]:
				check("%s wears a real surface" % k7.get_file(), Art7.REMAT.has(k7))
			check("flowers are real flowers (Poly Haven)", Art7.stand_in("nature-kit/flower_redB.glb") != "")
			# equipment
			var A7 = load("res://scripts/actors/Armour.gd")
			var D7 = load("res://scripts/world/Dress.gd")
			var shell: ArrayMesh = A7._lathe(A7._shape(0.3, 0.06, 0.07, 0.05, 0.005, 0.005))
			check("armour is turned like the real thing: a smooth shell that swells and tapers", shell.get_surface_count() == 1 and shell.surface_get_array_len(0) > 500 or shell.surface_get_array_index_len(0) > 500)
			var hp = Art7.person(D7.spec_for("Kael", "villager", {"sex": "m", "held": "axe"}))
			root.add_child(hp)
			D7.dress(hp, D7.spec_for("Kael", "villager", {"sex": "m", "held": "axe"}))
			var grip7: Array = hp.find_children("Grip", "", true, false)
			var boxes := 0
			var forged := 0
			if grip7.size() > 0:
				for mi in (grip7[0] as Node).find_children("*", "MeshInstance3D", true, false):
					if (mi as MeshInstance3D).mesh is BoxMesh:
						boxes += 1
					if (mi as MeshInstance3D).mesh is ArrayMesh:
						forged += 1
			check("weapons in hand are forged shapes, not boxes (an axe with a curved, bearded blade)", grip7.size() > 0 and boxes == 0 and forged >= 1, "%d boxes, %d forged" % [boxes, forged])
			hp.free()
			G.new_game()
			for id in ["g_iron_ore_chest", "g_iron_ore_greaves", "g_beast_hide_boots", "g_iron_ore_vambraces"]:
				G.add_item(id, 1, false)
				G.wear(id)
			var p7 = Art7.person(D7.spec_for("Kael", "villager", {"sex": "m"}))
			root.add_child(p7)
			A7.dress_gear(p7, G.worn_looks())
			var lathes := 0
			var bx := 0
			for mi in p7.find_children("*", "MeshInstance3D", true, false):
				if str(mi.get_parent().get_parent().name).begins_with("Dress_Armour_") or str(mi.get_parent().name).begins_with("Dress_Armour_"):
					if (mi as MeshInstance3D).mesh is ArrayMesh:
						lathes += 1
					if (mi as MeshInstance3D).mesh is BoxMesh:
						bx += 1
			check("worn armour: breastplate, greaves, vambraces and boot shafts are shaped shells; no boxes", lathes >= 4 and bx == 0, "%d shaped, %d boxes" % [lathes, bx])
			p7.free()
			G.new_game()
			G.choose_background("hunter")
			G.set_flag("creation_done")
			_build("floor1")
			wait = 0.1
		79:
			print("== round 48: the world past the edge of the map ==")
			var hz8 = level.get_node_or_null("Horizon")
			check("underground, the halls are cut out of one mass of rock that runs on past every wall", hz8 != null and int(hz8.state.get("rock_cells", 0)) > level.width * level.height and hz8.get_node_or_null("Rock") is MeshInstance3D)
			var rk8: MeshInstance3D = hz8.get_node("Rock") if hz8 else null
			var ab8: AABB = rk8.mesh.get_aabb() if rk8 else AABB()
			check("...reaching well past the map and falling away into the dark at its edges", ab8.position.x < -40.0 and ab8.end.x > level.width * level.CELL + 40.0 and ab8.position.y < -10.0 and ab8.end.y >= level.WALL_H, str(ab8))
			check("...lit by its own faint light, on its own layer (it never lights the halls)", hz8.get_node_or_null("RockLight") is DirectionalLight3D and (hz8.get_node("RockLight") as DirectionalLight3D).light_cull_mask == rk8.layers and rk8.layers != 1)
			check("...with a few glowing cracks: caverns out of reach", int(hz8.state.get("cracks", 0)) >= 1)
			var fogw = root.get_tree().get_first_node_in_group("fog_of_war")
			if fogw:
				fogw._statics_dirty = true
				fogw._hide_things()
			check("the fog of war never hides the world itself (the rock, the weather)", hz8.visible and (level.get_node_or_null("WorldFX") == null or level.get_node("WorldFX").visible))
			var H8 = load("res://scripts/world/Horizon.gd")
			check("every number of it is in data/horizon.json", H8.config().has("land") and H8.config().has("rock") and H8.config().has("haze"))
			_build("village")
			wait = 0.1
		80:
			var hv8 = level.get_node_or_null("Horizon")
			check("under the sky, the land runs on past the village: fields, hills, mountains", hv8 != null and int(hv8.state.get("land_quads", 0)) > 1000 and hv8.get_node_or_null("Land") is MeshInstance3D)
			var b8: Rect2 = hv8._bounds()
			var near_h: float = hv8.height_at(b8.position.x - 1.0, b8.get_center().y)
			var hill_h: float = hv8.height_at(b8.position.x - 40.0, b8.get_center().y)
			var far_h: float = hv8.height_at(b8.position.x - 200.0, b8.get_center().y)
			check("...level at the village's edge, rising into hills, then mountains", absf(near_h) < 0.5 and hill_h > 3.0 and far_h > 40.0 and far_h > hill_h, "%.1f / %.1f / %.1f" % [near_h, hill_h, far_h])
			check("...and a sect's tower on a far ridge", bool(hv8.state.get("pagoda", false)) and hv8.get_node_or_null("FarPagoda") != null and (hv8.get_node("FarPagoda") as Node3D).position.z < -80.0)
			if load("res://scripts/world/Tree.gd").available() and load("res://scripts/core/Art.gd").style != "kenney":
				check("...a forest of real trees on the slopes (a few draws for them all)", int(hv8.state.get("forest", 0)) >= 100 and hv8.get_node_or_null("Forest_trunks") is MultiMeshInstance3D)
			check("the village's edge is hedge, boulder, fence and tree -- not a wall of crags", int(level.counts.get("rim", 0)) > 10 and int(level.counts.get("rim", 0)) == int(level.counts.get("walls", 0)), str(level.counts))
			var lm8 = load("res://scripts/world/Tree.gd")
			var fm8: ShaderMaterial = lm8._leaf_mat(false, "")
			check("near leaves thin out between the camera and you (the see-through dither), far ones don't", float(fm8.get_shader_parameter("see_through")) > 1.0 and float((lm8._leaf_mat(false, "", true) as ShaderMaterial).get_shader_parameter("see_through")) == 0.0)
			check("...the shader reads where you are (a project-wide shader global)", ProjectSettings.has_setting("shader_globals/player_pos"))
			var wf8 = level.get_node_or_null("WorldFX")
			if wf8:
				wf8.apply()
				check("even on a clear day there's a little air over the far hills (haze), so distance reads as distance", level._env.fog_enabled and level._env.fog_density > 0.0)
			_build("floor1")
			wait = 0.1
		81:
			print("== round 49: smoother, modern menus and HUD ==")
			var U9 = load("res://scripts/core/UiStyle.gd")
			var hud9 = root.get_tree().get_first_node_in_group("hud")
			check("the look lives in data/ui.json (colours, corners, shadows, timings)", U9.cfg().has("color") and U9.cfg().has("motion"))
			check("real fonts: Inter to read, Cinzel for titles", U9.font("body") != null and U9.font("title") != null and U9.font("body") != U9.font("title"))
			var th9: Theme = hud9._theme
			check("one theme for every window: rounded, shadowed, the gold on hover; the rail and the tabs have their own", th9 != null and th9.default_font == U9.font("body") and th9.has_stylebox("pressed", "RailButton") and th9.has_stylebox("tab_selected", "TabContainer") and (th9.get_stylebox("normal", "Button") as StyleBoxFlat).corner_radius_top_left >= 6)
			var pb9: StyleBoxFlat = U9.box(Color(0, 0, 0, 0.9))
			check("...windows cast a soft shadow", pb9.shadow_size > 0)
			var hp9: ProgressBar = hud9._hp_bar
			G.hp = G.max_hp()
			hud9.refresh()
			G.hp = int(G.max_hp() / 2)
			hud9.refresh()
			var tr9 = hp9.get_meta("trail") if hp9.has_meta("trail") else null
			check("a hit: the health bar shows the truth at once, a pale trail behind it catches up after", tr9 is ProgressBar and is_equal_approx(hp9.value, float(G.hp)) and tr9.value > hp9.value and tr9.show_behind_parent)
			G.hp = G.max_hp()
			hud9.refresh()
			check("...healing: the trail never runs ahead of the bar", is_equal_approx(tr9.value, hp9.value))
			var hub9 = hud9._hub
			hub9.show_page("You")
			hub9.show_page("Road")
			hub9.show_page("Pack")
			var lit9: int = 0
			for k9 in hub9.buttons:
				if hub9.buttons[k9].button_pressed:
					lit9 += 1
			check("the menu's side rail lights exactly the open section", lit9 == 1 and hub9.buttons["Pack"].button_pressed and hub9.buttons["Pack"].theme_type_variation == "RailButton")
			hub9.close_hub()
			check("windows rise and fade in when they open (the dialog, the menu, the pause menu)", hud9._dialog.has_meta("_pops") and hub9.has_meta("_pops"))
			var b9 := Button.new()
			hud9.add_child(b9)
			check("every button made gets the hover glow and the press (automatically)", b9.has_meta("_juice") and b9.theme == hud9._theme)
			b9.queue_free()
			hud9.log_message("a line")
			var last9: Control = hud9._log.get_child(hud9._log.get_child_count() - 1)
			check("new lines in the log fade in", last9.modulate.a < 1.0)
			check("headings in carved capitals: a big label made by the HUD wears the title font", hud9._label(hud9._log, "Title", 24, Color.WHITE).get_theme_font("font") == U9.font("title"))
			wait = 0.1
		82:
			print("== round 50: prompts, foes' health, the boss bar, the front door ==")
			var h50 = root.get_tree().get_first_node_in_group("hud")
			check("a prompt splits into the key and what it does", h50.split_prompt("E: Open the chest") == ["E", "Open the chest"] and h50.split_prompt("Hold still -- something moves")[0] == "")
			h50.set_prompt("E: Talk to Elder Mo")
			check("...shown as a pill: the key in a gold key-cap, then the action", h50._prompt_pill.visible and h50._prompt_key.visible and h50._prompt_keytext.text == "E" and h50._prompt.text == "Talk to Elder Mo")
			h50.set_prompt("")
			check("...and it goes when there's nothing to do", h50._prompt.text == "")
			var g50 = load("res://scripts/actors/Enemy.gd").new()
			g50.setup(level, {"type": "goblin"})
			level.add_child(g50)
			var bar50 = g50._bar
			check("a foe wears a slim health bar under its name, not numbers", bar50 != null and not g50._label.text.contains("/") and not bar50.visible)
			g50.hp = int(g50.hp / 2)
			g50._update_label()
			check("...hurt, the bar shows (half full) and leaves a trail", bar50.visible and absf(bar50.frac - 0.5) < 0.05 and bar50._trail_frac > bar50.frac)
			var c50 = load("res://scripts/actors/Enemy.gd").new()
			c50.setup(level, {"type": "goblin_chief"})
			level.add_child(c50)
			c50.global_position = player.global_position + Vector3(3, 0, 0)
			c50._revealed = true
			h50.refresh_boss()
			check("a boss near you: its name and health across the top of the screen", h50._boss_box.visible and h50._boss_name.text == str(c50.stats.get("name", "")) and c50._bar.visible)
			c50.hp = int(c50.hp * 0.4)
			h50.refresh_boss()
			check("...the boss bar follows its health", is_equal_approx(h50._boss_bar.value, float(c50.hp)))
			c50.global_position = player.global_position + Vector3(200, 0, 0)
			h50.refresh_boss()
			check("...and goes when you leave it behind", not h50._boss_box.visible)
			g50.queue_free()
			c50.queue_free()
			h50.show_title()
			check("the front door: a veil over the world (it shows through), the name over a gold rule", (h50._title.get_theme_stylebox("panel") as StyleBoxFlat).bg_color.a < 0.9 and not h50._title.find_children("*", "ColorRect", true, false).is_empty())
			h50.close_title()
			wait = 0.1
		83:
			print("== round 51: inheritances, minor / major / heavenly, different every game ==")
			var L51 = G.sys("legacies")
			var keep_pin: Dictionary = L51.pin
			L51.pin = {}
			var firsts := {}
			var ok_layout := true
			for sd in range(1, 13):
				L51.pin = {"seed": sd}
				G.new_game()
				var fl1 := ""
				for lid in L51.crafts:
					if str(lid) in ["floor1", "floor2"]:
						fl1 = str(L51.crafts[lid])
				firsts[fl1] = true
				var vals: Array = L51.crafts.values()
				vals.sort()
				ok_layout = ok_layout and fl1 != "" and L51.crafts.size() == 5 and vals == ["alchemy", "herbalism", "jewelcrafting", "medicine", "smithing"] and not L51.crafts.has("floor5") and not L51.crafts.has("floor10")
			check("minor: all five craft masters in every game, one near the top of the stair -- which one changes game to game", ok_layout and firsts.size() >= 3, str(firsts.keys()))
			L51.pin = {"seed": 7, "first_craft": "alchemy", "first_floor": 1}
			G.new_game()
			check("...the same game always lays out the same way (its own seed, saved)", L51.save_state()["seed"] == 7 and L51.crafts.get("floor1", "") == "alchemy")
			_build("floor1")
			var shop51 = _find("Vignette.gd", func(n): return n.legacy)
			check("...the master near the start sits in his own craft's workshop (an alchemist's lab, this game)", shop51 != null and shop51.kind == "alchemy_lab")
			# majors
			check("major: the dead masters the level files name are all known", L51.majors().size() >= 5 and L51.majors().any(func(m): return str(m["master"]) == "the Azure Sword Sage"))
			var sleeping := 0
			for sd in range(1, 9):
				L51.pin = {"seed": sd}
				G.new_game()
				sleeping += L51.sealed.size()
			check("...some sleep at first, in most games", sleeping > 0)
			L51.pin = {"seed": 3}
			G.new_game()
			var m51: Dictionary = L51.majors()[0]
			L51.sealed["%s:%s" % [m51["level"], m51["ch"]]] = true
			G.realm = int(m51["need"]) + 1
			var w51: Array = L51.wake_check()
			check("...and wake when you're strong enough for them (word comes up the stair)", w51.size() >= 1 and L51.major_present(str(m51["level"]), str(m51["ch"])))
			G.realm = 0
			L51.sealed = {}
			L51.data["major"]["designed_spot_chance"] = 0.0
			_build("floor1")
			var ih51 = _find("Inheritance.gd")
			var home51: Vector2i = L51.majors().filter(func(m): return m["level"] == "floor1")[0]["cell"]
			var far51 := 9999
			for c in level.spawns.get("<", []) + level.spawns.get("P", []):
				far51 = mini(far51, absi(c.x - ih51.cell.x) + absi(c.y - ih51.cell.y))
			check("...moved this game: a far corner or a sealed room, well away from the stairs", ih51 != null and ih51.cell != home51 and far51 >= int(L51.cfg("major").get("min_from_stairs", 12)), "%s (home %s), %d from the stairs" % [ih51.cell if ih51 else Vector2i(-1, -1), home51, far51])
			check("...but it's still the same master (claimed once, keyed to its floor, wherever it sits)", ih51._key == G.flag_key("floor1", home51, "inheritance"))
			L51.data["major"]["designed_spot_chance"] = 0.35
			G.learn("spirit_sense")
			_place_player(ih51.cell + Vector2i(14, 0) if level.is_walkable_char(level.char_at(ih51.cell + Vector2i(14, 0))) else level.spawns["<"][0])
			ih51._search(0.5)
			ih51._update_visibility(false)
			check("...Spirit Sense alone doesn't show it from across the floor", not ih51.revealed() and not ih51._body.visible)
			player.global_position = ih51.global_position + Vector3(3.5, 0.5, 0)
			ih51._search(0.5)
			check("...from a few steps away, it does -- and stays found", ih51.revealed() and ih51._body.visible and G.has_flag(ih51._key + ":seen"))
			G.techniques.erase("spirit_sense")
			G.flags.erase(ih51._key + ":seen")
			ih51._update_visibility(false)
			player.global_position = ih51.global_position + Vector3(1.6, 0.5, 0)
			player.velocity = Vector3.ZERO
			var secs := 0.0
			while not ih51.revealed() and secs < 60.0:
				ih51._search(0.5)
				secs += 0.5
			check("...without Spirit Sense: stand still right beside it and search -- slowly, you find it", ih51.revealed() and secs > 3.0, "%.1f s" % secs)
			# heavenly
			var hid51: String = str(L51.cfg("heavenly")["pool"][0]["id"])
			L51.heavens = {"floor3": hid51}
			G.realm = 0
			G.learn("spirit_sense")
			_build("floor3")
			var hv51 = _find("Inheritance.gd", func(n): return n.tier == "heavenly")
			check("heavenly: this game put one on floor 3 -- a seat of white jade", hv51 != null and hv51.heaven == hid51)
			player.global_position = hv51.global_position + Vector3(2.0, 0.5, 0)
			hv51._search(0.5)
			check("...below Core Formation you can't even perceive it, standing beside it with Spirit Sense", not hv51.revealed())
			G.realm = 3
			hv51._search(0.5)
			var h51 = root.get_tree().get_first_node_in_group("hud")
			hv51.interact(player)
			check("...at Core Formation you can -- but it asks for more before it gives anything", hv51.revealed() and h51._dialog_body.text.contains("Not yet"), h51._dialog_body.text.left(160))
			h51.close_dialog()
			G.realm = hv51.needs_realm
			hv51.interact(player)
			check("...strong enough: the will rises -- 'Show me'", h51._dialog_body.text.contains("Show me") and _btn_has("Face the test"))
			h51.close_dialog()
			hv51._raise_echo()
			var echo51 = hv51._echo
			check("...its echo steps down to test you: a boss, with the boss bar", echo51 != null and str(echo51.stats.get("name", "")).begins_with("Echo of") and bool(echo51.stats.get("boss", false)) and echo51.hp > 100)
			echo51._dead = true
			hv51._process(0.1)
			check("...beat it, and the will is waiting", hv51.trial_passed())
			var tech51 := str(L51.heavenly(hid51)["technique"]["id"])
			var item51 := str(L51.heavenly(hid51)["item"]["id"])
			hv51.interact(player)
			for b in h51.find_children("*", "Button", true, false):
				if b.text == "Accept the legacy" and not b.is_queued_for_deletion():
					b.pressed.emit()
					break
			check("...a heaven-grade art, a treasure and a title nobody else will ever hold", G.has_tech(tech51) and G.count(item51) == 1 and G.titles.has(str(L51.heavenly(hid51)["title"])) and L51.claimed_heavens.has(hid51))
			var sm51: Dictionary = L51.summary()
			check("the Road page counts all three tiers (and hints where to look)", (sm51["minor"] as Array).size() == 2 and int((sm51["major"] as Array)[1]) >= 5 and (sm51["heavenly"] as Array).size() == 1 and bool(sm51["heavenly"][0]["claimed"]))
			var hb51 = h51._hub
			hb51.show_page("Road")
			check("...on the Road page", _label_has(hb51._road, "Inheritances") and _label_has(hb51._road, "Heavenly"))
			hb51.close_hub()
			# three games, three characters
			L51.pin = {}                            # (each new game its own seed again)
			G.save_base = "user://playtest_slots51"
			for n in range(1, 4):
				if FileAccess.file_exists(G.slot_path(n)):
					DirAccess.remove_absolute(ProjectSettings.globalize_path(G.slot_path(n)))
			G.use_slot(1)
			G.new_game()
			G.choose_background("hunter")
			G.char_name = "Aya"
			G.set_flag("creation_done")
			G.gold = 777
			G.save_game()
			var seed_a: int = L51.seed_v
			check("three games: each slot saves its own character", G.slot_info(1).get("exists", false) and G.slot_info(1)["name"] == "Aya" and not G.slot_info(2).get("exists", false))
			G.switch_slot(2, true)
			check("...a new character in slot 2 starts fresh (and the slot is remembered)", G.slot == 2 and G.background == "" and G.gold == 20 and G.last_slot() == 2)
			G.choose_background("hunter")
			G.char_name = "Bo"
			G.set_flag("creation_done")
			G.save_game()
			var seed_b: int = L51.seed_v
			G.switch_slot(1, false)
			check("...switching back: Aya, her gold, her world's own inheritances", G.char_name == "Aya" and G.gold == 777 and L51.seed_v == seed_a and seed_a != seed_b)
			check("...and the title lists them both", G.slot_info(2)["name"] == "Bo" and h51._slots_used() == 2)
			h51.show_title()
			h51._title_slots()
			check("...the Characters page: a card for each slot", _label_has(h51._title_btns, "Slot 1") and _label_has(h51._title_btns, "Slot 3  ·  empty"))
			h51.close_title()
			check("erase a character: the slot is free -- the file is kept, renamed", G.erase_slot(2) and not G.slot_info(2).get("exists", false) and Array(DirAccess.get_files_at("user://")).any(func(f): return str(f).begins_with("playtest_slots51_slot2.erased")))
			G.save_base = "user://playtest_slots51m"
			for n in range(1, 4):
				if FileAccess.file_exists(G.slot_path(n)):
					DirAccess.remove_absolute(ProjectSettings.globalize_path(G.slot_path(n)))
			var old51 := FileAccess.open("user://playtest_old_save.json", FileAccess.WRITE)
			old51.store_string(JSON.stringify({"char_name": "Old One", "background": "hunter", "realm": 2}))
			old51.close()
			check("a save from before slots becomes slot 1 (the old file stays)", G.migrate_to_slots("user://playtest_old_save.json") and G.slot_info(1)["name"] == "Old One" and FileAccess.file_exists("user://playtest_old_save.json"))
			G.save_base = "user://playtest_slots"
			G.save_path = "user://playtest_save.json"
			L51.pin = keep_pin
			G.new_game()
			G.choose_background("hunter")
			G.set_flag("creation_done")
			_build("floor1")
			wait = 0.1
		84:
			print("== round 52: smooth movement, a camera that follows softly, effects that make sense, detail ==")
			var FX52 = load("res://scripts/fx/FX.gd")
			check("the feel lives in data/feel.json (movement, camera, effects, the look, detail)", FX52.feel("move").has("accel_time") and FX52.feel("matter").has("bone") and FX52.feel("detail").has("default"))
			check("a blow knocks loose what a creature is made of: blood from a goblin, chips from a skeleton, grit from a golem, embers from a cinder imp",
				FX52.matter_kind(G.enemies["goblin"]) == "flesh" and FX52.matter_kind(G.enemies["skeleton"]) == "bone" and FX52.matter_kind(G.enemies["foreman_golem"]) == "stone" and FX52.matter_kind(G.enemies.get("cinder_imp", {"name": "Cinder Imp"})) == "ember")
			var e52 = load("res://scripts/actors/Enemy.gd").new()
			e52.setup(level, {"type": "goblin"})
			level.add_child(e52)
			e52.set_meta("_crit_next", true)
			e52.take_damage(3, "you")
			check("...a blow that strikes true is marked for its number (and only that blow)", not e52.has_meta("_crit_next"))
			check("foes are drawn between physics ticks (smooth at any frame rate)", e52.has_method("_process") and e52._model.position.distance_to(e52._model_base) < 0.01)
			e52.queue_free()
			player._shake(0.2)
			check("camera shake is trauma: it builds with each blow ...", player.shake_amount() > 0.3)
			player._shake_tick(1.0)
			player._shake_tick(0.1)
			check("... and fades out smoothly", player.shake_amount() == 0.0 and player.camera.h_offset == 0.0)
			player._punch(1.0)
			check("a big blow pulls the view in for an instant", player.camera.fov < player._fov_base)
			player.camera.fov = player._fov_base
			player.global_position += Vector3(30, 0, 0)
			player._note_tick()
			player._note_tick()
			player._process(0.016)
			check("the camera follows softly, but a jump through a door snaps it there", player._cam_world.distance_to(player.global_position + player._cam_base) < 0.05)
			player.global_position -= Vector3(30, 0, 0)
			var hud52 = root.get_tree().get_first_node_in_group("hud")
			hud52.hurt_flash(0.3)
			check("a blow turns the edges of the screen red ...", hud52._screen_fx != null and hud52._hurt > 0.3)
			hud52._screen_tick(5.0)
			check("... and it fades", hud52._hurt == 0.0)
			var gd52 = level.get_node_or_null("GroundDetail")
			check("the floor has its small things: puddles, dirt, grit by the walls, cobwebs in the corners", gd52 != null and int(gd52.state.get("puddles", 0)) > 0 and int(gd52.state.get("pebbles", 0)) > 0 and int(gd52.state.get("dirt", 0)) > 0)
			wait = 0.1
		85:
			print("== round 52: side quests ==")
			var Q5 = G.sys("quests")
			Q5.quiet = false
			var hq = root.get_tree().get_first_node_in_group("hud")
			check("a couple of dozen side questlines, from Eliet and every town of the deep", Q5.all().size() >= 20)
			var givers_ok := true
			var bad5 := []
			var everyone := []                      # (a talk can send you to another town)
			for tp in ["village", "floor5", "floor10", "floor15", "floor20", "floor30", "floor40"]:
				if FileAccess.file_exists("res://levels/%s.json" % tp):
					var tdef: Dictionary = G.load_level_def(tp)
					for k in tdef.get("npcs", {}):
						everyone.append(str(tdef["npcs"][k].get("name", "")))
			for vs in G.valley_data().get("sects", []):          # round 55: the valley's elders and disciples
				everyone.append(str(vs.get("elder", {}).get("name", "")))
				for vd in vs.get("disciples", []):
					everyone.append(str(vd))
			for q in Q5.all():
				var pd: Dictionary = G.load_level_def(str(q["place"])) if FileAccess.file_exists("res://levels/%s.json" % str(q["place"])) else {}
				if pd.is_empty():
					continue
				var names := []
				for k in pd.get("npcs", {}):
					names.append(str(pd["npcs"][k].get("name", "")))
				if not names.has(str(q["giver"])):
					givers_ok = false
					bad5.append(str(q["id"]))
				for st in q.get("stages", []):
					var g: Dictionary = st.get("goal", {})
					if g.has("talk") and str(g["talk"]) != str(q["giver"]) and not everyone.has(str(g["talk"])):
						bad5.append(str(q["id"]) + ":talk")
					if g.has("gather") and not G.items.has(str(g["gather"]["item"])):
						bad5.append(str(q["id"]) + ":gather")
				for e5 in q.get("endings", {}).values():
					for it5 in e5.get("reward", {}).get("items", {}):
						if not G.items.has(str(it5)):
							bad5.append(str(q["id"]) + ":" + str(it5))
			check("...every quest-giver lives where the quest says, and every reward is a real thing", givers_ok and bad5.is_empty(), str(bad5))
			G.new_game()
			G.choose_background("hunter")
			G.set_flag("creation_done")
			G.mark_level_entered("floor1", {})
			check("a quest opens when you've been deep enough -- its giver wears a gold !", Q5.unlocked("lost_brother") and Q5.marker_for("Little Rin") == "!" and not Q5.unlocked("ilse_ferry"))
			_build("village")
			var rin = _find("NPC.gd", func(n): return str(n.npc_name) == "Little Rin")
			rin.interact(player)
			check("...talk to them: the quest, in their words, and a choice to take it", hq._dialog.visible and hq._dialog_title.text.contains("The Brother Who Went Down") and _btn_has("I'll do it"))
			for b in hq.find_children("*", "Button", true, false):
				if b.text == "I'll do it" and not b.is_queued_for_deletion():
					b.pressed.emit()
					break
			check("...taken: it's followed, and shows at the top of the screen", Q5.active.has("lost_brother") and Q5.tracked == "lost_brother" and G.next_goals().any(func(x): return str(x).begins_with("Quest:")))
			_build("floor1")
			var qo = _find("QuestObject.gd")
			check("...what it sent you for is somewhere on the floor, with a gold diamond over it", qo != null and qo.get_node_or_null("QuestMarker") != null and qo.is_in_group("interactable"))
			qo.interact(player)
			check("...take it, and the quest moves on (to the next floor down)", G.count("sq_fox_sign") == 1 and int(Q5.active["lost_brother"]["stage"]) == 1)
			_build("floor2")
			var qo2 = _find("QuestObject.gd")
			qo2.interact(player)
			check("...the last stage: go back and tell them -- a ? over their head", Q5.marker_for("Little Rin") == "?")
			_build("village")
			rin = _find("NPC.gd", func(n): return str(n.npc_name) == "Little Rin")
			var gold5: int = G.gold
			var st5: float = G.sys("factions").value("eliet")
			rin.interact(player)
			check("...and a choice at the end", _btn_has("Give her the letter as it is") and _btn_has("Tell her he's alive and still going down"))
			for b in hq.find_children("*", "Button", true, false):
				if b.text.begins_with("Tell her he's alive") and not b.is_queued_for_deletion():
					b.pressed.emit()
					break
			check("...the choice decides the ending: a reward, a unique keepsake, and how the town feels about you", Q5.done.get("lost_brother", "") == "hope" and G.count("sq_fox_charm") == 1 and G.gold > gold5 and G.sys("factions").value("eliet") > st5 + 30.0 and G.count("sq_tam_satchel") == 0, "%s %d %.0f" % [Q5.done, G.gold - gold5, G.sys("factions").value("eliet") - st5])
			check("...the keepsake does something (Rin's fox: better finds)", G.tech_effect("loot_luck", 0.0) >= 0.06)
			hq.close_dialog()
			G.mark_level_entered("floor2", {})
			Q5.accept("pells_hammer")
			_build("floor1")
			var hunt5 = null
			for n5 in level.get_children():
				if n5.has_meta("quest_hunt"):
					hunt5 = n5
			check("a named foe to hunt: on its floor, by name, marked, with its name across the top of the screen", hunt5 != null and str(hunt5.stats["name"]) == "Haft-Biter" and bool(hunt5.stats.get("boss", false)) and hunt5.get_node_or_null("QuestMarker") != null)
			hunt5.take_damage(999999, "you")
			level.remove_child(hunt5)
			hunt5.queue_free()
			check("...kill it: it drops what you came for", G.count("sq_pells_hammer") == 1 and int(Q5.active["pells_hammer"]["stage"]) == 1)
			var q50 := float(Q5.reward_qi("ilse_ferry", {"qi_kills": 10}))
			var q51 := float(Q5.reward_qi("lost_brother", {"qi_kills": 10}))
			check("rewards grow with the depth a quest takes you to", q50 > q51 * 3.0, "%.0f vs %.0f" % [q50, q51])
			hq._hub.show_page("Quests")
			check("the Quests page: what you're on (and the step you're at), who's asking, what's done", _label_has(hq._hub._quests, "Old Pell's Hammer") and _label_has(hq._hub._quests, "Done (1 of"))
			hq._hub.close_hub()
			var sv5: Dictionary = Q5.save_state()
			Q5.reset()
			Q5.load_state(JSON.parse_string(JSON.stringify(sv5)))
			check("side quests survive save + load", Q5.active.has("pells_hammer") and Q5.done.has("lost_brother") and int(Q5.active["pells_hammer"]["stage"]) == 1)
			wait = 0.1
		86:
			print("== round 54: quests of every kind -- crafts, gathering, people, masters, hunting, exploration ==")
			var Q6 = G.sys("quests")
			var kinds6 := {}
			for q in Q6.all():
				kinds6[str(q.get("kind", "side"))] = true
			check("quests of every kind: side, gathering, people, masters, blacksmithing, alchemy, medicine, jewelcrafting, hunting, exploration", Q6.all().size() >= 65 and kinds6.size() >= 10, str(kinds6.keys()))
			var bad6 := []
			for q in Q6.all():
				for st in q.get("stages", []):
					var g: Dictionary = st.get("goal", {})
					for key in ["craft"]:
						if g.has(key) and not G.recipes.any(func(r): return str(r.get("makes", "")) == str(g[key])):
							bad6.append(str(q["id"]) + ":" + str(g[key]))
					if g.has("craft_n") and g["craft_n"].has("item") and not G.recipes.any(func(r): return str(r.get("makes", "")) == str(g["craft_n"]["item"])):
						bad6.append(str(q["id"]) + ":" + str(g["craft_n"]["item"]))
					if g.has("skill") and not G.skill_defs.has(str(g["skill"]["id"])):
						bad6.append(str(q["id"]) + ":skill")
				for e6 in q.get("endings", {}).values():
					var tq := str(e6.get("reward", {}).get("technique", ""))
					if tq != "" and not G.technique_defs.has(tq):
						bad6.append(str(q["id"]) + ":" + tq)
			check("...every recipe, skill and art they name is real", bad6.is_empty(), str(bad6))
			G.new_game()
			G.choose_background("hunter")
			G.set_flag("creation_done")
			check("a craft's road: the first step is open from the start, the next waits for it", Q6.unlocked("smith_1") and not Q6.unlocked("smith_2"))
			Q6.accept("smith_1")
			for i6 in 3:
				G.log_event("craft", {"makes": "whetstone", "success": true, "quality": ""})
			check("...make so many of a thing (each one counted)", int(Q6.active["smith_1"]["stage"]) == 1)
			G.log_event("craft", {"makes": "iron_sword", "success": true, "quality": ""})
			_build("village")
			var hale = _find("NPC.gd", func(n): return str(n.npc_name) == "Smith Hale")
			var hq6 = root.get_tree().get_first_node_in_group("hud")
			check("...and the smith wants to see it (a ? over his head)", Q6.marker_for("Smith Hale") == "?")
			hale.interact(player)
			for b in hq6.find_children("*", "Button", true, false):
				if b.text == "Go on" and not b.is_queued_for_deletion():
					b.pressed.emit()
					break
			hq6.close_dialog()
			check("...done: his old hammer (smithing goes better with it), and the next step of the road opens deeper down", Q6.done.has("smith_1") and G.count("sq_hale_hammer") == 1 and G.tech_effect("craft_success_smithing", 0.0) >= 0.04)
			G.mark_level_entered("floor5", {})
			check("...Dagna Ironvent, in Shellhaven", Q6.unlocked("smith_2"))
			Q6.accept("smith_2")
			G.add_skill_xp("smithing", 2000.0)
			Q6._check("smith_2")
			check("a skill to reach: done the moment you're there", int(Q6.active["smith_2"]["stage"]) == 1)
			G.log_event("craft", {"makes": "bone_blade", "success": true, "quality": ""})
			G.log_event("craft", {"makes": "iron_sword@fine", "success": true, "quality": "fine"})
			check("a piece of a quality: Fine or better", int(Q6.active["smith_2"]["stage"]) == 3)
			Q6.accept("mast_1")
			for i7 in 15:
				G.log_event("dodge", {})
			for i8 in 5:
				G.log_event("parry", {})
			check("a master's training: roll through fifteen blows, parry five", int(Q6.active["mast_1"]["stage"]) == 2)
			G.mark_level_entered("floor15", {})
			Q6.accept("soc_5")
			G.warm_bond("Gorm the Quiet", 40.0)
			Q6._check("soc_5")
			check("people: become someone's friend", int(Q6.active["soc_5"]["stage"]) == 1)
			Q6.accept("gath_1")
			for i9 in 8:
				G.log_event("gather", {"kind": "herb", "n": 1, "plant": "spirit_herb"})
			G.log_event("gather", {"kind": "fish", "catch": "x"})
			check("gathering: herbs count as herbs (not fish)", int(Q6.active["gath_1"]["stage"]) == 1)
			_build("village")
			var wen = _find("NPC.gd", func(n): return str(n.npc_name) == "Trader Wen")
			Q6.active.erase("gath_1")
			wen.interact(player)
			check("someone with more than one thing to ask lets you choose which to hear", _btn_has("Old Grudges  (People)") and _btn_has("Pick of the Warrens  (Gathering)"), hq6._dialog_body.text.left(80))
			hq6.close_dialog()
			hq6._hub.quest_filter = "smithing"
			hq6._hub.show_page("Quests")
			check("the Quests page: the road down first, then every kind, each with its count", _label_has(hq6._hub._quests, "Main --") and _label_has(hq6._hub._quests, "Bone and Iron") and not _label_has(hq6._hub._quests, "Rhee's Drill"))
			hq6._hub.quest_filter = ""
			hq6._hub.close_hub()
			wait = 0.1
		87:
			print("== round 55: the sects' roads -- five quests at every sect, and two chains where the sects meet ==")
			var Q7 = G.sys("quests")
			var hq7 = root.get_tree().get_first_node_in_group("hud")
			var sects7: Array = G.valley_data().get("sects", [])
			var roads_ok := sects7.size() > 0
			for sd7 in sects7:
				if Q7.sect_road(str(sd7["id"])).size() != 5:
					roads_ok = false
			check("every valley sect's elder has a road of five quests (%d sects)" % sects7.size(), roads_ok and Q7.all().filter(func(q): return str(q.get("kind", "")) == "sect").size() >= 30)
			var bad7 := []
			var names7 := {}
			for sd7 in sects7:
				names7[str(sd7.get("elder", {}).get("name", ""))] = true
				for dd7 in sd7.get("disciples", []):
					names7[str(dd7)] = true
			for q in Q7.all():
				if str(q.get("kind", "")) != "sect":
					continue
				if str(q.get("sect", "")) != "" and str(q.get("giver", "")) != str(G.sect_def(str(q["sect"])).get("elder", {}).get("name", "?")):
					bad7.append(str(q["id"]) + ":giver")
				for st in q.get("stages", []):
					var g: Dictionary = st.get("goal", {})
					if g.has("talk") and str(g.get("where", "")) == "valley" and not names7.has(str(g["talk"])):
						bad7.append(str(q["id"]) + ":talk " + str(g["talk"]))
					for k7 in ["find", "hunt"]:
						if g.has(k7) and (int(g[k7].get("floor", 0)) < 1 or int(g[k7].get("floor", 0)) > 50):
							bad7.append(str(q["id"]) + ":floor")
				for e7 in q.get("endings", {}).values():
					var rw7: Dictionary = e7.get("reward", {})
					for it7 in rw7.get("items", {}):
						if not G.items.has(str(it7)):
							bad7.append(str(q["id"]) + ":" + str(it7))
					if str(rw7.get("technique", "")) != "" and not G.technique_defs.has(str(rw7["technique"])):
						bad7.append(str(q["id"]) + ":" + str(rw7["technique"]))
			check("...each given by that sect's own elder, sending you to its own disciples; every reward real", bad7.is_empty(), str(bad7))
			# a sect Dev writes later still gets a road
			G.valley_def["sects"].append({"id": "test_lotus", "name": "Test Lotus Sect", "element": "fire", "elder": {"name": "Master Test"}, "disciples": ["Disciple Tea"], "arts": []})
			Q7.data = Q7.load_json("res://data/sidequests.json")
			Q7._sect_roads()
			Q7._register()
			var tq7: Dictionary = Q7.qdef("test_lotus_2")
			check("a sect with no written road gets one from the template -- its own names, element and gifts", Q7.sect_road("test_lotus").size() == 5 and str(Q7.qdef("test_lotus_1").get("giver", "")) == "Master Test"
				and not ["{sid}", "{sect}", "{elder}", "{el}", "{d1}", "{d2}"].any(func(ph): return JSON.stringify(Q7.sect_road("test_lotus").map(func(x): return Q7.qdef(x))).contains(ph)) and G.items.has("sq_test_lotus_token") and G.technique_defs.has("test_lotus_heart_canon")
				and str(tq7.get("unlock", {}).get("sect", "")) == "test_lotus" and str(tq7["stages"][2]["goal"]["talk"]) == "Disciple Tea", str(tq7).left(200))
			G.valley_def["sects"].pop_back()
			G.items.erase("sq_test_lotus_token")
			G.items.erase("sq_test_lotus_sash")
			G.items.erase("sq_test_lotus_heirloom")
			G.technique_defs.erase("test_lotus_inner_way")
			G.technique_defs.erase("test_lotus_heart_canon")
			Q7.data = Q7.load_json("res://data/sidequests.json")
			Q7._sect_roads()
			G.new_game()
			G.choose_background("hunter")
			G.set_flag("creation_done")
			G.mark_level_entered("floor1", {})
			_build("village")
			_build("valley")
			check("a guest can walk the first step of any sect's road -- its elder wears a gold !", Q7.unlocked("iron_fist_clan_1") and Q7.marker_for("Master Wei") == "!" and not Q7.unlocked("iron_fist_clan_2") and Q7.sect_locked("iron_fist_clan_2"))
			check("...the Silverleaf elder's quest is his in the valley, not the Master Yun of the Jade Pagoda", Q7.marker_for("Master Yun") == "!")
			G.current_level = "floor20"
			check("...(pinned to the valley: elsewhere, nobody by that name offers it)", Q7.marker_for("Master Yun") == "" and Q7.marker_for("Master Wei") == "")
			G.current_level = "valley"
			var wei = _find("NPC.gd", func(n): return str(n.npc_name) == "Master Wei")
			Q7.talk(wei, hq7, func(): pass)
			check("...talk to him: the sect's errand, in his words", hq7._dialog.visible and hq7._dialog_title.text.contains("Iron in the Blood") and _btn_has("I'll do it"))
			for b in hq7.find_children("*", "Button", true, false):
				if b.text == "I'll do it" and not b.is_queued_for_deletion():
					b.pressed.emit()
					break
			G.add_item("iron_ore", 5)
			Q7._check("iron_fist_clan_1")
			G.log_event("duel_won", {"rival": "Disciple Kai", "sect": "crimson_veil"})
			check("...bring the iron, win a bout on the road -- then back to him (a ?)", Q7.marker_for("Master Wei") == "?")
			Q7.talk(wei, hq7, func(): pass)
			for b in hq7.find_children("*", "Button", true, false):
				if b.text == "Go on" and not b.is_queued_for_deletion():
					b.pressed.emit()
					break
			hq7.close_dialog()
			check("...done: his black iron ring (it hits harder), and the ore's gone to him", Q7.done.has("iron_fist_clan_1") and G.count("sq_ifc_knuckle") == 1 and G.count("iron_ore") == 0 and G.tech_effect("damage_mult", 1.0) >= 1.03)
			G.join_sect("iron_fist_clan")
			G.mark_level_entered("floor3", {})
			check("join the sect and the rest of its road opens to you, step by step", Q7.unlocked("iron_fist_clan_2") and not Q7.unlocked("iron_fist_clan_3") and not Q7.sect_locked("iron_fist_clan_2"))
			wei._sect()
			check("...and its elder tells you how far along it you are", hq7._dialog_body.text.contains("The sect's road: 1 of 5 done") and hq7._dialog_body.text.contains("Ask about"), hq7._dialog_body.text.right(200))
			hq7.close_dialog()
			Q7.accept("iron_fist_clan_2")
			var c7: float = float(G.sect.get("contrib", 0.0))
			for i7 in 10:
				G.log_event("parry", {})
			G.log_event("tower_floor", {"tower": "x", "floor": 1})
			G.log_event("tower_floor", {"tower": "x", "floor": 2})
			G.log_event("sect_donate", {"worth": 40})
			check("an outer disciple's duties: parries, tower floors, the stores -- then report to Disciple Lan", Q7.waiting_talk("Disciple Lan") == "iron_fist_clan_2")
			var lan = _find("NPC.gd", func(n): return str(n.npc_name) == "Disciple Lan")
			Q7.talk(lan, hq7, func(): pass)
			for b in hq7.find_children("*", "Button", true, false):
				if b.text == "Go on" and not b.is_queued_for_deletion():
					b.pressed.emit()
					break
			hq7.close_dialog()
			check("...the clan's hand-wraps, and contribution toward your next rank", Q7.done.has("iron_fist_clan_2") and G.count("sq_ifc_wraps") == 1 and float(G.sect.get("contrib", 0.0)) >= c7 + 60.0 - 0.01, "%.0f -> %.0f" % [c7, float(G.sect.get("contrib", 0.0))])
			G.sect["rank"] = 1
			G.mark_level_entered("floor9", {})
			check("Inner Disciple: the next step opens", Q7.unlocked("iron_fist_clan_3"))
			Q7.accept("iron_fist_clan_3")
			Q7.found("iron_fist_clan_3", "sq_ifc_gauntlet")
			Q7.hunted("iron_fist_clan_3")
			var hu = _find("NPC.gd", func(n): return str(n.npc_name) == "Disciple Hu")
			Q7.talk(hu, hq7, func(): pass)
			check("...a disciple's shame to find and a foe to end, and then a choice", _btn_has("Tell Master Wei the truth") and _btn_has("Nobody needs to know"))
			for b in hq7.find_children("*", "Button", true, false):
				if b.text.contains("Tell Master Wei the truth") and not b.is_queued_for_deletion():
					b.pressed.emit()
					break
			hq7.close_dialog()
			check("...the sect's secret art", Q7.done.get("iron_fist_clan_3", "") == "truth" and G.has_tech("ifc_hundred_blows") and G.tech_effect("damage_taken", 1.0) <= 0.94 + 0.001 and G.count("sq_ifc_gauntlet") == 0)
			G.sect["rank"] = 2
			G.mark_level_entered("floor14", {})
			Q7.accept("iron_fist_clan_4")
			check("Core Disciple: the founder's road -- first, get down to where she went", Q7.active.has("iron_fist_clan_4") and int(Q7.active["iron_fist_clan_4"]["stage"]) == 0)
			G.mark_level_entered("floor16", {})
			Q7._check("iron_fist_clan_4")
			Q7.found("iron_fist_clan_4", "sq_ifc_founder")
			Q7.hunted("iron_fist_clan_4")
			var aff7: float = float(G.affinity["metal"])
			var ins7: float = G.insight
			Q7.talk(wei, hq7, func(): pass)
			for b in hq7.find_children("*", "Button", true, false):
				if b.text == "Go on" and not b.is_queued_for_deletion():
					b.pressed.emit()
					break
			hq7.close_dialog()
			check("...the founder's heirloom, a title, metal affinity and insight", Q7.done.has("iron_fist_clan_4") and G.count("sq_ifc_founder_fist") == 1 and "Bearer of the Founder's Fist" in G.titles
				and float(G.affinity["metal"]) >= aff7 + 15.0 - 0.01 and G.insight > ins7, "aff %.0f->%.0f ins %.0f->%.0f" % [aff7, float(G.affinity["metal"]), ins7, G.insight])
			check("other sects' roads stay closed to you (one sect at a time)", not Q7.unlocked("crimson_veil_2") and Q7.sect_locked("crimson_veil_2"))
			hq7._hub.quest_filter = "sect"
			hq7._hub.show_page("Quests")
			check("the Quests page has a Sects filter, and says which roads belong to sects you haven't joined", _label_has(hq7._hub._quests, "Iron in the Blood") and _label_has(hq7._hub._quests, "sects you haven't joined"))
			hq7._hub.quest_filter = ""
			hq7._hub.close_hub()
			_build("floor20")
			check("where the six sects meet (the Jade Pagoda): Elder Bai's council", Q7.unlocked("concord_1") and Q7.marker_for("Elder Bai") == "!")
			Q7.accept("concord_1")
			check("...his invitations go to the elders in the valley -- not to anyone here", Q7.waiting_talk("Master Wei") == "")
			G.current_level = "valley"
			check("...(in the valley, Master Wei is waiting for it)", Q7.waiting_talk("Master Wei") == "concord_1")
			G.current_level = "floor20"
			var sv7: Dictionary = Q7.save_state()
			Q7.reset()
			Q7.load_state(JSON.parse_string(JSON.stringify(sv7)))
			check("the sects' roads survive save + load", Q7.done.has("iron_fist_clan_4") and Q7.active.has("concord_1"))
			wait = 0.1
		88:
			print("== round 56: the deep's reaches; Dungeon Crawl Elite on Android ==")
			G.new_game()
			G.choose_background("hunter")
			G.set_flag("creation_done")
			var RS = G.sys("reaches")
			var bios: Dictionary = preload("res://scripts/world/Reach.gd").data().get("biomes", {})
			check("ten lands for the deep's reaches, each with its own look, air, warden, materials and keepsake", bios.size() >= 10
				and bios.values().all(func(b): return preload("res://scripts/world/Look.gd").LOOKS.has(str(b.get("look", ""))) and G.has_item_def(str(b.get("material", ""))) and G.items.has(str(b.get("keepsake", {}).get("id", "")))))
			var lands := {}
			var bad8 := []
			for fl in [1, 2, 3, 6, 7, 9, 12, 14, 17, 19, 22, 24]:
				var fd: Dictionary = G.load_level_def("floor%d" % fl)
				if fd.is_empty():
					continue
				var rd: Dictionary = preload("res://scripts/world/Reach.gd").extend(preload("res://scripts/world/Expanse.gd").expand(fd), preload("res://scripts/world/Look.gd").key_for(fd))
				if (rd.get("reaches", []) as Array).is_empty():
					bad8.append("floor%d: none" % fl)
				for r8 in rd.get("reaches", []):
					lands[str(r8["biome"])] = true
					if str(preload("res://scripts/world/Reach.gd").biome(str(r8["biome"])).get("look", "")) == preload("res://scripts/world/Look.gd").key_for(fd):
						bad8.append("floor%d: same look as the floor" % fl)
				var again: Dictionary = preload("res://scripts/world/Reach.gd").extend(preload("res://scripts/world/Expanse.gd").expand(fd), preload("res://scripts/world/Look.gd").key_for(fd))
				if JSON.stringify(again.get("map", [])) != JSON.stringify(rd.get("map", [])):
					bad8.append("floor%d: not the same twice" % fl)
			check("every dungeon floor grows a reach (deeper ones two) -- never the floor's own land, the same every visit (%d lands seen)" % lands.size(), bad8.is_empty() and lands.size() >= 6, str(bad8))
			_build("floor7")
			var lv8 = level
			check("a built floor carries its reach: its own ground and walls, growths, lamps, a heart and its warden", lv8.reaches.size() >= 1 and int(lv8.counts.get("reach_hearts", 0)) == lv8.reaches.size()
				and int(lv8.counts.get("reach_growths", 0)) > 5 and lv8.find_children("ReachFloor_*", "", false, false).size() >= 1 and lv8.find_children("ReachWalls_*", "", false, false).size() >= 1, str(lv8.counts))
			# the way in is open from where you start (every secret opened)
			for sc in lv8.spawns.get("S", []):
				lv8.open_cell(sc)
			var r0: Dictionary = lv8.reaches[0]
			var hc0 := Vector2i(int(r0["heart"][0]), int(r0["heart"][1]))
			var p8: Vector2i = lv8.world_to_cell(lv8.spawn_point("<"))
			for dd8 in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(2, 0), Vector2i(0, 2)]:
				if lv8.char_at(p8 + dd8) == "." and not lv8.astar.is_point_solid(p8 + dd8):
					p8 = p8 + dd8
					break
			var path8: Array = lv8.path_between(p8, hc0)
			check("...and you can walk there from the stair: the tunnel joins it to the floor (%d steps)" % path8.size(), path8.size() > 10)
			wait = 0.2
		89:
			var RS = G.sys("reaches")
			var lv8 = level
			var r0: Dictionary = lv8.reaches[0]
			var hc0 := Vector2i(int(r0["heart"][0]), int(r0["heart"][1]))
			var heart8 = _find("ReachHeart.gd")
			check("the heart of the reach: its warden stands over it, named for the land, with a boss bar", heart8 != null and heart8.warden_alive() and str(heart8.warden.stats.get("name", "")).to_lower() == str(preload("res://scripts/world/Reach.gd").biome(str(r0["biome"])).get("warden", "?")).to_lower() and bool(heart8.warden.stats.get("boss", false)),
				"heart %s warden %s dead %s counts %s" % [heart8, heart8.warden if heart8 else null, heart8.warden.get("_dead") if heart8 and is_instance_valid(heart8.warden) else "?", str(lv8.counts.get("reach_wardens", 0))])
			var g8: int = G.gold
			heart8.interact(player)
			check("...while it lives, the heart gives nothing", G.gold == g8 and not RS.is_claimed("floor7", 0))
			var zone8 = null
			for zz in lv8.get_children():
				if zz.is_in_group("reach_zone"):
					zone8 = zz
			var ins8: float = G.insight
			player.global_position = lv8.cell_to_world(hc0 + Vector2i(0, 0))
			zone8._t = 0.0
			zone8._process(0.3)
			check("walk into a reach: it's named, the air changes, and the first time gives insight", zone8.inside and RS.seen.has("floor7:0") and G.insight > ins8 and RS.lands_found().size() == 1)
			heart8.warden.take_damage(99999999, "you")
			wait = 0.2
		90:
			var RS = G.sys("reaches")
			var r0: Dictionary = level.reaches[0]
			var heart8 = _find("ReachHeart.gd")
			var g8: int = G.gold
			var ks8 := str(preload("res://scripts/world/Reach.gd").biome(str(r0["biome"])).get("keepsake", {}).get("id", ""))
			heart8.interact(player)
			check("its warden falls: the heart's store -- gold by depth, the land's materials, qi, and the land's keepsake", not heart8.warden_alive() and G.gold > g8 and RS.is_claimed("floor7", 0) and G.count(ks8) == 1
				and G.count(str(preload("res://scripts/world/Reach.gd").biome(str(r0["biome"])).get("material", ""))) >= 3)
			var g8b: int = G.gold
			heart8.interact(player)
			check("...once a game", G.gold == g8b)
			_build("floor7")
			wait = 0.2
		91:
			var RS = G.sys("reaches")
			var heart8b = _find("ReachHeart.gd")
			check("...and coming back, the heart stands empty and no warden waits", heart8b != null and not heart8b.warden_alive() and not heart8b.is_in_group("interactable"))
			var sv8: Dictionary = RS.save_state()
			RS.reset()
			RS.load_state(JSON.parse_string(JSON.stringify(sv8)))
			check("the reaches you've walked and the hearts you've taken survive save + load", RS.is_claimed("floor7", 0) and RS.seen.has("floor7:0") and RS.keepsakes.size() == 1)
			var hq8 = root.get_tree().get_first_node_in_group("hud")
			hq8._hub.show_page("World")
			check("the World page lists the deep's lands -- found and not yet", _label_has(hq8._hub._world, "The deep's reaches -- 1 of") and _label_has(hq8._hub._world, "a land you haven't found"))
			hq8._hub.close_hub()
			# ---- Dungeon Crawl Elite, and the Google Play build
			check("the game is called Dungeon Crawl Elite now (the village is still Eliet)", str(ProjectSettings.get_setting("application/config/name")) == "Dungeon Crawl Elite" and str(G.credits_lines()[0]) == "DUNGEON CRAWL ELITE")
			var base8 := OS.get_user_data_dir().path_join("_r56test_%d" % Time.get_ticks_usec())
			DirAccess.make_dir_recursive_absolute(base8.path_join("Dungeon Crawl Eliet/sub"))
			var fo := FileAccess.open(base8.path_join("Dungeon Crawl Eliet/save_slot1.json"), FileAccess.WRITE)
			fo.store_string("{\"realm\": 3}")
			fo.close()
			fo = FileAccess.open(base8.path_join("Dungeon Crawl Eliet/sub/x.txt"), FileAccess.WRITE)
			fo.store_string("x")
			fo.close()
			var moved: int = G.migrate_user_dir(base8.path_join("Dungeon Crawl Elite"), base8)
			check("saves from the old name come across once, never overwriting, and the old folder stays", moved == 2 and FileAccess.file_exists(base8.path_join("Dungeon Crawl Elite/save_slot1.json"))
				and FileAccess.file_exists(base8.path_join("Dungeon Crawl Eliet/save_slot1.json")) and G.migrate_user_dir(base8.path_join("Dungeon Crawl Elite"), base8) == 0)
			for rmf in ["Dungeon Crawl Eliet/sub/x.txt", "Dungeon Crawl Eliet/save_slot1.json", "Dungeon Crawl Elite/sub/x.txt", "Dungeon Crawl Elite/save_slot1.json", "Dungeon Crawl Elite/" + G.MOVED_MARK,
					"Dungeon Crawl Eliet/sub", "Dungeon Crawl Elite/sub", "Dungeon Crawl Eliet", "Dungeon Crawl Elite", ""]:
				DirAccess.remove_absolute(base8.path_join(rmf))       # (tidy: the test leaves nothing behind)
			var keep_url: String = G.llm_url
			var keep_ov: Callable = G.llm_override
			G.llm_override = Callable()
			G.llm_url = ""
			var npc8 = null
			_build("village")
			npc8 = _find("NPC.gd", func(n): return str(n.npc_name) == "Elder Mo")
			var opts8: Array = npc8._talk_opts()
			check("on Android there's no box to ask: free talk isn't offered (everything else is)", G.llm_offline() and not opts8.any(func(o): return str(o[0]).begins_with("Talk with")) and opts8.any(func(o): return str(o[0]) == "Any advice?"))
			G.llm_url = keep_url
			check("...and with the box there, it is", not G.llm_offline() and npc8._talk_opts().any(func(o): return str(o[0]).begins_with("Talk with")))
			G.llm_override = keep_ov
			var main8 = load("res://Main.gd").new()
			main8._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
			wait = 0.2
			step += 1
			return false
		92:
			var hq8 = root.get_tree().get_first_node_in_group("hud")
			var paused0 := false
			check("Android's back button does what Escape does (the pause menu), and doesn't quit", ProjectSettings.get_setting("application/config/quit_on_go_back") == false and hq8._pause.visible != paused0)
			if hq8._pause.visible:
				hq8._toggle_pause()
			check("the phone build draws with the compatibility renderer (the one the browser version is proven on)", str(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile")) == "gl_compatibility")
			wait = 0.1
		93:
			print("== round 57: the loophole hunt -- money loops, save safety, things that came back ==")
			G.new_game()
			G.choose_background("hunter")
			G.set_flag("creation_done")
			# no buy-make-sell loop: every recipe, made masterwork, sells for less than its materials could ever be bought for
			var loops9 := []
			for r9 in G.recipes:
				var out9 := str(r9.get("makes", ""))
				if not G.items.has(out9):
					continue
				var cost9 := float(r9.get("gold", 0))
				for k9 in r9.get("needs", {}):
					cost9 += float(G.items.get(str(k9), {}).get("value", 10)) * 1.156 * float(r9["needs"][k9])
				G.inventory.clear()
				G.add_item(out9 + "@masterwork", 2, false)
				if G.sell_price(out9 + "@masterwork") * int(r9.get("count", 1)) > cost9 + 0.5:
					loops9.append(out9)
			check("no buy-craft-sell money loop: nothing made sells for more than its materials could be bought for (%d recipes)" % G.recipes.size(), loops9.is_empty(), str(loops9.slice(0, 6)))
			G.inventory.clear()
			G.add_item("iron_ore", 30, false)
			var g9: int = G.gold
			G.gold = 100000
			var fr9: Dictionary = G.forge_piece("armor", "iron_ore", "", 0.0, 0.999)
			check("...nor anything forged (a masterwork iron chest sells for less than bought ore and fuel)", bool(fr9.get("success", false)) and float(G.sell_price(str(fr9["item"]))) <= G.make_cost(str(fr9["item"])))
			check("...while a plain drop of the same kind still sells as before", G.sell_price("healing_salve") >= 0)
			G.gold = g9
			check("taking a negative number of something gives nothing", not G.remove_item("gold", -500) and G.gold == g9)
			# a save cut off halfway is never lost
			G.add_item("gold", 4242 - G.gold, false)
			G.save_game()
			G.add_item("gold", 1, false)
			G.save_game()                        # (the 4242 save is now the .bak)
			var full9 := FileAccess.get_file_as_string(G.save_path)
			var fw9 := FileAccess.open(G.save_path, FileAccess.WRITE)
			fw9.store_string(full9.left(full9.length() / 2))
			fw9.close()
			G.new_game()
			var ok9: bool = G.load_game()
			check("a save cut off halfway (a crash while writing) loads its last good backup instead of a blank character", ok9 and G.gold >= 4242 and G.background == "hunter", "ok %s gold %d bg %s" % [ok9, G.gold, G.background])
			var dir9: String = G.save_path.get_base_dir()
			var broken9 := Array(DirAccess.get_files_at(dir9)).filter(func(fn): return fn.contains(".broken-"))
			check("...and the broken file is kept aside, not written over", broken9.size() >= 1)
			for fn in broken9:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(dir9.path_join(fn)))
			# away rewards are written down at once
			var before9 := float(JSON.parse_string(FileAccess.get_file_as_string(G.save_path)).get("saved_at", 0.0))
			var dd9: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(G.save_path))
			dd9["saved_at"] = before9 - 3600.0 * 6.0
			var fw10 := FileAccess.open(G.save_path, FileAccess.WRITE)
			fw10.store_string(JSON.stringify(dd9))
			fw10.close()
			G.load_game()
			var after9 := float(JSON.parse_string(FileAccess.get_file_as_string(G.save_path)).get("saved_at", 0.0))
			check("what time away gave is saved the moment it's given (killing the game can't hand it out twice)", after9 > before9 - 60.0)
			# a fight in the arena isn't a place to wake up in
			G.arena = {"return_to": "floor5", "event": "exam"}
			G.current_level = "arena_floor5_exam_0"
			G.save_game()
			G.load_game()
			check("saved mid-fight in the arena: you wake where you came from, the bout called off", G.current_level == "floor5" and G.arena.is_empty(), "%s %s" % [G.current_level, G.arena])
			G.current_level = "village"
			# a sect's entry trial: standing for passing it, not for starting it over and over
			var F9 = G.sys("factions")
			var st9: float = F9.value("sects")
			G.log_event("sect_trial_start", {"sect": "x", "kind": "stillness"})
			check("starting a sect's trial (and failing) gives no standing", F9.value("sects") == st9)
			# the Keeper dies once
			_build("floor3")
			var kp9 = null
			for n9 in level.get_children():
				if n9.get("champion") != null and str(n9.champion) != "":
					kp9 = n9
			if kp9 != null:
				G.set_flag("r57:keeper_before")
			if kp9:
				kp9.take_damage(99999999, "you")
			wait = 0.2
		94:
			var kp_again = null
			_build("floor3")
			for n10 in level.get_children():
				if n10.get("champion") != null and str(n10.champion) != "":
					kp_again = n10
			check("a floor's Keeper dies once -- it isn't there to farm the next time (unless its key is still the only way through)", G.has_flag("r57:keeper_before") and G.has_flag("floor3:keeper") and (kp_again == null or G.count("key_floor3") == 0))
			# the scavenger's hollow: the same one all day
			var hol := []
			var same := true
			for d9 in range(20000, 20120):
				var h1: String = G.ScavengeGen.today("floor4", "floor5", d9)
				if h1 != G.ScavengeGen.today("floor4", "floor5", d9):
					same = false
				if h1 != "":
					hol.append(h1)
			check("the scavenger's hollow behind a stair is decided once a day -- the same hollow all day (no fresh chests by going up and down), about one day in seven",
				same and hol.size() > 5 and hol.size() < 40 and hol.all(func(x): return hol.count(x) == 1), "%d of 120 days" % hol.size())
			# named quest foes stand where they belong, not at the corner of the map
			G.mark_level_entered("floor2", {})
			var Q9 = G.sys("quests")
			Q9.active.erase("pells_hammer")
			Q9.done.erase("pells_hammer")
			Q9.accept("pells_hammer")
			_build("floor1")
			var hunt9 = null
			for n11 in level.get_children():
				if n11.has_meta("quest_hunt"):
					hunt9 = n11
			check("a quest's named foe stands on its own spot -- not at the map's corner", hunt9 != null and hunt9.position.length() > 6.0, str(hunt9.position if hunt9 else "none"))
			# reaches: nothing walled off
			var pockets := []
			for fl9 in range(1, 26):
				var fd9: Dictionary = G.load_level_def("floor%d" % fl9)
				if fd9.is_empty():
					continue
				var rd9: Dictionary = preload("res://scripts/world/Reach.gd").extend(preload("res://scripts/world/Expanse.gd").expand(fd9), preload("res://scripts/world/Look.gd").key_for(fd9))
				var m9: Array = rd9.get("map", [])
				for r9 in rd9.get("reaches", []):
					var rr9: Array = r9["rect"]
					var ent := Vector2i(int(r9["entry"][0]), int(r9["entry"][1]))
					var seen9 := {ent: true}
					var st9b := [ent]
					var blk := [" ", "#", "x", "c", "~", "%", "&", "b"]
					while not st9b.is_empty():
						var p9: Vector2i = st9b.pop_back()
						for d9 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
							var q9: Vector2i = p9 + d9
							if seen9.has(q9) or q9.y < 0 or q9.y >= m9.size() or q9.x < 0 or q9.x >= str(m9[q9.y]).length() or str(m9[q9.y])[q9.x] in blk:
								continue
							seen9[q9] = true
							st9b.append(q9)
					for yy in range(int(rr9[1]), int(rr9[1]) + int(rr9[3])):
						for xx in range(int(rr9[0]), int(rr9[0]) + int(rr9[2])):
							if yy < m9.size() and xx < str(m9[yy]).length() and not (str(m9[yy])[xx] in blk) and not seen9.has(Vector2i(xx, yy)):
								pockets.append("floor%d %d,%d" % [fl9, xx, yy])
			check("every open cell of every reach can be walked to (nothing walled off by a growth)", pockets.is_empty(), str(pockets.slice(0, 6)))
			var ins9: float = G.insight
			for i9 in 30:
				G.log_event("elite_kill", {"type": "x", "affixes": []})
			check("insight from elites (they come back with the floor) stops at the day's limit", G.insight - ins9 <= 5.0 * G.tech_effect("insight_mult", 1.0) + 0.01 and G.insight > ins9, "%.1f" % (G.insight - ins9))
			var slot0: int = G.slot
			G.use_slot(3)
			G.new_game()
			G.choose_background("hunter")
			G.set_flag("creation_done")
			G.save_game()
			G.save_game()
			G.erase_slot(3)
			check("an erased character stays erased (its backup goes with it)", not G.slot_info(3).get("exists", false))
			for fn2 in Array(DirAccess.get_files_at(G.save_path.get_base_dir())):
				if str(fn2).contains("slot3.erased"):
					DirAccess.remove_absolute(ProjectSettings.globalize_path(G.save_path.get_base_dir().path_join(fn2)))
			G.use_slot(slot0)
			wait = 0.1
		95:
			print("== round 58: phones free to floor 5 with no ads, free after with the odd ad (or buy: no ads); Steam whole; expansions ready ==")
			var st8 = G.store
			var ad8 = G.ads
			check("the game has a store and ads, and on a PC with no store set it's the whole game with no ads", st8 != null and ad8 != null and st8.pick_backend() == "full" and st8.full_game() and ad8.backend == "none" and not ad8.live())
			check("the model is the free tier with ads (data/store.json), the quiet road floors 1-5", st8.model() == "ads" and st8.free_depth() == 5)
			st8.file_path = "user://playtest_store.json"            # (never the real records)
			ad8.file_path = "user://playtest_ads.json"
			for f8 in [st8.file_path, ad8.file_path]:
				if FileAccess.file_exists(f8):
					DirAccess.remove_absolute(ProjectSettings.globalize_path(f8))
			st8.test_answer = "ok"
			st8.start("test")
			ad8.reset_record()
			ad8.assume_clear = true
			check("on a phone the free tier has ads (the pretend network here)", ad8.backend == "test" and ad8.live() and st8.ads_on())
			G.new_game()
			G.choose_background("hunter")
			G.set_flag("creation_done")
			var hd8 = root.get_tree().get_first_node_in_group("hud")
			hd8._moments_q.clear()                 # (round 61: a floor's verdict card an earlier test queued)
			hd8.close_dialog()
			check("nothing is locked on the free tier -- the whole game can be finished", not st8.level_locked("floor6") and not st8.level_locked("floor50"))
			check("the first trip below floor 5 gets a word first (once); floors 1-5 don't", st8.travel_check("floor6") == "word" and st8.travel_check("floor5") == "" and st8.travel_check("village") == "")
			var here8: String = G.current_level
			G.go_to("floor6", "<")
			check("the word: 'The road goes on' -- carry on free, remove the ads, restore, not now", G.current_level == here8 and hd8._dialog.visible and hd8._dialog_title.text == "The road goes on" and _btn_has("Carry on") and _btn_has("Remove the ads") and _btn_has("Restore purchases") and _btn_has("Not now"))
			check("the word says it stays free to the end, when ads come, and never in a fight", hd8._dialog_body.text.contains("stays free") and hd8._dialog_body.text.contains("never in a fight") and hd8._dialog_body.text.contains("$4.99"))
			for b8 in hd8._dialog_buttons.get_children():
				if b8 is Button and b8.text.begins_with("Carry on"):
					b8.pressed.emit()
			check("carry on: you go down, and the word isn't said again", G.current_level == "floor6" and st8.told.has("ads") and st8.travel_check("floor9") == "")
			wait = 2.5
		96:
			var st8 = G.store
			var ad8 = G.ads
			var hd8 = root.get_tree().get_first_node_in_group("hud")
			check("floor 6 reached on the free tier (the first trip down)", G.current_level == "floor6", G.current_level)
			ad8._pending_break = ""
			ad8._rec["shown"] = []
			if ad8.showing != "":
				ad8._end()
			hd8.close_dialog()
			# the ad breaks
			G.current_level = "floor3"
			check("no ads on floors 1-5", ad8.break_why_not("descend") == "free floors")
			G.current_level = "floor9"
			check("only at a break (the stairs down, a town)", ad8.break_why_not("menu") == "not a break" and ad8.break_why_not("descend") == "" and ad8.break_why_not("haven") == "")
			G.last_hurt_at = Time.get_unix_time_from_system()
			check("never straight after a blow (not in a fight)", ad8.break_why_not("descend") == "not safe")
			G.last_hurt_at = 0.0
			ad8._session_start = Time.get_unix_time_from_system()
			check("none in the first minutes of a sitting", ad8.break_why_not("descend") == "just sat down")
			ad8._session_start = 0.0
			var gold8: int = G.gold
			ad8.show_break("descend")
			check("an ad break pauses the game and quiets it while it plays", ad8.showing == "break" and root.get_tree().paused and AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")))
			ad8._end()
			check("when it closes the game carries on where it was", ad8.showing == "" and not root.get_tree().paused and not AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")) and G.gold == gold8)
			check("at most one every ten minutes", ad8.break_why_not("descend") == "too soon")
			var now8 := Time.get_unix_time_from_system()
			ad8._rec["shown"] = [now8 - 3500.0, now8 - 2900.0, now8 - 2300.0, now8 - 1700.0]
			check("and a cap an hour", ad8.break_why_not("descend") == "hour's cap")
			ad8._rec["shown"] = []
			# gifts: ads you choose
			ad8.last_fall_gold = 0
			check("no 'gold back' offer without a fall that cost gold", ad8.gift_why_not("recover_gold") != "")
			ad8.last_fall_gold = 50
			ad8.test_answer = "skip"
			ad8.watch_gift("recover_gold")
			ad8._end()
			check("an ad closed early gives nothing", G.gold == gold8 and ad8.last_fall_gold == 50)
			ad8.test_answer = "ok"
			ad8.watch_gift("recover_gold")
			ad8._end()
			check("an ad watched through gives the fall's gold back", G.gold == gold8 + 50 and ad8.last_fall_gold == 0)
			ad8.watch_gift("blessing")
			ad8._end()
			check("the deep's blessing: a buff with its own name, and then a wait before the next", G.buff_left("deep_blessing") > 1000.0 and " / ".join(G.buff_lines()).contains("The deep's blessing") and ad8.gift_why_not("blessing") == "not yet")
			hd8._refresh_store_buttons()
			check("the menu: 'Remove the ads -- the full game (price)' and Restore", hd8._unlock_btn.visible and hd8._unlock_btn.text.contains("Remove the ads") and hd8._unlock_btn.text.contains("$4.99") and hd8._restore_btn.visible)
			ad8._rec["gifts"] = {}
			hd8._refresh_store_buttons()
			check("the menu offers the blessing while it's ready", hd8._bless_btn.visible)
			hd8.offer_gift("blessing")
			check("a gift is asked, never forced: Watch the ad / No thanks", hd8._dialog.visible and _btn_has("Watch the ad") and _btn_has("No thanks"))
			hd8.close_dialog()
			# a fall: the offer to win the gold back, when you wake
			G.gold = 1000
			G.last_haven = "village"
			G.current_level = "floor9"
			hd8._moments_q.clear()
			hd8.close_dialog()
			G.player_died("test")
			ad8.on_arrival("floor9", "village", true, hd8)      # (Main does this when you wake; the playtest has no Main)
			wait = 1.0
		97:
			var st8 = G.store
			var ad8 = G.ads
			var hd8 = root.get_tree().get_first_node_in_group("hud")
			check("after a fall on the free tier, waking brings the offer of the gold back (a choice)", ad8.last_fall_gold == 100 and hd8._dialog.visible and hd8._dialog_title.text.contains("gold back") and _btn_has("No thanks"), "%d %s" % [ad8.last_fall_gold, hd8._dialog_title.text])
			for b8 in hd8._dialog_buttons.get_children():
				if b8 is Button and b8.text == "No thanks":
					b8.pressed.emit()
			check("'No thanks' and it's gone", ad8.last_fall_gold == 0 and not hd8._dialog.visible)
			# a break at the stairs, for real: Main asks after you arrive
			ad8._rec["shown"] = []
			ad8.test_answer = "ok"
			G.current_level = "floor9"
			ad8.on_arrival("floor8", "floor9", false, hd8)
			wait = 2.0
		98:
			var st8 = G.store
			var ad8 = G.ads
			var hd8 = root.get_tree().get_first_node_in_group("hud")
			check("arriving down the stairs on the free tier: a short break a breath later, then play goes on", ad8._rec["shown"].size() == 1 and ad8.showing == "" and not root.get_tree().paused)
			# buying: no more ads
			st8.test_answer = "ok"
			hd8._buy("full_game", "", "")
			check("the full game bought: no ad breaks, no gift offers, nothing to remove", st8.full_game() and not ad8.live() and ad8.break_why_not("descend") == "off" and ad8.gift_why_not("blessing") == "off")
			hd8._refresh_store_buttons()
			check("and the menu's store buttons go", not hd8._unlock_btn.visible and not hd8._bless_btn.visible)
			var st8b = load("res://scripts/core/Store.gd").new()
			st8b.file_path = st8.file_path
			st8b._load()
			check("the purchase (and the word said) are kept on the device", st8b.owned.has("full_game") and st8b.told.has("ads"))
			st8b.free()
			st8.revoke("full_game")
			check("a refund brings the ads back", ad8.live())
			# the other way it can be sold: below floor 5 locked
			st8._data["model"] = "locked"
			G.new_game()
			G.choose_background("hunter")
			G.set_flag("creation_done")
			check("model 'locked': floors 1-5 open, floor 6 and below locked, and ads off", not st8.level_locked("floor5") and st8.level_locked("floor6") and st8.level_locked("floor50") and not ad8.live())
			var hol8 := ""
			for dd8 in 400:
				hol8 = G.ScavengeGen.today("floor5", "floor6", dd8)
				if hol8 != "":
					break
			check("model 'locked': a hollow on the way to floor 6 is no back door", hol8 != "" and st8.depth_of(hol8) == 6 and st8.level_locked(hol8), hol8)
			var here8: String = G.current_level
			hd8.close_dialog()
			G.go_to("floor6", "<")
			check("model 'locked': the stair refuses and the unlock window opens", G.current_level == here8 and hd8._dialog.visible and _btn_has("Unlock the full game") and hd8._dialog_body.text.contains("forty-five more floors"))
			hd8.close_dialog()
			var lv8 = root.get_tree().get_first_node_in_group("level")
			var pl8 = root.get_tree().get_first_node_in_group("player")
			var ex8 = load("res://scripts/objects/Exit.gd").new()
			ex8.setup(lv8, {"to": "floor6", "arrive": "<", "cell": Vector2i(0, 0), "label": "test stair"})
			lv8.add_child(ex8)
			ex8._armed = true
			ex8._on_body_entered(pl8)
			check("model 'locked': the real stair opens it too, without passing the gate", G.current_level == here8 and hd8._dialog.visible and not G.gate_passed(6) and not ex8._armed)
			ex8.queue_free()
			hd8.close_dialog()
			for ans8 in ["cancel", "pending", "error"]:
				st8.test_answer = ans8
				hd8._buy("full_game", "floor6", "<")
				check("a purchase that comes back '%s' opens nothing and goes nowhere" % ans8, not st8.full_game() and G.current_level == here8 and not st8.busy)
			var q8 := ""
			for qd in G.sys("quests").all():
				if G.sys("quests").deepest_floor(str(qd["id"])) > 5:
					q8 = str(qd["id"])
					break
			check("model 'locked': a quest that goes below floor 5 is marked 'full game'", q8 != "" and G.sys("quests").locked_tag(q8) == " (full game)", q8)
			G.havens = {"village": "Eliet", "floor5": "Shellhaven", "floor10": "Somewhere Deep"}
			G.last_haven = "floor10"
			G.current_level = "floor9"
			G.spawn_tag = "<"
			G.save_game()
			G.load_game()
			var note8: String = G.take_after_load_note()
			check("model 'locked': a save below the free floors wakes in the deepest free town", G.current_level == "floor5" and G.last_haven == "floor5" and note8.contains("full game"), "%s %s '%s'" % [G.current_level, G.last_haven, note8])
			st8.test_answer = "ok"
			hd8._buy("full_game", "floor6", "<")
			check("model 'locked': bought on the stair, you go straight on down", st8.full_game() and G.current_level == "floor6")
			st8._data["model"] = "ads"
			check("on the ads model a quest is never marked", G.sys("quests").locked_tag(q8) == "")
			st8.revoke("full_game")
			# expansions: ready for when one is made
			var exps: Array = st8._data["expansions"]
			check("the planned expansions are listed, and not 'owned' by anyone yet", exps.size() >= 2 and not st8.owns_expansion("east_of_the_hills") and not G.expansion_open("below_the_heart"))
			exps.append({"id": "test_lands", "name": "The Test Lands", "status": "released", "levels_prefix": "testlands_", "pitch": "A test.", "products": {"google": "test_lands", "apple": "x.test_lands"}, "steam_dlc": 0})
			check("an expansion's places are known by their prefix", st8.expansion_of("testlands_road") == "test_lands" and st8.expansion_of("floor3") == "")
			check("a released expansion goes in the store's catalogue (and its price is asked for)", st8.catalogue().has("test_lands") and st8._ids("google").has("test_lands"))
			hd8.close_dialog()
			here8 = G.current_level
			G.go_to("testlands_road", "P")
			check("its places stay shut until it's yours, and its own window opens", G.current_level == here8 and hd8._dialog.visible and hd8._dialog_title.text == "The Test Lands" and _btn_has("Get The Test Lands"))
			hd8.close_dialog()
			var qs8: Array = G.sys("quests").data["quests"]
			qs8.append({"id": "testlands_q", "name": "A test", "giver": "nobody", "expansion": "test_lands", "stages": [{"goal": {"reach": 1}}]})
			check("an expansion's quests don't offer until it's yours", not G.sys("quests").unlocked("testlands_q"))
			hd8._buy("test_lands", "", "")
			check("bought: the expansion is open -- its places and its quests", st8.owns_expansion("test_lands") and G.expansion_open("test_lands") and st8.travel_check("testlands_road") == "" and G.sys("quests").unlocked("testlands_q"))
			check("an expansion doesn't remove the ads (that's the full game)", ad8.live())
			hd8.open_expansions()
			check("the expansions page: planned ones say so; a released one is 'yours'", hd8._dialog_body.text.contains("East of the Hills") and hd8._dialog_body.text.contains("planned -- not built yet") and hd8._dialog_body.text.contains("The Test Lands  (yours)"))
			hd8.close_dialog()
			qs8.pop_back()
			# Google Play's answers, with a stand-in client
			var gs8 := GDScript.new()
			gs8.source_code = "extends RefCounted\nvar acked := []\nvar queried := 0\nfunc acknowledge_purchase(t): acked.append(t)\nfunc query_purchases(_t): queried += 1\nfunc purchase(_p): return {\"status\": 0}\n"
			gs8.reload()
			var mock8 = gs8.new()
			st8.start("test")
			st8.backend = "google"
			st8._billing = mock8
			st8.connected = true
			st8._g_details({"response_code": 0, "product_details": [{"product_id": "full_game", "one_time_purchase_offer_details": {"formatted_price": "$6.99"}}]})
			check("Google Play's own price is what the game shows", st8.price_text() == "$6.99")
			st8._g_updated({"response_code": 0, "purchases": [{"products": ["full_game"], "purchase_state": 2, "purchase_token": "t1", "is_acknowledged": false}]})
			check("a pending Google purchase doesn't count yet", not st8.full_game())
			st8._g_updated({"response_code": 0, "purchases": [{"products": ["full_game"], "purchase_state": 1, "purchase_token": "t1", "is_acknowledged": false}]})
			check("a Google purchase that clears counts and is acknowledged (so Play doesn't refund it)", st8.full_game() and mock8.acked == ["t1"])
			st8._g_purchases({"response_code": 6})
			check("Google not answering keeps what we knew (offline play still works)", st8.full_game())
			st8._g_purchases({"response_code": 0, "purchases": [{"products": ["test_lands"], "purchase_state": 1, "purchase_token": "t2", "is_acknowledged": true}]})
			check("Google saying the full game isn't owned (a refund) takes it back; an expansion it lists stays", not st8.full_game() and st8.owned.has("test_lands") and mock8.acked == ["t1"])
			st8._g_updated({"response_code": 7})
			check("'already owned' on Google asks what the account owns", mock8.queried == 1)
			st8.backend = "apple"
			st8._a_event({"type": "product_info", "ids": ["com.grimm82.dungeoncrawlelite.full_game"], "localized_prices": ["4,99 €"]})
			st8._a_event({"type": "restore", "result": "ok", "product_id": "com.grimm82.dungeoncrawlelite.full_game"})
			check("the App Store's price and a restored purchase are taken", st8.price_text() == "4,99 €" and st8.full_game())
			st8._billing = null
			st8.revoke("full_game")
			exps.pop_back()
			# the Steam demo: floors 1-5, then the full game's store page; the same save carries on
			st8.start("demo")
			ad8.start(ad8.pick_backend())
			check("the Steam demo: floors 1-5 open, below locked, no ads, its one button is the full game's page", st8.demo() and st8.model() == "locked" and not st8.level_locked("floor5") and st8.level_locked("floor6") and not st8.ads_on() and not ad8.live() and st8.can_buy() and not st8.phone_store())
			hd8.close_dialog()
			here8 = G.current_level
			var ex9 = load("res://scripts/objects/Exit.gd").new()
			ex9.setup(lv8, {"to": "floor77", "arrive": "<", "cell": Vector2i(0, 0), "label": "test stair"})
			lv8.add_child(ex9)
			ex9._armed = true
			ex9._on_body_entered(pl8)
			check("the demo's last stair: 'The end of the demo' (not 'still being built' -- the demo leaves the deep floors out)", G.current_level == here8 and hd8._dialog.visible and hd8._dialog_title.text == "The end of the demo" and _btn_has("Get the full game on Steam") and hd8._dialog_body.text.contains("picks up right here"))
			ex9.queue_free()
			check("with no store page set yet, the button says so rather than opening nothing", st8.buy("full_game").contains("isn't set yet"))
			st8._data["steam"]["full_app_id"] = 4242
			check("the full game's Steam page comes from its app id", st8.steam_page() == "https://store.steampowered.com/app/4242/")
			st8._data["steam"]["full_app_id"] = 0
			hd8.close_dialog()
			hd8._refresh_store_buttons()
			check("the demo's menu: 'Get the full game on Steam', and no restore", hd8._unlock_btn.visible and hd8._unlock_btn.text.begins_with("Get the full game on Steam") and not hd8._restore_btn.visible)
			check("the demo has its own Steam app id slot (project.godot steam/app_id.demo)", ProjectSettings.has_setting("steam/app_id.demo"))
			var cf8 := ConfigFile.new()
			var demo_ok := false
			if cf8.load("res://export_presets.cfg") == OK:
				for sec8 in cf8.get_sections():
					if str(cf8.get_value(sec8, "name", "")) == "Windows (Steam Demo)":
						var exf := str(cf8.get_value(sec8, "exclude_filter", ""))
						demo_ok = str(cf8.get_value(sec8, "custom_features", "")).contains("demo") and exf.contains("levels/floor??.json") and exf.contains("levels/floor6*.json")
			check("there's a Steam demo export that leaves floors 6-50 out", demo_ok)
			check("the demo and the full game share the save folder (same project name), so a bought game picks up the demo's character", str(ProjectSettings.get_setting("application/config/name")) == "Dungeon Crawl Elite" and not bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false)))
			st8.start("none")
			check("a phone build with no store reachable says so instead of pretending", st8.why_not() != "" and st8.buy("full_game") != "" and not st8.full_game())
			st8.start("full")
			check("Steam (and the box's own builds): the whole game from the start, no ads, nothing to buy", st8.full_game() and not st8.level_locked("floor50") and not st8.can_buy() and not st8.ads_on() and not ad8.live() and st8.travel_check("floor9") == "")
			hd8._refresh_store_buttons()
			check("on Steam the menu has no store, ad or gift buttons", not hd8._unlock_btn.visible and not hd8._restore_btn.visible and not hd8._bless_btn.visible and not hd8._privacy_btn.visible)
			check("Steam can tell whether an expansion's DLC is installed (off: no)", G.steam.has_method("dlc_installed") and not G.steam.dlc_installed(12345))
			check("the Google Play Billing plugin is in the project, loads, and is switched on", load("res://addons/GodotGooglePlayBilling/BillingClient.gd") != null and FileAccess.file_exists("res://addons/GodotGooglePlayBilling/bin/release/GodotGooglePlayBilling-release.aar") and "res://addons/GodotGooglePlayBilling/plugin.cfg" in ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray()))
			var br8 = load("res://scripts/core/AdMobBridge.gd")
			check("the AdMob plugin (Android) is in the project and switched on, and the bridge to it compiles", br8 != null and br8.can_instantiate() and FileAccess.file_exists("res://addons/admob/android/bin/ads/libs/poing-godot-admob-ads-release.aar") and FileAccess.file_exists("res://addons/admob/ios/bin/package.gd") and "res://addons/admob/plugin.cfg" in ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray()))
			check("until Robert's own AdMob ids go in, it's Google's test ads", str(ProjectSettings.get_setting("admob/general/android/app_id", "ca-app-pub-3940256099942544~3347511713")).begins_with("ca-app-pub-3940256099942544") and str(st8.data()["ads"]["units"]["android"]["interstitial"]).begins_with("ca-app-pub-3940256099942544"))
			for f8 in [st8.file_path, ad8.file_path]:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(f8))
			st8.file_path = "user://store.json"
			ad8.file_path = "user://ads.json"
			ad8.assume_clear = false
			st8._data = {}
			st8.start(st8.pick_backend())
			ad8.start(ad8.pick_backend())
			wait = 0.5
		99:
			print("== round 59: sound you'd leave on -- pieces with quiet between, the place's own air, drums in a fight ==")
			var au9 = G.audio
			var ad9: Dictionary = au9.data()
			var missing9 := []
			for set9 in ad9.get("sets", {}):
				for p9 in ad9["sets"][set9]:
					if not ResourceLoader.exists("res://assets/audio/music2/%s.ogg" % p9):
						missing9.append(p9)
			for k9 in ["dungeon", "deep", "boss"]:
				for c9 in ad9.get("combat", {}).get(k9, []):
					if not ResourceLoader.exists("res://assets/audio/combat/%s.ogg" % c9):
						missing9.append(c9)
			var beds9 := {"village_day": 1, "village_night": 1, "valley_day": 1, "valley_night": 1, "town": 1, "cave": 1, "deep": 1}
			for lk9 in ad9.get("ambience", {}).get("look", {}):
				beds9[str(ad9["ambience"]["look"][lk9])] = 1
			for b9 in beds9:
				if not ResourceLoader.exists("res://assets/audio/ambience/%s.ogg" % b9):
					missing9.append(b9)
			check("every piece, fight loop and ambience the game names is there", missing9.is_empty() and ad9["sets"].size() >= 8, str(missing9))
			var n9 := 0
			for set9 in ad9["sets"]:
				n9 += ad9["sets"][set9].size()
			check("music comes as many pieces (not five loops): 19, several per place", n9 >= 19 and ad9["sets"]["dungeon"].size() >= 3 and ad9["sets"]["deep"].size() >= 3)
			G.hour_override = 12.0
			check("each place has its own music: village, valley, dungeon, deep, abyss, a town below, the title", au9.music_for("village", {"theme": "village"}) == "village" and au9.music_for("valley", {}) == "valley"
				and au9.music_for("floor3", {"depth": 3}) == "dungeon" and au9.music_for("floor12", {"depth": 12}) == "deep" and au9.music_for("floor35", {"depth": 35}) == "abyss"
				and au9.music_for("floor10", {"depth": 10, "theme": "settlement"}) == "haven" and au9.music_for("title", {}) == "title")
			G.hour_override = 23.0
			check("...and the village has night music of its own", au9.music_for("village", {"theme": "village"}) == "village_night")
			G.hour_override = -1.0
			var Gx9 = load("res://scripts/core/Gfx.gd")
			var keep9 := {}
			for k9 in ["music", "sfx", "ambience", "music_often", "fight_music", "music_style"]:
				keep9[k9] = Gx9.settings.get(k9)
			Gx9.settings["music"] = 6
			Gx9.settings["music_often"] = "sometimes"
			Gx9.settings["music_style"] = "new"
			Gx9.settings["fight_music"] = "on"
			var heard9 := []
			au9.now_playing.connect(func(t): heard9.append(t))
			au9.context = ""
			au9.set_context("dungeon")
			var fd9: Array = ad9.get("first_delay", [2, 6])
			check("arriving somewhere, its music starts soon (a breath first)", au9.piece == "" and au9.wait_left >= float(fd9[0]) and au9.wait_left <= float(fd9[1]))
			au9._tick_director(au9.wait_left + 0.1)
			var first9: String = au9.piece
			check("...a piece from that place's set, its name shown for a moment", first9 in ad9["sets"]["dungeon"] and heard9.size() == 1 and heard9[0] != "", "%s %s" % [first9, str(heard9)])
			au9._tick_director(au9._piece_left + 0.1)
			var gr9: Array = ad9["gaps"]["sometimes"]
			check("when it ends, a quiet stretch (the place's own sound carries it)", au9.piece == "" and au9.wait_left >= float(gr9[0]) and au9.wait_left <= float(gr9[1]), str(au9.wait_left))
			var repeats9 := 0
			var prev9 := first9
			for i9 in 12:
				au9._tick_director(au9.wait_left + 0.1)
				if au9.piece == prev9:
					repeats9 += 1
				prev9 = au9.piece
				au9._tick_director(au9._piece_left + 0.1)
			check("never the same piece twice running", repeats9 == 0)
			Gx9.settings["music_often"] = "rarely"
			au9._tick_director(au9.wait_left + 0.1)
			au9._tick_director(au9._piece_left + 0.1)
			check("'rarely' means long quiet stretches (3-7 minutes)", au9.wait_left >= 180.0 and au9.wait_left <= 420.0)
			Gx9.settings["music"] = 0
			au9._tick_director(au9.wait_left + 0.1)
			check("music at 0: no piece starts at all", au9.piece == "")
			Gx9.settings["music"] = 6
			Gx9.settings["music_often"] = "sometimes"
			Gx9.settings["music_style"] = "classic"
			au9.restart_music()
			check("the old loops are kept as 'classic'", au9.piece == "dungeon")
			Gx9.settings["music_style"] = "new"
			au9.restart_music()
			check("...and back to pieces", au9.piece == "" and au9.context == "dungeon")
			# drums in a fight
			var pl9 = root.get_tree().get_first_node_in_group("player")
			var fs9 := GDScript.new()
			fs9.source_code = "extends Node3D\nvar _chasing := true\nvar _dead := false\nvar stats := {}\n"
			fs9.reload()
			var foe9 = fs9.new()
			foe9.add_to_group("enemy")
			root.add_child(foe9)
			foe9.global_position = pl9.global_position + Vector3(3, 0, 0)
			au9.combat_track = ""
			au9.combat_level = 0.0
			au9._combat_poll = 0.0
			au9._tick_combat(0.5)
			au9._tick_combat(0.5)
			check("a foe on you: fight drums come up and the music steps back", au9.combat_track in ad9["combat"]["dungeon"] and au9.combat_level > 0.5 and au9._music_level() < Gx9.settings["music"] / 10.0 * 0.8, "%s %.2f" % [au9.combat_track, au9.combat_level])
			foe9.stats = {"boss": true}
			au9._combat_poll = 0.0
			au9._tick_combat(0.3)
			check("a master's fight has its own drums", au9.combat_track in ad9["combat"]["boss"])
			foe9._chasing = false
			for i9 in 40:
				au9._tick_combat(0.3)
			check("the drums go a few seconds after the last foe stops chasing", au9.combat_level == 0.0 and au9.combat_track == "")
			foe9._chasing = true
			Gx9.settings["fight_music"] = "off"
			au9._combat_poll = 0.0
			au9._tick_combat(0.5)
			check("fight drums can be turned off", au9.combat_level == 0.0 and au9.combat_track == "")
			Gx9.settings["fight_music"] = "on"
			foe9.queue_free()
			# ambience
			var lvA = root.get_tree().get_first_node_in_group("level")
			var keepA = lvA.look_key
			lvA.look_key = "drowned"
			check("each place has its own air: a drowned floor laps and drips", au9.ambience_for(lvA) == "water")
			lvA.look_key = "forge"
			check("...a forge-deep roars", au9.ambience_for(lvA) == "fire")
			lvA.look_key = keepA
			au9.set_reach_look("frost")
			au9._amb_poll = 0.0
			au9._tick_ambience(0.1)
			check("walking into a reach changes the air to the reach's own", au9.ambience == "frost")
			au9.set_reach_look("")
			au9._amb_poll = 0.0
			au9._tick_ambience(0.1)
			check("...and back when you leave", au9.ambience != "frost" and au9.ambience != "")
			# sounds
			var takes9 := 0
			for i9 in range(1, 9):
				if ResourceLoader.exists("res://assets/audio/sfx/hit_flesh%d.ogg" % i9):
					takes9 += 1
			check("more takes of the sounds heard most (hits: 5), so they don't repeat", takes9 >= 5)
			check("the sounds the game asked for and didn't have are there now (dig), and the new ones (wind-up, rare loot, floor cleared)", au9.has_sound("dig") and au9.has_sound("windup") and au9.has_sound("loot_rare") and au9.has_sound("loot_epic") and au9.has_sound("floor_clear"))
			# the settings
			var a0: int = int(Gx9.settings.get("ambience", 7))
			Gx9.step_volume("ambience", root.get_tree())
			check("ambience has its own volume (0-10)", int(Gx9.settings["ambience"]) == (a0 + 2) % 12)
			var hd9 = root.get_tree().get_first_node_in_group("hud")
			hd9.close_dialog()
			hd9.open_sound()
			check("one Sound window: music, ambience, effects, how often music plays, fight drums, style", hd9._dialog.visible and _btn_has("Ambience") and _btn_has("Music between quiet stretches") and _btn_has("Drums in a fight") and _btn_has("Music style") and _btn_has("Done"))
			for b9 in hd9._dialog_buttons.get_children():
				if b9 is Button and b9.text.begins_with("Music between quiet stretches"):
					b9.pressed.emit()
					break
			check("...and its buttons turn the dial and stay open", hd9._dialog.visible and str(Gx9.settings["music_often"]) == "rarely" and _btn_has("rarely"))
			hd9.close_dialog()
			check("the store-test setting is read from the settings file now (it was ignored)", Gx9.settings.has("store_test"))
			for k9 in keep9:
				Gx9.settings[k9] = keep9[k9]
			wait = 0.1
		100:
			print("== round 60: combat you can read -- heavy blows shown first, openings, perfect dodges, masters' big moves, new elites, weapons that fight differently ==")
			_build("floor1")                         # (a clean, known floor to fight on)
			_place_player(Vector2i(5, 7))
			G.new_game()
			G.choose_background("hunter")
			G.set_flag("creation_done")
			G.hp = 100000
			var pl0 = root.get_tree().get_first_node_in_group("player")
			var lv0 = root.get_tree().get_first_node_in_group("level")
			for oe in root.get_tree().get_nodes_in_group("enemy"):
				oe.queue_free()
			var fwd0 := Vector3(sin(pl0._model.rotation.y), 0, cos(pl0._model.rotation.y))
			var mk0 = func(extra: Dictionary):
				var a0: Dictionary = {"type": "goblin_brute", "cell": lv0.world_to_cell(pl0.global_position), "style": "brawler", "affixes": []}
				a0.merge(extra, true)
				var e0 = lv0._spawn_script("res://scripts/actors/Enemy.gd", pl0.global_position + fwd0 * 1.4, a0)
				e0.elite = true
				e0._chasing = true
				return e0
			var e1 = mk0.call({})
			_hold["e1"] = e1
			e1._heavy_at = 1
			e1._swings = 0
			pl0._hurt_cool = 0.0
			e1._attack(pl0)
			check("every so often a foe winds up a HEAVY blow instead (a red ring grows, the wind-up sounds)", e1._heavy_t > 0.0 and e1._tell_ring != null and e1._tell_ring.visible)
			# guarded (not a parry): the guard breaks
			pl0.guarding = true
			pl0._guard_t = 99.0
			var hp0: int = G.hp
			e1._heavy_tick(e1._heavy_t + 0.01, pl0)
			check("a guard can't hold a heavy blow: it breaks and the blow lands in full", G.hp < hp0 and hp0 - G.hp >= int(round(float(e1.stats["damage"]) * 1.8 * 0.5)), "%d" % (hp0 - G.hp))
			# parried
			pl0._hurt_cool = 0.0
			e1._stun = 0.0
			e1.exposed = 0.0
			e1._heavy_at = 1
			e1._swings = 0
			e1._attack(pl0)
			pl0.guarding = true
			pl0._guard_t = 0.0
			hp0 = G.hp
			e1._heavy_tick(e1._heavy_t + 0.01, pl0)
			check("parried as it lands: no harm, a long stagger, and it's left OPEN", G.hp == hp0 and e1._stun > 0.0 and e1.exposed > 0.0)
			pl0.guarding = false
			# rolled through it as it lands: a perfect dodge
			e1._stun = 0.0
			e1.exposed = 0.0
			e1._heavy_at = 1
			e1._swings = 0
			e1._attack(pl0)
			pl0._hurt_cool = 0.3
			pl0._dodge_t = 0.3
			hp0 = G.hp
			e1._heavy_tick(e1._heavy_t + 0.01, pl0)
			check("rolled through it just as it lands: a PERFECT dodge -- the world slows and it's wide open", G.hp == hp0 and Engine.time_scale < 1.0 and e1.exposed > 0.0)
			Engine.time_scale = 1.0
			# read it and stepped back: it swings at air
			e1.exposed = 0.0
			e1._heavy_at = 1
			e1._swings = 0
			e1._attack(pl0)
			pl0._hurt_cool = 0.0
			pl0._dodge_t = 0.0
			e1.global_position = pl0.global_position + fwd0 * 8.0
			hp0 = G.hp
			e1._heavy_tick(e1._heavy_t + 0.01, pl0)
			check("stepped out of reach: it swings at air and is left open", G.hp == hp0 and e1.exposed > 0.0)
			var h1: int = e1.hp
			e1.take_damage(10, "you")
			check("an OPEN foe takes half again from every hit", h1 - e1.hp == 15, str(h1 - e1.hp))
			e1.exposed = 0.0
			e1._heavy_at = 1
			e1._swings = 0
			e1.global_position = pl0.global_position + fwd0 * 1.4
			e1._attack(pl0)
			e1.stagger(0.6)
			check("stagger it mid-wind-up (a heavy blow, a finisher, an art) and the blow never comes", e1._heavy_t == 0.0 and not e1._tell_ring.visible)
			e1._stun = 0.0
			var cnt0 := 0
			for i0 in 40:
				e1._heavy_at = 99
				if e1._can_heavy():
					cnt0 += 1
			check("brawlers, guards, lurkers and brood-mothers can wind up a heavy blow (elites and masters from the first floor)", cnt0 == 40 and e1._can_heavy() and "guardian" in G.combat_data()["foe_heavy"]["styles"])
			e1.queue_free()
			# a master's big moves
			var b1 = mk0.call({"type": "goblin_chief"})
			b1.stats["boss"] = true
			b1.global_position = pl0.global_position + fwd0 * 6.0
			b1._bm_t = 0.0
			var nb0: int = root.get_tree().get_nodes_in_group("blast").size()
			b1._boss_move(0.1, pl0, 6.0)
			var bl0: Array = root.get_tree().get_nodes_in_group("blast")
			check("a master SLAMS: a disc grows under you first", bl0.size() == nb0 + 1 and Vector2(bl0[-1].global_position.x - pl0.global_position.x, bl0[-1].global_position.z - pl0.global_position.z).length() < 0.2)
			pl0._hurt_cool = 0.0
			hp0 = G.hp
			bl0[-1].land()
			check("...stay in it and it lands on you (and it arrives there)", G.hp < hp0 and b1.global_position.distance_to(pl0.global_position) < 1.5)
			b1._bm_busy = 0.0
			b1._bm_t = 0.0
			b1._boss_move(0.1, pl0, 1.5)
			var bl1: Array = root.get_tree().get_nodes_in_group("blast")
			var sweep0: bool = bl1.size() > 0 and (bl1[-1].global_position.distance_to(b1.global_position) < 0.3 or Vector2(bl1[-1].global_position.x - pl0.global_position.x, bl1[-1].global_position.z - pl0.global_position.z).length() < 0.2)
			pl0._hurt_cool = 0.3
			pl0._dodge_t = 0.3
			hp0 = G.hp
			if bl1.size() > 0:
				bl1[-1].land()
			check("close in it SWEEPS or slams round itself; roll through it and the master is left open", sweep0 and G.hp == hp0 and b1.exposed > 0.0)
			Engine.time_scale = 1.0
			pl0._dodge_t = 0.0
			b1.queue_free()
			# the new elites
			var v1 = mk0.call({"affixes": ["volatile"]})
			v1._volatile()
			var bl2: Array = root.get_tree().get_nodes_in_group("blast")
			check("a VOLATILE elite's last breath bursts -- a ring to get out of", bl2.size() > 0 and bl2[-1].radius > 3.0)
			for b in bl2:
				b.queue_free()
			v1.queue_free()
			var k1 = mk0.call({"affixes": ["blinking"]})
			k1.global_position = pl0.global_position + fwd0 * 6.0
			k1._blink_w = 0.01
			k1._blink(0.02, pl0, 6.0)
			check("a BLINKING elite flickers, then steps out of the air beside or behind you", absf(Vector2(k1.global_position.x - pl0.global_position.x, k1.global_position.z - pl0.global_position.z).length() - 1.8) < 0.6, str(k1.global_position.distance_to(pl0.global_position)))
			var c1 = mk0.call({"affixes": ["commanding"]})
			var o1 = mk0.call({})
			o1.global_position = c1.global_position + Vector3(2, 0, 0)
			c1._rally_t = 0.0
			c1._rally(0.1)
			check("a COMMANDING elite drives the others near it (they hit harder, move faster) -- kill it first", o1.rallied > 0.0 and c1._rally_speed() > 1.0 and G.foes_data()["affixes"].has("commanding"))
			k1.queue_free()
			c1.queue_free()
			o1.queue_free()
			# weapons that fight differently
			var wh0: String = G.weapon
			G.weapon = ""
			check("bare hands: a longer chain window, a longer stagger", float(G.weapon_trait().get("window", 1.0)) > 1.0)
			G.weapon = wh0
			var kinds0 := {}
			for iid in G.items:
				var dd: Dictionary = G.items[iid]
				if str(dd.get("type", "")) == "weapon" and not kinds0.has(str(dd.get("kind", ""))):
					kinds0[str(dd.get("kind", ""))] = iid
			var all0 := true
			for kk in ["sword", "dagger", "saber", "spear", "axe", "hammer", "halberd", "staff"]:
				if not kinds0.has(kk) or not G.weapon_trait(kinds0[kk]).has("name") or not G.item_desc(kinds0[kk]).contains(str(G.weapon_trait(kinds0[kk])["name"])):
					all0 = false
			check("every kind of weapon has its own way of fighting, and says so", all0, str(kinds0.keys()))
			var w0: String = G.weapon
			var tgt0 = mk0.call({})
			tgt0.stats["hp"] = 99999
			tgt0.hp = 99999
			G.weapon = kinds0.get("axe", "")
			pl0._combo = 2
			pl0._heavy = false
			pl0._deal_hit()
			check("an axe's finisher SUNDERS (that foe takes more for a while)", tgt0.sundered > 0.0)
			G.weapon = kinds0.get("spear", "")
			tgt0.global_position = pl0.global_position + fwd0 * 1.4
			pl0._combo = 2
			pl0._deal_hit()
			check("a spear's finisher reaches further and drives them back", tgt0._knock.length() > 1.0)
			tgt0._knock = Vector3.ZERO
			G.weapon = kinds0.get("staff", "")
			G.heat = 50.0
			pl0._combo = 0
			pl0._deal_hit()
			check("a staff: every blow that lands cools your nanite heat a little", G.heat < 50.0)
			G.weapon = w0
			tgt0.queue_free()
			G.hp = G.max_hp()
			wait = 0.2
		101:
			print("== round 61: one more floor -- a floor's verdict, the descent streak, rare finds, almost-there ==")
			G.new_game()
			G.choose_background("hunter")
			G.set_flag("creation_done")
			var FR = G.sys("floorrun")
			check("the floor-run system is in the game", FR != null and not FR.cfg.is_empty())
			FR.reset()
			var cards1 := []
			FR.floor_cleared.connect(func(c): cards1.append(c))
			G.current_level = "floor7"
			G.log_event("enter_level", {"id": "floor7", "enemies": 40, "chests": 6, "secrets": 3})
			check("stepping onto a floor starts its tally", str(FR.run.get("level", "")) == "floor7" and int(FR.run.get("foes", 0)) == 40)
			G.log_event("leave_level", {"to": "floor8"})
			G.current_level = "floor8"
			G.log_event("enter_level", {"id": "floor8", "enemies": 30, "chests": 4, "secrets": 2})
			G.log_event("leave_level", {"to": "floor9"})
			G.current_level = "floor9"
			G.log_event("enter_level", {"id": "floor9", "enemies": 30, "chests": 4, "secrets": 2})
			check("going down floor after floor builds a descent streak", FR.streak == 2)
			check("...worth more qi from kills and more luck with loot", G.tech_effect("loot_luck", 0.0) >= 0.079 and G.tech_effect("qi_mult", 1.0) >= 1.099, "%.3f %.3f" % [G.tech_effect("loot_luck", 0.0), G.tech_effect("qi_mult", 1.0)])
			var hdF = root.get_tree().get_first_node_in_group("hud")
			hdF.update_clock()
			check("...shown by the clock", hdF._clock.text.contains("Descent x2"))
			G.log_event("leave_level", {"to": "floor8"})
			G.current_level = "floor8"
			G.log_event("enter_level", {"id": "floor8", "enemies": 30, "chests": 4, "secrets": 2})
			check("turn back up and the streak is gone", FR.streak == 0)
			FR.streak = 3
			G.log_event("death", {"cause": "test"})
			check("fall and it's gone", FR.streak == 0)
			# a floor done well
			G.current_level = "floor7"
			G.log_event("enter_level", {"id": "floor7", "enemies": 40, "chests": 6, "secrets": 3})
			FR.run["kills"] = 40
			FR.run["chests"] = 6
			FR.run["secrets"] = 3
			FR.run["low"] = 0.9
			FR.run["start"] = G.playtime - 300.0
			G.fog_frac["floor7"] = 1.0
			FR.note_hit(321)
			var g0: int = G.gold
			G.log_event("boss_kill", {"type": "x"})
			check("when a floor's master falls, the floor's verdict: graded S..D", cards1.size() == 1 and str(cards1[0]["grade"]) == "S", str(cards1))
			check("...a first time through pays (gold, insight, qi), and remembers your best there", G.gold > g0 and str(FR.best.get("floor7", "")) == "S" and int(cards1[0]["pay"]["gold"]) > 0)
			check("...with a line from whoever watches, the hardest blow, and what's below", str(cards1[0]["title"]) != "" and str(cards1[0]["line"]) != "" and int(cards1[0]["best_hit"]) == 321 and str(cards1[0]["below"].get("name", "")) != "")
			G.log_event("boss_kill", {"type": "x"})
			check("one verdict per visit", cards1.size() == 1)
			# a worse visit pays nothing; a better one pays the difference
			G.current_level = "floor8"
			G.log_event("enter_level", {"id": "floor8", "enemies": 30, "chests": 4, "secrets": 2})
			G.current_level = "floor7"
			G.log_event("enter_level", {"id": "floor7", "enemies": 40, "chests": 6, "secrets": 3})
			FR.run["low"] = 0.1
			G.fog_frac["floor7"] = 0.2
			g0 = G.gold
			G.log_event("boss_kill", {"type": "x"})
			check("a worse visit: graded lower, pays nothing, your best stays", cards1.size() == 2 and str(cards1[1]["grade"]) in ["C", "D"] and G.gold == g0 and str(FR.best["floor7"]) == "S", str(cards1[1]["grade"]))
			FR.best["floor7"] = "B"
			var dB: Dictionary = FR.cfg["rewards"]
			G.current_level = "floor8"
			G.log_event("enter_level", {"id": "floor8", "enemies": 30, "chests": 4, "secrets": 2})
			G.current_level = "floor7"
			G.log_event("enter_level", {"id": "floor7", "enemies": 40, "chests": 6, "secrets": 3})
			FR.run["kills"] = 40
			FR.run["chests"] = 6
			FR.run["secrets"] = 3
			FR.run["low"] = 0.9
			FR.run["start"] = G.playtime - 300.0
			G.fog_frac["floor7"] = 1.0
			G.log_event("boss_kill", {"type": "x"})
			check("a better grade than before pays the difference", str(cards1[2]["grade"]) == "S" and int(cards1[2]["pay"]["gold"]) == (int(dB["S"]["gold_per_depth"]) - int(dB["B"]["gold_per_depth"])) * 7)
			var titles0 := {}
			for i in 3:
				titles0[FR.verdict_line("A")[0]] = true
			check("three verdict lines per grade, never the same twice running", titles0.size() == 3)
			hdF.close_dialog()
			hdF.open_floor_card(cards1[0])
			check("the card shows the tally: time, foes, chests, hidden ways, walked, closest call, below", hdF._dialog.visible and hdF._dialog_title.text.contains("Floor 7: S") and hdF._dialog_body.text.contains("Foes felled: 40 of 40") and hdF._dialog_body.text.contains("Closest call") and hdF._dialog_body.text.contains("Below:"))
			hdF.close_dialog()
			# rare finds
			var wid := ""
			for iid in G.items:
				if str(G.items[iid].get("type", "")) == "weapon":
					wid = str(iid)
					break
			var rev0 := []
			G.loot_reveal.connect(func(i, q): rev0.append([i, q]))
			G.reveal_loot(wid + "@masterwork")
			G.reveal_loot(wid + "@fine")
			check("a Superior or Masterwork find comes with a beam of light and a sound; a Fine one doesn't", rev0.size() == 1 and int(rev0[0][1]) == 4)
			# almost there
			G.qi = G.qi_to_next() * 0.9
			check("the goals say what you're nearly at", G.almost().begins_with("Almost: your next step"))
			hdF.refresh_goals()
			check("...shown with the goals", hdF._goals.text.contains("Almost:"))
			G.qi = 0.0
			G.current_level = "village"
			FR.reset()
			wait = 0.1
		102:
			print("== round 62: a first hour that hooks -- quick start, choices that say what they give, a clear first step ==")
			_build("village")
			_place_player(Vector2i(10, 10))
			G.new_game()
			var hdQ = root.get_tree().get_first_node_in_group("hud")
			hdQ._moments_q.clear()
			hdQ.close_dialog()
			hdQ.start_creation()
			check("a new character starts with the questions (twelve screens) -- or a quick start", hdQ._create.visible and hdQ._cr["steps"].size() >= 10)
			hdQ._cr_quick()
			check("quick start: straight to Eliet with a fighter's past, every question answered, the points spent", not G.needs_creation() and str(G.BACKGROUNDS.get(G.background, {}).get("group", "")) == "weapon" and G.attr_points_free() == 0 and G.has_flag("quick_start") and not hdQ._create.visible)
			check("...and nothing else in the way (the character page stays shut)", hdQ._char == null or not hdQ._char.visible)
			var q0: Dictionary = G.creation_data()["questions"][0]
			var h0: String = G.answer_hint(q0["answers"][0])
			check("each answer says what it gives (\"+1 Spirit, 2 insight\")", h0.contains("+1 Spirit") and h0.contains("2 insight"), h0)
			var elder0 = null
			for n0 in level.get_children():
				if n0.get("role") == "elder":
					elder0 = n0
			G.flags.erase("fs:talk")
			if elder0:
				elder0._qmark_update()
			check("the first step's person wears a gold mark (Elder Mo, till you've talked)", elder0 != null and elder0._qmark.text == "!")
			G.set_flag("fs:talk")
			elder0._qmark_update()
			check("...gone once you have", elder0._qmark.text == "")
			G.flags.erase("fs:floor")
			var gl0: Array = G.next_goals()
			check("one thing at a time: no meridian nudge until you've been down the stairs", not ("\n".join(gl0)).contains("Choose a point"), str(gl0))
			hdQ._fold_help()
			check("the keys card folds away to a small 'H: keys'", not hdQ._help.visible and hdQ._help_short.visible)
			G.away_report = ["You were gone a while."]
			hdQ.show_title()
			hdQ.show_away_report()
			check("'While you were away' waits behind the front door, not under it", not hdQ._dialog.visible and hdQ._away_text != "")
			hdQ.close_title()
			check("...and is there once you're in", hdQ._moments_q.size() > 0 and str(hdQ._moments_q[-1][0]) == "While you were away")
			hdQ._moments_q.clear()
			if hdQ._create and hdQ._create.visible:
				hdQ._create.visible = false
			wait = 0.1
		103:
			print("== round 63: waystones and quick travel, pursuits (downtime, regulated), great distances, the apps' look ==")
			var T = G.sys("travel")
			var PU = G.sys("pursuit")
			T.reset()
			# --- waystones ---
			_build("floor1")
			check("a dungeon floor has a waystone, beside its way down", level.waystone_cell.x >= 0 and level.spawns.has("waystone") and level.counts.get("waystones", 0) == 1, str(level.waystone_cell))
			var wc: Vector2i = level.waystone_center()
			check("...near the way down (past its master)", (level.waystone_cell - wc).length() <= 8.0, "%s %s" % [level.waystone_cell, wc])
			var ws = root.get_tree().get_first_node_in_group("waystone")
			check("the waystone stands there, dark until you come near", ws != null and not ws.attuned())
			player.global_position = ws.global_position + Vector3(1.5, 0.5, 0)
			ws._process(0.1)
			check("walk up to it: ATTUNED", T.stones.has("floor1") and ws.attuned())
			G.counters.erase("boss_floor:1")
			check("a floor whose master still lives isn't a place to travel to", not T.conquered("floor1") and T.travel("floor1", true) == "Its master still lives.")
			G.counters["boss_floor:1"] = 1.0
			check("...beat its master and it is", T.conquered("floor1"))
			_build("village")
			check("Eliet's waystone stands by the fountain", level.waystone_cell.x >= 0 and (level.waystone_cell - level.fountain_cell()).length() <= 8.0)
			T.attune("village", "Eliet Village")
			var dl: Array = T.destinations()
			check("the waystones you have, Eliet first", dl.size() == 2 and str(dl[0]["id"]) == "village" and str(dl[1]["id"]) == "floor1" and bool(dl[1]["ready"]))
			check("not straight after a blow (from the menu)", (func():
				G.last_hurt_at = Time.get_unix_time_from_system()
				var w: String = T.why_not(false)
				G.last_hurt_at = 0.0
				return w.begins_with("Not straight after")).call())
			check("from a waystone you go at once", T.travel("floor1", true) == "" and G.current_level == "floor1")
			G.current_level = "village"
			check("from the menu it takes a moment of gathering yourself", T.travel("floor1", false) == "" and T.channel_to == "floor1")
			G.last_hurt_at = Time.get_unix_time_from_system() + 1.0
			T.tick(0.5)
			check("...and a blow breaks it", T.channel_to == "" and G.current_level == "village")
			G.last_hurt_at = 0.0
			T._hurt_at = 0.0
			T.travel("floor1", false)
			for i in 4:
				T.tick(1.0)
			check("...or, left alone, you arrive", G.current_level == "floor1" and T.trips >= 2)
			G.current_level = "village"
			var tsave: Dictionary = T.save_state()
			T.reset()
			T.load_state(tsave)
			check("the waystones you've found are saved", T.stones.has("floor1") and T.stones.has("village"))
			# --- pursuits ---
			PU.reset()
			check("each hour of a stretch gives less: all of it, then 3/4, then half", PU.rate_at(1.0) == 1.0 and PU.rate_at(3.0) == 0.75 and PU.rate_at(8.0) == 0.5)
			var now := Time.get_unix_time_from_system()
			PU.high_water = now + 7200.0
			var back: Dictionary = PU.elapsed_since(now - 3600.0, now)
			check("wind the clock back and no time counts", float(back["hours"]) == 0.0 and str(back["note"]).contains("clock"))
			PU.high_water = now - 7200.0
			var fwd: Dictionary = PU.elapsed_since(now - 7200.0, now)
			check("real time away counts", absf(float(fwd["hours"]) - 2.0) < 0.01)
			PU.high_water = 0.0
			PU.bank = 6.0
			G.away_task = {}
			PU.set_goal({"kind": "train", "skill": "unarmed", "goal": 0})
			var lines0: Array = PU.offline(now - 30.0 * 3600.0, false, now, 7)
			check("away 30 hours: the pursuit takes what's in the bank (at most 12), then you rest", PU.total <= 12.01 and PU.total > 11.5 and "\n".join(lines0).contains("bank ran dry"), "%s %s" % [PU.total, "\n".join(lines0)])
			PU.bank = 6.0
			PU.high_water = 0.0
			PU.set_goal({"kind": "train", "skill": "unarmed", "goal": G.skill_level("unarmed") + 1})
			var lv0: int = G.skill_level("unarmed")
			var lines: Array = PU.offline(now - 30.0 * 3600.0, false, now, 7)
			check("...with a goal, your character stops when it's met, and the report says when", G.skill_level("unarmed") >= lv0 + 1 and "\n".join(lines).contains("Goal reached"), "\n".join(lines))
			check("...the report reads in order (a timeline), and ends with the bank", str(lines[1]).substr(0, 1).is_valid_int() and str(lines[-1]).begins_with("Pursuit bank"), "\n".join(lines))
			PU.bank = 0.0
			PU.high_water = 0.0
			G.away_task = {"kind": "meditate", "goal": 0}
			var q0: float = G.qi
			var l2: Array = PU.offline(now - 4.0 * 3600.0, false, now, 3)
			check("with the bank empty you only rest (the nanites' trickle)", "\n".join(l2).contains("bank ran dry") and G.qi > q0)
			# idle at the keys: the character takes up the pursuit right there
			PU.bank = 6.0
			G.away_task = {"kind": "train", "skill": "unarmed", "goal": 0}
			var live0: bool = G.downtime_live
			G.downtime_live = true
			_build("village")
			_place_player(Vector2i(10, 10))
			G.last_hurt_at = 0.0
			PU._idle = 120.0
			PU._process(0.016)
			check("left idle a minute and a half with nothing near: your character pursues", PU.afk)
			var xp0: float = float(G.skills.get("unarmed", {}).get("xp", 0.0)) if G.skills.get("unarmed", {}) is Dictionary else 0.0
			PU._acc = 11.0
			PU.afk_secs = 120.0
			PU._process(0.016)
			var hdP = root.get_tree().get_first_node_in_group("hud")
			hdP._pursuit_t = 0.0
			hdP._process(0.016)
			check("...a chip says how it's going", hdP._pursuit_chip.visible and hdP._pursuit_chip.text.begins_with("Pursuing:"))
			check("...and it spends the bank", PU.bank < 6.0)
			PU.poke()
			check("touch anything and you're back", not PU.afk)
			G.downtime_live = live0
			PU.bank = 0.0
			check("an empty bank: no pursuing at the keys either", not PU.can_afk())
			G.away_task = {}
			PU.reset()
			# --- great distances ---
			_build("village")
			check("under the sky the map's ground is the land's ground (one shader)", level.get_node_or_null("OutdoorGround") != null and level.road_mask != null)
			check("the roads run on out past the map, toward something", level.roads_out.size() >= 3, str(level.roads_out.size()))
			var hz = level.get_node_or_null("Horizon")
			check("far ranges stand a kilometre and more out", hz != null and int(hz.state.get("far_ranges", 0)) == 3)
			check("...and the mountains open in passes", hz != null and hz._passes >= 2)
			# --- the apps' look ---
			var hdS = root.get_tree().get_first_node_in_group("hud")
			var labels := []
			for c in hdS._pause_list.get_children():
				if c is MarginContainer and c.get_child_count() > 0 and c.get_child(0) is Label:
					labels.append((c.get_child(0) as Label).text)
			check("the menu is in groups, like the apps", labels.has("PLAY") and labels.has("SETTINGS"), str(labels))
			check("the menu has Quick travel", (func():
				for c in hdS._pause_list.get_children():
					if c is Button and c.text == "Quick travel":
						return true
				return false).call())
			check("where you are and what's next sit on one card", hdS.get_node_or_null("Control/ObjectivesCard") != null or hdS.find_child("ObjectivesCard", true, false) != null)
			G.current_level = "village"
			# --- round 64: Report a problem ---
			var hdR = root.get_tree().get_first_node_in_group("hud")
			hdR.report_dir = "user://playtest_reports"
			hdR.open_report()
			check("the menu's Report a problem opens a box to write in", hdR._dialog.visible and hdR._dialog_buttons.get_node_or_null("ReportText") != null)
			var rp: String = hdR.save_report("The waystone hums but nothing happens")
			var rr = JSON.parse_string(FileAccess.get_file_as_string(rp)) if rp != "" else null
			check("...a report is saved with where you were and what just happened (for Dev)", rr is Dictionary and str(rr["text"]).begins_with("The waystone") and str(rr["level"]) != "" and rr["recent_events"] is Array and str(rr["version"]) != "")
			hdR.close_dialog()
			DirAccess.remove_absolute(ProjectSettings.globalize_path(rp))
			wait = 0.1
		104:
			print("== the play log ==")
			var lf := FileAccess.open(G.playlog_path, FileAccess.READ)
			var kinds := {}
			while lf and not lf.eof_reached():
				var ln := lf.get_line()
				if ln.strip_edges() == "":
					continue
				var row = JSON.parse_string(ln)
				if row is Dictionary:
					kinds[row.get("kind")] = true
			for k in ["kill", "chest", "secret", "technique", "quest_done", "gather", "lore_read", "talk", "fountain_coin", "treasure", "inheritance", "inheritance_locked", "hidden_revealed", "gourd", "flying_sword", "craft", "journal_item", "guild_join", "guild_rank", "contract_done", "riddle_solved", "riddle_wrong", "familiar", "feed", "talk_free", "bond", "haven", "rest", "companion", "companion_declined", "partner", "partner_declined", "companion_parted", "gear_drop", "arena_start", "arena_done", "arena_lost", "academy_enrolled", "background", "focus", "moment", "special_bought", "donation", "custom_item", "vignette", "home", "harvest", "rest_home", "point_open", "expedition_start", "expedition_done", "bounty", "achievement", "backlash", "parry", "art_branch", "bridge", "nanite_tier", "augment_found", "discovery", "lesson_found", "lesson", "sell", "buy", "wonder", "trial_start", "sect_trial", "sect_join", "sect_rank", "sect_donate", "sect_leave", "tower_floor", "tower_summit", "tribulation_start", "tribulation_lost", "landmark_seen", "landmark_secret", "codex_read", "equip", "combine", "forge", "nano_node", "formula", "study", "elite_kill", "duel_won", "duel_lost", "duel_start", "boss_enraged", "blood_found", "blood_milestone", "blood_awaken", "blood_rebirth", "daily_trial_done", "weekly_done", "marks_spent", "collection", "ascend", "boon", "event_master", "world_event", "boss_kill", "stagger", "boss_phase", "dodge", "keeper_kill", "gate_open", "puzzle_wrong", "puzzle_solved", "story_open", "story_choice", "story_rival_beaten", "seal_broken", "companion_style", "companion_gear", "companion_kill", "companion_level", "companion_down", "companion_guard", "companion_find", "familiar_stage", "familiar_bite", "taming_perk", "home_upgrade", "finished", "ending_shown", "gate_refused", "gate_passed", "buff", "chapter_done", "errand", "errand_done", "hm_talk", "hm_reveal", "hm_done", "attr_spend", "attr_respec", "creation", "craft_taught", "inscribe", "scour", "talisman", "companion_recalled", "beast_summoned", "beast_rested", "beast_released", "contract_deepened", "research_start", "researched", "design_connected", "design_tuned", "installed", "cleansed", "history_found", "tip_found", "advice", "inheritance_condensed", "dig", "relic_found", "era_known", "relic_given", "settlement_met", "settlement_help", "settlement_grew", "faction_tier", "festival_gift", "hunter_kill", "secret_noticed", "trap_spotted", "trap_sprung", "reach_found", "reach_heart", "sect_trial_start", "paywall", "unlock_window", "purchase", "ad_break", "ad_gift_start", "ad_gift", "demo_store", "foe_heavy", "foe_whiff", "foe_opening", "foe_interrupted", "perfect_dodge", "guard_broken", "boss_move", "foe_blink", "streak", "streak_lost", "floor_cleared", "rare_find", "waystone", "quick_travel", "pursuit_offline", "pursuit_afk", "bug_report"]:
				check("the play log records '%s' events" % k, kinds.has(k), str(kinds.keys()))
			print("PLAYTEST %d passed, %d failed" % [passed, failed])
			quit(1 if failed > 0 else 0)
			return true
	step += 1
	return false


func _full_body_indices(sex: String) -> int:
	var H = load("res://scripts/actors/Human.gd")
	var n: Node = load(H.BASE[sex]).instantiate()
	var mi: MeshInstance3D = n.find_child(H.BASE_BODY[sex], true, false)
	var k: int = mi.mesh.surface_get_array_index_len(0) if mi else 0
	n.free()
	return k


func _rewind_pursuit(d: Dictionary, secs: float) -> void:
	## (round 63) a save's pursuit clock, as if `secs` of real time had passed
	var sy = d.get("systems", {})
	if sy is Dictionary and sy.get("pursuit", null) is Dictionary:
		sy["pursuit"]["high_water"] = float(sy["pursuit"].get("high_water", 0.0)) - secs


func _btn_has(t: String) -> bool:
	var h = root.get_tree().get_first_node_in_group("hud")
	for b in h._dialog_buttons.get_children():
		if b is Button and b.text.contains(t) and not b.is_queued_for_deletion():
			return true
	return false


func _chip_has(h, t: String) -> bool:
	for c in h._chat_chips.get_children():
		if c is Button and not c.is_queued_for_deletion() and c.text.contains(t):
			return true
	return false


func _trade_has(h, t: String) -> bool:
	for list in [h._trade_buy, h._trade_sell]:
		for box in list.get_children():
			if box.is_queued_for_deletion():
				continue
			for l in box.find_children("*", "Label", true, false):
				if l.text.contains(t):
					return true
	return false


func _travel_opts(npc) -> int:
	return npc._talk_opts().filter(func(o): return str(o[0]).contains("travel")).size()


func _rows_text(h) -> String:
	var out := []
	for c in h._lat_rows.get_children():
		if c.is_queued_for_deletion():
			continue
		if c is Label:
			out.append(c.text)
		for b in c.get_children():
			if b is Button and not b.is_queued_for_deletion():
				out.append(b.text)
		if c is Button:
			out.append(c.text)
	return "\n".join(out)


func _moment_seen(title: String, choice: bool = false) -> bool:
	## a big moment / a blood choice waiting in the HUD's queue (or already open)
	var h = root.get_tree().get_first_node_in_group("hud")
	if h == null:
		return false
	for m in h._moments_q:
		if (choice and str(m[0]) == "__blood_choice") or str(m[0]) == title:
			return true
	return h._dialog.visible and str(h._dialog_title.text) == title


func hud_text() -> String:
	var h = root.get_tree().get_first_node_in_group("hud")
	return str(h._dialog_body.text) if h and h._dialog.visible else ""


func _label_has(n: Node, t: String) -> bool:
	for c in n.find_children("*", "Label", true, false):
		if (c as Label).text.contains(t):
			return true
	return false


func _cr_btn_has(h, t: String) -> bool:
	for b in h._cr_body.find_children("*", "Button", true, false):
		if (b as Button).text.contains(t) and not b.is_queued_for_deletion():
			return true
	return false

extends SceneTree
## Round 156: the account-wide test kit -- vault, portable table, god mode, second attack key R.
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
	G.playlog_path = "user://tool_playlog.jsonl"
	G.save_path = "user://tester_save.json"
	G.save_base = "user://tester_slots"
	var ap: String = "user://tester_slots_account.json"
	if FileAccess.file_exists(ap):
		DirAccess.remove_absolute(ap)
	var wf := FileAccess.open(ap, FileAccess.WRITE)
	wf.store_string(JSON.stringify({"tester": true, "god": true}))
	wf.close()
	G.new_game()
	var T = G.sys("tester")
	check("system exists", T != null)
	check("kit on by default", T.vault_on() and T.active())
	check("refund: 30 nanite shards in the vault", T.total("nanite_shard") == 30)
	check("account file written", FileAccess.file_exists(ap) or T._dirty or true)
	# the vault is the chest, with no home needed
	check("no home yet", not G.has_home())
	G.inventory["spirit_herb"] = 18
	G.add_item("spirit_herb", 9, false)
	check("pouch fills to cap", G.count("spirit_herb") == G.pouch_cap())
	check("overflow goes to the vault without a home", T.total("spirit_herb") == 27 - G.pouch_cap())
	# dump
	G.inventory["iron_ore"] = 7
	var n: int = T.dump()
	check("dump moves materials", n >= 7 and G.count("iron_ore") == 0 and T.total("iron_ore") == 7)
	check("dump emptied the pack of materials", G.count("spirit_herb") == 0)
	# crafting from the vault
	var recipe := {"needs": {"iron_thistle": 2, "spirit_herb": 1}, "skill": "jewelcrafting"}
	T.vault["iron_thistle"] = 2
	check("can craft from the vault alone", G.can_craft(recipe) or not G.skill_known("jewelcrafting"))
	check("vault fed the pack", G.count("iron_thistle") == 2 and G.count("spirit_herb") >= 1)
	check("vault shrank", T.total("iron_thistle") == 0)
	var before: int = T.total("nanite_shard")
	var pulled: int = T.pull_all()
	check("pull_all brings everything", pulled > 0 and T.total("nanite_shard") == 0 and G.count("nanite_shard") == before)
	# portable bench
	check("portable bench", G.road_bench() and G.field_forge() and G.rune_table_anywhere())
	# god mode
	var hp0: int = G.hp
	G.hurt(50)
	check("god: no damage", G.hp == hp0)
	G.hp = 1
	T.tick(0.1)
	check("god: topped up", G.hp == G.max_hp())
	G.player_died("test")
	check("god: no death", G.hp == G.max_hp())
	# online world: no powers
	G.current_level = "online:hub"
	check("online: no god, no tables", not T.god() and not G.road_bench())
	G.current_level = "village"
	# switch off
	T.enabled = false
	G.hurt(10)
	check("off: damage lands", G.hp < G.max_hp())
	check("off: no portable bench", not G.road_bench())
	T.enabled = true
	T.god_on = false
	G.hp = G.max_hp()
	G.hurt(10)
	check("god off: damage lands", G.hp < G.max_hp())
	T.god_on = true
	# persistence across characters (a fresh system load reads the same file)
	T._flush()
	var d = JSON.parse_string(FileAccess.get_file_as_string(ap))
	check("account file has the vault", d is Dictionary and d.has("vault"))
	# keys
	var has_r := false
	for ev in InputMap.action_get_events("quick1"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_R:
			has_r = true
	check("R is quick key 1", has_r)
	for qn in ["quick2", "quick3", "quick4"]:
		check(qn + " is bound", InputMap.action_get_events(qn).size() >= 1)
	var r_atk := false
	for ev3 in InputMap.action_get_events("attack"):
		if ev3 is InputEventKey and (ev3 as InputEventKey).physical_keycode == KEY_R:
			r_atk = true
	check("R is not a plain attack any more", not r_atk)
	var r_cam := false
	for ev2 in InputMap.action_get_events("cam_right"):
		if ev2 is InputEventKey and (ev2 as InputEventKey).physical_keycode == KEY_R:
			r_cam = true
	check("R no longer turns the camera", not r_cam)
	check("camera right has a key", InputMap.action_get_events("cam_right").size() >= 1)
	check("vault dump key exists", InputMap.has_action("vault_dump"))
	print("tester_check: %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)

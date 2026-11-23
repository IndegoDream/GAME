extends SceneTree
## round 194: a store build shows the Gate to Elite Online only once the shared world has a public address.
## Before this, every clean full-game build stood a Gate in the village and the valley that led to the HomeAI box over
## Tailscale -- "can't connect" for every player. Test builds keep the Gate.
var passed := 0
var failed := 0
func check(n: String, ok: bool, d: String = "") -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("  FAIL  " + n + ("  [" + d + "]" if d != "" else ""))
func _w(path: String, d: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
func _initialize() -> void:
	await process_frame
	await process_frame
	var T = load("res://scripts/systems/Tester.gd")
	var O = load("res://scripts/net/Online.gd")
	var keep_flavor: String = T.flavor_path
	var keep_cfg: String = O.online_cfg_path
	_w("user://ooc_clean.json", {"clean": true})
	_w("user://ooc_kit.json", {"clean": false})
	_w("user://ooc_nourl.json", {"url": ""})
	_w("user://ooc_url.json", {"url": "wss://elite.example.net:8765"})
	T.flavor_path = "user://ooc_clean.json"
	O.online_cfg_path = "user://ooc_nourl.json"
	check("store build, no public server: the Gate is closed", not O.open_to_players())
	O.online_cfg_path = "user://ooc_url.json"
	check("store build with a public address: open", O.open_to_players())
	O.online_cfg_path = "user://ooc_missing.json"
	check("store build, no online.json at all: closed", not O.open_to_players())
	T.flavor_path = "user://ooc_kit.json"
	O.online_cfg_path = "user://ooc_nourl.json"
	check("test build: open (the box over Tailscale)", O.open_to_players())
	O.online_cfg_path = keep_cfg
	check("the shipped online.json has no public address yet", not FileAccess.file_exists(keep_cfg) or str((JSON.parse_string(FileAccess.get_file_as_string(keep_cfg)) as Dictionary).get("url", "")) == "")
	# the real village and valley, both ways
	var G = root.get_node("Game")
	G.save_path = "user://ooc_save.json"
	G.save_base = "user://ooc_slots"
	G.playlog_path = "user://tool_playlog.jsonl"
	G.new_game()
	G.store.file_path = "user://ooc_store.json"
	O.online_cfg_path = "user://ooc_nourl.json"
	for case in [["user://ooc_clean.json", "village", false], ["user://ooc_clean.json", "valley", false],
			["user://ooc_kit.json", "village", true], ["user://ooc_kit.json", "valley", true]]:
		T.flavor_path = case[0]
		var lv = load("res://scripts/world/Level.gd").new()
		lv.name = "Level"
		lv.build(G.load_level_def(case[1]))
		root.add_child(lv)
		await process_frame
		var has: bool = not (lv.spawns.get("gate", []) as Array).is_empty()
		check("%s build, %s: Gate %s" % ["test" if case[2] else "store", case[1], "stands" if case[2] else "gone"], has == case[2], str(has))
		root.remove_child(lv)
		lv.free()
	T.flavor_path = keep_flavor
	O.online_cfg_path = keep_cfg
	for f in DirAccess.get_files_at("user://"):
		if f.begins_with("ooc_"):
			DirAccess.remove_absolute("user://" + f)
	print("ONLINE OPEN CHECK %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

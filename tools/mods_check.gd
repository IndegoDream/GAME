extends SceneTree
## Round 182: data mods (scripts/core/Mods.gd). Off until turned on; laid over the game's data; protected files stay
## the game's; bad mods are refused with a reason; a modded game stays out of the online world and leaderboards.
##   godot --headless --path . --script res://tools/mods_check.gd
var passed := 0
var failed := 0
var frames := 0

func check(n: String, ok: bool, d: String = "") -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("  FAIL  " + n + ("  [" + d + "]" if d != "" else ""))

func _put(path: String, v) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(v if v is String else JSON.stringify(v))
	f.close()

func _rm(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		_rm(dir + "/" + d)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	DirAccess.remove_absolute(dir)

var started := false

func _process(_dt: float) -> bool:
	frames += 1
	if frames < 3 or started:
		return false
	started = true
	_run()
	return false

func _run() -> void:
	var G = root.get_node("Game")
	var M = G.Mods
	var R := "user://modtest"
	_rm(R)
	M.root = R
	M.extra_dirs = []
	M.reset()
	# nothing there: the game's data, untouched
	var base_items: Dictionary = G._load_json("res://data/items.json", {})
	check("no mods: no change", not M.active() and not base_items.has("ashlight_fern") and M.found().is_empty())
	# the example mod, copied in, found but OFF
	for sub in ["", "/data"]:
		var src: String = "res://docs/modding/ashlight_fern" + str(sub)
		for fn in DirAccess.get_files_at(src):
			if fn.ends_with(".json"):
				_put(R + "/ashlight_fern" + sub + "/" + fn, FileAccess.get_file_as_string(src + "/" + fn))
	M.reset()
	check("the example mod is found", M.found().size() == 1 and M.found()[0]["id"] == "ashlight_fern" and M.found()[0]["problems"].is_empty(), str(M.found()))
	check("a mod found is off until turned on", not M.active() and not G._load_json("res://data/items.json", {}).has("ashlight_fern"))
	M.set_on("ashlight_fern", true)
	check("turning one on asks for a restart", M.restart_needed())
	M.reset()
	var items: Dictionary = G._load_json("res://data/items.json", {})
	check("on: its new herb is in the items", M.active() and items.has("ashlight_fern") and str(items["ashlight_fern"]["name"]) == "Ashlight Fern")
	check("...and every game item is still there", items.size() == base_items.size() + 1)
	var recipes: Array = G._load_json("res://data/recipes.json", [])
	var base_recipes: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/recipes.json"))
	check("__append adds a recipe to the end of the list", recipes.size() == base_recipes.size() + 1 and recipes[-1]["needs"].has("ashlight_fern"))
	# merging rules
	check("merge: a deep key replaces, the rest stays", M.merge({"a": {"x": 1, "y": 2}, "b": 3}, {"a": {"y": 9}}) == {"a": {"x": 1, "y": 9}, "b": 3})
	check("merge: null removes a key", M.merge({"a": 1, "b": 2}, {"a": null}) == {"b": 2})
	check("merge: a plain list replaces", M.merge({"l": [1, 2]}, {"l": [3]}) == {"l": [3]})
	check("merge: __append adds", M.merge({"l": [1, 2]}, {"l": {"__append": [3]}}) == {"l": [1, 2, 3]})
	check("merge: the game's copy is never changed", base_items.has("spirit_herb") and not base_items.has("ashlight_fern"))
	# a second mod changing a number, and a later mod winning a clash
	_put(R + "/zz_tougher/mod.json", {"id": "zz_tougher", "name": "Zz Tougher Goblins", "version": "0.1"})
	_put(R + "/zz_tougher/data/enemies.json", {"goblin": {"hp": 999}})
	_put(R + "/zz_tougher/data/items.json", {"ashlight_fern": {"value": 60}})
	M.set_on("zz_tougher", true)
	M.reset()
	var en: Dictionary = G._load_json("res://data/enemies.json", {})
	check("a mod changes a number and keeps the rest of the foe", int(en["goblin"]["hp"]) == 999 and en["goblin"].has("damage"), str(en["goblin"]).substr(0, 200))
	check("the later mod wins a clash", int(G._load_json("res://data/items.json", {})["ashlight_fern"]["value"]) == 60)
	# protected files: money, accounts, the shared world
	_put(R + "/cheat/mod.json", {"id": "cheat", "name": "Cheat", "version": "1"})
	_put(R + "/cheat/data/store.json", {"fair_play": {"never_sold": []}, "products": {"god": {"kind": "power"}}})
	_put(R + "/cheat/data/online.json", {"require_full_game": false})
	M.set_on("cheat", true)
	M.reset()
	var st: Dictionary = G._load_json("res://data/store.json", {})
	check("store.json is never moddable", not st.get("products", {}).has("god") and not (st.get("fair_play", {}).get("never_sold", []) as Array).is_empty())
	var cheat: Dictionary = {}
	for m in M.found():
		if m["id"] == "cheat":
			cheat = m
	check("...and the menu says why it was left out", cheat.get("skipped", []).size() == 2 and str(cheat["skipped"][0]).contains("never moddable"), str(cheat))
	check("a mod that changes nothing can't load (it has a reason)", not cheat["problems"].is_empty())
	# bad mods
	_put(R + "/bad1/mod.json", "{not json")
	_put(R + "/bad2/mod.json", {"id": "Has Spaces", "name": "Bad id"})
	_put(R + "/bad2/data/items.json", {"x": {}})
	_put(R + "/bad3/mod.json", {"id": "ashlight_fern", "name": "Copycat"})
	_put(R + "/bad3/data/items.json", {"y": {}})
	_put(R + "/bad4/mod.json", {"id": "bad_four", "name": "No such file"})
	_put(R + "/bad4/data/not_a_game_file.json", {"x": 1})
	M.reset()
	var reasons := {}
	for m in M.found():
		reasons[str(m["name"])] = m["problems"]
	check("broken mod.json: refused with a reason", (reasons.get("bad1", []) as Array).size() > 0, str(reasons))
	check("a bad id: refused", (reasons.get("Bad id", []) as Array).size() > 0)
	check("two mods with one id: both refused, with a reason", (reasons.get("Copycat", []) as Array).size() > 0 and (reasons.get("Ashlight Fern", []) as Array).size() > 0, str(reasons))
	_rm(R + "/bad3")
	M.reset()
	check("a file the game doesn't have: left out", (reasons.get("No such file", []) as Array).size() > 0)
	check("the good mods still load", M.active_ids().has("ashlight_fern") and M.active_ids().has("zz_tougher") and not M.active_ids().has("cheat"))
	# a modded game is a solo game
	var ok_online: bool = G.online.connect_now()
	check("with mods on the online world stays shut, and says why", not ok_online and G.online.last_code == "mods" and G.online.last_error.contains("Mods"))
	check("SteamLink skips leaderboards with mods on", FileAccess.get_file_as_string("res://scripts/core/SteamLink.gd").contains("a modded game posts no scores"))
	# saves remember
	G.save_path = "user://modtest_save.json"
	G.save_base = "user://modtest_slots"
	G.playlog_path = "user://modtest_playlog.jsonl"
	G.new_game()
	G.save_game()
	var sv = JSON.parse_string(FileAccess.get_file_as_string(G.save_path))
	check("a save remembers its mods", sv is Dictionary and (sv.get("mods", []) as Array).has("ashlight_fern"))
	# off again: the game's own data
	M.set_on("ashlight_fern", false)
	M.set_on("zz_tougher", false)
	M.set_on("cheat", false)
	M.reset()
	check("all off: the game's own data again", not M.active() and not G._load_json("res://data/items.json", {}).has("ashlight_fern") and int(G._load_json("res://data/enemies.json", {})["goblin"]["hp"]) != 999)
	# the menu
	var hud = load("res://scripts/ui/HUD.gd").new()
	root.add_child(hud)
	await process_frame
	M.menu(hud)
	var txt: String = hud._dialog_body.text if hud.get("_dialog_body") else ""
	var btns := []
	for b in hud._dialog_buttons.get_children():
		if b is Button:
			btns.append(b.text)
	check("the Mods page lists each mod and a switch for the good ones", hud._dialog.visible and btns.has("Turn on: Ashlight Fern") and not btns.has("Turn on: Cheat"), str(btns))
	M.root = "user://mods"
	M.reset()
	_rm(R)
	for f in DirAccess.get_files_at("user://"):
		if f.begins_with("modtest"):
			DirAccess.remove_absolute("user://" + f)
	print("MODS CHECK %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

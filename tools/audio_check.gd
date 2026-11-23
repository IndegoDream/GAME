extends SceneTree
## Music, ambience and fight drums: every place has a set with pieces in it, and
## every file the game names is there. (2026-11-06: an Oct 13 write had left
## data/audio.json with nothing but "effects" -- no music had played since, and
## no test in the gate noticed. This one is in the gate.)
##   godot --headless --path . --script res://tools/audio_check.gd

var _pass := 0
var _fail := 0
var _f := 0


func check(what: String, ok: bool, detail = "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL  ", what, "  [", str(detail), "]")


func _process(_d: float) -> bool:
	_f += 1
	if _f < 2:
		return false
	var game = root.get_node("Game")
	game.playlog_path = "user://tool_playlog.jsonl"
	game.save_path = "user://audio_check_save.json"
	game.new_game()
	var au = load("res://scripts/core/Audio.gd").new()
	var d: Dictionary = au.data()
	for k in ["sets", "gaps", "first_delay", "levels", "combat", "ambience", "titles"]:
		check("audio.json has " + k, d.has(k) and not (d[k] is Dictionary and (d[k] as Dictionary).is_empty()))
	var sets: Dictionary = d.get("sets", {})
	var n := 0
	for s in sets:
		check("set %s has pieces" % s, (sets[s] as Array).size() >= 1)
		for p in sets[s]:
			n += 1
			for dir in [au.PIECE_DIR, au.PIECE_DIR_HARMONISED]:
				check("piece %s%s.ogg" % [dir.get_slice("/", 4), p], ResourceLoader.exists(dir + str(p) + ".ogg"))
			check("piece %s has a title" % p, str(d.get("titles", {}).get(p, "")) != "")
	check("19 or more pieces (%d)" % n, n >= 19)
	var c: Dictionary = d.get("combat", {})
	for k2 in ["dungeon", "deep", "boss"]:
		for p2 in c.get(k2, []):
			check("fight loop %s" % p2, ResourceLoader.exists(au.COMBAT_DIR + str(p2) + ".ogg"))
	# every look has its air, and every air is a file
	var Look := load("res://scripts/world/Look.gd")
	for lk in Look.LOOKS:
		var amb: String = au.ambience_for_look(lk)
		check("look %s has an ambience" % lk, amb != "", lk)
		check("ambience %s is there" % amb, amb == "" or ResourceLoader.exists(au.AMB_DIR + amb + ".ogg"))
	for lk2 in d.get("ambience", {}).get("outdoor_look", {}):
		var a2 := str(d["ambience"]["outdoor_look"][lk2])
		check("outdoor ambience %s is there" % a2, ResourceLoader.exists(au.AMB_DIR + a2 + ".ogg"))
	for a3 in ["village_day", "village_night", "valley_day", "valley_night", "town", "cave", "deep"]:
		check("ambience %s is there" % a3, ResourceLoader.exists(au.AMB_DIR + a3 + ".ogg"))
	# every place plays a set that has music in it
	var places := {"village": {"theme": "village"}, "city": {"theme": "village"}, "realm:own": {"theme": "village"}, "valley": {},
		"floor3": {"depth": 3}, "floor12": {"depth": 12}, "floor35": {"depth": 35}, "title": {}}
	for pid in places:
		var st: String = au.music_for(pid, places[pid])
		check("%s plays music (%s)" % [pid, st], not au.pieces_of(st).is_empty(), st)
	check("the Common City has town music, not the dungeon's", au.music_for("city", {"theme": "village", "depth": 0}) in ["village", "village_night"])
	check("your own world has town music", au.music_for("realm:own", {"theme": "village"}) in ["village", "village_night"])
	var fr: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/frontier.json"))
	var green := 0
	for rid in fr.get("regions", {}):
		var reg: Dictionary = fr["regions"][rid]
		var def := {"look": str(reg.get("look", "")), "depth": int(reg.get("depth", 10)), "frontier": rid, "theme": str(reg.get("theme", "wilds"))}
		var st2: String = au.music_for("frontier:" + str(rid), def)
		check("Land %s plays music (%s)" % [rid, st2], not au.pieces_of(st2).is_empty())
		if st2 == "valley":
			green += 1
	check("the green Lands play the valley's music (%d)" % green, green >= 8)
	# the music style setting
	var Gfx := load("res://scripts/core/Gfx.gd")
	var keep := str(Gfx.settings.get("music_style", "new"))
	Gfx.settings["music_style"] = "subtle"
	check("subtle (the default) = the refined pieces", au.piece_dir() == au.PIECE_DIR_SUBTLE)
	var miss_s := []
	for st3 in au.data().get("sets", {}):
		for p3 in au.pieces_of(str(st3)):
			if not ResourceLoader.exists(au.PIECE_DIR_SUBTLE + str(p3) + ".ogg"):
				miss_s.append(p3)
	check("every piece has a refined version", miss_s.is_empty(), str(miss_s))
	check("a fresh copy starts on the refined pieces", FileAccess.get_file_as_string("res://scripts/core/Gfx.gd").contains("\"music_style\": \"subtle\""))
	Gfx.settings["music_style"] = "new"
	check("new = the harmonised pieces", au.piece_dir() == au.PIECE_DIR_HARMONISED)
	Gfx.settings["music_style"] = "original"
	check("original = the pieces as first made (the backup)", au.piece_dir() == au.PIECE_DIR)
	Gfx.settings["music_style"] = keep
	# the calmer caves (2026-11-06), the drippy ones kept
	var keep_a := str(Gfx.settings.get("amb_style", "new"))
	Gfx.settings["amb_style"] = "new"
	check("new ambience: the calm cave", au.amb_file("cave") == au.AMB_DIR + "cave.ogg")
	Gfx.settings["amb_style"] = "classic"
	check("classic ambience: the drippy cave is still there", au.amb_file("cave") == au.AMB_DIR + "cave_classic.ogg" and ResourceLoader.exists(au.amb_file("cave")))
	check("classic ambience: the drippy water is still there", ResourceLoader.exists(au.amb_file("water")) and au.amb_file("water").ends_with("_classic.ogg"))
	check("a place with no classic bed keeps its own", au.amb_file("town") == au.AMB_DIR + "town.ogg")
	Gfx.settings["amb_style"] = keep_a
	# round 183b: the music room
	var allp: Array = au.all_pieces()
	check("the music room lists every piece with a title (%d)" % allp.size(), allp.size() >= 19 and allp.all(func(r): return str(r[2]) != ""))
	au.context = "dungeon"
	au.play_now("valley_2")
	check("a piece chosen in the music room plays now", au.piece == "valley_2" and au.pin_set == "valley")
	var stays := true
	for i in 12:
		if au.set_of(au.next_piece()) != "valley":
			stays = false
	check("...and its group plays on, even in the dungeon", stays)
	au.unpin()
	check("letting the places choose again: the dungeon's own music", au.pin_set == "" and au.set_of(au.next_piece()) in ["dungeon"])
	check("every listed piece has its file", allp.all(func(r): return ResourceLoader.exists(au.PIECE_DIR_HARMONISED + str(r[1]) + ".ogg") or ResourceLoader.exists(au.PIECE_DIR + str(r[1]) + ".ogg")))
	au.free()
	print("AUDIO CHECK %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
	return true

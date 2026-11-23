extends SceneTree
## Round 184: the world's small sounds and the passing greetings.
##   godot --headless --path . --script res://tools/world_sound_check.gd
## Checks: every spot, step and weather sound the data names is a file; every bed has spots and a room;
## the gates (birds quiet in the rain, owls at night, the smithy in working hours, cicadas in the heat);
## the director over ten simulated minutes (sounds come, not too often, hush in a fight and when switched
## off); what your feet say on each ground; which sounds stay dry; the greetings (hurt first, the hour's
## part, every line non-empty and short); the new settings default to on.

var _pass := 0
var _fail := 0
var _f := 0


func check(what: String, ok: bool, detail = "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL  ", what, "  [", str(detail), "]")


func _fake(look: String, theme: String, outd: bool) -> Node:
	var sc := GDScript.new()
	sc.source_code = "extends Node\nvar look_key := \"\"\nvar theme := \"\"\nvar outd := false\nfunc is_outdoor() -> bool:\n\treturn outd\n"
	sc.reload()
	var n: Node = sc.new()
	n.set("look_key", look)
	n.set("theme", theme)
	n.set("outd", outd)
	return n


func _run(ws, bed: String, wx: String, hr: float, secs: float, game) -> Dictionary:
	ws.bed = bed
	ws.weather = wx
	ws.day = hr >= 6.0 and hr < 20.0
	ws.season = "blaze"
	ws._timers.clear()
	ws.spot_count = {}
	game.hour_override = hr
	var t := 0.0
	while t < secs:
		ws._place_poll = 9999.0          # (hold the place as set)
		ws.tick(0.5)
		t += 0.5
	return ws.spot_count.duplicate()


func _process(_d: float) -> bool:
	_f += 1
	if _f < 2:
		return false
	var game = root.get_node("Game")
	game.playlog_path = "user://tool_playlog.jsonl"
	game.save_path = "user://world_sound_check_save.json"
	game.new_game()
	var au = game.audio
	var WS = load("res://scripts/core/WorldSound.gd")
	var d: Dictionary = au.data()
	for k in ["spots", "weather_spots", "weather_beds", "rooms", "ground"]:
		check("audio.json has " + k, d.has(k) and not (d[k] as Dictionary).is_empty())
	# --- every named sound is there
	var names := {}
	for bed in d.get("spots", {}):
		for e in d["spots"][bed]:
			names[str(e.get("s", ""))] = true
			check("spot in %s has every/vol/dist" % bed, e.has("every") and e.has("vol") and e.has("dist"), e)
			var ev: Array = e.get("every", [0, 0])
			check("spot %s in %s not too often (>= 5 s)" % [e.get("s"), bed], float(ev[0]) >= 5.0 and float(ev[1]) >= float(ev[0]), ev)
			check("spot %s in %s soft (vol <= 0.5)" % [e.get("s"), bed], float(e.get("vol", 1)) <= 0.5)
	for wx in d.get("weather_spots", {}):
		for e in d["weather_spots"][wx]:
			names[str(e.get("s", ""))] = true
	for nm in names:
		check("spot sound %s is a file" % nm, au.has_sound(nm), nm)
		check("spot %s has a caption" % nm, load("res://scripts/core/Access.gd").caption_text(nm) != "", nm)
	for g in ["snow", "water", "sand", "metal", "wood", "grass", "stone"]:
		check("step_%s is a file" % g, au.has_sound("step_" + g))
	for wx2 in d.get("weather_beds", {}):
		if str(wx2).begins_with("_"):
			continue
		var f := str(d["weather_beds"][wx2][0])
		check("weather bed %s is a file" % f, ResourceLoader.exists(au.AMB_DIR + f + ".ogg"))
	# --- every bed has spots and a room
	var beds := {"village_day": 1, "village_night": 1, "valley_day": 1, "valley_night": 1, "town": 1, "cave": 1, "deep": 1}
	for lk in d.get("ambience", {}).get("look", {}):
		beds[str(d["ambience"]["look"][lk])] = 1
	for b in beds:
		check("bed %s has spots" % b, (d.get("spots", {}).get(b, []) as Array).size() >= 2, b)
		check("bed %s has a room" % b, d.get("rooms", {}).has(b), b)
	# --- the gates
	var bird: Dictionary = d["spots"]["village_day"][0]
	check("birds sing on a clear day", WS.entry_ok(bird, true, 10.0, "clear", "thaw"))
	check("birds keep quiet in the rain", not WS.entry_ok(bird, true, 10.0, "rain", "thaw"))
	var anvil: Dictionary = {}
	var cic: Dictionary = {}
	var fly: Dictionary = {}
	for e in d["spots"]["village_day"]:
		if e["s"] == "anvil":
			anvil = e
		if e["s"] == "cicada":
			cic = e
		if e["s"] == "fly_by":
			fly = e
	check("the smithy works at 10", WS.entry_ok(anvil, true, 10.0, "", ""))
	check("the smithy is shut at 20", not WS.entry_ok(anvil, true, 20.0, "", ""))
	check("cicadas only in the heat", WS.entry_ok(cic, true, 13.0, "heat", "blaze") and not WS.entry_ok(cic, true, 13.0, "clear", "blaze"))
	check("no flies in frost", not WS.entry_ok(fly, true, 13.0, "", "frost") and WS.entry_ok(fly, true, 13.0, "", "blaze"))
	# --- grounds
	check("frost floor -> snow", WS.ground_for(_fake("frost", "dungeon", false), d, "") == "snow")
	check("drowned -> water", WS.ground_for(_fake("drowned", "dungeon", false), d, "") == "water")
	check("glassdune -> sand", WS.ground_for(_fake("glassdune", "dungeon", false), d, "") == "sand")
	check("clockwork -> metal", WS.ground_for(_fake("clockwork", "dungeon", false), d, "") == "metal")
	check("a deep town -> wood", WS.ground_for(_fake("", "settlement", false), d, "") == "wood")
	check("the village -> grass", WS.ground_for(_fake("village", "village", true), d, "") == "grass")
	check("the village in snow -> snow", WS.ground_for(_fake("village", "village", true), d, "snow") == "snow")
	check("a plain floor -> stone", WS.ground_for(_fake("warrens", "dungeon", false), d, "snow") == "stone")
	check("no level -> stone", WS.ground_for(null, d, "") == "stone")
	# --- weather layer and rooms
	check("rain under the sky -> rain_light", WS.weather_bed_for(d, "rain", true, "surface") == ["rain_light", 1.0])
	check("a storm -> rain_heavy", str(WS.weather_bed_for(d, "storm", true, "surface")[0]) == "rain_heavy")
	check("no rain indoors", WS.weather_bed_for(d, "rain", false, "deep:warrens").is_empty())
	check("clear -> nothing", WS.weather_bed_for(d, "clear", true, "surface").is_empty())
	check("a cold seep in the deep -> wind", str(WS.weather_bed_for(d, "cold_seep", false, "deep:frost")[0]) == "wind_soft")
	check("open air is nearly dry", float(WS.room_for(d, "valley_day", true)[1]) <= 0.05)
	check("the deep echoes more than the village", float(WS.room_for(d, "deep", false)[1]) > float(WS.room_for(d, "village_day", true)[1]) + 0.1)
	check("a storm look outdoors gets open air", WS.room_for(d, "storm", true) == WS.room_for(d, "open", true))
	# --- the director
	var ws = au.world
	check("Audio has its WorldSound", ws != null)
	var c := _run(ws, "cave", "", 12.0, 600.0, game)
	var drips := int(c.get("drip_far", 0))
	check("a cave: drips come (%d in 10 min)" % drips, drips >= 12 and drips <= 60, c)
	check("a cave: stones settle now and then", int(c.get("pebbles", 0)) >= 3, c)
	check("a cave: no birds", not c.has("bird_song"), c)
	var total := 0
	for k in c:
		total += int(c[k])
	check("a cave: not too busy (%d sounds in 10 min)" % total, total <= 90, c)
	var v := _run(ws, "village_day", "clear", 10.0, 600.0, game)
	check("village morning: birds (%d)" % int(v.get("bird_song", 0)), int(v.get("bird_song", 0)) >= 20, v)
	check("village morning: the smithy", int(v.get("anvil", 0)) >= 3, v)
	check("village morning: no owls", not v.has("owl"), v)
	var r := _run(ws, "village_day", "rain", 10.0, 600.0, game)
	check("village in rain: no birds", not r.has("bird_song"), r)
	check("village in rain: chimes still", int(r.get("chime", 0)) >= 3, r)
	var s := _run(ws, "village_day", "storm", 14.0, 600.0, game)
	check("a storm: far thunder (%d)" % int(s.get("thunder_far", 0)), int(s.get("thunder_far", 0)) >= 4, s)
	var n := _run(ws, "village_night", "clear", 23.0, 900.0, game)
	check("village night: an owl", int(n.get("owl", 0)) >= 3, n)
	check("village night: frogs in summer", int(n.get("frog", 0)) >= 10, n)
	var t := _run(ws, "deep", "tremor", 12.0, 600.0, game)
	check("a tremor brings the rumble (%d)" % int(t.get("rumble", 0)), int(t.get("rumble", 0)) >= 10, t)
	au.combat_level = 1.0
	var f := _run(ws, "cave", "", 12.0, 300.0, game)
	check("hushed in a fight", f.is_empty(), f)
	au.combat_level = 0.0
	var Gfx = load("res://scripts/core/Gfx.gd")
	Gfx.settings["world_sounds"] = "off"
	var o := _run(ws, "cave", "", 12.0, 300.0, game)
	check("switched off: silent", o.is_empty(), o)
	Gfx.settings["world_sounds"] = "on"
	game.hour_override = -1.0
	# --- steps
	ws.ground_kind = "snow"
	check("snow steps", ws.step_sounds(false)[0][0] == "step_snow")
	ws.ground_kind = "grass"
	ws.outdoor = true
	ws.weather = "rain"
	check("grass in the rain: a splash under it", ws.step_sounds(true).size() == 2 and ws.step_sounds(true)[1][0] == "step_water")
	ws.weather = ""
	check("grass, dry: one sound", ws.step_sounds(true).size() == 1)
	ws.ground_kind = "stone"
	check("stone", ws.step_sounds(false)[0][0] == "step_stone")
	check("running is louder", float(ws.step_sounds(true)[0][1]) > float(ws.step_sounds(false)[0][1]))
	# --- dry or wet
	var Au = load("res://scripts/core/Audio.gd")
	check("menu clicks stay dry", Au.is_dry("ui_click") and Au.is_dry("jingle_levelup") and Au.is_dry("loot_epic"))
	check("blows and steps carry the room", not Au.is_dry("hit_flesh") and not Au.is_dry("step_stone") and not Au.is_dry("bird_song"))
	# --- settings
	for k3 in ["world_sounds", "room_echo", "greetings"]:
		check("setting %s defaults on" % k3, str(Gfx.settings.get(k3, "")) == "on")
	# --- greetings
	var NPC = load("res://scripts/actors/NPC.gd")
	var GD: Dictionary = NPC.greet_data()
	var L: Dictionary = GD.get("lines", {})
	for k4 in ["dawn", "morning", "afternoon", "evening", "night", "rain", "storm", "snow", "hurt", "deep_town", "merchant", "smith"]:
		check("greetings for %s" % k4, (L.get(k4, []) as Array).size() >= 1)
	for k5 in L:
		for ln in L[k5]:
			check("greeting short: %s" % ln, str(ln).length() > 3 and str(ln).length() <= 64, ln)
	check("6:00 is dawn", NPC.hour_part(6.0) == "dawn")
	check("10:00 is morning", NPC.hour_part(10.0) == "morning")
	check("14:00 is afternoon", NPC.hour_part(14.0) == "afternoon")
	check("19:00 is evening", NPC.hour_part(19.0) == "evening")
	check("23:00 and 3:00 are night", NPC.hour_part(23.0) == "night" and NPC.hour_part(3.0) == "night")
	var rng := RandomNumberGenerator.new()
	var hurt_ok := true
	var saw_rain := false
	var saw_role := false
	var all_known := true
	var known := {}
	for k6 in L:
		for ln2 in L[k6]:
			known[str(ln2)] = k6
	for i in 300:
		rng.seed = i
		var h: String = NPC.greeting_for("smith", 10.0, "", "", true, false, rng)
		if known.get(h, "") != "hurt":
			hurt_ok = false
		rng.seed = 1000 + i
		var g2: String = NPC.greeting_for("smith", 10.0, "rain", "thaw", false, false, rng)
		if known.get(g2, "") == "rain":
			saw_rain = true
		if known.get(g2, "") == "smith":
			saw_role = true
		if not known.has(g2):
			all_known = false
		rng.seed = 2000 + i
		var g3: String = NPC.greeting_for("villager", 23.0, "", "", false, false, rng)
		if known.get(g3, "") not in ["night"]:
			all_known = false
	check("hurt: they say so first", hurt_ok)
	check("rain: they talk of the rain sometimes", saw_rain)
	check("a smith talks shop sometimes", saw_role)
	check("a villager at night says a night thing", all_known)
	# --- round 184b: the life of the air, breath, step puffs, thunder after the flash
	var WF = load("res://scripts/world/WorldFX.gd")
	check("warm summer night: fireflies", WF.life_for(true, 0.0, "blaze", "clear", "") == "fireflies")
	check("no fireflies in frost", WF.life_for(true, 0.0, "frost", "clear", "") == "")
	check("no fireflies in the rain (it lands instead)", WF.life_for(true, 0.0, "blaze", "rain", "rain") == "splashes")
	check("spring day: petals", WF.life_for(true, 1.0, "thaw", "clear", "") == "petals")
	check("summer day: fluff", WF.life_for(true, 1.0, "blaze", "heat", "") == "fluff")
	check("fog: nothing", WF.life_for(true, 1.0, "thaw", "fog", "mist") == "")
	check("underground: nothing", WF.life_for(false, 0.0, "blaze", "clear", "") == "")
	check("snow: breath shows", WF.is_cold(true, "thaw", "snow", "", 1.0))
	check("frost season: breath shows", WF.is_cold(true, "frost", "clear", "", 1.0))
	check("summer day: no breath", not WF.is_cold(true, "blaze", "clear", "", 1.0))
	check("a frost floor: breath shows", WF.is_cold(false, "", "still", "frost", 1.0))
	check("a warm floor: no breath", not WF.is_cold(false, "", "still", "warrens", 1.0))
	check("step on snow throws snow", WS.step_fx_kind("snow", true, "") == "snow")
	check("step in water splashes", WS.step_fx_kind("water", false, "") == "water")
	check("wet grass: a puddle splash", WS.step_fx_kind("grass", true, "rain") == "puddle")
	check("dry grass: nothing", WS.step_fx_kind("grass", true, "clear") == "")
	check("stone: nothing", WS.step_fx_kind("stone", false, "rain") == "")
	var M = load("res://scripts/fx/Motes.gd")
	for k7 in ["fireflies", "petals", "fluff", "splashes"]:
		check("motes know %s" % k7, M.SPEC.has(k7) and k7 in M.FOLLOW_KINDS)
	ws.bed = "village_night"
	ws.spot_count = {}
	ws.thunder_after(2.0, Vector3(30, 30, 0))
	for i in 8:
		ws._place_poll = 9999.0
		ws.tick(0.5)
	check("thunder follows the flash", int(ws.spot_count.get("thunder_far", 0)) == 1, ws.spot_count)
	# --- round 185: the wow -- night sky, cloud shadows, lantern night
	check("frost, clear night: northern lights", WF.sky_wonders("frost", "clear", 0.3, 5, 0.0)[0] == 1.0)
	check("by day: no lights", WF.sky_wonders("frost", "clear", 0.3, 5, 1.0) == [0.0, 0.0])
	check("cloudy night: no lights", WF.sky_wonders("frost", "clear", 0.8, 5, 0.0) == [0.0, 0.0])
	check("snowing: no lights", WF.sky_wonders("frost", "snow", 0.3, 5, 0.0) == [0.0, 0.0])
	check("a shower night: many falling stars", float(WF.sky_wonders("blaze", "clear", 0.3, 13, 0.0)[1]) >= 0.7)
	check("any clear night: a falling star now and then", float(WF.sky_wonders("blaze", "clear", 0.3, 14, 0.0)[1]) > 0.0)
	check("cloud shadows by day", WF.cloud_shadow_for(1.0, 0.45) > 0.3)
	check("no cloud shadows at night", WF.cloud_shadow_for(0.0, 0.45) == 0.0)
	check("all-grey sky: hardly any cloud shadow", WF.cloud_shadow_for(1.0, 1.0) < 0.05)
	check("lantern night: village, 20:00, clear, an even day", WF.lanterns_tonight("village", 20.0, "clear", false, 4))
	check("not every night", not WF.lanterns_tonight("village", 20.0, "clear", false, 5))
	check("every festival night", WF.lanterns_tonight("village", 20.0, "clear", true, 5))
	check("not before dusk", not WF.lanterns_tonight("village", 18.0, "clear", false, 4))
	check("not in the rain", not WF.lanterns_tonight("village", 20.0, "rain", false, 4))
	check("only in Eliet", not WF.lanterns_tonight("valley", 20.0, "clear", false, 4))
	var SL = load("res://scripts/world/SkyLanterns.gd").new()
	SL.setup(null)
	root.add_child(SL)
	SL.start(true)
	check("arriving mid-evening: the sky already has lanterns (%d)" % SL.alive(), SL.alive() >= 15)
	for i in 400:
		SL._process(0.5)
	check("they keep coming, never too many (%d)" % SL.alive(), SL.alive() >= 30 and SL.alive() <= SL.MAX_ALIVE)
	check("they climb high (%.0f m)" % SL.highest(), SL.highest() > 60.0)
	SL.stop()
	for i in 700:
		SL._process(0.5)
	check("after the night they're gone (%d)" % SL.alive(), SL.alive() == 0)
	SL.queue_free()
	var saw_l := false
	for i in 200:
		rng.seed = 5000 + i
		var gl: String = NPC.greeting_for("villager", 20.0, "", "", false, false, rng, "lanterns")
		if gl in (L.get("lanterns", []) as Array):
			saw_l = true
	check("on lantern night folk talk of the lanterns", saw_l)
	check("a sky line never beats being hurt", NPC.greeting_for("villager", 20.0, "", "", true, false, rng, "lanterns") in (L.get("hurt", []) as Array))
	print("WORLD SOUND CHECK %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
	return true

extends SceneTree
## The tech frontier (round 123): maps, ways in and out, reachability, region-only finds, variety, surfaces,
## and the graphics fine-tune. Pure data and map checks (smoke.gd builds the levels for real).
##   godot --headless --path . --script res://tools/frontier_check.gd
var G
var passed = 0
var failed = 0
const WALK := [".", ",", "L", "h", "o", "^", "&", "b", "<", "P"]


func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("  FAIL  " + name + ("  [" + detail + "]" if detail != "" else ""))


var _frames = 0


func _process(_d: float) -> bool:
	_frames += 1
	if _frames < 3:
		return false          # (let the Game autoload finish its _ready first)
	G = root.get_node_or_null("Game")
	if G == null:
		print("FRONTIER CHECK: no Game autoload")
		quit(1)
		return true
	_run()
	print("FRONTIER CHECK %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
	return true


func _flood(rows: Array, start: Vector2i) -> Dictionary:
	## over every cell a person could stand on (things standing on the floor are floor)
	var blocked = [" ", "#", "x", "c", "S", "~", "%", "t", "H", "f"]
	var dist = {start: 0}
	var q = [start]
	var i = 0
	while i < q.size():
		var c: Vector2i = q[i]
		i += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.y < 0 or n.y >= rows.size() or n.x < 0 or n.x >= str(rows[n.y]).length() or dist.has(n):
				continue
			if str(rows[n.y])[n.x] in blocked:
				continue
			dist[n] = int(dist[c]) + 1
			q.append(n)
	return dist


func _find(rows: Array, ch: String) -> Array:
	var out = []
	for y in rows.size():
		var row = str(rows[y])
		for x in row.length():
			if row[x] == ch:
				out.append(Vector2i(x, y))
	return out


func _run() -> void:
	var F = load("res://scripts/world/Frontier.gd")
	var ids = ["crash_site", "launch_yard", "ring_station", "ashen_moon", "glass_desert", "nanite_foundry"]
	var data: Dictionary = F.data()
	check("six regions in frontier.json", (data.get("regions", {}) as Dictionary).size() == 6)
	var defs = {}
	var sides = {}
	var notes_all = {}
	for rid in ids:
		var lid = "frontier:" + rid
		check(rid + ": exists", G.level_exists(lid))
		var d: Dictionary = G.load_level_def(lid)
		check(rid + ": def made", not d.is_empty())
		if d.is_empty():
			continue
		defs[rid] = d
		var rows: Array = d["map"]
		var reg: Dictionary = data["regions"][rid]
		check(rid + ": map size", rows.size() == int(reg["h"]) and str(rows[0]).length() == int(reg["w"]), "%d x %d" % [str(rows[0]).length(), rows.size()])
		var entries = _find(rows, "<")
		check(rid + ": one arrival", entries.size() == 1)
		if entries.is_empty():
			continue
		var start: Vector2i = entries[0]
		var reach = _flood(rows, start)
		var open_total = 0
		for y in rows.size():
			for x in str(rows[y]).length():
				if str(rows[y])[x] == ".":
					open_total += 1
		var reached_open = 0
		for c in reach:
			if str(rows[c.y])[c.x] == ".":
				reached_open += 1
		check(rid + ": the floor is all joined up", reached_open >= int(open_total * 0.97), "%d of %d" % [reached_open, open_total])
		# every placed thing can be reached
		var lost = []
		for ch in (d["chests"] as Dictionary).keys() + (d["npcs"] as Dictionary).keys() + (d["exits"] as Dictionary).keys() + (d["enemies"] as Dictionary).keys() + (d["lore"] as Dictionary).keys():
			for c in _find(rows, str(ch)):
				var near = reach.has(c)
				for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if reach.has(c + dd):
						near = true
				if not near:
					lost.append("%s@%s" % [ch, str(c)])
		check(rid + ": nothing sealed away", lost.is_empty(), ", ".join(lost.slice(0, 5)))
		check(rid + ": has foes, chests, a stone and a person", (d["enemies"] as Dictionary).size() >= 2 and (d["chests"] as Dictionary).size() >= 3 and not (d["lore"] as Dictionary).is_empty() and not (d["npcs"] as Dictionary).is_empty())
		if str(reg.get("boss", "")) != "":
			check(rid + ": the boss stands somewhere", _find(rows, "Y").size() == 1)
		# the way out resolves, and the char it arrives at exists on the other side
		for ch in d["exits"]:
			var e: Dictionary = d["exits"][ch]
			var to = str(e["to"])
			check("%s: way %s leads somewhere real (%s)" % [rid, ch, to], G.level_exists(to))
			var other: Dictionary = G.load_level_def(to)
			if other.is_empty():
				continue
			check("%s: arrival '%s' exists in %s" % [rid, e["arrive"], to], not _find(other["map"], str(e["arrive"])).is_empty())
		# what grows and is dug here
		var g: Dictionary = d["gather"]
		for kind in g:
			for it in g[kind]:
				check("%s: %s is a real item" % [rid, it["id"]], G.items.has(str(it["id"])))
		for fl in d["enemies"]:
			check("%s: foe %s defined" % [rid, d["enemies"][fl]], G.enemies.has(str(d["enemies"][fl])))
		for cl in d["chests"]:
			for lootid in d["chests"][cl]["loot"]:
				check("%s: chest loot %s is real" % [rid, lootid], str(lootid) == "gold" or G.items.has(str(lootid)))
			notes_all[rid + cl] = str(d["chests"][cl].get("note", ""))
		# several different ways of being hidden, not one
		var notes = {}
		for cl in d["chests"]:
			notes[str(d["chests"][cl].get("note", ""))] = true
		check(rid + ": chests are hidden in different ways", notes.size() >= 3, str(notes.size()))
		# the same region draws the same every time
		check(rid + ": same every time", G.load_level_def(lid)["map"] == rows)
		var side = "top" if start.y < 14 and rows.size() > 30 else ("bottom" if start.y > rows.size() - 14 else ("left" if start.x < 14 else "right"))
		sides[rid] = side
	# no two places lay out alike
	var seen = {}
	for rid in defs:
		var h = hash(str(defs[rid]["map"]))
		check(rid + ": its own layout", not seen.has(h))
		seen[h] = true
	var distinct = {}
	for rid in ["crash_site", "launch_yard", "ashen_moon", "glass_desert"]:
		if sides.has(rid):
			distinct[sides[rid]] = true
	check("the open places are not all entered from the same edge", distinct.size() >= 2, str(sides))
	# the pads need the card and the card exists
	if defs.has("launch_yard"):
		var pads = 0
		for ch in defs["launch_yard"]["exits"]:
			if str(defs["launch_yard"]["exits"][ch].get("needs", "")) == "skyhook_keycard":
				pads += 1
		check("three pads need the Skyhook keycard", pads == 3, str(pads))
	check("the keycard is an item", G.items.has("skyhook_keycard"))
	check("the Beacon Warden carries the keycard", ((G.enemies["beacon_warden"]["loot"] as Dictionary).has("skyhook_keycard")))
	# the valley's ways out
	var v: Dictionary = G.load_level_def("valley")
	var vrows: Array = v["map"]
	var five = _find(vrows, "5")
	var six = _find(vrows, "6")
	check("valley: a way to the Fallen Beacon", five.size() == 1 and (v["exits"] as Dictionary).has("5"))
	check("valley: a way to Skyhook Yard", six.size() == 1 and (v["exits"] as Dictionary).has("6"))
	if five.size() == 1 and six.size() == 1:
		check("valley: the two are far apart", absi(five[0].x - six[0].x) + absi(five[0].y - six[0].y) > 60, str(five[0]) + str(six[0]))
		var home = _find(vrows, "<")
		var reach = _flood(vrows, home[0])
		check("valley: both can be walked to from Eliet's road", reach.has(five[0]) and reach.has(six[0]), str(reach.has(five[0])) + str(reach.has(six[0])))
		check("valley: the way back arrives at a real spot", not _find(defs["crash_site"]["map"], "<").is_empty())
	# region-only finds: nothing grows in two regions at once
	var owner = {}
	var dup = []
	for rid in defs:
		for kind in defs[rid]["gather"]:
			for it in defs[rid]["gather"][kind]:
				var iid = str(it["id"])
				if iid in ["silver_ore", "sapphire_shard", "rough_ruby", "rough_jade", "iron_ore", "qi_pill"]:
					continue
				if owner.has(iid) and owner[iid] != rid:
					dup.append(iid)
				owner[iid] = rid
	check("every plant, ore and gem grows in one place only", dup.is_empty(), ", ".join(dup))
	# crafting: new materials have traits and the products can be made
	var cd: Dictionary = G.craft_data()
	for pid in ["ion_alloy", "lumen_extract", "lunar_steel", "sunglass_lens", "foundry_plate", "skyweave"]:
		var found = false
		for f in cd.get("formulas", []):
			if str(f["id"]) == pid:
				found = true
				for need in f["needs"]:
					check("%s needs %s which has traits" % [pid, need], (cd["materials"] as Dictionary).has(need))
		check(pid + ": a formula exists", found)
	# surfaces drawn in code
	var TT = load("res://scripts/world/TechTex.gd")
	for k in TT.KINDS:
		var imgs: Dictionary = TT.build(k, 64)
		check(k + ": three maps", imgs.size() == 3 and imgs["albedo"].get_width() == 64)
		var a: Image = imgs["albedo"]
		var mn = 1.0
		var mx = 0.0
		for y in 64:
			for x in 64:
				var l = a.get_pixel(x, y).get_luminance()
				mn = minf(mn, l)
				mx = maxf(mx, l)
		check(k + ": not flat", mx - mn > 0.08, "%.3f" % (mx - mn))
	# the graphics fine-tune
	var Gfx = load("res://scripts/core/Gfx.gd")
	var keep: Dictionary = Gfx.settings.duplicate(true)
	Gfx.load_settings()
	Gfx.settings["preset"] = "medium"
	Gfx.settings["custom"] = {}
	check("fine-tune: medium has glow", bool(Gfx.p()["glow"]))
	Gfx.settings["custom"] = {"glow": false, "shadow": 1024, "msaa": 4.0}
	check("fine-tune: an override replaces the preset's value", not bool(Gfx.p()["glow"]) and int(Gfx.p()["shadow"]) == 1024)
	check("fine-tune: a number from the JSON file still reads as a whole number", typeof(Gfx.p()["msaa"]) == TYPE_INT and int(Gfx.p()["msaa"]) == 4)
	check("fine-tune: the others stay as the preset had them", bool(Gfx.p()["ssao"]) == bool(Gfx.PRESETS["medium"]["ssao"]))
	check("fine-tune: one row for each effect", Gfx.TUNE.size() >= 12)
	for row in Gfx.TUNE:
		check("fine-tune: " + str(row[0]) + " is a real setting with a name for every value", Gfx.PRESETS["medium"].has(row[0]) and (row[2] as Array).all(func(v): return (row[3] as Dictionary).has(v)))
	Gfx.settings["custom"] = {}
	Gfx.settings.merge(keep, true)

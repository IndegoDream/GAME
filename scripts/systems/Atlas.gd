extends "res://scripts/systems/GameSystem.gd"
## Atlas (round 75). Robert: "be able to build a map of the world and area the
## player has traveled through."
##
##   remembers   which places you've been, in the order you first came (and when you
##               were last there), and the landmarks you've come across in each: ways
##               out, shrines, waystones, the lairs of masters, people. All of it is saved.
##   explored    the cells you've seen are the fog of war's own (Game.fog_seen, saved
##               per place); the atlas reads them -- live while you're in a place --
##               rather than keeping a second copy.
##   the map     scripts/MapScreen.gd (a page in the menu) draws all this.
## Numbers are in data/atlas.json.

var cfg := {}
var visits := []          # [{"id", "name", "first", "last", "n", "reaches"}] in order of first visit
var marks := {}           # level_id -> [{"kind", "x", "y", "name"}]
var _t := 0.0
var _maps := {}           # level_id -> the grid of a place you're not in (a few kept)


func setup(game) -> void:
	super.setup(game)
	cfg = G._load_json("res://data/atlas.json", {})


func reset() -> void:
	visits = []
	marks = {}
	_maps = {}


func save_state() -> Dictionary:
	return {"visits": visits, "marks": marks}


func load_state(d: Dictionary) -> void:
	# (a save comes back from JSON with every number a float: put the whole numbers back, so a save of a load is the same save)
	visits = []
	for v in (d.get("visits", []) if d.get("visits", []) is Array else []):
		if v is Dictionary:
			visits.append({"id": str(v.get("id", "")), "name": str(v.get("name", "")), "first": float(v.get("first", 0.0)),
				"last": float(v.get("last", 0.0)), "n": int(v.get("n", 1)), "reaches": int(v.get("reaches", 0))})
	marks = {}
	var raw: Dictionary = d.get("marks", {}) if d.get("marks", {}) is Dictionary else {}
	for id in raw:
		var arr := []
		for m in (raw[id] if raw[id] is Array else []):
			if m is Dictionary:
				arr.append({"kind": str(m.get("kind", "")), "x": int(m.get("x", 0)), "y": int(m.get("y", 0)), "name": str(m.get("name", ""))})
		marks[str(id)] = arr
	_maps = {}


func _n(key: String, dflt: float) -> float:
	return float(cfg.get(key, dflt))


# ---- what's remembered ------------------------------------------------------------------

func forgettable(id: String) -> bool:
	## places drawn fresh each time keep nothing
	return id == "" or preload("res://scripts/world/Arena.gd").is_arena(id) or preload("res://scripts/world/ScavengeGen.gd").is_scavenge(id) or preload("res://scripts/world/TrialGen.gd").is_trial(id) or id.begins_with("tribulation:")


func on_event(kind: String, data: Dictionary) -> void:
	if kind == "enter_level":
		visit(str(data.get("id", "")))


func visit(id: String) -> void:
	if forgettable(id):
		return
	var now := Time.get_unix_time_from_system()
	for v in visits:
		if str(v.get("id", "")) == id:
			v["last"] = now
			v["n"] = int(v.get("n", 0)) + 1
			return
	var nm := id
	var d: Dictionary = G.load_level_def(id)
	if d.has("name"):
		nm = str(d["name"])
	visits.append({"id": id, "name": nm, "first": now, "last": now, "n": 1, "reaches": 0})
	var cap := int(_n("max_levels", 120.0))
	while visits.size() > cap:
		var gone: Dictionary = visits.pop_front()
		marks.erase(str(gone.get("id", "")))


func visited(id: String) -> bool:
	for v in visits:
		if str(v.get("id", "")) == id:
			return true
	return false


func visit_row(id: String) -> Dictionary:
	for v in visits:
		if str(v.get("id", "")) == id:
			return v
	return {}


func marks_for(id: String) -> Array:
	var m = marks.get(id, [])
	return m if m is Array else []


func add_mark(id: String, kind: String, cell: Vector2i, nm: String) -> bool:
	var arr: Array = marks.get(id, [])
	for m in arr:
		if str(m.get("kind", "")) == kind and int(m.get("x", -1)) == cell.x and int(m.get("y", -1)) == cell.y:
			return false
	arr.append({"kind": kind, "x": cell.x, "y": cell.y, "name": nm})
	marks[id] = arr
	return true


# ---- the place you're in ------------------------------------------------------------------

func live_level():
	if G == null or not G.is_inside_tree():
		return null
	var lv = G.get_tree().get_first_node_in_group("level")
	return lv if lv != null and lv.is_inside_tree() and "level_id" in lv else null


func fog_node(lv):
	for n in G.get_tree().get_nodes_in_group("fog_of_war"):
		if "level" in n and n.level == lv:
			return n
	return null


func tick(delta: float) -> void:
	_t += delta
	if _t < _n("refresh_s", 1.5):
		return
	_t = 0.0
	scan_live()


func scan_live() -> int:
	## look through the place you're in for landmarks you've come across; how many were new
	var lv = live_level()
	if lv == null:
		return 0
	var id := str(lv.level_id)
	if forgettable(id):
		return 0
	if not visited(id):
		visit(id)
	var row := visit_row(id)
	if not row.is_empty():
		row["reaches"] = (lv.reaches as Array).size() if "reaches" in lv else 0
	var fog = fog_node(lv)
	var pl = G.get_tree().get_first_node_in_group("player")
	var pc := Vector2i(-9999, -9999)
	if pl != null:
		pc = lv.world_to_cell(pl.global_position)
	var sight := int(_n("sight_cells", 10.0))
	var added := 0
	for cand in candidates(lv):
		var cell: Vector2i = cand["cell"]
		var known := false
		if fog != null:
			known = fog.seen.has(cell)
		else:
			known = absi(cell.x - pc.x) <= sight and absi(cell.y - pc.y) <= sight
		if known and add_mark(id, str(cand["kind"]), cell, str(cand["name"])):
			added += 1
	return added


func candidates(lv) -> Array:
	## everything a place has that's worth marking: [{"kind", "cell", "name"}]
	var out := []
	var d: Dictionary = lv.def
	var ex: Dictionary = d.get("exits", {}) if d.get("exits", {}) is Dictionary else {}
	for ch in ex:
		for c in lv.spawns.get(str(ch), []):
			out.append({"kind": "exit", "cell": c, "name": str((ex[ch] as Dictionary).get("label", I18n.t("A way out")))})
	for c in lv.spawns.get("Z", []):
		out.append({"kind": "shrine", "cell": c, "name": I18n.t("Cultivation shrine")})
	var en: Dictionary = d.get("enemies", {}) if d.get("enemies", {}) is Dictionary else {}
	for ch in en:
		var eid := str(en[ch])
		var ed: Dictionary = G.enemies.get(eid, {})
		if bool(ed.get("boss", false)):
			for c in lv.spawns.get(str(ch), []):
				out.append({"kind": "boss", "cell": c, "name": str(ed.get("name", eid)).capitalize()})
	var npcs: Dictionary = d.get("npcs", {}) if d.get("npcs", {}) is Dictionary else {}
	for ch in npcs:
		for c in lv.spawns.get(str(ch), []):
			out.append({"kind": "npc", "cell": c, "name": str((npcs[ch] as Dictionary).get("name", I18n.t("Someone")))})
	if "waystone_cell" in lv and lv.waystone_cell.x >= 0:
		out.append({"kind": "waystone", "cell": lv.waystone_cell, "name": I18n.t("Waystone")})
	return out


# ---- what the map draws -------------------------------------------------------------------

func grid_of(id: String) -> Array:
	## the map of a place, as the level builds it (the live one if you're in it)
	var lv = live_level()
	if lv != null and str(lv.level_id) == id:
		return lv.grid
	if _maps.has(id):
		return _maps[id]
	var d: Dictionary = G.load_level_def(id)
	if d.is_empty():
		return []
	d = preload("res://scripts/world/Expanse.gd").expand(d)
	d = preload("res://scripts/world/Reach.gd").extend(d, preload("res://scripts/world/Look.gd").key_for(d))
	var rows := []
	for r in d.get("map", []):
		rows.append(str(r))
	if _maps.size() > 6:
		_maps.clear()
	_maps[id] = rows
	return rows


func is_fogged(id: String) -> bool:
	## does this place keep a fog of war (the dungeon floors do; towns and the open land don't)?
	var lv = live_level()
	if lv != null and str(lv.level_id) == id:
		return fog_node(lv) != null
	var d: Dictionary = G.load_level_def(id)
	var th := str(d.get("theme", "dungeon"))
	if th == "village" or th == "settlement" or th == "wilds" or bool(d.get("arena", false)) or bool(d.get("tribulation", false)):
		return false
	return str(preload("res://scripts/core/Gfx.gd").load_settings().get("fog", "on")) != "off"


func seen_cells(id: String) -> Dictionary:
	## the cells you've seen of a place ({} if it isn't fogged: all of it is known once you've been)
	var lv = live_level()
	if lv != null and str(lv.level_id) == id:
		var fog = fog_node(lv)
		return fog.seen if fog != null else {}
	if not is_fogged(id):
		return {}
	return G.fog_load(id, grid_of(id))


func explored_share(id: String) -> float:
	if not is_fogged(id):
		return 1.0 if visited(id) else 0.0
	var lv = live_level()
	if lv != null and str(lv.level_id) == id:
		var fog = fog_node(lv)
		if fog != null and fog.has_method("explored_fraction"):
			return float(fog.explored_fraction())
	return float(G.fog_frac.get(id, 0.0))


func world_nodes() -> Array:
	## the world overview, from data: [{"id", "name", "x", "y", "kind", "visited", "attuned", "reaches"}] with x, y in 0..1
	var out := []
	var T = G.sys("travel")
	var stones: Dictionary = T.stones if T != null else {}
	var total := int(_n("floors_total", 50.0))
	var deepest := 0
	for v in visits:
		var vid := str(v.get("id", ""))
		if vid.begins_with("floor"):
			deepest = maxi(deepest, int(vid.substr(5)) if vid.substr(5).is_valid_int() else 0)
	total = maxi(total, deepest)
	out.append({"id": "village", "name": I18n.t("Eliet Village"), "x": 0.5, "y": 0.04, "kind": "village", "visited": visited("village"), "attuned": stones.has("village"), "reaches": 0})
	var vr := visit_row("valley")
	out.append({"id": "valley", "name": I18n.t("The Valley"), "x": 0.2, "y": 0.04, "kind": "valley", "visited": not vr.is_empty(), "attuned": stones.has("valley"), "reaches": 0})
	for n in range(1, total + 1):
		var fid := "floor%d" % n
		var row := visit_row(fid)
		out.append({"id": fid, "name": I18n.t("Floor %d") % n, "x": 0.5, "y": 0.12 + 0.86 * float(n - 1) / float(maxi(total - 1, 1)),
			"kind": "floor", "visited": not row.is_empty(), "attuned": stones.has(fid), "reaches": int(row.get("reaches", 0))})
	var k := 0
	for v in visits:                           # everywhere else you've been (towns of the deep, towers, ...), down the left
		var id := str(v.get("id", ""))
		if id == "village" or id == "valley" or id.begins_with("floor"):
			continue
		out.append({"id": id, "name": str(v.get("name", id)), "x": 0.16 + 0.06 * float(k % 2), "y": 0.14 + 0.05 * float(k), "kind": "place",
			"visited": true, "attuned": stones.has(id), "reaches": 0})
		k += 1
	return out


func route() -> Array:
	## the ids of the places you've been, in the order you first came to them
	var out := []
	for v in visits:
		out.append(str(v.get("id", "")))
	return out

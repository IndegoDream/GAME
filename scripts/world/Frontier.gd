extends RefCounted
## The tech frontier (round 123). Robert, 2026-10-16: "we have a medieval type world with high tech ... more high
## tech regions to bridge that gap ... introduce space travel ... put more space between key locations, give more
## variety, do not hide things in a similar spot in each similar location ... certain items, plants or reagents
## [that] only grow within that region."
##
## Level ids are "frontier:<region>". Like the valley, they are not files in levels/: they are drawn here, when
## entered, from data/frontier.json (tools/gen/frontier_gen.py writes that file). Same region every time (seeded).
##
## Three layouts:
##   open   -- a field under the sky (the Fallen Beacon, Skyhook Yard, the Ashen Moon, the Glass Desert): noise
##             cliffs, then features (a hull, craters, dish arrays, camps, ruins, landing pads) set far apart
##   rooms  -- indoors (the Halcyon Ring, the Nanite Foundry): rooms and corridors, garden halls, sealed vaults
## What makes two regions NOT feel alike (the "no similar hiding spots" rule): every region seeds its own mix of
## features, its entrance edge, how each resource is scattered (scattered / in clusters / hugging walls / far
## out / ringing craters), and every hidden chest picks a DIFFERENT way of being hidden than the one before.
##
## Map characters are the level legend's. Enemy letters are lower-case from ENEMY_LETTERS; chests, NPCs, exits and
## lore stones take capitals from their own pools so nothing collides with the engine's own letters.

const DATA := "res://data/frontier.json"
const ENEMY_LETTERS := "adegijkmnqrsuvwyz"
const CHEST_LETTERS := "JGFIUQ"           # (K is the vault locker, R the lore stone)
const NPC_LETTERS := "MNOWXE"
const WALKABLE := [".", ",", "L", "h", "o", "^", "&", "b", "<", "P"]

static var _d := {}


static func data() -> Dictionary:
	if _d.is_empty():
		var t := FileAccess.get_file_as_string(DATA) if FileAccess.file_exists(DATA) else ""
		var j = JSON.parse_string(t) if t != "" else null
		_d = j if j is Dictionary else {"regions": {}, "sites": []}
	return _d


static func is_frontier(level_id: String) -> bool:
	return level_id.begins_with("frontier:")


static func region_id(level_id: String) -> String:
	return level_id.substr(9)


static func region(rid: String) -> Dictionary:
	return data().get("regions", {}).get(rid, {})


static func exists(level_id: String) -> bool:
	return is_frontier(level_id) and not region(region_id(level_id)).is_empty()


static func name_of(level_id: String) -> String:
	return str(region(region_id(level_id)).get("name", level_id))


# ---------------------------------------------------------------------------------------------------------------
# small helpers on the character grid g[y][x]
# ---------------------------------------------------------------------------------------------------------------

static func _blank(w: int, h: int, ch: String) -> Array:
	var g := []
	for y in h:
		var row := []
		for x in w:
			row.append(ch if x >= 2 and x < w - 2 and y >= 2 and y < h - 2 else " ")
		g.append(row)
	return g


static func _at(g: Array, x: int, y: int) -> String:
	if y < 0 or y >= g.size() or x < 0 or x >= g[0].size():
		return " "
	return str(g[y][x])


static func _put(g: Array, x: int, y: int, ch: String) -> void:
	if x >= 2 and x < g[0].size() - 2 and y >= 2 and y < g.size() - 2:
		g[y][x] = ch


static func _walk(ch: String) -> bool:
	return WALKABLE.has(ch)


static func _flood(g: Array, start: Vector2i) -> Dictionary:
	## cell -> steps from start, over walkable cells (4-way)
	var dist := {start: 0}
	var q := [start]
	var i := 0
	while i < q.size():
		var c: Vector2i = q[i]
		i += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not dist.has(n) and _walk(_at(g, n.x, n.y)):
				dist[n] = int(dist[c]) + 1
				q.append(n)
	return dist


static func _area_clear(g: Array, cx: int, cy: int, rx: int, ry: int, taken: Dictionary) -> bool:
	## mostly open ground, bounds respected, nothing else already standing there (a feature clears the rest itself)
	var open := 0
	var total := 0
	for y in range(cy - ry, cy + ry + 1):
		for x in range(cx - rx, cx + rx + 1):
			if x < 5 or y < 5 or x >= g[0].size() - 5 or y >= g.size() - 5:
				return false
			if taken.has(Vector2i(x, y)):
				return false
			total += 1
			if _at(g, x, y) == ".":
				open += 1
	return _at(g, cx, cy) == "." and open >= int(total * 0.8)


static func _find_spot(rng: RandomNumberGenerator, g: Array, rx: int, ry: int, taken: Dictionary, sites: Array, sep: int, tries: int = 600) -> Vector2i:
	## an open patch rx x ry (radii) at least `sep` cells from every site already placed
	var w: int = g[0].size()
	var h: int = g.size()
	for t in tries:
		var x := rng.randi_range(8, w - 9)
		var y := rng.randi_range(8, h - 9)
		var s := sep if t < tries * 2 / 3 else sep / 2          # (a crowded map settles for a tighter footing)
		var ok := true
		for c in sites:
			if absi(c.x - x) + absi(c.y - y) < s:
				ok = false
				break
		if ok and _area_clear(g, x, y, rx, ry, taken):
			return Vector2i(x, y)
	return Vector2i(-1, -1)


static func _reserve(taken: Dictionary, cx: int, cy: int, rx: int, ry: int) -> void:
	for y in range(cy - ry, cy + ry + 1):
		for x in range(cx - rx, cx + rx + 1):
			taken[Vector2i(x, y)] = true


static func _shuffle(rng: RandomNumberGenerator, a: Array) -> void:
	## (Array.shuffle() would use the game's own dice, and a region must come out the same every time)
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


static func _pick_w(rng: RandomNumberGenerator, list: Array) -> Dictionary:
	var tot := 0.0
	for e in list:
		tot += float(e.get("w", 1))
	var r := rng.randf() * tot
	for e in list:
		r -= float(e.get("w", 1))
		if r <= 0.0:
			return e
	return list[list.size() - 1]


# ---------------------------------------------------------------------------------------------------------------
# the entrance, terrain, features (open layouts)
# ---------------------------------------------------------------------------------------------------------------

static func _terrain(rng: RandomNumberGenerator, g: Array, reg: Dictionary, entry: Vector2i) -> void:
	var w: int = g[0].size()
	var h: int = g.size()
	var rock := float(reg.get("rock", 0.2))
	var nz := FastNoiseLite.new()
	nz.seed = rng.randi()
	nz.frequency = float(reg.get("freq", 0.04))
	nz.fractal_octaves = 3
	for attempt in 5:
		var vals := []
		for y in range(3, h - 3):
			for x in range(3, w - 3):
				vals.append(nz.get_noise_2d(x, y))
		vals.sort()
		var cut: float = vals[int(vals.size() * (1.0 - rock))] if rock > 0.0 and not vals.is_empty() else 2.0
		for y in range(3, h - 3):
			for x in range(3, w - 3):
				g[y][x] = " " if nz.get_noise_2d(x, y) >= cut else "."
		if bool(reg.get("dunes", false)):
			_dunes(rng, g)
		# a clearing round the entrance, always
		for y in range(entry.y - 5, entry.y + 6):
			for x in range(entry.x - 5, entry.x + 6):
				if Vector2i(x - entry.x, y - entry.y).length() <= 5.2:
					_put(g, x, y, ".")
		var reach := _flood(g, entry)
		var open_total := 0
		for y in range(3, h - 3):
			for x in range(3, w - 3):
				if g[y][x] == ".":
					open_total += 1
		if reach.size() >= int(open_total * 0.8) or attempt == 4:
			break
		rock *= 0.7
	var reach2 := _flood(g, entry)
	for y in range(3, h - 3):
		for x in range(3, w - 3):
			if g[y][x] == "." and not reach2.has(Vector2i(x, y)):
				g[y][x] = " "           # what the walker can't reach is rock


static func _dunes(rng: RandomNumberGenerator, g: Array) -> void:
	## long curved glass ridges across the map, each with gaps so nothing is sealed off
	var w: int = g[0].size()
	var h: int = g.size()
	var bands := rng.randi_range(5, 8)
	for b in bands:
		var horizontal := rng.randf() < 0.65
		var base := rng.randi_range(12, (h if horizontal else w) - 13)
		var amp := rng.randf_range(3.0, 9.0)
		var ph := rng.randf() * TAU
		var fq := rng.randf_range(0.04, 0.09)
		var thick := rng.randi_range(1, 2)
		var gap_every := rng.randi_range(16, 28)
		var along: int = w if horizontal else h
		for a in range(4, along - 4):
			if (a + b * 7) % gap_every < 4:
				continue
			var off := int(round(amp * sin(a * fq + ph)))
			for t in thick:
				if horizontal:
					_put(g, a, base + off + t, " ")
				else:
					_put(g, base + off + t, a, " ")


static func _feature_wreck(rng: RandomNumberGenerator, g: Array, reg: Dictionary, c: Vector2i, out: Dictionary) -> void:
	var hw := rng.randi_range(7, 10)
	var hh := rng.randi_range(5, 7)
	for y in range(c.y - hh - 2, c.y + hh + 3):
		for x in range(c.x - hw - 2, c.x + hw + 3):
			_put(g, x, y, ".")
	var gaps := []
	for s in 4:
		if rng.randf() < 0.6 or gaps.size() < 2:
			gaps.append(s)
	for y in range(c.y - hh, c.y + hh + 1):
		for x in range(c.x - hw, c.x + hw + 1):
			var edge := y == c.y - hh or y == c.y + hh or x == c.x - hw or x == c.x + hw
			if edge:
				_put(g, x, y, "#")
	for s in gaps:
		var shift := rng.randi_range(-3, 3)
		for k in [-1, 0, 1]:
			if int(s) == 0:
				_put(g, c.x + k + shift, c.y - hh, ".")
			elif int(s) == 1:
				_put(g, c.x + k + shift, c.y + hh, ".")
			elif int(s) == 2:
				_put(g, c.x - hw, c.y + k + shift / 2, ".")
			else:
				_put(g, c.x + hw, c.y + k + shift / 2, ".")
	# debris inside: torn plating, a console or two
	for i in rng.randi_range(5, 9):
		var x := c.x + rng.randi_range(-hw + 2, hw - 2)
		var y := c.y + rng.randi_range(-hh + 2, hh - 2)
		if _at(g, x, y) == ".":
			_put(g, x, y, "x" if rng.randf() < 0.7 else "L")
	out["wreck"] = {"cell": c, "rx": hw, "ry": hh}


static func _feature_crater(rng: RandomNumberGenerator, g: Array, c: Vector2i, out: Dictionary) -> void:
	var r := rng.randi_range(4, 7)
	var gap := rng.randf() * TAU
	for y in range(c.y - r - 1, c.y + r + 2):
		for x in range(c.x - r - 1, c.x + r + 2):
			var d := Vector2(x - c.x, y - c.y).length()
			if d <= r + 0.6:
				_put(g, x, y, ".")
			if d >= r - 0.7 and d <= r + 0.6:
				var ang := Vector2(x - c.x, y - c.y).angle()
				if absf(angle_difference(ang, gap)) > 0.45 and rng.randf() < 0.85:
					_put(g, x, y, "x")
	out.get("craters", []).append({"cell": c, "r": r})


static func _feature_pylons(rng: RandomNumberGenerator, g: Array, c: Vector2i) -> void:
	var line := rng.randf() < 0.5
	var n := rng.randi_range(5, 9)
	for i in n:
		var p := Vector2i(c.x + (i * 3 - n * 3 / 2 if line else int(round(cos(i * TAU / n) * 5.0))), c.y + (rng.randi_range(-1, 1) if line else int(round(sin(i * TAU / n) * 5.0))))
		if _at(g, p.x, p.y) == ".":
			_put(g, p.x, p.y, "c")
	_put(g, c.x, c.y, "L")


static func _feature_camp(rng: RandomNumberGenerator, g: Array, c: Vector2i, out: Dictionary) -> void:
	_put(g, c.x, c.y, "L")
	for a in 8:
		if rng.randf() < 0.55:
			var ang := a * TAU / 8.0
			_put(g, c.x + int(round(cos(ang) * 2.6)), c.y + int(round(sin(ang) * 2.6)), "b")
	out.get("camps", []).append(c)


static func _feature_dish_array(rng: RandomNumberGenerator, g: Array, c: Vector2i) -> void:
	var n := rng.randi_range(2, 3)
	for gy in range(-n, n + 1, 2):
		for gx in range(-n, n + 1, 2):
			if rng.randf() < 0.85:
				_put(g, c.x + gx * 2, c.y + gy * 2, "c")
	_put(g, c.x, c.y, "L")


static func _feature_ruins(rng: RandomNumberGenerator, g: Array, c: Vector2i, out: Dictionary) -> void:
	var hw := rng.randi_range(3, 5)
	var hh := rng.randi_range(3, 4)
	for y in range(c.y - hh, c.y + hh + 1):
		for x in range(c.x - hw, c.x + hw + 1):
			var edge := y == c.y - hh or y == c.y + hh or x == c.x - hw or x == c.x + hw
			if edge and rng.randf() < 0.65:
				_put(g, x, y, "x")
	out.get("ruins", []).append(c)


static func _feature_tanks(rng: RandomNumberGenerator, g: Array, c: Vector2i) -> void:
	var n := rng.randi_range(3, 6)
	for i in n:
		var x := c.x + (i % 3) * 4 - 4
		var y := c.y + (i / 3) * 4 - 2
		_put(g, x, y, "x")
		if rng.randf() < 0.4:
			_put(g, x + 1, y, "x")
	_put(g, c.x, c.y + 3, "L")


# ---------------------------------------------------------------------------------------------------------------
# rooms layouts
# ---------------------------------------------------------------------------------------------------------------

static func _carve(g: Array, r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			_put(g, x, y, ".")


static func _corridor(g: Array, a: Vector2i, b: Vector2i, wide: int, horizontal_first: bool) -> void:
	var p := a
	var legs := [Vector2i(b.x, a.y), b] if horizontal_first else [Vector2i(a.x, b.y), b]
	for leg in legs:
		while p != leg:
			p += Vector2i(signi(leg.x - p.x), signi(leg.y - p.y))
			for k in wide:
				if horizontal_first == (leg == legs[0]):
					_put(g, p.x, p.y + k, ".")
				else:
					_put(g, p.x + k, p.y, ".")


static func _rooms(rng: RandomNumberGenerator, g: Array, reg: Dictionary) -> Array:
	var w: int = g[0].size()
	var h: int = g.size()
	var cfg: Dictionary = reg.get("rooms", {})
	var want := rng.randi_range(int(cfg.get("n", [14, 18])[0]), int(cfg.get("n", [14, 18])[1]))
	var lo := int(cfg.get("min", 6))
	var hi := int(cfg.get("max", 13))
	var rooms: Array = []
	var tries := 0
	while rooms.size() < want and tries < 900:
		tries += 1
		var rw := rng.randi_range(lo, hi)
		var rh := rng.randi_range(lo - 1, hi - 3)
		var r := Rect2i(rng.randi_range(6, w - rw - 7), rng.randi_range(6, h - rh - 7), rw, rh)
		var grown := r.grow(4)
		var clash := false
		for o in rooms:
			if grown.intersects(o):
				clash = true
				break
		if clash:
			continue
		rooms.append(r)
		_carve(g, r)
	# join each room to the nearest earlier one, then two extra loops
	for i in range(1, rooms.size()):
		var best := 0
		var bd := 1 << 30
		for j in i:
			var d: int = (rooms[i].get_center() - rooms[j].get_center()).length_squared()
			if d < bd:
				bd = d
				best = j
		_corridor(g, rooms[i].get_center(), rooms[best].get_center(), rng.randi_range(1, 2), rng.randf() < 0.5)
	for k in 2:
		if rooms.size() > 4:
			var a := rng.randi_range(0, rooms.size() - 1)
			var b := rng.randi_range(0, rooms.size() - 1)
			if a != b:
				_corridor(g, rooms[a].get_center(), rooms[b].get_center(), 1, rng.randf() < 0.5)
	return rooms


# ---------------------------------------------------------------------------------------------------------------
# hidden things: each one picks a way of being hidden that the last one did not use
# ---------------------------------------------------------------------------------------------------------------

const HIDE_WAYS := ["nook", "far", "behind", "edge", "centre"]


static func _hide_cell(rng: RandomNumberGenerator, g: Array, way: String, reach: Dictionary, taken: Dictionary, maxd: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var cells: Array = reach.keys()
	if cells.is_empty():
		return best
	for t in 500:
		var c: Vector2i = cells[rng.randi() % cells.size()]
		if taken.has(c) or _at(g, c.x, c.y) != ".":
			continue
		var solid := 0
		var obst := 0
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var ch := _at(g, c.x + dx, c.y + dy)
				if ch == " " or ch == "#":
					solid += 1
				elif ch in ["x", "c"]:
					obst += 1
		var d := int(reach[c])
		var ok := false
		match way:
			"nook":
				ok = solid >= 5
			"far":
				ok = d >= int(maxd * 0.8)
			"behind":
				ok = obst >= 2 and solid + obst >= 3
			"edge":
				ok = c.x < 12 or c.y < 12 or c.x > g[0].size() - 13 or c.y > g.size() - 13
			"centre":
				ok = absi(c.x - g[0].size() / 2) < g[0].size() / 6 and absi(c.y - g.size() / 2) < g.size() / 6 and d > 12
		if ok:
			return c
		if best.x < 0 and d > 10:
			best = c         # (a fallback if the way finds nothing)
	return best


# ---------------------------------------------------------------------------------------------------------------
# the def
# ---------------------------------------------------------------------------------------------------------------

static func make_def(level_id: String, enemy_ids: Dictionary) -> Dictionary:
	var rid := region_id(level_id)
	var reg: Dictionary = region(rid)
	if reg.is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("frontier:%s:v1" % rid)
	var w := int(reg.get("w", 96))
	var h := int(reg.get("h", 76))
	var kind := str(reg.get("kind", "open"))
	var g := _blank(w, h, " ")
	var taken := {}
	var extras := {"craters": [], "camps": [], "ruins": []}
	var sites: Array = []
	var entry := Vector2i.ZERO
	var rooms: Array = []
	var room_roles := {}
	# ---- the ground
	if kind == "rooms":
		rooms = _rooms(rng, g, reg)
		entry = rooms[0].get_center()
	else:
		var side := rng.randi_range(0, 3)           # which edge you come in by differs from region to region
		var along := rng.randf_range(0.2, 0.8)
		match side:
			0: entry = Vector2i(int(w * along), 9)
			1: entry = Vector2i(int(w * along), h - 10)
			2: entry = Vector2i(9, int(h * along))
			_: entry = Vector2i(w - 10, int(h * along))
		for yy in h:
			for xx in w:
				g[yy][xx] = "." if xx >= 2 and xx < w - 2 and yy >= 2 and yy < h - 2 else " "
		_terrain(rng, g, reg, entry)
	var reach := _flood(g, entry)
	var maxd := 0
	for c in reach:
		maxd = maxi(maxd, int(reach[c]))
	sites.append(entry)
	_reserve(taken, entry.x, entry.y, 4, 4)
	var exits := {}
	var npcs := {}
	var chests := {}
	var lore := {}
	var enemies := {}
	var npc_i := 0
	var chest_i := 0
	var letter_i := 0
	# ---- open layouts: features set far apart
	var boss_cell := Vector2i(-1, -1)
	if kind == "open":
		var sep := int(minf(w, h) * 0.30)
		for f in reg.get("features", []):
			var rx := 7
			var ry := 6
			match str(f):
				"wreck": rx = 12; ry = 10
				"crater": rx = 9; ry = 9
				"dish_array": rx = 8; ry = 8
				"pads": rx = 12; ry = 7
				"tanks": rx = 7; ry = 5
				"ruins": rx = 7; ry = 6
				"dunes": continue
			var c := _find_spot(rng, g, rx, ry, taken, sites, sep)
			if c.x < 0:
				continue
			sites.append(c)
			_reserve(taken, c.x, c.y, rx, ry)
			match str(f):
				"wreck":
					_feature_wreck(rng, g, reg, c, extras)
					if str(reg.get("boss", "")) != "":
						boss_cell = c
				"crater": _feature_crater(rng, g, c, extras)
				"pylons": _feature_pylons(rng, g, c)
				"camp": _feature_camp(rng, g, c, extras)
				"dish_array": _feature_dish_array(rng, g, c)
				"ruins": _feature_ruins(rng, g, c, extras)
				"tanks": _feature_tanks(rng, g, c)
				"pads":
					var pads: Array = reg.get("pads", [])
					for i in pads.size():
						var pc := Vector2i(c.x + (i - pads.size() / 2) * 8, c.y)
						for yy in range(pc.y - 2, pc.y + 3):
							for xx in range(pc.x - 2, pc.x + 3):
								_put(g, xx, yy, ",")
						var pch := "ABC"[i]
						_put(g, pc.x, pc.y, pch)
						for q in [Vector2i(-2, -2), Vector2i(2, -2), Vector2i(-2, 2), Vector2i(2, 2)]:
							_put(g, pc.x + q.x, pc.y + q.y, "L")
						exits[pch] = {"to": "frontier:%s" % str(pads[i]["to"]), "arrive": "<", "label": str(pads[i]["label"]), "down": false, "style": "pad", "needs": "skyhook_keycard"}
	else:
		# rooms: roles. First room is the arrival (and the hub); farthest is the boss's hall
		var order := []
		for i in range(1, rooms.size()):
			order.append(i)
		var far_i := 1
		var far_d := -1
		for i in range(1, rooms.size()):
			var cc: Vector2i = rooms[i].get_center()
			var dd: int = int(reach.get(cc, 0))
			if dd > far_d:
				far_d = dd
				far_i = i
		room_roles[far_i] = "boss"
		order.erase(far_i)
		_shuffle(rng, order)
		var rc: Dictionary = reg.get("rooms", {})
		for k in int(rc.get("garden", 0)):
			if not order.is_empty():
				room_roles[order.pop_back()] = "garden"
		for k in int(rc.get("vault", 0)):
			if not order.is_empty():
				room_roles[order.pop_back()] = "vault"
		for i in order:
			room_roles[i] = "hall"
		room_roles[0] = "hub"
		boss_cell = rooms[far_i].get_center()
	# ---- the way out
	var gate_from := str(reg.get("gate_from", "valley"))
	var back_to := gate_from if gate_from == "valley" else "frontier:%s" % gate_from
	_put(g, entry.x, entry.y, "<")
	_put(g, entry.x + 1, entry.y + 1, "P")
	exits["<"] = {"to": back_to, "arrive": str(reg.get("gate_back", "<")), "label": I18n.t("Back to %s") % (I18n.t("the valley") if gate_from == "valley" else name_of("frontier:" + gate_from)), "down": false, "style": "hatch" if kind == "open" and gate_from == "valley" else ("pad" if gate_from == "launch_yard" else "stairs")}
	# ---- a second way (the Foundry hatch inside the Fallen Beacon)
	var eg: Dictionary = data().get("extra_gates", {}).get(rid, {})
	if not eg.is_empty():
		var gc := Vector2i(-1, -1)
		if kind == "open":
			gc = _hide_cell(rng, g, "far", reach, taken, maxd)
		if gc.x >= 0:
			_put(g, gc.x, gc.y, str(eg["char"]))
			exits[str(eg["char"])] = {"to": "frontier:%s" % str(eg["to"]), "arrive": str(eg["arrive"]), "label": str(eg["label"]), "down": true, "style": str(eg.get("style", "hatch"))}
			_reserve(taken, gc.x, gc.y, 2, 2)
	# ---- what the features did to the ground: look again at what can be walked to
	reach = _flood(g, entry)
	maxd = 0
	for c in reach:
		maxd = maxi(maxd, int(reach[c]))
	var dens: Dictionary = reg.get("density", {})
	var open_cells := reach.keys()
	var area_cells := 0
	for y in range(3, h - 3):
		for x in range(3, w - 3):
			if g[y][x] == ".":
				area_cells += 1
	# ---- resources: each kind is scattered its own way, chosen from the seed
	var ways := ["scatter", "clusters", "walls", "far", "rings"]
	var scatter := func(ch: String, per: int, way: String) -> int:
		if per <= 0:
			return 0
		var n: int = maxi(1, area_cells / per)
		var placed := 0
		var guard := 0
		var centres := []
		for i in rng.randi_range(2, 5):
			centres.append(open_cells[rng.randi() % open_cells.size()])
		var way_now := way
		while placed < n and guard < n * 120:
			guard += 1
			if guard == n * 40 and placed < n / 2:
				way_now = "scatter"          # (the chosen way found too few places: fill the rest anywhere)
			var c: Vector2i
			if way_now == "clusters":
				var cen: Vector2i = centres[rng.randi() % centres.size()]
				c = cen + Vector2i(rng.randi_range(-5, 5), rng.randi_range(-5, 5))
			elif way_now == "rings" and not extras["craters"].is_empty():
				var cr: Dictionary = extras["craters"][rng.randi() % extras["craters"].size()]
				var ang := rng.randf() * TAU
				var rr := float(cr["r"]) - 1.6
				c = cr["cell"] + Vector2i(int(round(cos(ang) * rr)), int(round(sin(ang) * rr)))
			else:
				c = open_cells[rng.randi() % open_cells.size()]
			if not reach.has(c) or taken.has(c) or _at(g, c.x, c.y) != ".":
				continue
			if absi(c.x - entry.x) + absi(c.y - entry.y) < 8:
				continue
			if way_now == "walls":
				var solid := 0
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if _at(g, c.x + d.x, c.y + d.y) in [" ", "#"]:
						solid += 1
				if solid == 0:
					continue
			if way_now == "far" and int(reach[c]) < int(maxd * 0.45):
				continue
			g[c.y][c.x] = ch
			placed += 1
		return placed
	for ch in ["h", "o", "^", "x", "c"]:
		var per := int(dens.get(ch, 0))
		if kind == "rooms" and ch in ["h", "x", "c"]:
			continue         # rooms get these room by room, below
		scatter.call(ch, per, ways[rng.randi() % ways.size()])
	# ---- rooms: dress each by its role
	if kind == "rooms":
		for i in rooms.size():
			var r: Rect2i = rooms[i]
			var role: String = room_roles.get(i, "hall")
			var c0 := r.get_center()
			match role:
				"hub":
					for k in 4:
						_put(g, r.position.x + 1 + k * 2, r.position.y + 1, "L" if k % 2 == 0 else ".")
				"garden":
					for yy in range(r.position.y + 1, r.end.y - 1, 2):
						for xx in range(r.position.x + 1, r.end.x - 1):
							if (xx + yy) % 3 != 0 and _at(g, xx, yy) == ".":
								_put(g, xx, yy, "h")
					_put(g, c0.x, c0.y, "L")
				"vault":
					_put(g, c0.x, c0.y, "K")
					_put(g, r.position.x + 1, r.position.y + 1, "L")
					_put(g, r.end.x - 2, r.end.y - 2, "L")
				"boss":
					for xx in range(r.position.x + 2, r.end.x - 2, 3):
						_put(g, xx, r.position.y + 1, "c")
						_put(g, xx, r.end.y - 2, "c")
				_:
					if rng.randf() < 0.6:
						for xx in range(r.position.x + 1, r.end.x - 1, 3):
							if rng.randf() < 0.7:
								_put(g, xx, r.position.y + 1, "x")
					if rng.randf() < 0.5 and r.size.x >= 8 and r.size.y >= 7:
						for sx in [-2, 2]:
							for sy in [-2, 2]:
								_put(g, c0.x + sx, c0.y + sy, "c")          # (never on the middle row or column: that's where the passages run)
					_put(g, r.position.x, r.position.y, "L")
	# ---- NPCs: by the camps/hub/entry, never in a row
	var npc_defs: Array = reg.get("npcs", [])
	var npc_spots: Array = []
	for cp in extras["camps"]:
		npc_spots.append(cp + Vector2i(1, 1))
	if kind == "rooms" and not rooms.is_empty():
		var hub: Rect2i = rooms[0]
		for i in npc_defs.size():
			npc_spots.append(Vector2i(hub.position.x + 2 + i * 2, hub.end.y - 3))
	else:
		npc_spots.append(entry + Vector2i(-3, 2))
		npc_spots.append(entry + Vector2i(3, 3))
		npc_spots.append(entry + Vector2i(0, 4))
	for nd in npc_defs:
		if npc_i >= NPC_LETTERS.length() or npc_spots.is_empty():
			break
		var sp: Vector2i = npc_spots.pop_front()
		var found := sp
		if _at(g, sp.x, sp.y) != ".":
			found = Vector2i(-1, -1)
			for rad in range(1, 6):
				for dy in range(-rad, rad + 1):
					for dx in range(-rad, rad + 1):
						if found.x < 0 and _at(g, sp.x + dx, sp.y + dy) == ".":
							found = sp + Vector2i(dx, dy)
		if found.x < 0:
			continue
		var nl := NPC_LETTERS[npc_i]
		npc_i += 1
		g[found.y][found.x] = nl
		var nm: Dictionary = (nd as Dictionary).duplicate(true)
		npcs[nl] = nm
		_reserve(taken, found.x, found.y, 1, 1)
	# ---- lore stones
	var lore_defs: Array = reg.get("lore", [])
	for i in lore_defs.size():
		var lc := _hide_cell(rng, g, "centre" if kind == "open" else "behind", reach, taken, maxd)
		if lc.x < 0:
			lc = entry + Vector2i(2, -3)
		g[lc.y][lc.x] = "R"
		lore["R"] = lore_defs[i]
		_reserve(taken, lc.x, lc.y, 1, 1)
		break
	# ---- hidden chests: every one hidden a different way from the one before
	var ways_left := HIDE_WAYS.duplicate()
	_shuffle(rng, ways_left)
	var cnum := 3 + rng.randi_range(0, 2)
	var mats: Array = []
	for e in (reg.get("gather", {}) as Dictionary).values():
		for it in e:
			mats.append(str(it["id"]))
	var depth := int(reg.get("depth", 10))
	for i in cnum:
		if ways_left.is_empty():
			ways_left = HIDE_WAYS.duplicate()
			_shuffle(rng, ways_left)
		var way: String = ways_left.pop_back()
		var cc := _hide_cell(rng, g, way, reach, taken, maxd)
		if cc.x < 0 or chest_i >= CHEST_LETTERS.length():
			continue
		var cl := CHEST_LETTERS[chest_i]
		chest_i += 1
		g[cc.y][cc.x] = cl
		_reserve(taken, cc.x, cc.y, 2, 2)
		var loot := {"gold": [depth * 14, depth * 26]}
		for m in 2:
			if not mats.is_empty():
				loot[mats[rng.randi() % mats.size()]] = [1, 3]
		if rng.randf() < 0.5:
			loot["qi_pill"] = [1, 2]
		chests[cl] = {"loot": loot, "note": "Tucked %s." % {"nook": "into a corner of the rock", "far": "a long way from anywhere", "behind": "behind a stand of wreckage", "edge": "out by the edge of the map", "centre": "right in the open, under a scatter of plate"}.get(way, "away"), "hidden": way in ["nook", "behind"]}
	# vault chests (rooms layouts) share one rich table
	if kind == "rooms":
		var mk := str(mats[rng.randi() % mats.size()]) if not mats.is_empty() else "iron_ore"
		chests["K"] = {"loot": {"gold": [depth * 30, depth * 50], mk: [2, 4]}, "note": "A sealed locker, never opened.", "hidden": false}
	# ---- the foes
	var dist_of := func(c: Vector2i) -> int:
		return int(reach.get(c, 0))
	var foe_rows: Array = reg.get("foes", [])
	for fr in foe_rows:
		var fid := str(fr[0])
		if not enemy_ids.has(fid) or letter_i >= ENEMY_LETTERS.length():
			continue
		var fl := ENEMY_LETTERS[letter_i]
		letter_i += 1
		enemies[fl] = fid
		var n := int(fr[1])
		var pack := rng.randi_range(1, 3)
		var placed := 0
		var guard := 0
		while placed < n and guard < 4000:
			guard += 1
			var base: Vector2i
			if kind == "rooms":
				var ri := rng.randi_range(1, rooms.size() - 1)
				if str(room_roles.get(ri, "hall")) in ["hub", "boss", "vault"]:
					continue
				var rr: Rect2i = rooms[ri]
				base = Vector2i(rng.randi_range(rr.position.x + 1, rr.end.x - 2), rng.randi_range(rr.position.y + 1, rr.end.y - 2))
			else:
				base = open_cells[rng.randi() % open_cells.size()]
			if not reach.has(base) or taken.has(base) or _at(g, base.x, base.y) != ".":
				continue
			if int(dist_of.call(base)) < 16:
				continue
			for k in pack:
				if placed >= n:
					break
				var c: Vector2i = base + Vector2i(rng.randi_range(-2, 2), rng.randi_range(-2, 2))
				if _at(g, c.x, c.y) == "." and not taken.has(c) and int(dist_of.call(c)) >= 14:
					g[c.y][c.x] = fl
					placed += 1
	# ---- the boss
	var bid := str(reg.get("boss", ""))
	if bid != "" and enemy_ids.has(bid) and letter_i < ENEMY_LETTERS.length():
		var bl := "Y"
		var bc := boss_cell
		if kind == "open" and extras.has("wreck"):
			bc = (extras["wreck"] as Dictionary)["cell"]
		if bc.x < 0 or _at(g, bc.x, bc.y) not in ["."]:
			bc = _hide_cell(rng, g, "far", reach, taken, maxd)
		if bc.x >= 0:
			g[bc.y][bc.x] = bl
			enemies[bl] = bid
			# the boss guards a locker
			if chest_i < CHEST_LETTERS.length():
				var lk := Vector2i(bc.x + 2, bc.y)
				if _at(g, lk.x, lk.y) == ".":
					var cl2 := CHEST_LETTERS[chest_i]
					chest_i += 1
					g[lk.y][lk.x] = cl2
					chests[cl2] = {"loot": {"gold": [depth * 40, depth * 70], "qi_pill": [2, 3]}, "note": "The guardian's own cache.", "hidden": false}
	# ---- done
	var out := []
	for row in g:
		out.append("".join(PackedStringArray(row)))
	var d := {"id": level_id, "name": str(reg.get("name", rid)), "theme": str(reg.get("theme", "wilds")), "look": str(reg.get("look", "warrens")), "depth": int(reg.get("depth", 10)),
		"no_expand": true, "no_reach": true, "frontier": rid, "notes": str(reg.get("blurb", "")), "map": out, "enemies": enemies, "npcs": npcs, "exits": exits, "chests": chests, "lore": lore,
		"gather": reg.get("gather", {}), "giants": reg.get("giants", {}), "lamp": str(reg.get("lamp", "")), "motes": str(reg.get("motes", ""))}
	for k in ["rim", "ground_tint", "deco", "cliff_tint"]:
		if reg.has(k):
			d[k] = reg[k]
	if (reg.get("atmos", {}) as Dictionary).size() > 0:
		d["atmos"] = reg["atmos"]
	if reg.has("ambient"):
		d["ambient"] = reg["ambient"]
	return d

extends RefCounted
## The Valley of Eliet -- the open country outside the village (round 24).
## Robert, 2026-10-02: "as close to Morrowind or Skyrim in style ... towers
## to climb and sects outside of the dungeon -- the dungeon is the primary
## way to progress but not the only way." He chose ONE open region.
##
## The valley isn't a file in levels/ (those are Dev's): it's drawn here,
## when it's entered, from data/valley.json -- the sects Dev wrote and the
## three towers -- so it grows as Dev's writing room fills it. Same valley
## every time (seeded).
##
## South: the road out of Eliet, meadows, goblins and hares. The river runs
## east-west across the middle with three bridges. North of it: older
## things (the crypt dead, mine crawlers, moss stags). Under the northern
## peaks: thornlings, cinder imps, the clay soldiers. Six sect seats ring the
## valley, each a walled yard with its hall; three towers stand at rising
## distances -- the Stair (south), the Spire (centre), the Pagoda (north).
##
## Map characters are the level legend's; the sect halls, towers and
## wonders are carried in the def ("sects", "towers", "extras") and placed
## by Level.gd.

## Round 150 (Robert: "the places need to be a bit more spaced out with more hunting and gathering grounds"):
## SPREAD 1.45 -> 1.85, and GROUNDS below -- named hunting and gathering grounds set well away from every
## hall and tower. (Far creatures sleep, Enemy.gd, so the bigger country costs no frames.)
## Round 36 (Robert: "the world needs more space between locations"): the
## valley was drawn on a 128 x 104 plan; everything's place on it is now
## spread by SPREAD (the river, the roads, the sects, the towers, the
## shrine, the lanterns) while the buildings keep their size -- more country
## between them, and more creatures, woods and finds to fill it.
const SPREAD := 1.85
const BASE_W := 128
const BASE_H := 104
const W := int(BASE_W * SPREAD)
const H := int(BASE_H * SPREAD)
const BASE_SECT_SLOTS := [Vector2i(22, 76), Vector2i(106, 76), Vector2i(16, 38), Vector2i(112, 38), Vector2i(34, 14), Vector2i(94, 14)]
const BASE_TOWER_SLOTS := [Vector2i(44, 93), Vector2i(82, 41), Vector2i(64, 9)]
static var SECT_SLOTS: Array = BASE_SECT_SLOTS.map(func(v): return sc2(v))
static var TOWER_SLOTS: Array = BASE_TOWER_SLOTS.map(func(v): return sc2(v))
const TOWER_RADIUS := [3, 4, 4]
const NPC_LETTERS := "ABCDEFGIJKMNOQRUVW"
## round 150: game animals (all passive, huntable and tameable) for the hunting grounds; r s u v w y z are free enemy letters
const GAME := {"r": "cave_hare", "s": "lantern_newt", "u": "tunnel_boar", "v": "ridge_goat", "w": "rock_badger", "y": "river_otter", "z": "moon_lynx"}
## name, kind (hunt / herbs / ore / reeds), zone, game letters, count, radius (cells, before spread is applied to the gaps between them)
const GROUNDS := [
	{"name": "Hare Meadow", "kind": "hunt", "zone": "south", "game": "rs", "n": 10, "r": 10},
	{"name": "Boar Flats", "kind": "hunt", "zone": "south", "game": "ur", "n": 9, "r": 11},
	{"name": "Goat Ridge", "kind": "hunt", "zone": "middle", "game": "vw", "n": 9, "r": 10},
	{"name": "Otter Bend", "kind": "hunt", "zone": "middle", "game": "y", "n": 7, "r": 9},
	{"name": "Lynx Heights", "kind": "hunt", "zone": "north", "game": "zv", "n": 8, "r": 10},
	{"name": "Spirit Herb Glade", "kind": "herbs", "zone": "south", "n": 20, "r": 9},
	{"name": "Moonpetal Hollow", "kind": "herbs", "zone": "middle", "n": 18, "r": 8},
	{"name": "Highland Herb Terraces", "kind": "herbs", "zone": "north", "n": 16, "r": 8},
	{"name": "The Iron Seam", "kind": "ore", "zone": "middle", "n": 14, "r": 8},
	{"name": "Glass Scree", "kind": "ore", "zone": "north", "n": 12, "r": 8},
	{"name": "Reed Bend", "kind": "reeds", "zone": "river", "n": 9, "r": 0},
]
## zone -> [[map letter, enemy id], ...]; ids are the hand-made floors 1-9,
## so they're always in data/enemies.json
const ZONES := {
	"south": [["a", "goblin"], ["d", "cave_hare"], ["e", "tunnel_boar"]],
	"middle": [["g", "mine_crawler"], ["i", "skeleton"], ["j", "moss_stag"]],
	"north": [["k", "thornling"], ["m", "cinder_imp"], ["n", "clay_soldier"], ["q", "steel_crow"]],
}


static func sc(v: int) -> int:
	## a coordinate on the old plan, spread
	return int(round(v * SPREAD))


static func sc2(v: Vector2i) -> Vector2i:
	return Vector2i(sc(v.x), sc(v.y))


static func area() -> float:
	return SPREAD * SPREAD


static func make_def(V: Dictionary, enemy_ids: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("valley-of-eliet:v1")
	var g := []
	for y in H:
		var row := []
		for x in W:
			row.append("." if x >= 2 and x < W - 2 and y >= 2 and y < H - 2 else " ")
		g.append(row)
	var reserved := {}           # cells nothing random may land on
	var set_ := func(x: int, y: int, ch: String) -> void:
		if x >= 2 and x < W - 2 and y >= 2 and y < H - 2:
			g[y][x] = ch
	# ---- the river, east to west, and its banks
	var river_y := {}
	for x in range(2, W - 2):
		var ry := sc(60) + int(round(3.0 * sin(x / 9.0)))
		river_y[x] = ry
		for y in range(ry - 1, ry + 2):
			set_.call(x, y, "~")
			reserved[Vector2i(x, y)] = true
	# ---- roads (they bridge the river where they cross it)
	var road := func(x0: int, y0: int, x1: int, y1: int) -> void:
		var x := x0
		var y := y0
		while true:
			for w in 2:
				var cx := x + (w if y0 != y1 and x0 == x1 else 0)
				var cy := y + (w if x0 != x1 and y0 == y1 else 0)
				set_.call(cx, cy, ",")
				reserved[Vector2i(cx, cy)] = true
			if x == x1 and y == y1:
				break
			x += signi(x1 - x)
			y += signi(y1 - y)
	var mid := sc(63)
	road.call(mid, H - 4, mid, sc(14))          # the north road, out of Eliet to the Pagoda
	road.call(sc(20), sc(84), sc(108), sc(84))  # the southern way
	road.call(sc(14), sc(48), sc(114), sc(48))  # the river way
	road.call(sc(30), sc(24), sc(98), sc(24))   # the high way
	road.call(sc(40), sc(84), sc(40), sc(48))   # the west bridge
	road.call(sc(88), sc(84), sc(88), sc(48))   # the east bridge
	road.call(sc(30), sc(24), sc(30), sc(48))
	road.call(sc(98), sc(24), sc(98), sc(48))
	# ---- the gate home
	set_.call(mid, H - 3, "<")
	set_.call(mid + 1, H - 5, "P")
	reserved[Vector2i(mid, H - 3)] = true
	# ---- sect seats
	var npcs := {}
	var sects_out := []
	var letters := NPC_LETTERS
	var li := 0
	for s in V.get("sects", []):
		var slot := int(s.get("slot", sects_out.size()))
		if slot < 0 or slot >= SECT_SLOTS.size():
			continue
		var c: Vector2i = SECT_SLOTS[slot]
		_stamp_compound(g, c, reserved)
		# a short path from the gate to the nearest road
		var gy := c.y + 7
		var road_y := sc(84) if c.y > sc(60) else (sc(48) if c.y > sc(30) else sc(24))
		var span := range(gy, road_y + 1) if road_y > gy else range(road_y, gy + 1)
		for y in span:
			for dx in [-1, 0]:
				set_.call(c.x + dx, y, ",")
				reserved[Vector2i(c.x + dx, y)] = true
		var el := str(s.get("element", "earth"))
		var e_l := letters[li % letters.length()]
		li += 1
		set_.call(c.x, c.y - 3, e_l)
		var elder: Dictionary = s.get("elder", {})
		npcs[e_l] = {"name": str(elder.get("name", "the Elder")), "role": "sect", "sect": str(s["id"]),
			"persona": I18n.t("%s, elder of the %s (a %s sect in the hills above Eliet). %s Their creed: %s") % [elder.get("name", I18n.t("the Elder")), s.get("name", ""), el,
				elder.get("persona", ""), str(s.get("creed", "")).left(300)],
			"line": "\"%s\"" % str(s.get("creed", "")).get_slice(".", 0).strip_edges() + "."}
		var discs: Array = s.get("disciples", [])
		for k in 2:
			var d_l := letters[li % letters.length()]
			li += 1
			var dx := -5 if k == 0 else 5
			set_.call(c.x + dx, c.y + 2, d_l)
			npcs[d_l] = {"name": str(discs[k]) if k < discs.size() else "Disciple", "role": "villager", "sect": str(s["id"]), "stays": true,
				"persona": I18n.t("%s, a young disciple of the %s. Proud of the sect, a little homesick, serious about training. The sect's way with nanites: %s") % [
					discs[k] if k < discs.size() else "a disciple", s.get("name", ""), str(s.get("nanite_way", "")).left(200)],
				"line": I18n.t("We of the %s train from dawn. %s") % [s.get("name", ""), str(s.get("seat", "")).left(120)]}
		sects_out.append({"id": str(s["id"]), "slot": slot, "cell": [c.x, c.y - 1], "element": el})
	# ---- towers
	var exits := {"<": {"to": "village", "arrive": "@valley", "label": "Back to Eliet", "down": false}}
	var towers_out := []
	for t in V.get("towers", []):
		var slot := int(t.get("slot", towers_out.size()))
		if slot < 0 or slot >= TOWER_SLOTS.size():
			continue
		var c: Vector2i = TOWER_SLOTS[slot]
		var r: int = TOWER_RADIUS[slot]
		for y in range(c.y - r - 1, c.y + r + 2):
			for x in range(c.x - r - 1, c.x + r + 2):
				if g[y][x] != "~":
					set_.call(x, y, ".")
				reserved[Vector2i(x, y)] = true
		var north := slot == 0           # the Stair's road runs above it; the others' below
		var door := Vector2i(c.x, c.y - r - 1) if north else Vector2i(c.x, c.y + r + 1)
		var dl := str(slot + 1)
		set_.call(door.x, door.y, dl)
		exits[dl] = {"to": "tower:%s:1" % t["id"], "arrive": "<", "label": str(t.get("name", "a tower")), "down": false}
		# a path from the door down to the nearest road
		var step_y := -1 if north else 1
		var ry := door.y + step_y
		while ry > 2 and ry < H - 2 and g[ry][door.x] != ",":
			set_.call(door.x, ry, ",")
			reserved[Vector2i(door.x, ry)] = true
			ry += step_y
			if absi(ry - door.y) > sc(12):
				break
		towers_out.append({"id": str(t["id"]), "slot": slot, "cell": [c.x, c.y], "radius": r, "tier": int(t.get("tier", slot + 1)), "door": [door.x, door.y]})
	# ---- a wayside shrine, and lanterns along the north road
	set_.call(mid + 4, sc(70), "Z")
	reserved[Vector2i(mid + 4, sc(70))] = true
	for y in range(sc(18), H - 6, 9):
		if g[y][mid - 2] == ".":
			set_.call(mid - 2, y, "L")
		if g[y][mid + 3] == ".":
			set_.call(mid + 3, y, "L")
	# ---- fishing on the banks
	for i in int(6 * SPREAD):
		var x := rng.randi_range(6, W - 7)
		if g[river_y[x] - 2][x] == ".":
			g[river_y[x] - 1][x] = "&"
	# ---- woods, rocks, herbs, ore, gems
	var free := func(x: int, y: int) -> bool:
		return x >= 3 and x < W - 3 and y >= 3 and y < H - 3 and g[y][x] == "." and not reserved.has(Vector2i(x, y))
	for k in int(22 * area()):
		var cx := rng.randi_range(6, W - 7)
		var cy := rng.randi_range(6, H - 8)
		for i in rng.randi_range(10, 26):
			var x := cx + rng.randi_range(-6, 6)
			var y := cy + rng.randi_range(-5, 5)
			if free.call(x, y) and absi(x - mid) > 3:
				g[y][x] = "t"
	var scatter := func(ch: String, n: int, y_lo: int, y_hi: int) -> void:
		var placed := 0
		var tries := 0
		while placed < n and tries < n * 40:
			tries += 1
			var x := rng.randi_range(4, W - 5)
			var y := rng.randi_range(y_lo, y_hi)
			if free.call(x, y) and free.call(x + 1, y) and free.call(x - 1, y):
				g[y][x] = ch
				placed += 1
	scatter.call("x", int(55 * area()), 4, H - 6)
	scatter.call("h", int(34 * area()), sc(30), H - 8)
	scatter.call("h", int(12 * area()), 4, sc(30))
	scatter.call("o", int(10 * area()), 4, sc(34))
	scatter.call("^", int(4 * area()), 4, sc(22))
	# ---- the valley's creatures, by zone
	var enemies := {}
	var zone_rows := {"south": [sc(66), H - 14], "middle": [sc(30), sc(56)], "north": [4, sc(28)]}
	var zone_n := {"south": int(12 * area()), "middle": int(12 * area()), "north": int(12 * area())}
	for z in ZONES:
		var rows: Array = ZONES[z]
		var ok := []
		for r in rows:
			if enemy_ids.has(str(r[1])):
				enemies[str(r[0])] = str(r[1])
				ok.append(str(r[0]))
		if ok.is_empty():
			continue
		var placed := 0
		var tries := 0
		while placed < int(zone_n[z]) and tries < 1400:
			tries += 1
			var x := rng.randi_range(5, W - 6)
			var y := rng.randi_range(int(zone_rows[z][0]), int(zone_rows[z][1]))
			if not free.call(x, y) or (absi(x - mid) < 14 and y > H - 16):
				continue
			var near_seat := false
			for c in SECT_SLOTS:
				if absi(c.x - x) < 14 and absi(c.y - y) < 11:
					near_seat = true
			if near_seat:
				continue
			g[y][x] = ok[placed % ok.size()]
			placed += 1
	# ---- landmarks (Landmark.gd): Dev's places, spread across the valley
	var extras := []
	var lms: Array = V.get("landmarks", [])
	var lmi := 0
	var ltries := 0
	while lmi < lms.size() and ltries < 8000:
		ltries += 1
		var x := rng.randi_range(8, W - 9)
		var y := rng.randi_range(8, H - 12)
		var clear := true
		var reach := 3 if ltries < 4000 else 2           # (if the valley's crowded, a tighter footing will do)
		for dy in range(-reach - 1, reach + 1):
			for dx in range(-reach, reach + 1):
				if not free.call(x + dx, y + dy):
					clear = false
		for e in extras:
			if absi(int(e["cell"][0]) - x) + absi(int(e["cell"][1]) - y) < (sc(14) if ltries < 4000 else 9):
				clear = false
		if clear and str(lms[lmi].get("kind", "")) == "lake":
			for yy in range(y - 4, y - 1):
				for xx in range(x - 2, x + 3):
					if not free.call(xx, yy):
						clear = false
		if not clear:
			continue
		if str(lms[lmi].get("kind", "")) == "lake":
			# a pond north of the landmark's footing, with a place to fish
			for yy in range(y - 4, y - 1):
				for xx in range(x - 2, x + 3):
					g[yy][xx] = "~"
			g[y - 2][x] = "&"
		for dy in range(-4, 4):
			for dx in range(-3, 4):
				reserved[Vector2i(x + dx, y + dy)] = true
		extras.append({"kind": "landmark", "cell": [x, y], "i": lmi, "index": lmi})
		lmi += 1
	# ---- wonders (Wonder.gd), out in the wild
	var wkinds := ["relic", "echo", "cache", "hermitage", "trial", "cache", "relic", "echo"]
	var wi := 0
	var tries := 0
	while wi < wkinds.size() and tries < 2000:
		tries += 1
		var x := rng.randi_range(6, W - 7)
		var y := rng.randi_range(6, H - 10)
		var clear := true
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if not free.call(x + dx, y + dy):
					clear = false
		for e in extras:
			if absi(int(e["cell"][0]) - x) + absi(int(e["cell"][1]) - y) < sc(16):
				clear = false
		if not clear:
			continue
		extras.append({"kind": wkinds[wi], "cell": [x, y], "i": wi + 100})
		reserved[Vector2i(x, y)] = true
		wi += 1
	# ---- rival disciples (Rival.gd, round 28): by the roads, waiting for someone worth a bout
	var ri := 0
	var rtries := 0
	while ri < 3 and rtries < 3000:
		rtries += 1
		var x := rng.randi_range(10, W - 11)
		var y := rng.randi_range(10, H - 12)
		var clear := true
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if not free.call(x + dx, y + dy):
					clear = false
		for e in extras:
			if absi(int(e["cell"][0]) - x) + absi(int(e["cell"][1]) - y) < 12:
				clear = false
		if not clear:
			continue
		extras.append({"kind": "rival", "cell": [x, y], "i": 200 + ri, "index": ri})
		reserved[Vector2i(x, y)] = true
		ri += 1
	# ---- round 150: hunting and gathering grounds, each set well away from every hall, tower and other ground
	var grounds_out := []
	var zrows := {"south": [sc(66), H - 16], "middle": [sc(30), sc(56)], "north": [8, sc(28)]}
	for gd in GROUNDS:
		var rad := int(gd["r"])
		var zname := str(gd["zone"])
		if zname == "river":
			var placed_r := 0
			var rt := 0
			var rx0 := rng.randi_range(12, W - 40)
			while placed_r < int(gd["n"]) and rt < 600:
				rt += 1
				var rx := rx0 + rng.randi_range(0, 30)
				if rx < 6 or rx > W - 7:
					continue
				var by: int = river_y[rx] - 2
				if g[by][rx] == "." and not reserved.has(Vector2i(rx, by)) and g[by + 1][rx] == "~":
					g[by][rx] = "&"
					reserved[Vector2i(rx, by)] = true
					placed_r += 1
			if placed_r > 0:
				grounds_out.append({"name": str(gd["name"]), "kind": "reeds", "cell": [rx0 + 15, river_y[clampi(rx0 + 15, 2, W - 3)] - 3], "r": 18})
			continue
		var zr: Array = zrows[zname]
		var spot := Vector2i(-1, -1)
		for t in 4000:
			var x := rng.randi_range(rad + 8, W - rad - 9)
			var y := rng.randi_range(maxi(int(zr[0]), rad + 8), mini(int(zr[1]), H - rad - 10))
			var ok := true
			var open_n := 0
			for k in 24:
				var a := TAU * float(k) / 24.0
				for rr in [0.4, 0.8]:
					if free.call(x + int(cos(a) * rad * rr), y + int(sin(a) * rad * rr)):
						open_n += 1
			if open_n < 40:
				continue
			var far_g := sc(26) if t < 2500 else sc(16)
			for sl in SECT_SLOTS + TOWER_SLOTS:
				if absi(sl.x - x) + absi(sl.y - y) < sc(18) + rad:
					ok = false
			for e in extras:
				if absi(int(e["cell"][0]) - x) + absi(int(e["cell"][1]) - y) < rad + 8:
					ok = false
			for o in grounds_out:
				if absi(int(o["cell"][0]) - x) + absi(int(o["cell"][1]) - y) < far_g:
					ok = false
			if ok and absi(x - mid) > 12 and not (y > H - 22):
				spot = Vector2i(x, y)
				break
		if spot.x < 0:
			continue
		var kind := str(gd["kind"])
		var cells := []
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				if float(dx * dx + dy * dy) <= float(rad * rad) * 0.9:
					var cx2 := spot.x + dx
					var cy2 := spot.y + dy
					if free.call(cx2, cy2):
						cells.append(Vector2i(cx2, cy2))
					elif cx2 >= 3 and cx2 < W - 3 and cy2 >= 3 and cy2 < H - 3 and g[cy2][cx2] == "t":
						g[cy2][cx2] = "."          # a clearing: the grounds are open country
						cells.append(Vector2i(cx2, cy2))
		var want := int(gd["n"])
		var put := 0
		var tries2 := 0
		while put < want and tries2 < want * 40 and not cells.is_empty():
			tries2 += 1
			var c: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
			if g[c.y][c.x] != "." or not free.call(c.x + 1, c.y) or not free.call(c.x - 1, c.y):
				continue
			if kind == "hunt":
				var gl := str(gd["game"])[put % str(gd["game"]).length()]
				if not enemy_ids.has(str(GAME[gl])):
					break
				g[c.y][c.x] = gl
				enemies[gl] = str(GAME[gl])
			elif kind == "herbs":
				g[c.y][c.x] = "h"
			else:
				g[c.y][c.x] = "o" if put % 4 != 3 else "^"
			put += 1
		for dy in range(-rad - 2, rad + 3):
			for dx in range(-rad - 2, rad + 3):
				reserved[Vector2i(spot.x + dx, spot.y + dy)] = true
		if kind != "hunt":
			for q in [Vector2i(-rad, 0), Vector2i(rad, 0)]:
				if free.call(spot.x + q.x, spot.y + q.y):
					g[spot.y + q.y][spot.x + q.x] = "L"        # a lantern at each end, so the ground can be found by night
		grounds_out.append({"name": str(gd["name"]), "kind": kind, "cell": [spot.x, spot.y], "r": rad})
	# ---- round 123: ways out to the tech frontier, set far from everything else (and different each in where they sit)
	var FR := preload("res://scripts/world/Frontier.gd")
	var frng := RandomNumberGenerator.new()
	frng.seed = hash("valley-frontier:v1")
	var site_cells := []
	for st in FR.data().get("sites", []):
		var box: Array = st.get("box", [0.1, 0.1, 0.9, 0.9])
		for t in 6000:
			var sx := frng.randi_range(int(W * float(box[0])), int(W * float(box[2])))
			var sy := frng.randi_range(int(H * float(box[1])), int(H * float(box[3])))
			var ok := true
			for dy in range(-4, 5):
				for dx in range(-4, 5):
					if not free.call(sx + dx, sy + dy):
						ok = false
			if not ok:
				continue
			var far := sc(22) if t < 3000 else sc(12)
			for e in extras:
				if absi(int(e["cell"][0]) - sx) + absi(int(e["cell"][1]) - sy) < far:
					ok = false
			for sl in SECT_SLOTS + TOWER_SLOTS:
				if absi(sl.x - sx) + absi(sl.y - sy) < far:
					ok = false
			for oc in site_cells:
				if absi(oc.x - sx) + absi(oc.y - sy) < sc(40):
					ok = false
			if not ok:
				continue
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					g[sy + dy][sx + dx] = "."
					reserved[Vector2i(sx + dx, sy + dy)] = true
			g[sy][sx] = str(st["char"])
			for q in [Vector2i(-3, -3), Vector2i(3, -3), Vector2i(-3, 3), Vector2i(3, 3)]:
				g[sy + q.y][sx + q.x] = "L"
			# a trodden way to the nearest road, so it can be found by following the land
			var ty := sy + 4
			var dirn := 1
			var best_road := 99999
			for rr in [sc(24), sc(48), sc(84)]:
				if absi(rr - sy) < best_road:
					best_road = absi(rr - sy)
					dirn = 1 if rr > sy else -1
			ty = sy + 4 * dirn
			var steps := 0
			while ty > 2 and ty < H - 2 and g[ty][sx] != "," and steps < sc(40):
				if g[ty][sx] == "." or g[ty][sx] == "t":
					g[ty][sx] = ","
					reserved[Vector2i(sx, ty)] = true
				elif g[ty][sx] == "~":
					break
				ty += dirn
				steps += 1
			exits[str(st["char"])] = {"to": "frontier:%s" % str(st["to"]), "arrive": str(st.get("arrive", "<")), "label": str(st.get("label", "")), "down": false, "style": str(st.get("style", "hatch"))}
			site_cells.append(Vector2i(sx, sy))
			break
	var out := []
	for row in g:
		out.append("".join(PackedStringArray(row)))
	return {"id": "valley", "name": "The Valley of Eliet", "theme": "wilds", "look": "village", "depth": 3, "no_expand": true, "spread": SPREAD,
		"map": out, "enemies": enemies, "npcs": npcs, "exits": exits, "extras": extras, "sects": sects_out, "towers": towers_out, "grounds": grounds_out}


static func _stamp_compound(g: Array, c: Vector2i, reserved: Dictionary) -> void:
	## a walled yard 21x15 around c: a ring of rock (the auto-walls make it
	## crag), a three-wide gate in the south side, a hall of house blocks
	## along the north, banners, lights, a tree in each corner
	for y in range(c.y - 7, c.y + 8):
		for x in range(c.x - 10, c.x + 11):
			reserved[Vector2i(x, y)] = true
			var edge := y == c.y - 7 or y == c.y + 7 or x == c.x - 10 or x == c.x + 10
			if edge and not (y == c.y + 7 and absi(x - c.x) <= 1):
				g[y][x] = "#"           # dressed stone (Level._wall in the wilds)
			else:
				g[y][x] = "."
	for y in range(c.y - 6, c.y - 4):
		for x in range(c.x - 5, c.x + 6):
			g[y][x] = "H"
	g[c.y - 4][c.x - 3] = "="
	g[c.y - 4][c.x + 3] = "="
	for q in [Vector2i(c.x - 8, c.y - 5), Vector2i(c.x + 8, c.y - 5), Vector2i(c.x - 2, c.y + 6), Vector2i(c.x + 2, c.y + 6)]:
		g[q.y][q.x] = "L"
	for q in [Vector2i(c.x - 9, c.y + 6), Vector2i(c.x + 9, c.y + 6), Vector2i(c.x - 9, c.y - 6), Vector2i(c.x + 9, c.y - 6)]:
		g[q.y][q.x] = "t"

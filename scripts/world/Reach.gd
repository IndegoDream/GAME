extends RefCounted
## Reach: the deep goes on past the edge of every floor (round 56).
## Robert, 2026-10-05: "give the world more depth -- more ground to cover,
## more diverse."
##
## When a dungeon floor is BUILT (after Expanse's side chambers), Reach grows
## one or two REACHES onto it: a wide natural region past the right (or
## bottom) edge of the map -- a cave grown by a cellular automaton, not drawn
## rooms -- joined to the floor by a winding tunnel through the rock. Each
## reach is a different land from the floor around it (data/reaches.json
## "biomes"): an underground lake with causeways between islands, a wood of
## giant glowing mushrooms, crystal hollows, a cathedral of roots, a rift of
## slow fire, fields of bones, a frozen gallery, a sunken street of an old
## city, a chasm where lightning lives, old mine workings. Its own ground and
## walls, its own light and air (ReachZone.gd), its own things to gather and
## things that live there, and a HEART at the far end where a warden keeps
## what the reach gathered (ReachHeart.gd).
##
## Map characters it writes (all ones Level.gd already knows):
##   .  floor      ~  water (frozen in the Frost Gallery)   &  a place to fish
##   %  fire (the Ember Rift's lava: solid, glowing)        L  light
##   x  a big growth (a giant mushroom, crystal, root, pillar ...)  c  a column of the land
##   h o ^  herbs, ore, gems    T  a trap   and the floor's own foe letters
## Deterministic: seeded by the floor's id, so a reach is where you left it.
## Level files on the box are never touched -- this runs on the copy being built.

const DATA := "res://data/reaches.json"
const OPENISH := [".", ",", "L", "h", "o", "^", "&", "T", "P", "S", "x", "c", "b"]

static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var t := FileAccess.get_file_as_string(DATA)
		var d = JSON.parse_string(t) if t != "" else null
		_data = d if d is Dictionary else {"biomes": {}}
		# Dev's words for each land, when the writing room has them (data/drafts/reaches.json)
		var dt := FileAccess.get_file_as_string("res://data/drafts/reaches.json") if FileAccess.file_exists("res://data/drafts/reaches.json") else ""
		var dr = JSON.parse_string(dt) if dt != "" else null
		if dr is Dictionary and _data.get("biomes", {}) is Dictionary:
			for it in dr.get("items", []):
				if it is Dictionary and _data["biomes"].has(str(it.get("id", ""))) and str(it.get("text", "")).strip_edges() != "":
					_data["biomes"][str(it["id"])]["desc"] = str(it["text"]).strip_edges()
	return _data


static func should_reach(d: Dictionary) -> bool:
	if bool(d.get("arena", false)) or bool(d.get("no_expand", false)) or bool(d.get("no_reach", false)) or bool(d.get("reached", false)):
		return false
	if bool(d.get("tribulation", false)):
		return false
	if str(d.get("theme", "dungeon")) in ["village", "settlement", "wilds"]:
		return false
	return str(d.get("id", "")).begins_with("floor")


static func biome(key: String) -> Dictionary:
	return data().get("biomes", {}).get(key, {})


static func extend(d: Dictionary, look_key: String = "") -> Dictionary:
	if not should_reach(d):
		return d
	var D := data()
	var biomes: Dictionary = D.get("biomes", {})
	if biomes.is_empty():
		return d
	var src: Array = d.get("map", [])
	if src.size() < 6:
		return d
	var w := 0
	for r in src:
		w = maxi(w, str(r).length())
	var h := src.size()
	var depth := maxi(1, int(d.get("depth", int(str(d.get("id", "floor1")).trim_prefix("floor")))))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(d.get("id", "")) + ":reach:" + str(w) + "x" + str(h))
	var n := 1
	if depth >= int(D.get("second_from_depth", 12)) and rng.randf() < float(D.get("second_chance", 0.55)):
		n = 2
	# which lands: never the floor's own look; spread across the deep by floor
	var keys := biomes.keys()
	keys.sort()
	var pool := keys.filter(func(k): return str(biomes[k].get("look", "")) != look_key)
	if pool.is_empty():
		pool = keys
	var start := (depth * 7 + int(absi(hash(str(d.get("id", ""))))) % 5) % pool.size()
	var picks := []
	for i in n:
		picks.append(str(pool[(start + i * 3) % pool.size()]))
	# the grid, with room to grow right and down
	var sz: Dictionary = D.get("size", {})
	var tdep := clampf(float(depth - 1) / 49.0, 0.0, 1.0)
	var gap_r: Array = D.get("gap", [4, 7])
	var maxw := 0
	var maxh := 0
	var sizes := []
	for i in n:
		var rw := int(lerpf(float(sz.get("w", [44, 66])[0]), float(sz.get("w", [44, 66])[1]), tdep)) + rng.randi_range(-int(sz.get("jitter", 4)), int(sz.get("jitter", 4)))
		var rh := int(lerpf(float(sz.get("h", [32, 44])[0]), float(sz.get("h", [32, 44])[1]), tdep)) + rng.randi_range(-int(sz.get("jitter", 4)), int(sz.get("jitter", 4)))
		sizes.append(Vector2i(rw, rh))
		maxw = maxi(maxw, rw)
		maxh = maxi(maxh, rh)
	var W := w + int(gap_r[1]) + maxw + 3
	var H := h + int(gap_r[1]) + maxh + 3
	var g := []
	for y in H:
		var row := []
		var s := str(src[y]) if y < h else ""
		for x in W:
			row.append(s[x] if x < s.length() else " ")
		g.append(row)
	var old := {}
	for y in h:
		for x in w:
			var ch: String = g[y][x]
			if ch != " " and ch != "#":
				old[Vector2i(x, y)] = true
	if old.size() < 40:
		return d
	var foes := _foe_letters(d)
	var reaches := []
	var extras: Array = (d.get("extras", []) as Array).duplicate(true)
	for i in n:
		var bk: String = picks[i]
		var B: Dictionary = biomes[bk]
		var size: Vector2i = sizes[i]
		var gap := rng.randi_range(int(gap_r[0]), int(gap_r[1]))
		var origin: Vector2i
		if i == 0:
			origin = Vector2i(w + gap, rng.randi_range(0, maxi(0, h - size.y)))
		else:
			origin = Vector2i(rng.randi_range(0, maxi(0, w - size.x)), h + gap)
		var region := _cave(size, float(B.get("fill", 0.45)), rng, float(D.get("min_open_share", 0.28)))
		if region.is_empty():
			continue
		# stamp it
		var cells := []
		for c in region:
			var q: Vector2i = origin + c
			g[q.y][q.x] = "."
			cells.append(q)
		# the way in: a winding tunnel from the floor to the reach
		var tunnel := _tunnel(g, cells, old, rng)
		if tunnel.is_empty():
			for q in cells:
				g[q.y][q.x] = " "
			continue
		for q in tunnel:
			g[q.y][q.x] = "."
		var mouth: Vector2i = tunnel[tunnel.size() - 1] if tunnel.size() > 0 else cells[0]
		var entry: Vector2i = tunnel[0]
		# water, fire, frozen pools -- with causeways so every island is reachable
		if B.has("water"):
			_pools(g, cells, B["water"], "~", rng, entry)
		if B.has("lava"):
			_pools(g, cells, B["lava"], "%", rng, entry)
		var allowed := {}
		for q0 in cells:
			allowed[q0] = true
		for q0 in tunnel:
			allowed[q0] = true
		var dist := _distances(g, entry, allowed)
		var open := cells.filter(func(q): return g[q.y][q.x] == "." and dist.has(q))
		if open.size() < 60:
			continue
		# the heart: as far from the way in as the reach goes
		var heart: Vector2i = open[0]
		for q in open:
			if int(dist[q]) > int(dist.get(heart, 0)):
				heart = q
		var reserved := {}
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				reserved[heart + Vector2i(dx, dy)] = true
		for q in tunnel:
			reserved[q] = true
		var free := open.filter(func(q): return not reserved.has(q) and _open_around(g, q) >= 7)
		_shuffle(free, rng)
		var per: Dictionary = D.get("per_cells", {})
		var lim: Dictionary = D.get("limits", {})
		var cnt := open.size()
		# lights, spread out (the farthest-first pick)
		var nl := clampi(cnt / int(per.get("light", 70)), int(lim.get("light", [4, 12])[0]), int(lim.get("light", [4, 12])[1]))
		for q in _spread(free, nl, rng):
			g[q.y][q.x] = "L"
		free = free.filter(func(q): return g[q.y][q.x] == ".")
		# what grows and stands here
		var bper: Dictionary = B.get("per", {})
		for ch in ["x", "c", "h", "o", "^"]:
			var every := int(bper.get(ch, 0))
			if every <= 0:
				continue
			var k := cnt / every
			for j in k:
				if free.is_empty():
					break
				var q: Vector2i = free.pop_back()
				g[q.y][q.x] = ch
		# fishing spots: shore water next to land
		if int(bper.get("&", 0)) > 0:
			var shore := []
			for q in cells:
				if g[q.y][q.x] == "~":
					for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var nn: Vector2i = q + dir
						if g[nn.y][nn.x] == "." and dist.has(nn):
							shore.append(q)
							break
			_shuffle(shore, rng)
			for j in mini(shore.size(), cnt / int(bper["&"])):
				var q2: Vector2i = shore[j]
				g[q2.y][q2.x] = "&"
		# who lives here: the floor's own, away from the tunnel's mouth
		var nf := clampi(cnt / int(per.get("foe", 85)), int(lim.get("foe", [4, 14])[0]), int(lim.get("foe", [4, 14])[1]))
		if not foes.is_empty():
			var far := free.filter(func(q): return int(dist.get(q, 0)) >= 8 and g[q.y][q.x] == ".")
			for j in mini(nf, far.size()):
				var q3: Vector2i = far[j]
				g[q3.y][q3.x] = str(foes[(j * 7 + rng.randi()) % foes.size()])
		var nt := clampi(cnt / int(per.get("trap", 260)), int(lim.get("trap", [0, 3])[0]), int(lim.get("trap", [0, 3])[1]))
		var tfree := free.filter(func(q): return g[q.y][q.x] == "." and int(dist.get(q, 0)) >= 6)
		for j in mini(nt, tfree.size()):
			var q4: Vector2i = tfree[tfree.size() - 1 - j]
			g[q4.y][q4.x] = "T"
		# nothing the land grew may wall a pocket off (a growth that does goes back to floor)
		_unpocket(g, allowed, entry)
		# the heart's clearing stays clear
		for q5 in reserved:
			if q5.y >= 0 and q5.y < H and q5.x >= 0 and q5.x < W and g[q5.y][q5.x] not in [" ", "~", "%", "&"] and not tunnel.has(q5):
				g[q5.y][q5.x] = "."
		var rect := Rect2i(origin - Vector2i(1, 1), size + Vector2i(2, 2))
		reaches.append({"biome": bk, "name": str(B.get("name", bk)), "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
			"mouth": [mouth.x, mouth.y], "entry": [entry.x, entry.y], "heart": [heart.x, heart.y], "i": i, "cells": cnt,
			"tunnel": tunnel.map(func(q): return [q.x, q.y])})
		extras.append({"kind": "reach_heart", "cell": [heart.x, heart.y], "biome": bk, "i": i})
		for q6 in cells:
			old[q6] = true
	if reaches.is_empty():
		return d
	# trim the padding nothing grew into
	var last_row := h - 1
	var last_col := w - 1
	for y in H:
		for x in W:
			if g[y][x] != " ":
				last_row = maxi(last_row, y)
				last_col = maxi(last_col, x)
	var out := []
	for y in range(0, last_row + 2):
		out.append("".join(PackedStringArray(g[y].slice(0, last_col + 2))).rstrip(" "))
	var d2 := d.duplicate()
	d2["map"] = out
	d2["reaches"] = reaches
	d2["extras"] = extras
	d2["reached"] = true
	return d2


# ---- the shapes --------------------------------------------------------------------------

static func _cave(size: Vector2i, fill: float, rng: RandomNumberGenerator, min_share: float) -> Array:
	## a natural cave: random rock, smoothed five times (a cell becomes rock
	## with five or more rock neighbours), then only the biggest connected
	## space is kept. Returns cells relative to the region's corner.
	for attempt in 6:
		var f := fill - attempt * 0.02
		var m := []
		for y in size.y:
			var row := []
			for x in size.x:
				var edge := x == 0 or y == 0 or x == size.x - 1 or y == size.y - 1
				row.append(edge or rng.randf() < f)
			m.append(row)
		for it in 5:
			var nm := []
			for y in size.y:
				var row2 := []
				for x in size.x:
					if x == 0 or y == 0 or x == size.x - 1 or y == size.y - 1:
						row2.append(true)
						continue
					var k := 0
					for dy in [-1, 0, 1]:
						for dx in [-1, 0, 1]:
							if (dx != 0 or dy != 0) and m[y + dy][x + dx]:
								k += 1
					row2.append(k >= 5 or (k == 4 and m[y][x]))
				nm.append(row2)
			m = nm
		# the biggest open space
		var seen := {}
		var best := []
		for y in size.y:
			for x in size.x:
				var c := Vector2i(x, y)
				if m[y][x] or seen.has(c):
					continue
				var comp := []
				var stack := [c]
				seen[c] = true
				while not stack.is_empty():
					var p: Vector2i = stack.pop_back()
					comp.append(p)
					for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var q: Vector2i = p + dir
						if q.x < 0 or q.y < 0 or q.x >= size.x or q.y >= size.y or seen.has(q) or m[q.y][q.x]:
							continue
						seen[q] = true
						stack.append(q)
				if comp.size() > best.size():
					best = comp
		if best.size() >= int(size.x * size.y * min_share):
			return best
	return []


static func _tunnel(g: Array, cells: Array, old: Dictionary, rng: RandomNumberGenerator) -> Array:
	## a way from the reach to the floor, through solid rock only: a search
	## from every cell at the reach's edge, with a little wander in its cost
	## so it bends like a real passage. Returns cells from the reach's side
	## (index 0 touches the reach) to the floor's side (last touches the floor).
	var H := g.size()
	var W: int = g[0].size()
	var inreach := {}
	for c in cells:
		inreach[c] = true
	var buckets := {}                  # cost -> cells (costs are small whole numbers: a bucket queue)
	var cost := {}
	var prev := {}
	for c in cells:
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = c + dir
			if q.x < 1 or q.y < 1 or q.x >= W - 1 or q.y >= H - 1 or inreach.has(q) or g[q.y][q.x] != " ":
				continue
			if not cost.has(q):
				cost[q] = 0
				prev[q] = Vector2i(-1, -1)
				if not buckets.has(0):
					buckets[0] = []
				buckets[0].append(q)
	var noise := {}
	var goal := Vector2i(-1, -1)
	var guard := 0
	var at_cost := 0
	var top := 0
	while guard < 80000 and at_cost <= top:
		var bucket: Array = buckets.get(at_cost, [])
		if bucket.is_empty():
			buckets.erase(at_cost)
			at_cost += 1
			continue
		guard += 1
		var p: Vector2i = bucket.pop_back()
		if at_cost > int(cost.get(p, 1 << 30)):
			continue
		# touching the floor (but never through a wall it already has)
		var touch := false
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + dir
			if old.has(q) and not inreach.has(q) and str(g[q.y][q.x]) in OPENISH and str(g[q.y][q.x]) != "S":
				touch = true
		if touch:
			goal = p
			break
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + dir
			if q.x < 1 or q.y < 1 or q.x >= W - 1 or q.y >= H - 1 or inreach.has(q) or g[q.y][q.x] != " ":
				continue
			# keep a cell of rock between the passage and any other floor (no accidental holes)
			var side_floor := false
			for d2 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var r: Vector2i = q + d2
				if r != p and old.has(r) and not inreach.has(r):
					side_floor = true
			var nz: int
			if noise.has(q):
				nz = noise[q]
			else:
				nz = rng.randi_range(0, 3)
				noise[q] = nz
			var nc := int(cost[p]) + 1 + nz
			if side_floor:
				nc += 0           # (reaching the floor is the point: no penalty for the last step)
			if nc < int(cost.get(q, 1 << 30)):
				cost[q] = nc
				prev[q] = p
				if not buckets.has(nc):
					buckets[nc] = []
				buckets[nc].append(q)
				top = maxi(top, nc)
	if goal.x < 0:
		return []
	var path := []
	var p2 := goal
	while p2.x >= 0:
		path.append(p2)
		p2 = prev.get(p2, Vector2i(-1, -1))
	path.reverse()                       # index 0 is at the reach
	return path


static func _pools(g: Array, cells: Array, spec: Dictionary, ch: String, rng: RandomNumberGenerator, entry: Vector2i) -> void:
	## blobs of water (or fire) in the open; then every bit of land the
	## pools cut off is joined back by a causeway across them
	var cellset := {}
	for c in cells:
		cellset[c] = true
	var blobs := rng.randi_range(int(spec.get("blobs", [2, 3])[0]), int(spec.get("blobs", [2, 3])[1]))
	var ra: Array = spec.get("radius", [3, 6])
	for b in blobs:
		var c: Vector2i = cells[rng.randi() % cells.size()]
		var r := rng.randf_range(float(ra[0]), float(ra[1]))
		for q in cells:
			var dd := Vector2(q - c).length() + rng.randf_range(-0.8, 0.8)
			if dd < r and g[q.y][q.x] == "." and _open_around(g, q) >= 8 and q.distance_to(entry) > 4.0:
				g[q.y][q.x] = ch
	# join cut-off land back to the land around the way in
	for guard in 40:
		var reach := _land_from(g, entry, cellset)
		var lost := []
		for q in cells:
			if g[q.y][q.x] == "." and not reach.has(q):
				lost.append(q)
		if lost.is_empty():
			return
		# a causeway: the shortest run through the pool from the lost piece to the reached land
		var start: Vector2i = lost[0]
		var seen := {start: Vector2i(-1, -1)}
		var queue := [start]
		var found := Vector2i(-1, -1)
		while not queue.is_empty():
			var p: Vector2i = queue.pop_front()
			if reach.has(p):
				found = p
				break
			for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = p + dir
				if seen.has(q) or not cellset.has(q):
					continue
				if g[q.y][q.x] == "." or g[q.y][q.x] == ch:
					seen[q] = p
					queue.append(q)
		if found.x < 0:
			# can't be joined: give it back to the pool
			for q in lost:
				g[q.y][q.x] = ch
			return
		var p3: Vector2i = found
		while p3.x >= 0:
			if g[p3.y][p3.x] == ch:
				g[p3.y][p3.x] = "."
			p3 = seen.get(p3, Vector2i(-1, -1))


static func _land_from(g: Array, start: Vector2i, cellset: Dictionary) -> Dictionary:
	var out := {start: true}
	var stack := [start]
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + dir
			if out.has(q) or not cellset.has(q):
				continue
			if g[q.y][q.x] == ".":
				out[q] = true
				stack.append(q)
	return out


static func _distances(g: Array, start: Vector2i, allowed: Dictionary = {}) -> Dictionary:
	## steps from the way in, over open ground
	var out := {start: 0}
	var queue := [start]
	var H := g.size()
	var W: int = g[0].size()
	while not queue.is_empty():
		var p: Vector2i = queue.pop_front()
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + dir
			if q.x < 0 or q.y < 0 or q.x >= W or q.y >= H or out.has(q):
				continue
			if not allowed.is_empty() and not allowed.has(q):
				continue
			if str(g[q.y][q.x]) in OPENISH:
				out[q] = int(out[p]) + 1
				queue.append(q)
	return out


static func _open_around(g: Array, q: Vector2i) -> int:
	var n := 0
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var y: int = q.y + dy
			var x: int = q.x + dx
			if y >= 0 and y < g.size() and x >= 0 and x < g[y].size() and g[y][x] == ".":
				n += 1
	return n


static func _spread(cells: Array, n: int, rng: RandomNumberGenerator) -> Array:
	## n cells spread as far apart as they'll go
	if cells.is_empty() or n <= 0:
		return []
	var out := [cells[rng.randi() % cells.size()]]
	while out.size() < mini(n, cells.size()):
		var best: Vector2i = cells[0]
		var bd := -1.0
		for c in cells:
			var md := 1e9
			for o in out:
				md = minf(md, Vector2(c - o).length_squared())
			if md > bd:
				bd = md
				best = c
		out.append(best)
	return out


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


static func _foe_letters(d: Dictionary) -> Array:
	## the floor's ordinary foes (no bosses, no passive things)
	var en: Dictionary = d.get("enemies", {})
	var g = Engine.get_main_loop().root.get_node_or_null("Game") if Engine.get_main_loop() is SceneTree else null
	var out := []
	var keys := en.keys()
	keys.sort()
	for k in keys:
		var e: Dictionary = g.enemies.get(str(en[k]), {}) if g else {}
		if not e.is_empty() and not bool(e.get("boss", false)) and not bool(e.get("passive", false)):
			out.append(str(k))
	return out


static func reach_at(d: Dictionary, cell: Vector2i) -> Dictionary:
	## the reach this cell is in ({} if none) -- its rect, or its tunnel
	for r in d.get("reaches", []):
		var rr: Array = r.get("rect", [0, 0, 0, 0])
		if Rect2i(int(rr[0]), int(rr[1]), int(rr[2]), int(rr[3])).has_point(cell):
			return r
	return {}


const BLOCKS := [" ", "#", "x", "c", "~", "%", "&", "b", "S"]


static func _unpocket(g: Array, allowed: Dictionary, entry: Vector2i) -> void:
	## every open cell of the reach must be walkable-to from the way in; a
	## growth or column that shuts one off is taken out (round 57: the audit
	## found single cells sealed off behind growths, now and then with a foe in them)
	for guard in 12:
		var seen := {entry: true}
		var stack := [entry]
		while not stack.is_empty():
			var p: Vector2i = stack.pop_back()
			for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = p + dir
				if seen.has(q) or not allowed.has(q) or str(g[q.y][q.x]) in BLOCKS:
					continue
				seen[q] = true
				stack.append(q)
		var fixed := false
		for c in allowed:
			if seen.has(c) or str(g[c.y][c.x]) in BLOCKS:
				continue
			# a shut-off cell: open the growths around it
			for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + dir
				if allowed.has(n) and str(g[n.y][n.x]) in ["x", "c", "b"]:
					g[n.y][n.x] = "."
					fixed = true
		if not fixed:
			return

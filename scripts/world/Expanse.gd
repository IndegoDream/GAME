extends RefCounted
## Expanse: every dungeon floor, wider than it was drawn.
## Robert, 2026-10-02: "make each floor more expansive and immersive --
## more things to do and explore and find."
##
## The floors themselves are Dev's (the forge writes levels/*.json on the
## box). This doesn't touch them: when a floor is BUILT, Expanse looks for
## the empty rock between its rooms and carves side chambers into it --
## three to six per floor, each joined to the nearest room by a passage,
## one of them sealed behind a secret wall. Each chamber is a small place
## with a reason to go there (data: the "extras" it returns, which
## Level.gd turns into Wonder.gd nodes):
##
##   relic      a nanite relic -- draw the swarm out of the old machine
##   hermitage  a quiet alcove -- meditation runs half again as deep here
##   echo       an echo stone -- watch an old fight; a glimpse of an art
##   cache      a buried cache -- loose stones; Spirit Sense shows it
##   grotto     a glowing pool -- herbs, fish, and (at night) Moonwater
##   lair       something lives here -- a fight, and what it guarded
##   trial      an altar of trial -- call a fight, beat it in time, be paid
##
## Deterministic: the same floor always grows the same chambers (seeded by
## its id and its map), so they're where you left them. The map only ever
## grows right and down (nothing already on it moves).

const KINDS_CORE := ["relic", "hermitage", "echo", "cache"]
const KINDS_MORE := ["grotto", "lair", "trial"]
const PAD := 18


static func should_expand(d: Dictionary) -> bool:
	if bool(d.get("arena", false)) or bool(d.get("no_expand", false)) or bool(d.get("expanded", false)):
		return false
	if str(d.get("theme", "dungeon")) in ["village", "settlement"]:
		return false
	return str(d.get("id", "")).begins_with("floor")


static func expand(d: Dictionary) -> Dictionary:
	if not should_expand(d):
		return d
	var src: Array = d.get("map", [])
	if src.is_empty():
		return d
	var w := 0
	for r in src:
		w = maxi(w, str(r).length())
	var h := src.size()
	var W := w + PAD
	var H := h + PAD
	var g := []                 # g[y][x] -> one-character String
	for y in H:
		var row := []
		var s := str(src[y]) if y < h else ""
		for x in W:
			row.append(s[x] if x < s.length() else " ")
		g.append(row)
	var floor_cells := []
	for y in h:
		for x in w:
			if g[y][x] != " " and g[y][x] != "#":
				floor_cells.append(Vector2i(x, y))
	if floor_cells.size() < 40:
		return d
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(d.get("id", "")) + ":expanse:" + str(floor_cells.size()))
	var want := clampi(floor_cells.size() / 300 + 3, 3, 6)
	var kinds := KINDS_CORE.duplicate()
	var more := KINDS_MORE.duplicate()
	for i in more.size():
		var j := rng.randi_range(i, more.size() - 1)
		var t = more[i]
		more[i] = more[j]
		more[j] = t
	kinds += more
	kinds = kinds.slice(0, want)
	var weak := _weak_letter(d)
	var extras := []
	var sealed := false
	var made := 0
	for kind in kinds:
		var placed := false
		for attempt in 500:
			var cw := rng.randi_range(7, 11)
			var chh := rng.randi_range(6, 8)
			var x0 := rng.randi_range(2, W - cw - 3)
			var y0 := rng.randi_range(2, H - chh - 3)
			if not _clear(g, x0 - 2, y0 - 2, cw + 4, chh + 4):
				continue
			var c := Vector2i(x0 + cw / 2, y0 + chh / 2)
			var tgt := _nearest(floor_cells, c, 34)
			if tgt.x < 0:
				continue
			var path := _corridor(g, c, tgt, Rect2i(x0, y0, cw, chh))
			if path.is_empty():
				continue
			# carve the chamber and its passage
			for yy in range(y0, y0 + chh):
				for xx in range(x0, x0 + cw):
					g[yy][xx] = "."
			for p in path:
				g[p.y][p.x] = "."
			# one chamber per floor hides behind a secret wall, where its
			# passage meets the old floor
			if not sealed and kind != "lair" and path.size() >= 3:
				var last: Vector2i = path[path.size() - 1]
				g[last.y][last.x] = "S"
				sealed = true
			_furnish(g, kind, Rect2i(x0, y0, cw, chh), rng, weak)
			extras.append({"kind": kind, "cell": [c.x, c.y], "i": made, "sealed": g[path[path.size() - 1].y][path[path.size() - 1].x] == "S"})
			for yy in range(y0, y0 + chh):
				for xx in range(x0, x0 + cw):
					floor_cells.append(Vector2i(xx, yy))
			made += 1
			placed = true
			break
		if not placed:
			continue
	if extras.is_empty():
		return d
	# trim the padding that nothing grew into
	var last_row := 0
	var last_col := 0
	for y in H:
		for x in W:
			if g[y][x] != " ":
				last_row = maxi(last_row, y)
				last_col = maxi(last_col, x)
	var out := []
	for y in range(0, maxi(last_row + 2, h)):
		var s := "".join(PackedStringArray(g[y].slice(0, maxi(last_col + 2, w))))
		out.append(s.rstrip(" "))
	var d2 := d.duplicate()
	d2["map"] = out
	d2["extras"] = extras
	d2["expanded"] = true
	return d2


static func _weak_letter(d: Dictionary) -> String:
	## the floor's ordinary foe (for a lair)
	var en: Dictionary = d.get("enemies", {})
	var g = Engine.get_main_loop().root.get_node_or_null("Game") if Engine.get_main_loop() is SceneTree else null
	var keys := en.keys()
	keys.sort()
	if en.has("g"):
		keys.erase("g")
		keys.insert(0, "g")
	for k in keys:
		var e: Dictionary = g.enemies.get(str(en[k]), {}) if g else {}
		if not e.is_empty() and not bool(e.get("boss", false)) and not bool(e.get("passive", false)):
			return str(k)
	return ""


static func _clear(g: Array, x: int, y: int, w: int, h: int) -> bool:
	if x < 0 or y < 0 or y + h > g.size() or x + w > g[0].size():
		return false
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			if g[yy][xx] != " ":
				return false
	return true


static func _nearest(cells: Array, c: Vector2i, limit: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bd := limit + 1
	for q in cells:
		var dd: int = absi(q.x - c.x) + absi(q.y - c.y)
		if dd < bd:
			bd = dd
			best = q
	return best


static func _corridor(g: Array, from: Vector2i, to: Vector2i, room: Rect2i) -> Array:
	## an L-shaped passage from the chamber's centre to the old floor: the
	## cells outside the chamber, ending on the last rock cell before the
	## floor it reaches. Empty if it would have to cut through anything.
	var cells := []
	var p := from
	var steps := 0
	var horizontal_first := absi(to.x - from.x) >= absi(to.y - from.y)
	for leg in 2:
		var along_x := horizontal_first if leg == 0 else not horizontal_first
		while (p.x != to.x) if along_x else (p.y != to.y):
			if along_x:
				p.x += signi(to.x - p.x)
			else:
				p.y += signi(to.y - p.y)
			steps += 1
			if steps > 80:
				return []
			if room.has_point(p):
				continue
			if p.y < 0 or p.y >= g.size() or p.x < 0 or p.x >= g[0].size():
				return []
			var ch: String = g[p.y][p.x]
			if ch != " ":
				# reached the old floor -- the passage is everything before it
				if ch in [".", ",", "L", "h", "o", "^", "&"] or ch.to_lower() != ch.to_upper():
					return cells if cells.size() >= 2 else []
				return []
			cells.append(p)
	return []


static func _furnish(g: Array, kind: String, r: Rect2i, rng: RandomNumberGenerator, weak: String) -> void:
	var c := Vector2i(r.position.x + r.size.x / 2, r.position.y + r.size.y / 2)
	var spots := []
	for yy in range(r.position.y + 1, r.end.y - 1):
		for xx in range(r.position.x + 1, r.end.x - 1):
			var q := Vector2i(xx, yy)
			if absi(q.x - c.x) + absi(q.y - c.y) >= 2:
				spots.append(q)
	var put := func(ch: String, n: int) -> void:
		for i in n:
			if spots.is_empty():
				return
			var q: Vector2i = spots.pop_at(rng.randi() % spots.size())
			g[q.y][q.x] = ch
	# light in two corners, always
	g[r.position.y][r.position.x] = "L"
	g[r.end.y - 1][r.end.x - 1] = "L"
	match kind:
		"relic":
			put.call("x", 2)
		"hermitage":
			put.call("h", 2)
		"echo":
			put.call("c", 2)
		"cache":
			put.call("b", 2)
			put.call("x", 1)
		"grotto":
			# a little pool with a place to fish
			var px := r.position.x + 1
			var py := r.position.y + 1
			for yy in range(py, py + 2):
				for xx in range(px, px + 3):
					g[yy][xx] = "~"
			g[py + 2][px + 1] = "&"
			put.call("h", 3)
		"lair":
			if weak != "":
				put.call(weak, 3)
			put.call("x", 1)
		"trial":
			for q in [Vector2i(c.x - 2, c.y - 2), Vector2i(c.x + 2, c.y - 2), Vector2i(c.x - 2, c.y + 2), Vector2i(c.x + 2, c.y + 2)]:
				if r.has_point(q):
					g[q.y][q.x] = "c"

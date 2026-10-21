extends RefCounted
## The daily trial (round 30 -- Robert: "we don't want a boring game we want
## it to keep people coming back"). One a day, the same for everyone on the
## same day: a sealed run of halls cut to how deep YOU have climbed, with
## one or two of the day's twists (data/retention.json "daily.mods": Blood
## Moon, Glass Edge, Swarming Halls...). Clear every foe in it -- the
## master in the last hall too -- and the Trial Board pays out: gold,
## insight, trial marks, a streak bonus for coming back, and your score
## (time, kills, the blood you kept) goes on the board.
##
## Level id: "trial:<YYYY-MM-DD>". Game.load_level_def() sees the prefix.

const PREFIX := "trial:"
const W := 60
const H := 40


static func make_id(day: String) -> String:
	return PREFIX + day


static func is_trial(level_id: String) -> bool:
	return level_id.begins_with(PREFIX)


static func day_of(level_id: String) -> String:
	return level_id.trim_prefix(PREFIX)


static func mods_for(day: String, mods: Dictionary, per_day: Array) -> Array:
	## the day's twists: the same for everyone on the same day
	var ids: Array = mods.keys()
	ids.sort()
	if ids.is_empty():
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("trial|" + day)
	var n := rng.randi_range(int(per_day[0]) if per_day.size() > 0 else 1, int(per_day[1]) if per_day.size() > 1 else 1)
	var out := []
	while out.size() < n and ids.size() > 0:
		var k: String = ids[rng.randi() % ids.size()]
		ids.erase(k)
		out.append(k)
	return out


static func generate(level_id: String, depth: int, pool: Array, boss: String, mods: Array, cfg: Dictionary) -> Dictionary:
	var day := day_of(level_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("trialmap|%s|%d" % [day, depth])
	var g := []
	for y in H:
		var row := []
		row.resize(W)
		row.fill(" ")
		g.append(row)
	var rr: Array = cfg.get("rooms", [7, 10])
	var want := rng.randi_range(int(rr[0]), int(rr[1]))
	var rooms := []
	var tries := 0
	while rooms.size() < want and tries < 800:
		tries += 1
		var w := rng.randi_range(6, 12)
		var h := rng.randi_range(5, 9)
		var x := rng.randi_range(2, W - w - 2)
		var y := rng.randi_range(2, H - h - 2)
		var ok := true
		for r in rooms:
			if x < r.x + r.w + 2 and x + w + 2 > r.x and y < r.y + r.h + 2 and y + h + 2 > r.y:
				ok = false
				break
		if ok:
			rooms.append({"x": x, "y": y, "w": w, "h": h})
	if rooms.size() < 3:
		rooms = [{"x": 3, "y": 3, "w": 10, "h": 7}, {"x": 20, "y": 12, "w": 10, "h": 7}, {"x": 36, "y": 22, "w": 12, "h": 8}]
	rooms.sort_custom(func(a, b): return a.x + a.y < b.x + b.y)
	for r in rooms:
		for yy in range(r.y, r.y + r.h):
			for xx in range(r.x, r.x + r.w):
				g[yy][xx] = "."
		# walls on the room's edge, so it reads as a hall
		for xx in range(r.x - 1, r.x + r.w + 1):
			for yy in [r.y - 1, r.y + r.h]:
				if g[yy][xx] == " ":
					g[yy][xx] = "#"
		for yy in range(r.y - 1, r.y + r.h + 1):
			for xx in [r.x - 1, r.x + r.w]:
				if g[yy][xx] == " ":
					g[yy][xx] = "#"
	for i in range(1, rooms.size()):
		var a: Dictionary = rooms[i - 1]
		var b: Dictionary = rooms[i]
		var ax: int = a.x + a.w / 2
		var ay: int = a.y + a.h / 2
		var bx: int = b.x + b.w / 2
		var by: int = b.y + b.h / 2
		var x := ax
		while x != bx:
			g[ay][x] = "."
			x += 1 if bx > x else -1
		var y := ay
		while y != by:
			g[y][bx] = "."
			y += 1 if by > y else -1
	# a corridor cut through a wall leaves wall on both sides: tidy any "#"
	# that ended up walled in by floor
	var free := func(r: Dictionary) -> Vector2i:
		for t in 60:
			var cx: int = rng.randi_range(r.x + 1, r.x + r.w - 2)
			var cy: int = rng.randi_range(r.y + 1, r.y + r.h - 2)
			if g[cy][cx] == ".":
				return Vector2i(cx, cy)
		return Vector2i(-1, -1)
	var put := func(r: Dictionary, ch: String) -> bool:
		var c: Vector2i = free.call(r)
		if c.x >= 0:
			g[c.y][c.x] = ch
			return true
		return false
	var enemies := {}
	var chars := ["e", "j", "k"]
	var kinds := []
	var p2 := pool.duplicate()
	p2.sort()
	while kinds.size() < 3 and p2.size() > 0:
		var k: String = p2[rng.randi() % p2.size()]
		p2.erase(k)
		kinds.append(k)
	for i in kinds.size():
		enemies[chars[i]] = kinds[i]
	var count_mult := 1.0
	for m in mods:
		count_mult *= float(cfg.get("mods", {}).get(m, {}).get("foe_count", 1.0))
	var fr: Array = cfg.get("foes_per_room", [1, 3])
	var foes := 0
	put.call(rooms[0], "<")
	put.call(rooms[0], "L")
	for i in range(1, rooms.size()):
		var r: Dictionary = rooms[i]
		var n := int(round(rng.randi_range(int(fr[0]), int(fr[1])) * count_mult))
		for k in maxi(n, 1):
			if kinds.size() > 0 and put.call(r, chars[rng.randi() % kinds.size()]):
				foes += 1
		if rng.randf() < 0.5:
			put.call(r, "L")
	if boss != "":
		enemies["B"] = boss
		var last: Dictionary = rooms[rooms.size() - 1]
		if put.call(last, "B"):
			foes += 1
	var rows := []
	for row in g:
		rows.append("".join(row).rstrip(" "))
	var names := []
	for m in mods:
		names.append(str(cfg.get("mods", {}).get(m, {}).get("name", m)))
	return {
		"id": level_id,
		"name": "The Daily Trial -- %s" % (", ".join(names) if names.size() > 0 else "Plain Halls"),
		"theme": "dungeon",
		"depth": depth,
		"trial": true,
		"trial_mods": mods,
		"trial_foes": foes,
		"map": rows,
		"enemies": enemies,
		"chests": {},
		"exits": {
			"<": {"to": "village", "arrive": "P", "label": "Back to Eliet (the trial waits)", "down": false},
		},
	}

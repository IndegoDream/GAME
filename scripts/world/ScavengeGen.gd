extends RefCounted
## Scavenger floors -- Robert, 2026-10-01: "create a scavenger level
## randomly at 15% ... mining nodes for making weapons and armor and
## jewelry, finding precious gems and metals randomly. plants ... for
## potions pills and other alchemical health needs."
##
## Sometimes (SCAVENGE_CHANCE) the stairs down open onto a hollow between
## two floors instead: caves full of ore, glittering veins, plants and
## still water to fish, a few of the floor's monsters, sometimes a chest.
## Its '<' leads back up, its '>' on down to where you were going. It is
## drawn from a seed, so the same hollow is the same hollow if you come
## back to it (and what you gathered there stays gathered).
##
## Level id: "scavenge_<from>_<to>_<seed>" -- Game.load_level_def() sees
## the prefix and asks this file instead of res://levels/.

const PREFIX := "scavenge_"
const SCAVENGE_CHANCE := 0.15
const W := 58
const H := 42


static func make_id(from_id: String, to_id: String, seed_: int) -> String:
	return "%s%s_%s_%d" % [PREFIX, from_id, to_id, seed_]


static func today(from_id: String, to_id: String, day: int = -1) -> String:
	## round 57: whether this stair opens onto a hollow today, and which one --
	## decided once a day per stair, so going up and down again changes nothing
	if day < 0:
		day = int(Time.get_unix_time_from_system() / 86400.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("hollow|%s|%s|%d" % [from_id, to_id, day])
	if rng.randf() >= SCAVENGE_CHANCE:
		return ""
	return make_id(from_id, to_id, day % 1000000)


static func is_scavenge(level_id: String) -> bool:
	return level_id.begins_with(PREFIX)


static func parse(level_id: String) -> Dictionary:
	## "scavenge_floor1_floor2_123" -> {from, to, seed}
	var rest := level_id.trim_prefix(PREFIX)
	var parts := rest.split("_")
	if parts.size() < 3:
		return {}
	var seed_s: String = parts[parts.size() - 1]
	if not seed_s.is_valid_int():
		return {}
	# level ids have no "_" in this game ("floor1"), so from / to are the
	# first two pieces
	return {"from": parts[0], "to": parts[1], "seed": int(seed_s)}


static func generate(level_id: String, depth: int, enemy_pool: Array, animal_pool: Array = []) -> Dictionary:
	var p := parse(level_id)
	if p.is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = int(p["seed"])
	var g := []
	for y in H:
		var row := []
		row.resize(W)
		row.fill(" ")
		g.append(row)
	var rooms := []
	var tries := 0
	while rooms.size() < 10 and tries < 600:
		tries += 1
		var w := rng.randi_range(5, 14)
		var h := rng.randi_range(4, 10)
		var x := rng.randi_range(2, W - w - 2)
		var y := rng.randi_range(2, H - h - 2)
		var ok := true
		for r in rooms:
			if x < r.x + r.w + 2 and x + w + 2 > r.x and y < r.y + r.h + 2 and y + h + 2 > r.y:
				ok = false
				break
		if ok:
			rooms.append({"x": x, "y": y, "w": w, "h": h})
	if rooms.size() < 2:
		rooms = [{"x": 3, "y": 3, "w": 10, "h": 7}, {"x": 20, "y": 12, "w": 10, "h": 7}]
	rooms.sort_custom(func(a, b): return a.x < b.x)
	for r in rooms:
		for yy in range(r.y, r.y + r.h):
			for xx in range(r.x, r.x + r.w):
				g[yy][xx] = "."
		# rough cave edges: nibble a few corners
		for k in 3:
			var cx: int = r.x + (0 if rng.randf() < 0.5 else r.w - 1)
			var cy: int = r.y + (0 if rng.randf() < 0.5 else r.h - 1)
			g[cy][cx] = " "
	for i in range(1, rooms.size()):
		var a: Dictionary = rooms[i - 1]
		var b: Dictionary = rooms[i]
		var ax: int = a.x + a.w / 2
		var ay: int = a.y + a.h / 2
		var bx: int = b.x + b.w / 2
		var by: int = b.y + b.h / 2
		var x := ax
		while x != bx:
			if g[ay][x] == " ":
				g[ay][x] = "."
			x += 1 if bx > x else -1
		var y := ay
		while y != by:
			if g[y][bx] == " ":
				g[y][bx] = "."
			y += 1 if by > y else -1
	# what makes it a scavenger floor: lots to gather
	var free := func(r: Dictionary) -> Vector2i:
		for t in 40:
			var cx: int = rng.randi_range(r.x + 1, r.x + r.w - 2)
			var cy: int = rng.randi_range(r.y + 1, r.y + r.h - 2)
			if g[cy][cx] == ".":
				return Vector2i(cx, cy)
		return Vector2i(-1, -1)
	var put := func(r: Dictionary, ch: String) -> void:
		var c: Vector2i = free.call(r)
		if c.x >= 0:
			g[c.y][c.x] = ch
	var first: Dictionary = rooms[0]
	var last: Dictionary = rooms[rooms.size() - 1]
	put.call(first, "<")
	put.call(last, ">")
	for r in rooms:
		put.call(r, "L")
		for k in rng.randi_range(1, 3):
			put.call(r, "o")
		for k in rng.randi_range(1, 3):
			put.call(r, "h")
		if rng.randf() < 0.6:
			put.call(r, "^")
	# a pool with a fishing spot in one or two rooms
	for k in 2:
		var r: Dictionary = rooms[rng.randi_range(1, rooms.size() - 1)]
		var c: Vector2i = free.call(r)
		if c.x >= 0:
			g[c.y][c.x] = "&"
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1)]:
				var n: Vector2i = c + d
				if n.y < r.y + r.h - 1 and n.x < r.x + r.w - 1 and n.x > r.x and g[n.y][n.x] == "." and rng.randf() < 0.6:
					g[n.y][n.x] = "~"
	var enemies := {}
	if enemy_pool.size() > 0:
		enemies["e"] = str(enemy_pool[rng.randi_range(0, enemy_pool.size() - 1)])
		for r in rooms.slice(1):
			if rng.randf() < 0.6:
				put.call(r, "e")
	# game to hunt: hollows are quiet places, the animals haven't learned to hide
	var animals := []
	for a in animal_pool:
		animals.append(str(a))
	if animals.size() > 0:
		enemies["a"] = animals[rng.randi_range(0, animals.size() - 1)]
		for r in rooms:
			if rng.randf() < 0.4:
				put.call(r, "a")
	var chests := {}
	if rng.randf() < 0.5:
		chests["C"] = {"loot": {"gold": [10 + depth * 5, 25 + depth * 10], "qi_pill": [0, 1]}, "note": "A scavenger's cache, half-buried."}
		put.call(rooms[rng.randi_range(1, rooms.size() - 1)], "C")
	var rows := []
	for row in g:
		rows.append("".join(row).rstrip(" "))
	return {
		"id": level_id,
		"name": "Scavenger's Hollow",
		"theme": "dungeon",
		"depth": depth,
		"scavenge": true,
		"map": rows,
		"enemies": enemies,
		"chests": chests,
		"exits": {
			"<": {"to": p["from"], "arrive": ">", "label": "Back up", "down": false},
			">": {"to": p["to"], "arrive": "<", "label": "On down"},
		},
	}

extends RefCounted
## The shared world's two kinds of place (round 125): the Gate hub (a plaza players gather in) and the arena (where a
## dungeon run, a raid or a world boss happens). Neither is a file: "online:hub" and "online:arena" are drawn here.
## Online.gd / OnlineWorld.gd fill them with people and foes.

const HUB := "online:hub"
const ARENA := "online:arena"
const CELL := 2.0


static func is_online(level_id: String) -> bool:
	return level_id.begins_with("online:")


static func hub_size() -> int:
	return 48


static func arena_cells(radius_m: float) -> int:
	return int(ceil(radius_m / CELL)) * 2 + 10


static func center_cell(level_id: String, radius_m: float = 24.0) -> Vector2i:
	var n := hub_size() if level_id == HUB else arena_cells(radius_m)
	return Vector2i(n / 2, n / 2)


static func make_def(level_id: String, radius_m: float = 24.0) -> Dictionary:
	if level_id == HUB:
		return _hub()
	if level_id == ARENA:
		return _arena(radius_m)
	return {}


static func _grid(n: int) -> Array:
	var g := []
	for y in n:
		var row := []
		row.resize(n)
		row.fill(" ")
		g.append(row)
	return g


static func _out(g: Array) -> Array:
	var out := []
	for row in g:
		out.append("".join(PackedStringArray(row)))
	return out


static func _hub() -> Dictionary:
	var n := hub_size()
	var g := _grid(n)
	var c := n / 2
	var r_plaza := 21.0
	for y in n:
		for x in n:
			var d := Vector2(x - c + 0.5, y - c + 0.5).length()
			if d <= r_plaza:
				g[y][x] = ","  if (absi(x - c) <= 1 or absi(y - c) <= 1 or int(round(d)) == 8 or int(round(d)) == 15) else "."
	# a ring of columns and lanterns
	for i in 24:
		var a := TAU * float(i) / 24.0
		var p := Vector2i(c + int(round(cos(a) * 19.0)), c + int(round(sin(a) * 19.0)))
		if absi(p.x - c) <= 1 and p.y < c:
			continue
		g[p.y][p.x] = "c" if i % 2 == 0 else "L"
	for i in 8:
		var a := TAU * (float(i) + 0.5) / 8.0
		g[c + int(round(sin(a) * 12.0))][c + int(round(cos(a) * 12.0))] = "L"
	g[c][c] = "f"
	for i in 28:
		var a := TAU * float(i) / 28.0 + 0.1
		var p := Vector2i(c + int(round(cos(a) * 20.4)), c + int(round(sin(a) * 20.4)))
		if g[p.y][p.x] == "." and i % 3 == 0:
			g[p.y][p.x] = "t"
	g[c + 9][c] = "P"
	g[c - 19][c] = "<"
	return {"id": HUB, "name": "The Gate", "theme": "wilds", "look": "warrens", "depth": 0, "no_expand": true, "no_reach": true, "online": "hub", "cliff_tint": [0.55, 0.5, 0.45],
		"ambient": [0.62, 0.62, 0.72], "notes": "Elite Online: the hub.", "map": _out(g), "enemies": {}, "chests": {}, "npcs": {},
		"exits": {"<": {"to": "village", "arrive": "P", "label": "Back to the village", "down": false, "style": "portal"}}}


static func _arena(radius_m: float) -> Dictionary:
	var n := arena_cells(radius_m)
	var g := _grid(n)
	var c := n / 2
	var rc := radius_m / CELL + 1.5
	for y in n:
		for x in n:
			var d := Vector2(x - c + 0.5, y - c + 0.5).length()
			if d <= rc:
				g[y][x] = "."
	var ring := int(radius_m / 1.2)
	for i in ring:
		var a := TAU * float(i) / float(ring)
		var p := Vector2i(c + int(round(cos(a) * (rc - 1.0))), c + int(round(sin(a) * (rc - 1.0))))
		g[p.y][p.x] = "c" if i % 3 == 0 else "L"
	for frac: float in [0.62, 0.3]:
		var k := int(radius_m * frac / 1.6)
		for i in k:
			var a := TAU * float(i) / float(k) + frac
			var p := Vector2i(c + int(round(cos(a) * rc * frac)), c + int(round(sin(a) * rc * frac)))
			if g[p.y][p.x] == ".":
				g[p.y][p.x] = "L"
	var py := c + int(round(radius_m * 0.55 / CELL))
	g[mini(py, n - 2)][c] = "P"
	return {"id": ARENA, "name": "The Gate -- the arena", "theme": "dungeon", "look": "warrens", "depth": 1, "no_expand": true, "no_reach": true, "online": "arena",
		"arena_radius": radius_m, "ambient": [0.95, 0.9, 0.95], "map": _out(g), "enemies": {}, "chests": {}, "npcs": {}, "exits": {}}

extends RefCounted
## Your own world, drawn (2026-11-06). Level id "realm:own". The Worldkeeper system holds what you built; this turns
## it into a map each time you enter. A meadow under your chosen Land's sky, a keeper's lectern by the arrival,
## and up to twelve plots in a ring around a central green. Deterministic for the same state.

const ID := "realm:own"
const PW := 16          # a plot, in cells
const PH := 12


static func is_keeper(level_id: String) -> bool:
	return level_id == ID


static func make_def(K, realm: int) -> Dictionary:
	var n: int = K.plot_count()
	var W := 4 * PW + 36
	var H := 3 * PH + 34
	var g := []
	for y in H:
		var row := []
		for x in W:
			row.append("." if x >= 3 and x < W - 3 and y >= 3 and y < H - 3 else " ")
		g.append(row)
	var put := func(x: int, y: int, c: String) -> void:
		if x >= 3 and x < W - 3 and y >= 3 and y < H - 3:
			g[y][x] = c
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("keeper|" + K.world_name() + "|" + K.land)
	# woods round the edge, thick, so it reads as a hidden place
	for y in H:
		for x in W:
			if g[y][x] == ".":
				var e := mini(mini(x - 3, W - 4 - x), mini(y - 3, H - 4 - y))
				if e < 2 or (e < 5 and rng.randf() < 0.45):
					g[y][x] = "t"
	var cx := W / 2
	var cy := H / 2
	# the green in the middle: a fountain, paths out to the plots
	for y in range(cy - 4, cy + 5):
		for x in range(cx - 7, cx + 8):
			if Vector2((x - cx) / 7.0, (y - cy) / 4.0).length() <= 1.0:
				put.call(x, y, ",")
	put.call(cx, cy, "f")
	# twelve plots in a ring: 4 near (N E S W), then the far ring, then the corners -- as many as are open
	var spots := [Vector2i(cx, cy - 13), Vector2i(cx + 22, cy), Vector2i(cx, cy + 13), Vector2i(cx - 22, cy),
		Vector2i(cx, cy - 26), Vector2i(cx + 40, cy), Vector2i(cx, cy + 26), Vector2i(cx - 40, cy),
		Vector2i(cx + 30, cy - 18), Vector2i(cx + 30, cy + 18), Vector2i(cx - 30, cy + 18), Vector2i(cx - 30, cy - 18)]
	for i in spots.size():
		var c: Vector2i = spots[i]
		var open := i < n
		# a path from the green
		var p := Vector2i(cx, cy)
		while p != c and open:
			put.call(p.x, p.y, "," if g[p.y][p.x] in [".", "t"] else g[p.y][p.x])
			if p.x != c.x:
				p.x += 1 if c.x > p.x else -1
			elif p.y != c.y:
				p.y += 1 if c.y > p.y else -1
		if not open:
			continue
		for y in range(c.y - PH / 2 + 1, c.y + PH / 2):
			for x in range(c.x - PW / 2 + 1, c.x + PW / 2):
				if g[y][x] == "t":
					put.call(x, y, ".")
		_draw_plot(str(K.plots.get(str(i), "")), c, put, rng)
	# the lectern and the way home
	put.call(cx - 3, cy + 5, "K")
	put.call(cx + 2, cy + 5, "P")
	put.call(cx, cy + 8, "E")
	var reg: Dictionary = (Engine.get_main_loop().root.get_node("Game").FrontierGen.region(K.land) as Dictionary)
	var out := []
	for row in g:
		out.append("".join(PackedStringArray(row)))
	var d := {"id": ID, "name": K.world_name(), "theme": "village", "look": str(reg.get("look", "grove")), "depth": 0, "no_expand": true, "no_reach": true,
		"notes": I18n.t("Your own world. Shape it at the keeper's lectern."), "map": out,
		"npcs": {"K": {"role": "keeper", "name": I18n.t("The Keeper's Lectern"), "stays": true, "line": I18n.t("Everything here is yours to shape.")}},
		"exits": {"E": {"to": "village", "arrive": "P", "label": I18n.t("The way back -- Eliet")}},
		"lore": {}, "gather": reg.get("gather", {}), "giants": reg.get("giants", {}), "keeper": true}
	for k in ["atmos", "ground_tint", "rim", "deco", "motes", "lamp"]:
		if reg.has(k):
			d[k] = reg[k]
	return d


static func _draw_plot(kind: String, c: Vector2i, put: Callable, rng: RandomNumberGenerator) -> void:
	match kind:
		"house":
			for y in range(c.y - 3, c.y + 1):
				for x in range(c.x - 3, c.x + 4):
					put.call(x, y, "H")
			for x in range(c.x - 1, c.x + 2):
				put.call(x, c.y + 2, ",")
			put.call(c.x - 4, c.y + 2, "L")
			put.call(c.x + 4, c.y + 2, "L")
		"shrine":
			for y in range(c.y - 3, c.y + 4):
				for x in range(c.x - 4, c.x + 5):
					put.call(x, y, ",")
			put.call(c.x, c.y, "Z")
			for q in [Vector2i(-3, -2), Vector2i(3, -2), Vector2i(-3, 2), Vector2i(3, 2)]:
				put.call(c.x + q.x, c.y + q.y, "L")
		"pond":
			for y in range(c.y - 3, c.y + 4):
				for x in range(c.x - 5, c.x + 6):
					if Vector2((x - c.x) / 5.0, (y - c.y) / 3.0).length() <= 1.0:
						put.call(x, y, "~")
			put.call(c.x, c.y - 4, "&")
		"grove":
			for a in 24:
				var ang := a * TAU / 24.0
				if a % 8 != 0:
					put.call(c.x + int(round(cos(ang) * 5.5)), c.y + int(round(sin(ang) * 4.0)), "t")
			for k in 6:
				put.call(c.x + rng.randi_range(-3, 3), c.y + rng.randi_range(-2, 2), "h")
		"garden":
			for y in range(c.y - 3, c.y + 4, 2):
				for x in range(c.x - 5, c.x + 6):
					if (x + y) % 3 != 0:
						put.call(x, y, "h")
		"mine":
			for y in range(c.y - 3, c.y + 4):
				for x in range(c.x - 5, c.x + 6):
					var e := Vector2((x - c.x) / 5.0, (y - c.y) / 3.0).length()
					if e > 0.8 and e <= 1.05:
						put.call(x, y, "c")
			for k in 7:
				put.call(c.x + rng.randi_range(-3, 3), c.y + rng.randi_range(-2, 2), "o" if k % 3 else "^")
		"orchard":
			for y in range(c.y - 3, c.y + 4, 3):
				for x in range(c.x - 5, c.x + 6, 3):
					put.call(x, y, "t")
		"lanterns":
			for a in 10:
				var ang2 := a * TAU / 10.0
				put.call(c.x + int(round(cos(ang2) * 5.0)), c.y + int(round(sin(ang2) * 3.5)), "L")
			put.call(c.x, c.y, "f")
		_:
			pass          # meadow, waiting

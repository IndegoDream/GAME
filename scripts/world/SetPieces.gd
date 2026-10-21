extends RefCounted
## Set-pieces (round 32 -- Robert: "bigger, handmade floors"). Every dungeon
## floor from the second down gets, drawn from its own seed, on top of what
## its level file says (the file is never changed):
##   * THE KEEPER -- a named mini-boss (two affixes, bigger, tougher) standing
##     in the floor's widest room. It carries the floor's key.
##   * THE GATE -- iron bars across a corridor that cuts off part of the
##     floor (never the way down). Behind it, the VAULT: a chest with real
##     gear and gold, and now and then a drop of old blood.
##   * THE LEVERS -- three coloured levers in a room and a stone that says
##     the order (the stone's words can be Dev's: data/drafts/puzzle_hints).
##     The right order opens a second, lockless gate; the wrong one wakes
##     everything near and resets them.
## Nothing here changes a level's map; it all stands on floor the map
## already had, placed where the paths allow.

const TITLES := ["Butcher", "Warden", "Reaver", "Toll-Taker", "Hangman", "Gatekeeper", "Hound", "Sentinel"]
const COLORS := {"red": Color(0.85, 0.2, 0.2), "jade": Color(0.25, 0.75, 0.4), "gold": Color(0.95, 0.8, 0.3), "blue": Color(0.3, 0.5, 0.95)}
const MIN_DEPTH := 2


static func wants(level) -> bool:
	var d: Dictionary = level.def
	return str(d.get("theme", "dungeon")) == "dungeon" and int(d.get("depth", 0)) >= MIN_DEPTH and str(level.level_id).begins_with("floor") \
		and not bool(d.get("arena", false)) and not bool(d.get("trial", false))


static func _free_cells(level) -> Dictionary:
	var out := {}
	for c in level._floor_cells:
		if level.is_free(c):
			out[c] = true
	return out


static func _bfs(level, free: Dictionary, start: Vector2i, blocked: Vector2i = Vector2i(-99, -99)) -> Dictionary:
	## cell -> steps from start, walking the free cells (4-way)
	var dist := {start: 0}
	var q := [start]
	var i := 0
	while i < q.size():
		var c: Vector2i = q[i]
		i += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n == blocked or not free.has(n) or dist.has(n):
				continue
			dist[n] = int(dist[c]) + 1
			q.append(n)
	return dist


static func _corridor(level, free: Dictionary, c: Vector2i) -> bool:
	## a cell with floor on exactly two opposite sides and wall on the others
	var l := free.has(c + Vector2i(-1, 0))
	var r := free.has(c + Vector2i(1, 0))
	var u := free.has(c + Vector2i(0, -1))
	var dn := free.has(c + Vector2i(0, 1))
	return (l and r and not u and not dn) or (u and dn and not l and not r)


static func _important_cells(level) -> Array:
	## what must stay reachable from the way in: the way down, the boss, the player start
	var out := []
	for ch in level.spawns:
		var s := str(ch)
		if s == ">" or s == "P" or s == "<" or (level.def.get("exits", {}) as Dictionary).has(s):
			out.append_array(level.spawns[ch])
		elif (level.def.get("enemies", {}) as Dictionary).has(s) and bool(Game.enemies.get(str(level.def["enemies"][s]), {}).get("boss", false)):
			out.append_array(level.spawns[ch])
	# the cells themselves may not be walkable (stairs, a boss): what must
	# stay reachable is the floor around them
	var grown := []
	for c in out:
		grown.append(c)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			grown.append(c + d)
	return grown


static func place(level) -> Dictionary:
	if not wants(level):
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("setpieces|" + str(level.level_id))
	var free := _free_cells(level)
	var starts: Array = level.spawns.get("<", level.spawns.get("P", []))
	if starts.is_empty() or free.size() < 60:
		return {}
	var start: Vector2i = starts[0]
	if not free.has(start):
		# the stairs cell itself isn't walkable: start from a free neighbour
		for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			if free.has(start + d):
				start = start + d
				break
	var dist := _bfs(level, free, start)
	var important := _important_cells(level)
	var out := {}
	var depth := int(level.def.get("depth", 1))
	# ---- the gate: a corridor cell past the middle that cuts off a pocket
	# of floor the way down isn't in
	var cands := []
	var maxd := 0
	for c in dist:
		maxd = maxi(maxd, int(dist[c]))
	for c in dist:
		if int(dist[c]) >= maxd * 0.35 and _corridor(level, free, c):
			cands.append(c)
	cands.sort_custom(func(a, b): return int(dist[a]) < int(dist[b]))
	var gate_cell := Vector2i(-1, -1)
	var pocket := []
	for t in mini(cands.size(), 40):
		var c: Vector2i = cands[(rng.randi() % cands.size())]
		var d2 := _bfs(level, free, start, c)
		var cut := []
		for f in free:
			if f != c and not d2.has(f) and dist.has(f):
				cut.append(f)
		if cut.size() < 6 or cut.size() > free.size() * 0.4:
			continue
		var ok := true
		for imp in important:
			if cut.has(imp) or imp == c:
				ok = false
				break
		if ok:
			gate_cell = c
			pocket = cut
			break
	var key_id := "key_%s" % str(level.level_id)
	if gate_cell.x >= 0:
		Game.register_key(key_id, str(level.def.get("name", level.level_id)))
		level._spawn_script("res://scripts/objects/Gate.gd", level.cell_to_world(gate_cell), {"cell": gate_cell, "key": key_id})
		level._count("gates")
		# the vault: the chest at the far end of the pocket
		pocket.sort_custom(func(a, b): return int(dist[a]) > int(dist[b]))
		var vc: Vector2i = pocket[0]
		var loot := {"gold": [45 * depth, 90 * depth], "qi_pill": [1, 2], "nanite_shard": [2, 4]}
		level._spawn_script("res://scripts/objects/Chest.gd", level.cell_to_world(vc), {"cell": vc, "loot": loot, "gear": 1 + (1 if depth >= 8 else 0), "essence": depth >= 20,
			"note": "The Keeper's vault: what the floor kept for itself."})
		level._count("vaults")
		out["gate"] = gate_cell
		out["vault"] = vc
		free.erase(gate_cell)
		for pc in pocket:
			free.erase(pc)
	# round 119: a floor with no corridor to bar (a cavern, a mine) used to get
	# no vault at all. It gets a CACHE instead: the same chest, at the far end
	# of the floor, with the Keeper standing over it.
	var cache_cell := Vector2i(-1, -1)
	if gate_cell.x < 0:
		var far := []
		for c in dist:
			if free.has(c) and not important.has(c) and int(dist[c]) >= maxd * 0.6 and free.has(c + Vector2i(1, 0)) and free.has(c + Vector2i(-1, 0)) and free.has(c + Vector2i(0, 1)) and free.has(c + Vector2i(0, -1)):
				far.append(c)
		far.sort_custom(func(a, b): return int(dist[a]) > int(dist[b]))
		if far.size() > 0:
			cache_cell = far[mini(far.size() - 1, rng.randi() % maxi(1, far.size() / 4 + 1))]
			var loot2 := {"gold": [35 * depth, 70 * depth], "qi_pill": [1, 2], "nanite_shard": [1, 3]}
			level._spawn_script("res://scripts/objects/Chest.gd", level.cell_to_world(cache_cell), {"cell": cache_cell, "loot": loot2, "gear": 1 + (1 if depth >= 8 else 0), "essence": depth >= 20,
				"note": "The Keeper's cache: no door to bar here, so it stands guard."})
			level._count("vaults")
			out["vault"] = cache_cell
			free.erase(cache_cell)
	# ---- the Keeper: the widest open spot on the near side, not by the start
	var open_cells: Array = level._free_area_cells(9).filter(func(c): return free.has(c) and dist.has(c) and int(dist[c]) >= 8)
	if open_cells.is_empty():
		open_cells = level._free_area_cells(5).filter(func(c): return free.has(c) and dist.has(c) and int(dist[c]) >= 6)
	if cache_cell.x >= 0 and not open_cells.is_empty():
		# stand over the cache: the open spot nearest it
		open_cells.sort_custom(func(a, b): return (a - cache_cell).length_squared() < (b - cache_cell).length_squared())
		open_cells = open_cells.slice(0, mini(open_cells.size(), 3))
	# round 57: a Keeper that's dead stays dead -- unless its key is still the only way through
	var keeper_dead := Game.has_flag("%s:keeper" % str(level.level_id))
	var key_needed := gate_cell.x >= 0 and not Game.has_flag(Game.flag_key(level.level_id, gate_cell, "gate")) and Game.count(key_id) <= 0
	if not open_cells.is_empty():
		var kc: Vector2i = open_cells[rng.randi() % open_cells.size()]
		var pool := []
		for ch in level.def.get("enemies", {}):
			var et := str(level.def["enemies"][ch])
			if Game.enemies.has(et) and not bool(Game.enemies[et].get("boss", false)) and not bool(Game.enemies[et].get("passive", false)):
				pool.append(et)
		if pool.is_empty():
			for e in Game.enemies:
				if int(Game.enemies[e].get("floor", -1)) == depth and not bool(Game.enemies[e].get("boss", false)) and not bool(Game.enemies[e].get("passive", false)):
					pool.append(e)
		if not pool.is_empty():
			pool.sort()
			var et2: String = pool[rng.randi() % pool.size()]
			var keys: Array = (Game.foes_data().get("affixes", {}) as Dictionary).keys()
			keys.sort()
			var aff := []
			while aff.size() < 2 and keys.size() > 0:
				var k: String = keys[rng.randi() % keys.size()]
				keys.erase(k)
				aff.append(k)
			var title: String = TITLES[rng.randi() % TITLES.size()]
			var fname := str(level.def.get("name", "the deep")).replace("Floor %d -- " % depth, "").replace("Floor %d, " % depth, "")
			var champ := I18n.t("The %s of %s") % [title, fname]
			if not keeper_dead or key_needed:          # (the place is still chosen the same way, so nothing else moves)
				level._spawn_script("res://scripts/actors/Enemy.gd", level.cell_to_world(kc), {"type": et2, "cell": kc, "affixes": aff, "champion": champ,
					"drops_key": key_id if gate_cell.x >= 0 else "", "hp_mult": 1.8, "scale_mult": 1.25})
				level._count("keepers")
			out["keeper"] = kc
			free.erase(kc)
	# ---- the levers: three in one open room, the order on a stone beside them
	var rooms: Array = level._free_area_cells(9).filter(func(c): return free.has(c) and dist.has(c) and (not out.has("keeper") or (c - out["keeper"]).length_squared() > 36))
	if rooms.size() < 6:
		rooms = level._free_area_cells(5).filter(func(c): return free.has(c) and dist.has(c) and (not out.has("keeper") or (c - out["keeper"]).length_squared() > 16))
	if rooms.size() >= 3:
		# round 119: try several spots (the first pick used to be the only one -- if its
		# corners were wall the floor simply got no levers)
		var centre: Vector2i = rooms[0]
		var spots := []
		var okp := false
		var hint_cell := Vector2i.ZERO
		for attempt in mini(rooms.size(), 24):
			var cc: Vector2i = rooms[rng.randi() % rooms.size()]
			var sp3 := [cc + Vector2i(-1, -1), cc + Vector2i(1, -1), cc + Vector2i(0, 1)]
			var hc := cc + Vector2i(-1, 1)
			var good := free.has(hc) and hc != start
			for sp in sp3:
				if not free.has(sp) or sp == start:
					good = false
			if good:
				centre = cc
				spots = sp3
				hint_cell = hc
				okp = true
				break
		if okp:
			var names: Array = COLORS.keys()
			names.sort()
			var order := []
			while order.size() < 3:
				var n: String = names[rng.randi() % names.size()]
				if not order.has(n):
					order.append(n)
			var gid := "levers"
			for i in 3:
				level._spawn_script("res://scripts/objects/Lever.gd", level.cell_to_world(spots[i]), {"cell": spots[i], "color": order[(i * 2) % 3], "rgb": COLORS[order[(i * 2) % 3]], "group": gid})
			level.puzzle_order = order
			level.puzzle_group = gid
			var hint := Game.puzzle_hint(order)
			level._spawn_script("res://scripts/objects/Stele.gd", level.cell_to_world(hint_cell), {"cell": hint_cell, "def": {"title": "A Worn Tablet", "text": hint}})
			level._count("puzzles")
			# the puzzle gate: another corridor cell cutting off a second pocket, if the floor has one
			var g2 := Vector2i(-1, -1)
			var pocket2 := []
			for t in (mini(cands.size(), 30) if cands.size() > 0 else 0):
				var c2: Vector2i = cands[rng.randi() % cands.size()]
				if not free.has(c2):
					continue
				var d3 := _bfs(level, free, start, c2)
				var cut2 := []
				for f in free:
					if f != c2 and not d3.has(f) and dist.has(f):
						cut2.append(f)
				if cut2.size() < 4 or cut2.size() > free.size() * 0.3:
					continue
				var ok2 := true
				for imp in important:
					if cut2.has(imp) or imp == c2:
						ok2 = false
				for sp in spots:
					if cut2.has(sp) or sp == c2:
						ok2 = false
				if cut2.has(hint_cell) or hint_cell == c2:
					ok2 = false
				if ok2:
					g2 = c2
					pocket2 = cut2
					break
			if g2.x >= 0:
				level._spawn_script("res://scripts/objects/Gate.gd", level.cell_to_world(g2), {"cell": g2, "puzzle": true})
				pocket2.sort_custom(func(a, b): return int(dist[a]) > int(dist[b]))
				var pc2: Vector2i = pocket2[0]
				level._spawn_script("res://scripts/objects/Chest.gd", level.cell_to_world(pc2), {"cell": pc2, "loot": {"gold": [30 * depth, 60 * depth], "healing_salve": [1, 2]}, "gear": 1,
					"note": "Whoever set the levers kept their best behind them."})
				level._count("puzzle_vaults")
				out["puzzle_gate"] = g2
			else:
				# no pocket to lock: the right order drops the reward where you stand
				level.puzzle_reward_cell = centre
			out["levers"] = spots
	return out

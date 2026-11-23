extends SceneTree
## Is a locked vault reachable without opening its gate?  godot --headless --path . --script res://tools/_gate_probe.gd -- floor6 [floor7 ...]
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.save_path = "user://gate_probe_save.json"
	G.save_base = "user://gate_probe_slots"
	G.new_game()
	load("res://scripts/systems/LegacyLines.gd").skip = true
	var SPt = load("res://scripts/world/SetPieces.gd")
	for id in OS.get_cmdline_user_args():
		var level = load("res://scripts/world/Level.gd").new()
		level.build(G.load_level_def(id))
		root.add_child(level)
		var sp: Dictionary = level.set_pieces
		var gate = null
		for n in level.get_children():
			if n.get_script() and str(n.get_script().resource_path).ends_with("Gate.gd") and not n.puzzle:
				gate = n
		if gate == null:
			print(id, ": no key gate; set pieces ", sp.keys())
			level.free()
			continue
		var free_t: Dictionary = SPt._free_cells(level)
		free_t[gate.cell] = true
		for g2 in level.get_children():
			if g2.is_in_group("gate"):
				free_t[g2.cell] = true
		var st_c: Vector2i = level.spawns["<"][0] + Vector2i(0, 1)
		var best := st_c
		var best_n := 0
		for d0 in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var rr: Dictionary = SPt._bfs(level, free_t, level.spawns["<"][0] + d0)
			if rr.size() > best_n:
				best_n = rr.size()
				best = level.spawns["<"][0] + d0
		print("  '<' at ", level.spawns["<"][0], " +(0,1) free? ", free_t.has(st_c), "  best side ", best, " reaches ", best_n, "  player spawn ", level.spawns.get("@", level.spawns.get("P", "?")))
		st_c = best
		var open_reach: Dictionary = SPt._bfs(level, free_t, st_c)
		var shut_reach: Dictionary = SPt._bfs(level, free_t, st_c, gate.cell)
		var vault = sp.get("vault", {})
		var vcells: Array = []
		if vault is Dictionary:
			for k in ["cells", "room", "chest", "cell", "at"]:
				if vault.has(k):
					vcells.append([k, vault[k]])
		var chars := {}
		var walk_chars := {}
		for c in level._floor_cells:
			var ch: String = level.char_at(c)
			chars[ch] = int(chars.get(ch, 0)) + 1
			if level.astar.region.has_point(c) and not level.astar.is_point_solid(c):
				walk_chars[ch] = int(walk_chars.get(ch, 0)) + 1
		print("  floor chars ", chars, "\n  walkable (astar) chars ", walk_chars)
		# the truth: walk every cell the pathfinder can (not just the ones marked "free")
		var walk := {}
		for c in level._floor_cells:
			if level.astar.region.has_point(c) and not level.astar.is_point_solid(c):
				walk[c] = true
		walk[gate.cell] = true
		var others := []
		for g3 in level.get_children():
			if g3.is_in_group("gate") or (g3.get_script() and str(g3.get_script().resource_path).ends_with("Gate.gd")):
				walk[g3.cell] = true
				others.append([g3.cell, g3.puzzle if "puzzle" in g3 else "?"])
		print("  gates: ", others)
		var w_open: Dictionary = SPt._bfs(level, walk, level.spawns["<"][0] + Vector2i(0, 1) if walk.has(level.spawns["<"][0] + Vector2i(0, 1)) else st_c)
		var w_shut: Dictionary = SPt._bfs(level, walk, level.spawns["<"][0] + Vector2i(0, 1) if walk.has(level.spawns["<"][0] + Vector2i(0, 1)) else st_c, gate.cell)
		var vc: Vector2i = sp.get("vault", Vector2i(-1, -1)) if sp.get("vault") is Vector2i else Vector2i(-1, -1)
		var vreach_open := false
		var vreach_shut := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i.ZERO]:
			vreach_open = vreach_open or w_open.has(vc + d)
			vreach_shut = vreach_shut or w_shut.has(vc + d)
		print("  WALKABLE: total ", walk.size(), " open ", w_open.size(), " shut ", w_shut.size(), "  vault ", vc, " reachable open ", vreach_open, " / with the gate SHUT ", vreach_shut, "  stairs down reachable ", w_open.has(level.spawns[">"][0]), "/", w_shut.has(level.spawns[">"][0]))
		var a0: Vector2i = level.spawns["<"][0]
		var down: Vector2i = level.spawns[">"][0]
		var pth: Array = level.astar.get_id_path(a0, down, true) if level.astar.region.has_point(a0) else []
		print("  ASTAR (gate closed) '<'->'>' path len ", pth.size(), "  ends at ", pth[pth.size() - 1] if pth.size() > 0 else "-", "  gate solid ", level.astar.is_point_solid(gate.cell), "  spawns ", level.spawns.keys())
		print(id, ": floor cells ", level._floor_cells.size(), " free ", free_t.size(), " open ", open_reach.size(), " shut ", shut_reach.size(), " gate ", gate.cell, " vault ", str(vault).substr(0, 300))
		# which vault chest cells are reachable with the gate shut?
		for n in level.get_children():
			if n.get_script() and str(n.get_script().resource_path).ends_with("Chest.gd"):
				var c: Vector2i = n.cell if "cell" in n else Vector2i(-1, -1)
				if n.has_meta("vault") or (vault is Dictionary and str(vault).contains(str(c))):
					var nb_open := false
					var nb_shut := false
					for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i.ZERO]:
						nb_open = nb_open or open_reach.has(c + d)
						nb_shut = nb_shut or shut_reach.has(c + d)
					print("  vault chest at ", c, " reach open ", nb_open, " shut ", nb_shut)
		level.free()
	quit()

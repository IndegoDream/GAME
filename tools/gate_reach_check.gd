extends SceneTree
## 2026-11-06: the Keeper's gate and the lever gate never stand across the way on.
## On every dungeon floor: with the key gate shut the stairs down, the boss and the
## Keeper are still reachable from the way in, and the vault is not; with the lever
## gate shut the levers and the stairs down still are.
##   godot --headless --path . --script res://tools/gate_reach_check.gd [-- floor6 floor8 ...]
var fails := 0
var total := 0


func check(what: String, ok: bool, detail := "") -> void:
	total += 1
	if not ok:
		fails += 1
		print("  FAIL: ", what, "  ", detail)


func _walk(level) -> Dictionary:
	var out := {}
	var r: Rect2i = level.astar.region
	for x in range(r.position.x, r.end.x):
		for y in range(r.position.y, r.end.y):
			var c := Vector2i(x, y)
			if not level.astar.is_point_solid(c):
				out[c] = true
	for n in level.get_children():
		if n.is_in_group("gate") or (n.get_script() and str(n.get_script().resource_path).ends_with("Gate.gd")):
			out[n.cell] = true
	return out


func _near(reach: Dictionary, c: Vector2i) -> bool:
	for d in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if reach.has(c + d):
			return true
	return false


func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.save_path = "user://gate_reach_save.json"
	G.save_base = "user://gate_reach_slots"
	G.playlog_path = "user://tool_playlog.jsonl"
	G.new_game()
	load("res://scripts/systems/LegacyLines.gd").skip = true
	var SPt = load("res://scripts/world/SetPieces.gd")
	var ids: Array = OS.get_cmdline_user_args()
	if ids.is_empty():
		for d in range(2, 61):
			if G.load_level_def("floor%d" % d).size() > 0:
				ids.append("floor%d" % d)
	var gated := 0
	for id in ids:
		var level = load("res://scripts/world/Level.gd").new()
		level.build(G.load_level_def(id))
		root.add_child(level)
		var sp: Dictionary = level.set_pieces
		var walk := _walk(level)
		if not level.spawns.has("<") or not level.spawns.has(">"):
			level.free()
			continue
		var start: Vector2i = level.spawns["<"][0]
		for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			if walk.has(start + d):
				start = start + d
				break
		var all_open: Dictionary = SPt._bfs(level, walk, start)
		if OS.get_environment("DIFF") != "" and level.has_meta("sp_walk"):
			var seen: Dictionary = level.get_meta("sp_walk")
			var added := []
			var removed := 0
			for c in walk:
				if not seen.has(c):
					added.append([c, level.char_at(c)])
			var rem := []
			for c in seen:
				if not walk.has(c):
					removed += 1
					var what := ""
					for n in level.get_children():
						if n is Node3D and "cell" in n and n.cell == c:
							what = str(n.get_script().resource_path.get_file()) if n.get_script() else n.name
					rem.append([c, level.char_at(c), what])
			print("  removed: ", rem)
			if not _near(SPt._bfs(level, walk, start), level.spawns[">"][0]):
				for r0 in rem:
					var w2 := walk.duplicate()
					w2[r0[0]] = true
					if _near(SPt._bfs(level, w2, start), level.spawns[">"][0]):
						print("  THE BLOCKER: ", r0)
				var w3 := walk.duplicate()
				var r3: Rect2i = level.astar.region
				for x in range(r3.position.x, r3.end.x):
					for y in range(r3.position.y, r3.end.y):
						if level.char_at(Vector2i(x, y)) == "S":
							w3[Vector2i(x, y)] = true
				print("  with secret walls open, the way down: ", _near(SPt._bfs(level, w3, start), level.spawns[">"][0]))
				var w4 := w3.duplicate()
				for x in range(r3.position.x, r3.end.x):
					for y in range(r3.position.y, r3.end.y):
						var ch4: String = level.char_at(Vector2i(x, y))
						if ch4 != "#" and ch4 != " " and ch4 != "":
							w4[Vector2i(x, y)] = true
				var rr4: Dictionary = SPt._bfs(level, w4, start)
				print("  with every non-# cell open: ", _near(rr4, level.spawns[">"][0]))
				var path4 := []
				var cur: Vector2i = level.spawns[">"][0] + Vector2i(0, -1)
				for k4 in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]:
					if rr4.has(level.spawns[">"][0] + k4):
						cur = level.spawns[">"][0] + k4
				while rr4.has(cur) and int(rr4[cur]) > 0:
					var nxt := cur
					for k5 in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]:
						if rr4.has(cur + k5) and int(rr4[cur + k5]) == int(rr4[cur]) - 1:
							nxt = cur + k5
					if not walk.has(cur):
						path4.append([cur, level.char_at(cur), level.astar.is_point_solid(cur)])
					cur = nxt
				print("  cells on the way that aren't walkable now: ", path4.slice(0, 20))
				print("  start ", start, " '<' ", level.spawns["<"][0], " in seen ", seen.has(start))
			print(id, " walkable after placement: +", added.size(), " ", str(added.slice(0, 12)), "  -", removed)
		var down: Vector2i = level.spawns[">"][0]
		check(id + ": the way down can be reached at all", _near(all_open, down))
		if sp.has("gate"):
			gated += 1
			var shut: Dictionary = SPt._bfs(level, walk, start, sp["gate"])
			check(id + ": the Keeper's gate shut, the way down is still open", _near(shut, down), str([sp["gate"], down, shut.size(), all_open.size()]))
			if sp.has("keeper"):
				check(id + ": ...and so is the Keeper (who has the key)", _near(shut, sp["keeper"]), str([sp["keeper"], "open", _near(all_open, sp["keeper"]), "seen", level.get_meta("sp_walk", {}).has(sp["keeper"])]))
			if sp.has("vault"):
				check(id + ": ...and the vault is behind it", not _near(shut, sp["vault"]) and _near(all_open, sp["vault"]), str([sp["vault"], "shut", _near(shut, sp["vault"]), "open", _near(all_open, sp["vault"])]))
			for ch in level.spawns:
				var et := str((level.def.get("enemies", {}) as Dictionary).get(str(ch), ""))
				if et != "" and bool(G.enemies.get(et, {}).get("boss", false)):
					check(id + ": ...and so is the boss", _near(shut, level.spawns[ch][0]))
		if sp.has("puzzle_gate"):
			var shut2: Dictionary = SPt._bfs(level, walk, start, sp["puzzle_gate"])
			check(id + ": the lever gate shut, the way down is still open", _near(shut2, down))
			for lv in sp.get("levers", []):
				check(id + ": ...and so is every lever", _near(shut2, lv), str([lv, sp["puzzle_gate"], "open", _near(all_open, lv)]))
		level.free()
	check("most floors still get a Keeper's gate", gated >= ids.size() / 3, "%d of %d" % [gated, ids.size()])
	print("GATE REACH CHECK %d passed, %d failed (%d floors, %d gated)" % [total - fails, fails, ids.size(), gated])
	quit(1 if fails > 0 else 0)

extends SceneTree
## Stress bot (round 111): the whole game, floor by floor, for the things a playtest of one route can't see.
##   godot --headless --path . --script res://tools/stress.gd -- [floor1 floor7 ... | economy | all]
## With no arguments it does every level in res://levels/ plus the economy and save/load probes.
##
## FLOORS (per level): builds it for real and
##   - can the player get from the arrival point to every exit, every chest, every ore vein and every herb?
##     (a floor you can't leave, or a chest behind a wall, is a softlock or a hole in the map)
##   - walks the critical path -- arrival to the way on -- in short hops, with the physics running, and checks the
##     player stays on the floor (no hole in the ground, no wall to snag on, no falling out of the world)
##   - how long it takes to build, how many nodes it makes, and how long a frame costs with every foe awake
## ECONOMY: no buy-sell loop, no craft-sell loop, nothing priced at zero or negative, nothing that gives items or gold
##   when asked for a negative amount, no number that turns into nan/inf/negative where it must not.
## SAVE/LOAD: save, load, save again -- the same things come back, none twice.
## Prints "STRESS ..." lines and one "STRESS DONE <floors> floors, <n> problems" line; writes user://stress_report.json.

const FRAME_SAMPLES := 24
const SETTLE := 5
const HOP := 2                  # cells between the walk's stops
const MAX_HOPS := 400
const SLOW_BUILD_MS := 6000.0
const SLOW_FRAME_MS := 12.0

var G
var _ids: Array = []
var _i := 0
var _phase := 0
var _frames := 0
var _level
var _player
var _t0 := 0
var _report := {"floors": [], "problems": [], "economy": [], "saveload": []}
var _problems := 0
var _cur := {}
var _frame_ms: Array = []
var _last_us := 0
var _hops: Array = []
var _hop_i := 0
var _hop_wait := 0
var _do_econ := true
var _do_floors := true
var _fell := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var want_floors: Array = []
	for a in args:
		if a == "economy":
			_do_floors = false
		elif a == "all":
			pass
		else:
			want_floors.append(a)
	if not want_floors.is_empty():
		_ids = want_floors
		_do_econ = false
	else:
		var d := DirAccess.open("res://levels")
		if d:
			for f in d.get_files():
				if f.ends_with(".json"):
					_ids.append(f.get_basename())
		_ids.sort_custom(func(a, b): return _floor_no(a) < _floor_no(b) if _floor_no(a) != _floor_no(b) else a < b)
	if not _do_floors:
		_ids = []


func _floor_no(id: String) -> int:
	if id.begins_with("floor"):
		return int(id.substr(5))
	return 1000


func _problem(where: String, what: String) -> void:
	_problems += 1
	_report["problems"].append({"where": where, "what": what})
	print("STRESS PROBLEM %s: %s" % [where, what])


func _setup_game() -> void:
	Engine.max_fps = 0
	Engine.physics_ticks_per_second = 60
	G = root.get_node("Game")
	G.playlog_path = "user://stress_playlog.jsonl"
	G.downtime_live = false
	G.retention_live = false
	G.sys("world").calm = true
	G.save_path = "user://stress_save.json"           # never the real save
	G.save_base = "user://stress_slots"
	G.sys("quests").quiet = true
	G.new_game()
	var hud = load("res://scripts/ui/HUD.gd").new()
	root.add_child(hud)


func _process(delta: float) -> bool:
	if _phase == -1:
		return false
	if G == null:
		_setup_game()
	if _i >= _ids.size():
		return _finish()
	var id: String = _ids[_i]
	match _phase:
		0: _begin_floor(id)
		1: _measure_frames()
		2: _walk()
		3: _end_floor(id)
	return false


func _begin_floor(id: String) -> void:
	_cur = {"id": id, "problems": []}
	_t0 = Time.get_ticks_usec()
	var def: Dictionary = G.load_level_def(id)
	if def.is_empty():
		_flag("levels/%s.json is missing or isn't valid JSON" % id)
		_phase = 3
		return
	var _LV = load("res://scripts/world/Level.gd")
	_LV.stream_on = OS.get_environment("STREAM") != ""
	_level = _LV.new()
	_level.name = "Level"
	_level.build(def)
	root.add_child(_level)
	G.current_level = id
	_cur["build_ms"] = snappedf((Time.get_ticks_usec() - _t0) / 1000.0, 0.1)
	_player = load("res://scripts/actors/Player.gd").new()
	root.add_child(_player)
	var tag := "<" if _level.spawns.has("<") else "P"        # how a player really arrives: through the stairs from the floor above
	var start: Vector3 = _level.spawn_point(tag)
	_player.global_position = start + Vector3(0, 0.5, 0)
	_player.velocity = Vector3.ZERO
	_cur["nodes"] = _count_nodes(_level)
	_cur["enemies"] = get_nodes_in_group("enemy").size()
	_reachability(def)
	_frames = 0
	_frame_ms.clear()
	_last_us = Time.get_ticks_usec()
	_phase = 1


func _why(c: Vector2i) -> String:
	## r114: what is actually at a cell -- so whoever fixes the problem (Dev) starts from facts, not a guess
	var here: Array = []
	for n in _level.get_children():
		var sc = n.get_script()
		var nc = n.get("cell")
		var at_cell: bool = (nc is Vector2i and nc == c)
		if not at_cell and n is Node3D:
			at_cell = _level.world_to_cell((n as Node3D).global_position) == c
		if at_cell:
			var nm: String = str(sc.resource_path).get_file() if sc else n.get_class()
			var note: String = str(n.get("note")) if n.get("note") != null else ""
			here.append(nm + ("(" + note.substr(0, 50) + ")" if note != "" else ""))
	var open_n := 0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		if _level.astar.region.has_point(c + d) and not _level.astar.is_point_solid(c + d):
			open_n += 1
	var rows: Array = []
	for y in range(c.y - 3, c.y + 4):
		var line := ""
		for x in range(c.x - 6, c.x + 7):
			var cc := Vector2i(x, y)
			if cc == c:
				line += "X"
			elif not _level.astar.region.has_point(cc):
				line += " "
			elif _level.astar.is_point_solid(cc):
				line += "#"
			else:
				line += _level.char_at(cc) if _level.char_at(cc) != " " else "#"
		rows.append(line)
	return "cell %s map char '%s', %d of 8 neighbours open, objects here: %s; surroundings (X = the cell, # = solid): %s" % [
		str(c), _level.char_at(c), open_n, ", ".join(here) if not here.is_empty() else "none", " / ".join(rows)]


func _why_print(c) -> void:
	if c is Vector2i:
		print("STRESS WHY %s %s" % [str(_cur.get("id", "?")), _why(c)])


func _flag(what: String) -> void:
	_cur["problems"].append(what)
	_problem(str(_cur.get("id", "?")), what)


func _count_nodes(n: Node) -> int:
	var c := 1
	for k in n.get_children():
		c += _count_nodes(k)
	return c


func _things(suffix: String) -> Array:
	var out := []
	for n in _level.get_children():
		var s = n.get_script()
		if s and str(s.resource_path).ends_with(suffix):
			out.append(n)
	return out


func _path(a: Vector2i, b: Vector2i) -> Array:
	var p: Array = _level.path_between(a, b)
	if not p.is_empty() or a == b:
		return p
	for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		p = _level.path_between(a, b + dv)
		if not p.is_empty():
			return p
	return []


func _reach(a: Vector2i, b: Vector2i) -> bool:
	## can the player stand next to (or on) b, coming from a -- things sit on cells the map marks solid
	if a == b or not _level.path_between(a, b).is_empty():
		return true
	for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		if not _level.path_between(a, b + dv).is_empty():
			return true
	return false


func _object_cells() -> Array:
	## cells taken by solid things placed on the map (chests, ore, shrines) -- what can plug a doorway
	var out := []
	for suffix in ["Chest.gd", "GatherNode.gd", "Shrine.gd"]:
		for n in _things(suffix):
			var oc = n.get("cell")
			if oc != null and _level.astar.region.has_point(oc) and _level.astar.is_point_solid(oc):
				out.append([suffix.get_basename(), oc])
	return out


func _frontier(start_cell: Vector2i, target: Vector2i) -> void:
	## diagnostic: flood from the arrival point over open cells, then name what sits on the solid cells at the edge
	var seen := {start_cell: true}
	var q: Array = [start_cell]
	var edge := {}
	while not q.is_empty():
		var c: Vector2i = q.pop_back()
		for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + dv
			if seen.has(n) or not _level.astar.region.has_point(n):
				continue
			if _level.astar.is_point_solid(n):
				if _level.char_at(n) != "#":
					edge[n] = true
			else:
				seen[n] = true
				q.append(n)
	var names := []
	for n in _level.get_children():
		if not (n is Node3D):
			continue
		var c: Vector2i = _level.world_to_cell((n as Node3D).global_position)
		if edge.has(c) and absi(c.x - target.x) <= 10 and absi(c.y - target.y) <= 10:
			var sc = n.get_script()
			names.append("%s@%s" % [str(sc.resource_path.get_file()) if sc else str(n.name), str(c)])
	print("STRESS FRONTIER %s reached=%d edge_solid=%d on_edge=%s" % [str(_cur.get("id", "?")), seen.size(), edge.size(), ", ".join(names.slice(0, 20))])


func _blockers(a: Vector2i, b: Vector2i) -> Array:
	## which placed objects sit on the only way from a to b (the shortest route if they were walk-through)
	var objs := _object_cells()
	for o in objs:
		_level.astar.set_point_solid(o[1], false)
	var path: Array = _path(a, b)
	for o in objs:
		_level.astar.set_point_solid(o[1], true)
	var hit := []
	for o in objs:
		if o[1] in path:
			hit.append(o)
	return hit


func _reachability(def: Dictionary) -> void:
	# secret walls and gates are doors the player opens: for "can you get there at all" they count as open
	var opened: Array = []
	for suffix in ["SecretWall.gd", "Gate.gd"]:
		for n in _things(suffix):
			var oc = n.get("cell")
			if oc != null and _level.astar.region.has_point(oc) and _level.astar.is_point_solid(oc):
				_level.astar.set_point_solid(oc, false)
				opened.append(oc)
	var start_cell: Vector2i = _level.world_to_cell(_player.global_position)
	var exits := _things("Exit.gd")
	var is_dungeon: bool = str(_level.def.get("theme", "dungeon")) == "dungeon"
	if is_dungeon and exits.is_empty():
		_flag("a dungeon floor with no exits")
	var unreachable := []
	for e in exits:
		if not _reach(start_cell, e.cell):
			unreachable.append(["exit to %s at %s" % [e.target, str(e.cell)], e.cell])
	# things you are meant to be able to get to (hidden things sit behind secret walls on purpose -- those are skipped)
	var checked := 0
	for suffix in ["Chest.gd", "GatherNode.gd", "Shrine.gd"]:
		for n in _things(suffix):
			var c = n.get("cell")
			if c == null:
				continue
			var hid = n.get("hidden")
			if hid != null and hid == true:
				continue
			checked += 1
			if not _reach(start_cell, c):
				unreachable.append(["%s at %s" % [suffix.get_basename(), str(c)], c])
	_cur["unreachable"] = unreachable.size()
	_cur["checked"] = checked
	if not unreachable.is_empty():
		var plugs := {}
		for u in unreachable:
			for b in _blockers(start_cell, u[1]):
				if not plugs.has(str(b[0]) + " at " + str(b[1])):
					_why_print(b[1])
				plugs[str(b[0]) + " at " + str(b[1])] = true
		if not plugs.is_empty():
			_cur["plug_msg"] = "%d places can't be reached by the map's pathing: solid %s sits in the only way through" % [unreachable.size(), " / ".join(plugs.keys().slice(0, 4))]
		else:
			_frontier(start_cell, unreachable[0][1])
			for u in unreachable.slice(0, 5):
				_flag("can't get to " + str(u[0]) + " from the arrival point")
				_why_print(u[1])
			if unreachable.size() > 5:
				_flag("...and %d more places nobody can get to" % (unreachable.size() - 5))
	# the critical path for the walk: arrival -> the exit that goes deeper (else any exit)
	var goal = null
	for e in exits:
		if bool(e.down):
			goal = e
			break
	if goal == null and not exits.is_empty():
		goal = exits[0]
	_hops.clear()
	for oc in opened:
		_level.astar.set_point_solid(oc, true)
	if goal != null:
		var path: Array = _path(start_cell, goal.cell)
		if path.is_empty():
			# no plain way. 1) with the placed objects (chests, ore) out of the way -- the walk tells us if the player really fits past
			var objs := _object_cells()
			for o in objs:
				_level.astar.set_point_solid(o[1], false)
			path = _path(start_cell, goal.cell)
			for o in objs:
				_level.astar.set_point_solid(o[1], true)
			if not path.is_empty():
				_cur["via_objects"] = true
			else:
				# 2) only through a secret wall or a locked gate: not walked (they are doors you have to open), but said out loud
				var gate_cells: Array = []
				for g in _things("Gate.gd"):
					if g.get("cell") != null and g.cell in opened:
						gate_cells.append(g.cell)
				for oc in gate_cells:
					_level.astar.set_point_solid(oc, false)
				var thru: Array = _path(start_cell, goal.cell)
				for oc in gate_cells:
					_level.astar.set_point_solid(oc, true)
				if not thru.is_empty():
					_cur["needs_door"] = true          # a locked gate (the floor's key, or levers): by design
					_cur["path_cells"] = thru.size()
				else:
					for oc in opened:
						_level.astar.set_point_solid(oc, false)
					thru = _path(start_cell, goal.cell)
					for oc in opened:
						_level.astar.set_point_solid(oc, true)
					if not thru.is_empty():
						_flag("the only way on from the arrival point is through a SECRET wall (a player who doesn't find it is stuck on this floor)")
						for oc in opened:
							_why_print(oc)
		var i := HOP
		while i < path.size() and _hops.size() < MAX_HOPS:
			_hops.append(path[i])
			i += HOP
		if not path.is_empty():
			_hops.append(path[path.size() - 1])
			_cur["path_cells"] = path.size()
		_cur["hops"] = _hops.size()
	_hop_i = 0
	_hop_wait = 0


func _measure_frames() -> void:
	## wall time between frames, with the engine's frame cap off, so it is what the scripts and physics really cost
	var now := Time.get_ticks_usec()
	if _frames >= SETTLE:
		# run every foe's own per-frame code by hand and time it: what the AI of everything awake costs per frame
		var t_us := Time.get_ticks_usec()
		for e in get_nodes_in_group("enemy"):
			if is_instance_valid(e):
				e._process(0.016)
				e._physics_process(0.016)
		_frame_ms.append((Time.get_ticks_usec() - t_us) / 1000.0)
	_last_us = now
	_frames += 1
	if _frames < FRAME_SAMPLES + SETTLE:
		return
	var sum := 0.0
	var worst := 0.0
	for x in _frame_ms:
		sum += float(x)
		worst = maxf(worst, float(x))
	_cur["frame_ms_avg"] = snappedf(sum / maxf(1.0, _frame_ms.size()), 0.1)
	_cur["frame_ms_max"] = snappedf(worst, 0.1)
	_cur["objects"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	if float(_cur.get("build_ms", 0.0)) > SLOW_BUILD_MS:
		_flag("took %.1f s to build (more than %.0f s)" % [float(_cur["build_ms"]) / 1000.0, SLOW_BUILD_MS / 1000.0])
	if float(_cur["frame_ms_avg"]) > SLOW_FRAME_MS:
		_flag("the foes' own code costs %.1f ms a frame with all of them awake (budget %.0f ms)" % [_cur["frame_ms_avg"], SLOW_FRAME_MS])
	# the walk: nothing hits the player on the way (this is about the ground, not the fights)
	for e in get_nodes_in_group("enemy"):
		e.queue_free()
	_hop_wait = 0
	_phase = 2


func _walk() -> void:
	## the player really walks the critical path: its own collision shape, the level's real walls and props
	if _hop_i >= _hops.size():
		_phase = 3
		return
	var want: Vector3 = _level.cell_to_world(_hops[_hop_i])
	if _hop_wait == 0:
		if _hop_i == 0:
			_player.set_physics_process(false)         # we drive it; its own input code would stop it
			_player.global_position = _level.cell_to_world(_level.world_to_cell(_player.global_position)) + Vector3(0, 0.6, 0)
		G.hp = maxi(int(G.hp), 50)
	_hop_wait += 1
	var blocked_by := ""
	for k in 24:
		var d: Vector3 = want - _player.global_position
		d.y = 0.0
		if d.length() < 0.5:
			break
		_player.velocity = d.normalized() * 6.0 + Vector3(0, -3.0, 0)
		_player.move_and_slide()
		if _player.get_slide_collision_count() > 0 and d.length() > 0.5:
			var col = _player.get_last_slide_collision().get_collider()
			if col:
				var holder = col
				while holder and not holder.get_script() and holder != _level:
					holder = holder.get_parent()
				blocked_by = (str(holder.get_script().resource_path.get_file()) if holder and holder.get_script() else str(col.get_class())) + " '" + str(col.name) + "' at cell " + str(_level.world_to_cell(col.global_position)) + " char '" + str(_level.char_at(_level.world_to_cell(col.global_position))) + "'"
	var p: Vector3 = _player.global_position
	var left := Vector2(p.x - want.x, p.z - want.z).length()
	if p.y < -2.0:
		_flag("the player falls out of the world near cell %s (no ground there)" % str(_hops[_hop_i]))
		_phase = 3
		return
	if left < 0.6:
		_hop_i += 1
		_hop_wait = 0
		if _hop_i >= _hops.size():
			_cur["walked"] = true
	elif _hop_wait > 40 and not bool(_cur.get("retry_%d" % _hop_i, false)):
		# a real player slides round a wall corner; this bot doesn't, and sometimes catches one. Put it back on the
		# centre of the previous stop and let it try this hop once more -- a wall that really blocks it still does.
		_cur["retry_%d" % _hop_i] = true
		var back: Vector3 = _level.cell_to_world(_hops[maxi(_hop_i - 1, 0)])
		_player.global_position = Vector3(back.x, _player.global_position.y, back.z)
		_hop_wait = 1
	elif _hop_wait > 40:
		_cur["stuck"] = true
		_why_print(_hops[mini(_hop_i, _hops.size() - 1)])
		_flag("the player can't walk on from cell %s -- stuck %.1f m short%s" % [str(_hops[maxi(_hop_i - 1, 0)]), left, (" (blocked by " + blocked_by + ")") if blocked_by != "" else ""])
		_phase = 3


func _end_floor(id: String) -> void:
	if bool(_cur.get("needs_door", false)):
		print("STRESS NOTE %s: the way on goes through a locked gate (the floor's key or its levers)" % id)
	if _cur.has("plug_msg") and (_cur.has("via_objects") or not bool(_cur.get("needs_door", false))):
		if bool(_cur.get("walked", false)):
			_flag(str(_cur["plug_msg"]) + " -- the player can squeeze through, but foes' pathing treats it as a wall")
		elif bool(_cur.get("stuck", false)):
			_flag(str(_cur["plug_msg"]) + " -- and the player really can't get past it: a SOFTLOCK")
		else:
			_flag(str(_cur["plug_msg"]))
	_cur["ok"] = _cur["problems"].is_empty()
	_report["floors"].append(_cur)
	print("STRESS %s %s build=%sms nodes=%s foes=%s foes_cost=%s/%sms path=%s hops=%s unreachable=%s%s" % [
		"OK  " if _cur["ok"] else "FAIL", id, _cur.get("build_ms", "?"), _cur.get("nodes", "?"), _cur.get("enemies", "?"),
		_cur.get("frame_ms_avg", "?"), _cur.get("frame_ms_max", "?"), _cur.get("path_cells", "-"), _cur.get("hops", 0), _cur.get("unreachable", "?"),
		"" if _cur["ok"] else "  <- " + "; ".join(_cur["problems"].slice(0, 3))])
	if is_instance_valid(_player):
		_player.queue_free()
	if is_instance_valid(_level):
		_level.queue_free()
	for e in get_nodes_in_group("enemy"):
		e.queue_free()
	_i += 1
	_phase = 0


func _finish() -> bool:
	if _do_econ:
		if G == null:
			_setup_game()
		_economy()
		_saveload()
	var f := FileAccess.open("user://stress_report.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_report, "  "))
	print("STRESS DONE %d floors, %d problems" % [_report["floors"].size(), _problems])
	_phase = -1
	quit(1 if _problems > 0 else 0)
	return true


# ---------------------------------------------------------------------------------------------------------------
# the economy
# ---------------------------------------------------------------------------------------------------------------

func _econ_flag(what: String) -> void:
	_report["economy"].append(what)
	_problem("economy", what)


func _economy() -> void:
	var factor: float = float(G.economy_data().get("cheapest_buy_factor", 1.156))
	var checked := 0
	var priced := 0
	# every item: the cheapest any shop could ever sell it must stay above what a trader pays for it
	for id in G.items:
		var d: Dictionary = G.items[id]
		if not d.has("value"):
			continue
		var v := float(d.get("value", 0))
		if v < 0.0:
			_econ_flag("%s has a negative value (%s)" % [id, str(v)])
			continue
		G.inventory[id] = 1
		var sp: int = G.sell_price(id)
		G.inventory.erase(id)
		checked += 1
		if sp <= 0:
			continue
		priced += 1
		# the cheapest a shop can ever ask, rounded the way NPC.trade_stock rounds: x2, a story debt 15% off, top standing 15% off, a harvest festival 20% off
		var cheapest_buy := maxi(1, int(round(v * 2.0)))
		cheapest_buy = maxi(1, int(round(float(cheapest_buy) * 0.85)))
		cheapest_buy = maxi(1, int(round(float(cheapest_buy) * 0.85 * 0.8)))
		if sp >= cheapest_buy:
			_econ_flag("buy-then-sell loop: %s sells for %d but the cheapest shop price is %d" % [id, sp, cheapest_buy])
	# every recipe: what the made thing sells for must not beat what its materials cost to buy
	var loops := 0
	for r in G.recipes:
		var mk := str(r.get("makes", ""))
		if mk == "" or not G.items.has(mk):
			continue
		var cost := float(r.get("gold", 0))
		for need in r.get("needs", {}):
			cost += float(G.items.get(G.base_id(str(need)), {}).get("value", 0)) * float(r["needs"][need]) * factor
		G.inventory[mk] = 1
		var revenue: float = float(G.sell_price(mk)) * float(r.get("count", 1))
		G.inventory.erase(mk)
		if revenue > cost and revenue > 0.0:
			loops += 1
			_econ_flag("craft-then-sell loop: %s sells for %d but its materials cost %.0f" % [mk, int(revenue), cost])
	# nothing asked for in a negative amount may give anything
	var gold0: int = G.gold
	G.add_item("gold", -50)
	if G.gold != gold0:
		_econ_flag("add_item('gold', -50) changed gold %d -> %d" % [gold0, G.gold])
	G.inventory["iron_ore"] = 3
	var before: int = G.count("iron_ore")
	G.add_item("iron_ore", -4)
	G.remove_item("iron_ore", -4)
	if G.count("iron_ore") != before:
		_econ_flag("a negative amount of iron_ore changed the count %d -> %d" % [before, G.count("iron_ore")])
	var got: int = G.sell("iron_ore", -3)
	if got != 0 or G.count("iron_ore") != before:
		_econ_flag("selling a negative amount paid %d or changed the stack" % got)
	var g1: int = G.gold
	var sold: int = G.sell("iron_ore", 1000)
	if sold > 0 and G.count("iron_ore") != 0:
		_econ_flag("selling more than you hold left %d in the stack" % G.count("iron_ore"))
	if G.gold != g1 + sold:
		_econ_flag("gold after a sale (%d) isn't gold before + what was paid (%d + %d)" % [G.gold, g1, sold])
	G.inventory.erase("iron_ore")
	# a craft you can't afford must not happen, and must not cost anything
	for r in G.recipes:
		if int(r.get("gold", 0)) > 0:
			var gold_save: int = G.gold
			G.gold = 0
			var ok: bool = G.craft(r)
			if ok or G.gold != 0:
				_econ_flag("crafting %s with no gold worked or changed gold (gold=%d)" % [str(r.get("makes", "?")), G.gold])
			G.gold = gold_save
			break
	# numbers that must stay numbers
	for k in ["hp", "gold", "qi"]:
		var val = G.get(k)
		if typeof(val) == TYPE_FLOAT and (is_nan(val) or is_inf(val)):
			_econ_flag("%s is %s" % [k, str(val)])
		elif float(val) < 0.0:
			_econ_flag("%s is negative (%s) at the start of a new game" % [k, str(val)])
	print("STRESS ECON checked %d items (%d sellable), %d recipes, %d loops" % [checked, priced, G.recipes.size(), loops])


# ---------------------------------------------------------------------------------------------------------------
# save and load
# ---------------------------------------------------------------------------------------------------------------

func _snapshot() -> Dictionary:
	return {"gold": G.gold, "hp": G.hp, "inv": G.inventory.duplicate(), "realm": G.realm, "sublevel": G.sublevel,
		"flags": G.flags.size(), "marks": G.marks}


func _sl_flag(what: String) -> void:
	_report["saveload"].append(what)
	_problem("save/load", what)


func _saveload() -> void:
	G.new_game()
	G.add_item("gold", 777)
	G.add_item("healing_salve", 3)
	G.add_item("iron_ore", 9)
	G.set_flag("stress:probe")
	G.save_game()
	var a := _snapshot()
	# change things, load, they must come back exactly -- and a second load must not add anything
	G.add_item("gold", 100000)
	G.add_item("healing_salve", 50)
	G.gold -= 100
	if not G.load_game():
		_sl_flag("load_game() returned false right after save_game()")
		return
	var b := _snapshot()
	for k in a:
		if str(a[k]) != str(b[k]):
			_sl_flag("after save -> change -> load, %s is %s (was %s when saved)" % [k, str(b[k]), str(a[k])])
	G.load_game()
	var c := _snapshot()
	for k in b:
		if str(b[k]) != str(c[k]):
			_sl_flag("loading twice changed %s: %s -> %s (duplication)" % [k, str(b[k]), str(c[k])])
	G.save_game()
	G.load_game()
	var d := _snapshot()
	for k in c:
		if str(c[k]) != str(d[k]):
			_sl_flag("save -> load -> save -> load drifted %s: %s -> %s" % [k, str(c[k]), str(d[k])])
	if not G.has_flag("stress:probe"):
		_sl_flag("a flag set before saving is gone after loading")
	print("STRESS SAVELOAD %s" % ("ok" if _report["saveload"].is_empty() else "%d problems" % _report["saveload"].size()))

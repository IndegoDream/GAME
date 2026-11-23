extends SceneTree
## w007: the Atlas remembers where you've been and what you found (saved and loaded with the game)
var passed := 0
var failed := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("FAIL ", name, "  [", detail, "]")

func _enter(G, id: String) -> Node:
	var level = load("res://scripts/world/Level.gd").new()
	level.name = "Level"
	level.build(G.load_level_def(id))
	root.add_child(level)
	G.current_level = id
	G.mark_level_entered(id, level.counts)
	return level

func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	var A = G.sys("atlas")
	_ok("the atlas system is registered", A != null)
	if A == null:
		print("CHECK %d passed, %d failed" % [passed, failed])
		quit()
		return
	A.reset()
	var lv = _enter(G, "village")
	await process_frame
	_ok("entering a place records it", A.visited("village"))
	var n0: int = A.visits.size()
	A.visit("village")
	_ok("coming back doesn't add it twice", A.visits.size() == n0 and int(A.visit_row("village").get("n", 0)) == 2)
	_ok("a place drawn fresh each time keeps nothing", not A.forgettable("village") and A.forgettable("trial:2026-01-01") == true or A.forgettable("tribulation:x"))
	# landmarks: the village's exits are marked once you are near them
	var found: int = A.scan_live()
	var cands: Array = A.candidates(lv)
	_ok("the village has landmarks to find", cands.size() > 0, str(cands.size()))
	lv.free()
	await process_frame
	var lv1 = _enter(G, "floor1")
	await process_frame
	_ok("a second place comes after the first", A.visits.size() == 2 and str(A.visits[1]["id"]) == "floor1")
	# the fog of war's seen set is the atlas's too: reveal the cells around the way down, then it is marked
	var fog = A.fog_node(lv1)
	_ok("floor 1 keeps a fog of war", fog != null)
	var before: int = A.marks_for("floor1").size()
	var down: Array = lv1.spawns.get(">", [])
	_ok("floor 1 has a way down", not down.is_empty())
	if fog != null and not down.is_empty():
		var c: Vector2i = down[0]
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				fog.seen[c + Vector2i(dx, dy)] = true
		A.scan_live()
		var m: Array = A.marks_for("floor1")
		var has_exit := false
		for mk in m:
			if str(mk["kind"]) == "exit" and int(mk["x"]) == c.x and int(mk["y"]) == c.y:
				has_exit = true
		_ok("a way out you've seen is marked", has_exit, str(m))
		_ok("marking is once only", A.scan_live() == 0)
		_ok("a landmark you haven't seen isn't marked", m.size() < A.candidates(lv1).size(), "%d of %d" % [m.size(), A.candidates(lv1).size()])
	# save and load
	var st: Dictionary = A.save_state()
	var j: String = JSON.stringify(st)
	A.reset()
	_ok("a new game forgets", A.visits.is_empty() and A.marks.is_empty())
	A.load_state(JSON.parse_string(j))
	_ok("saving and loading keeps the places and the marks", A.visits.size() == 2 and A.marks_for("floor1").size() >= 1)
	# the world overview comes from data
	var w: Array = A.world_nodes()
	var lit := 0
	var floors := 0
	for nd in w:
		if str(nd["kind"]) == "floor":
			floors += 1
		if bool(nd["visited"]):
			lit += 1
	_ok("the world lists the village, the valley and every floor", floors >= 50 and w.size() >= 52, "%d floors, %d nodes" % [floors, w.size()])
	_ok("the places you've been are lit", lit == 2, str(lit))
	_ok("your route is in the order you went", A.route() == ["village", "floor1"], str(A.route()))
	lv1.free()
	print("CHECK %d passed, %d failed" % [passed, failed])
	quit()

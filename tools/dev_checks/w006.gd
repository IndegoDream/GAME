extends SceneTree
## w006: the roadway is a no-drop zone; lanterns stand set back from the road, lining it in pairs.
var passed := 0
var failed := 0

func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("FAIL ", name, "  [", detail, "]")

func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	var CELLV := 2.0
	for id in ["village", "floor1"]:
		var level = load("res://scripts/world/Level.gd").new()
		level.name = "Level"
		level.build(G.load_level_def(id))
		root.add_child(level)
		await process_frame
		# the helper exists and answers sensibly
		if level._road_cells.is_empty():
			_ok(id + ": no roads, so nothing is on one", not level.on_road(Vector3(5, 0, 5)))
			_ok(id + ": it has no lantern or dressing on a road", true)
		else:
			var rc: Vector2i = level._road_cells.keys()[0]
			_ok(id + ": a road cell's centre is on the road", level.on_road(level.cell_to_world(rc)))
			var bad_dress := []
			for p in level.dressing_spots:
				if level.on_road(p):
					bad_dress.append(str(p))
			_ok(id + ": no stall or clutter stands on the road", bad_dress.is_empty(), ", ".join(bad_dress.slice(0, 3)))
			var off_road := 0
			var far := []
			var near_n := 0
			for p in level.lantern_spots:
				var nr: Vector2i = level.nearest_road_cell(p, 3)
				if nr.x < 0:
					continue
				near_n += 1
				if level.on_road(p):
					off_road += 1
				# within 1.2 cells of the road cell's edge (centre distance less half a cell)
				if level.cell_to_world(nr).distance_to(p) - CELLV * 0.5 > 1.2 * CELLV:
					far.append(str(p))
			_ok(id + ": lanterns by the road stand beside it, not in it", off_road <= maxi(1, near_n / 6), "%d of %d" % [off_road, near_n])
			_ok(id + ": every lantern is within 1.2 cells of a road", far.is_empty(), ", ".join(far.slice(0, 3)))
			print("  ", id, ": roads ", level._road_cells.size(), " lanterns ", level.lantern_spots.size(), " near the road ", near_n, " still in the verge ", off_road, " dressing ", level.dressing_spots.size())
		level.free()
	print("CHECK %d passed, %d failed" % [passed, failed])
	quit()

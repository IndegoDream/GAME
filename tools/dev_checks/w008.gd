extends SceneTree
## w008: the map page opens and draws for the village and floor 1 without errors
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
	A.reset()
	var m = load("res://scripts/ui/MapScreen.gd").new()
	m.setup(null)
	root.add_child(m)
	m.size = Vector2(1000, 640)
	for id in ["village", "floor1"]:
		var lv = _enter(G, id)
		await process_frame
		var fog = A.fog_node(lv)
		if fog != null:
			for y in range(0, lv.height, 2):
				for x in range(0, lv.width, 2):
					fog.seen[Vector2i(x, y)] = true
		A.scan_live()
		m.view = "place"
		m.refresh()
		await process_frame
		_ok(id + ": the map page draws the place", m.tex != null and m.tex_size.x > 0 and m.tex_size.y > 0)
		var img: Image = m.tex.get_image() if m.tex != null else null
		var lit := 0
		if img != null:
			for y in img.get_height():
				for x in img.get_width():
					if img.get_pixel(x, y).a > 0.5:
						lit += 1
		_ok(id + ": what's been seen is coloured in", lit > 20, str(lit))
		if fog != null:
			_ok(id + ": unseen cells stay dark", lit < m.tex_size.x * m.tex_size.y, "%d of %d" % [lit, m.tex_size.x * m.tex_size.y])
		_ok(id + ": it says where you are and how much is explored", m._info.text.find("explored") >= 0, m._info.text)
		m.zoom_by(2.0)
		m.recentre()
		await process_frame
		_ok(id + ": zoom and centre work", m.zoom > 1.5)
		m.zoom = 1.0
		lv.free()
		await process_frame
	# the world view
	m.set_view("world")
	await process_frame
	await process_frame
	_ok("the world view has places to draw", m.nodes_world.size() >= 52, str(m.nodes_world.size()))
	var pos: Vector2 = m.world_pos(m.nodes_world[2])
	_ok("places sit inside the page", pos.x >= 0 and pos.x <= 1000 and pos.y >= 0 and pos.y <= 640, str(pos))
	m._tap(pos)
	_ok("tapping a place reads about it", m.picked != "" and m._info.text.length() > 3, m._info.text)
	m.set_view("place")
	await process_frame
	_ok("and back to this place", m.view == "place")
	print("CHECK %d passed, %d failed" % [passed, failed])
	quit()

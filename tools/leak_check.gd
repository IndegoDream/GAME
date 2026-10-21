extends SceneTree
## round 158: change level 36 times -- the world must not keep growing (nodes, orphans, objects)
var fails := 0
var total := 0
func check(what: String, ok: bool) -> void:
	total += 1
	if not ok:
		fails += 1
		print("  FAIL: ", what)
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.save_path = "user://leak_save.json"
	G.save_base = "user://leak_slots"
	G.playlog_path = "user://leak_playlog.jsonl"
	var MainS = load("res://Main.gd")
	MainS.force_veil = true
	load("res://scripts/world/Level.gd").stream_on = true
	var m = load("res://Main.tscn").instantiate()
	root.add_child(m)
	for i in 5:
		await process_frame
	var ids := ["floor1", "village", "floor5", "floor9", "floor21", "village"]
	var samples := []
	for round in 6:
		for id in ids:
			G.go_to(id, "<" if id != "village" else "P")
			for i in 14:
				await process_frame
		for i in 10:
			await process_frame
		samples.append([int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_COUNT))])
		print("  round ", round, " nodes/orphans/objects ", samples[-1])
	var a: Array = samples[1]
	var b: Array = samples[5]
	check("orphan nodes do not pile up (%d -> %d)" % [a[1], b[1]], int(b[1]) <= int(a[1]) + 50)
	check("node count steady (%d -> %d)" % [a[0], b[0]], int(b[0]) <= int(a[0]) * 1.15 + 200)
	check("objects steady (%d -> %d)" % [a[2], b[2]], int(b[2]) <= int(a[2]) * 1.2 + 500)
	MainS.force_veil = false
	load("res://scripts/world/Level.gd").stream_on = false
	print("leak_check: %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)

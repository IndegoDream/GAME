extends SceneTree
## round 158: the loading screen path -- veil up before the build, level changes, a second request mid-load is not dropped
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
	G.save_path = "user://veil_save.json"
	G.save_base = "user://veil_slots"
	G.playlog_path = "user://veil_playlog.jsonl"
	var MainS = load("res://Main.gd")
	MainS.force_veil = true
	var m = load("res://Main.tscn").instantiate()
	root.add_child(m)
	for i in 6:
		await process_frame
	check("starts in a level", m.level != null)
	G.go_to("floor1", "<")
	await process_frame            # the deferred request lands
	await process_frame
	var veil = m._loading_screen
	check("veil exists", veil != null)
	check("veil is up while loading", veil != null and veil.visible and m._changing)
	for i in 8:
		await process_frame
	check("arrived at floor1", G.current_level == "floor1" and m.level.level_id == "floor1")
	check("not stuck loading", not m._changing)
	# two requests close together: both are honoured, the last one wins
	G.go_to("village", "P")
	await process_frame
	await process_frame
	G.go_to("floor2", "<")
	for i in 20:
		await process_frame
	check("second request was not dropped", m.level.level_id == "floor2" and G.current_level == "floor2")
	check("ends unstuck", not m._changing)
	for i in 30:
		await process_frame
	check("veil gone", not m._loading_screen.visible)
	MainS.force_veil = false
	print("veil_check: %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)

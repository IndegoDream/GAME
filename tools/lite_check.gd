extends SceneTree
## round 124: the Lite world (village + dungeon only on a phone), and the way back to Full.
var G
var passed := 0
var failed := 0
var frames := 0
func check(n: String, ok: bool, d: String = "") -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("  FAIL  " + n + ("  [" + d + "]" if d != "" else ""))
func _process(_dt: float) -> bool:
	frames += 1
	if frames < 3:
		return false
	G = root.get_node_or_null("Game")
	var Gfx = load("res://scripts/core/Gfx.gd")
	Gfx.load_settings()
	var keep = Gfx.settings.get("world", "auto")
	Gfx.settings["world"] = "full"
	check("full: valley open", not G.lite_blocked("valley"))
	check("full: frontier open", not G.lite_blocked("frontier:crash_site"))
	Gfx.settings["world"] = "lite"
	check("lite: world_lite", Gfx.world_lite())
	check("lite: valley shut", G.lite_blocked("valley"))
	check("lite: frontier shut", G.lite_blocked("frontier:ashen_moon"))
	check("lite: a tower shut", G.lite_blocked("tower:x:1") == G.TowerGen.is_tower("tower:x:1"))
	check("lite: village open", not G.lite_blocked("village"))
	for i in [1, 10, 25, 50]:
		check("lite: floor%d open" % i, not G.lite_blocked("floor%d" % i))
	check("lite: a message for the road", G.lite_message().find("Full") >= 0)
	# a save from the valley wakes in the village
	var path := "user://lite_test_save.json"
	G.save_base = "user://lite_test"
	G.current_level = "valley"
	G.save_game()
	G.current_level = "valley"
	var ok: bool = G.load_game()
	check("lite: load works", ok)
	check("lite: a valley save wakes in the village", G.current_level == "village", G.current_level)
	# the cycle
	Gfx.settings["world"] = "auto"
	var seen := {}
	for i in 3:
		seen[Gfx.next_world()] = true
	check("world cycles auto -> lite -> full", seen.size() == 3)
	Gfx.settings["world"] = keep
	Gfx.save_settings()
	for f in DirAccess.get_files_at("user://"):
		if f.begins_with("lite_test"):
			DirAccess.remove_absolute("user://" + f)
	print("LITE CHECK %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
	return true

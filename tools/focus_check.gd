extends SceneTree
## Round 157: who gets the E key (the one you face; followers last), and the player stays put while a menu holds the world.
var G
var fails := 0
var total := 0
func check(what: String, ok: bool) -> void:
	total += 1
	if not ok:
		fails += 1
		print("  FAIL: ", what)
func _mk(pos: Vector3, low: bool, nm: String) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	root.add_child(n)
	n.global_position = pos
	n.add_to_group("interactable")
	if low:
		n.set_meta("low_priority", true)
	return n
func _initialize() -> void:
	await process_frame
	G = root.get_node("Game")
	G.playlog_path = "user://tool_playlog.jsonl"
	G.save_path = "user://focus_save.json"
	G.save_base = "user://focus_slots"
	G.new_game()
	var P = (load("res://scripts/actors/Player.gd") as GDScript).new()
	root.add_child(P)
	await process_frame
	P.global_position = Vector3.ZERO
	P._model.rotation.y = 0.0                 # facing +z
	var npc := _mk(Vector3(0, 0, 2.5), false, "npc")
	var f1 := _mk(Vector3(1.0, 0, -0.5), true, "follower1")
	var f2 := _mk(Vector3(-0.8, 0, 0.3), true, "follower2")
	check("the NPC you face beats two close followers", P._nearest_interactable() == npc)
	npc.queue_free()
	await process_frame
	P._model.rotation.y = PI / 2.0             # facing +x: follower1 is ahead
	check("with nobody else, the follower you face wins", P._nearest_interactable() == f1)
	P._model.rotation.y = -PI / 2.0            # facing -x: follower2 is ahead
	check("turn the other way: the other follower", P._nearest_interactable() == f2)
	var chest := _mk(Vector3(0.3, 0, -0.3), false, "chest")
	check("a chest at your feet still comes before followers", P._nearest_interactable() == chest)
	# the frozen world: no moving, no falling
	G.world_frozen = true
	P.velocity = Vector3(5, -30, 0)
	var y0: float = P.global_position.y
	P._physics_process(0.1)
	check("frozen: velocity zeroed", P.velocity == Vector3.ZERO)
	check("frozen: did not fall", is_equal_approx(P.global_position.y, y0))
	G.world_frozen = false
	print("focus_check: %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)

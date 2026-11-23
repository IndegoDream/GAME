extends SceneTree
## Round 157b: the REAL scene. With a menu page open the player must not move, fall or leave the level, whatever is held.
var fails := 0
var total := 0
func check(what: String, ok: bool) -> void:
	total += 1
	if not ok:
		fails += 1
		print("  FAIL: ", what)
func _initialize() -> void:
	var G = root.get_node("Game")
	G.playlog_path = "user://tool_playlog.jsonl"
	G.save_path = "user://mw_save.json"
	G.save_base = "user://mw_slots"
	var m: Node = (load("res://Main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 40:
		await physics_frame
	var pl = m.player
	check("player exists", pl != null)
	var lv = m.level
	check("level exists", lv != null)
	for i in 30:
		await physics_frame
	var p0: Vector3 = pl.global_position
	var hud = m.hud
	hud.open_hub("Party")
	for i in 5:
		await physics_frame
	check("menu pages open", hud.menu_pages_open())
	check("world frozen", G.world_frozen)
	# hold everything a hand might hold
	for a in ["move_forward", "move_left", "sprint", "jump", "dodge", "wind_step", "attack"]:
		Input.action_press(a)
	for i in 240:
		await physics_frame
	for a in ["move_forward", "move_left", "sprint", "jump", "dodge", "wind_step", "attack"]:
		Input.action_release(a)
	var p1: Vector3 = pl.global_position
	print("moved %.2f m (dy %.2f)" % [Vector2(p1.x - p0.x, p1.z - p0.z).length(), p1.y - p0.y])
	check("did not walk", Vector2(p1.x - p0.x, p1.z - p0.z).length() < 0.3)
	check("did not fall", absf(p1.y - p0.y) < 0.3)
	hud._hub.close_hub()
	for i in 60:
		await physics_frame
	check("world thawed", not G.world_frozen)
	var p2: Vector3 = pl.global_position
	check("still where it was after closing", Vector2(p2.x - p0.x, p2.z - p0.z).length() < 0.6)
	var cell: Vector2i = lv.world_to_cell(p2)
	check("inside the level", lv.char_at(cell) != " " or lv.is_walkable_char(lv.char_at(cell)))
	print("menu_walk_check: %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)

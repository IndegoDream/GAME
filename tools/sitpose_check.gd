extends SceneTree
## Round 141c: navigating the menu (clicks, page changes, a gear change) must not stand you up from meditation.
var fails := 0
func check(w: String, ok: bool) -> void:
	if not ok:
		fails += 1
		print("  FAIL: ", w)
func _press() -> void:
	var e := InputEventAction.new()
	e.action = "attack"
	e.pressed = true
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _release() -> void:
	var e := InputEventAction.new()
	e.action = "attack"
	e.pressed = false
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.save_path = "user://sit_save.json"
	G.new_game()
	var main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	var hud = get_first_node_in_group("hud")
	var pl = get_first_node_in_group("player")
	check("player and hud exist", pl != null and hud != null)
	pl.start_meditating(false)
	for i in 5:
		await physics_frame
	check("sitting", pl.meditating and pl._anim.current_animation == "sit")
	hud.open_hub("Craft")
	for i in 3:
		await physics_frame
	check("menu open blocks", hud.is_blocking())
	_press()
	await physics_frame
	await physics_frame
	_release()
	for sec in ["Craft", "Party", "You"]:
		hud._hub.show_page(sec)
		await physics_frame
	check("a click in the menu does not stand you up", pl.meditating and G.sitting)
	pl.rebuild_model()
	for i in 3:
		await physics_frame
	check("a rebuilt body keeps the sitting pose", pl._anim.current_animation == "sit")
	hud._hub.close_hub()
	for i in 3:
		await physics_frame
	check("closing the menu keeps you sitting", pl.meditating)
	print("SITPOSE CHECK %d failed" % fails if fails > 0 else "SITPOSE CHECK 4 passed, 0 failed")
	quit(1 if fails > 0 else 0)

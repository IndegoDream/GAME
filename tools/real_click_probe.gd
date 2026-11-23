extends SceneTree
## the REAL game (Main) in a window: open the Pack page and click an item for real. xvfb-run godot --path . --resolution 1280x720 --script res://tools/real_click_probe.gd
func _click(p: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = p
	m.global_position = p
	root.push_input(m)
	for t in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.position = p
		e.global_position = p
		e.pressed = t
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if t else 0
		root.push_input(e)
		await process_frame

func _initialize() -> void:
	var main_scene: PackedScene = load(str(ProjectSettings.get_setting("application/run/main_scene")))
	var inst: Node = main_scene.instantiate()
	root.add_child(inst)
	var hud: Node = null
	var n := 0
	while hud == null and n < 900:
		await process_frame
		n += 1
		hud = get_first_node_in_group("hud")
	print("hud after frames: ", n)
	for i in 120:
		await process_frame
	var G = root.get_node("Game")
	for id in ["healing_salve", "iron_sword", "qi_pill"]:
		G.add_item(id, 2, false)
	print("title visible: ", hud._title != null and hud._title.visible, " blocking: ", hud.is_blocking(), " mouse_mode: ", Input.mouse_mode)
	var hub = hud._hub
	hub.show_page("Pack")
	for i in 40:
		await process_frame
	print("hub visible: ", hub.visible, " mouse_mode: ", Input.mouse_mode)
	var pg: Control = hub.pages["Pack"]
	var slots: Array = pg.find_children("*", "Button", true, false).filter(func(b): return b.is_visible_in_tree() and (b as Button).icon != null and b.size.x > 40)
	print("slot buttons: ", slots.size())
	for k in mini(3, slots.size()):
		var b := slots[k] as Button
		var c: Vector2 = b.get_global_rect().get_center()
		await _click(c)
		await process_frame
		var hov = root.gui_get_hovered_control()
		print("clicked ", b.tooltip_text, " at ", c, " hovered=", hov, " bag_sel=", hud._kit.bag_sel)
		slots = pg.find_children("*", "Button", true, false).filter(func(bb): return bb.is_visible_in_tree() and (bb as Button).icon != null and bb.size.x > 40)
	quit()

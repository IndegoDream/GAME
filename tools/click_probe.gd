extends SceneTree
## can every visible button on a menu page actually be clicked? godot --path . --resolution 1280x720 --script res://tools/click_probe.gd -- [pages]
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
	await process_frame
	var a := OS.get_cmdline_user_args()
	var only: Array = (a[0] as String).split(",") if a.size() > 0 else ["Pack"]
	var G = root.get_node("Game")
	G.new_game()
	for id in ["spirit_herb", "iron_ore", "healing_salve", "iron_sword", "qi_pill", "goblin_tooth", "bone_shard"]:
		G.add_item(id, 2, false)
	var hud = load("res://scripts/ui/HUD.gd").new()
	root.add_child(hud)
	for i in 20:
		await process_frame
	var hub = hud._hub
	for sec in only:
		hub.show_page(sec)
		for i in 30:
			await process_frame
		var pg: Control = hub.pages[sec]
		var btns: Array = pg.find_children("*", "Button", true, false).filter(func(b): return b.is_visible_in_tree() and not b.disabled and b.size.x > 4)
		var hit := 0
		var miss: Array = []
		for bi in btns.size():
			var cur: Array = pg.find_children("*", "Button", true, false).filter(func(b): return b.is_visible_in_tree() and not b.disabled and b.size.x > 4)
			if bi >= cur.size():
				break
			var bb := cur[bi] as Button
			var ctr: Vector2 = bb.get_global_rect().get_center()
			if not root.get_visible_rect().has_point(ctr):
				miss.append("offscreen %s" % bb.text.left(14))
				continue
			var got := [false]
			var cb := func(): got[0] = true
			bb.pressed.connect(cb)
			await _click(ctr)
			var gone: bool = not is_instance_valid(bb) or bb.is_queued_for_deletion()
			if not gone and bb.is_connected("pressed", cb):
				bb.pressed.disconnect(cb)
			if got[0] or gone:
				hit += 1
			else:
				var top = root.gui_get_hovered_control() if root.has_method("gui_get_hovered_control") else null
				miss.append("%s '%s' at %s hovered=%s" % [bb.get_class(), bb.text.left(14) if bb.text != "" else bb.tooltip_text.left(20), str(ctr), str(top)])
			if not hub.visible:
				hub.show_page(sec)
		print("PAGE ", sec, " buttons=", btns.size(), " clicked_ok=", hit, " MISS=", miss.size())
		for m in miss.slice(0, 8):
			print("   ", m)
	quit()

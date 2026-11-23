extends SceneTree
## Round 181: the REAL game: open the Pack > Bench dropdown, then let stat ticks fire (as they do every second while sitting) --
## the list must stay open. xvfb-run godot --path . --script res://tools/dropdown_probe.gd
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
	for i in 120:
		await process_frame
	var G = root.get_node("Game")
	for id in ["healing_salve", "iron_ore", "spirit_herb"]:
		G.add_item(id, 5, false)
	var hub = hud._hub
	hub.show_page("Pack")
	for i in 20:
		await process_frame
	hud._kit.show_tab("Bench")
	for i in 20:
		await process_frame
	var obs: Array = hub.pages["Pack"].find_children("*", "OptionButton", true, false)
	print("pickers: ", obs.size())
	var fails := 0
	if obs.size() == 0:
		print("FAIL: no picker found")
		quit(1)
		return
	var ob: OptionButton = obs[0]
	ob.show_popup()
	for i in 10:
		await process_frame
	print("popup open: ", ob.get_popup().visible)
	var kept := true
	for k in 40:
		G.stats_changed.emit()          # a sitting beat
		G.heal(1)
		for i in 6:
			await process_frame
		if not is_instance_valid(ob) or not ob.get_popup().visible:
			kept = false
			break
	print("dropdown stayed open through 40 stat ticks: ", kept)
	if not kept:
		fails += 1
	# once closed, the page does catch up
	if is_instance_valid(ob):
		ob.get_popup().hide()
	for i in 90:
		await process_frame
	var ob2: Array = hub.pages["Pack"].find_children("*", "OptionButton", true, false)
	print("after closing: pickers ", ob2.size(), " (page rebuilt: ", not is_instance_valid(ob) or ob2.size() > 0 and ob2[0] != ob, ")")
	print("dropdown_probe: ", "OK" if fails == 0 else "FAIL")
	quit(fails)

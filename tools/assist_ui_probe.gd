extends SceneTree
## Round 176: Assist in the real game (clean build + assist flag): pause-menu entry, god mode switch, MAP WARP by a real tap + the Warp button, FLOOR WARP to another floor.
## godot --path . --script res://tools/assist_ui_probe.gd   (xvfb: it opens real windows)
var G
var m
var bad := 0
func fail(s: String) -> void:
	bad += 1
	print("ASSIST FAIL ", s)
func click(pos: Vector2) -> void:
	var ev := InputEventMouseButton.new(); ev.position = pos; ev.global_position = pos
	ev.button_index = MOUSE_BUTTON_LEFT; ev.pressed = true
	root.push_input(ev)
	var up := ev.duplicate(); up.pressed = false
	root.push_input(up)
func hud_title_off(h) -> bool:
	if h._title != null:
		h._title.visible = false
	return true
func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	await process_frame
	G = root.get_node("Game")
	G.save_path = "user://aprobe_save.json"; G.save_base = "user://aprobe_slots"; G.playlog_path = "user://aprobe_playlog.jsonl"
	var ff := "user://aprobe_flavor.json"
	var fw := FileAccess.open(ff, FileAccess.WRITE); fw.store_string(JSON.stringify({"clean": true, "assist": true})); fw.close()
	var Tst = load("res://scripts/systems/Tester.gd")
	Tst.flavor_path = ff
	load("res://scripts/core/I18n.gd").set_language("en")
	G.new_game()
	G.current_level = "floor1"
	load("res://Main.gd").force_veil = true
	m = load("res://Main.tscn").instantiate()
	root.add_child(m)
	for i in 6: await process_frame
	for i in 30: await process_frame
	var T = G.sys("tester")
	if hud_title_off(m.hud): pass
	var p = m.player
	var hud = m.hud
	if p == null: fail("no player"); quit(1); return
	if not (T.clean() and T.assist()): fail("flavor not applied")
	# pause menu has the Assist entry
	var found := false
	for b in hud.find_children("*", "Button", true, false):
		if str((b as Button).text).begins_with("Assist"): found = true
	if not found: fail("no Assist button in the pause menu")
	# the page opens with its four buttons
	T.assist_menu(hud)
	for i in 4: await process_frame
	var names := []
	for b in hud.find_children("*", "Button", true, false):
		if (b as Button).is_visible_in_tree(): names.append((b as Button).text)
	for want in ["God mode", "Floor warp", "Map warp"]:
		var ok := false
		for n in names: if str(n).begins_with(want): ok = true
		if not ok: fail("Assist page lacks '%s' (saw %s)" % [want, str(names.slice(0, 12))])
	hud.close_dialog()
	# god mode through its real button
	var gb: Button = null
	T.assist_menu(hud)
	for i in 4: await process_frame
	for b in hud.find_children("*", "Button", true, false):
		if (b as Button).is_visible_in_tree() and str((b as Button).text).begins_with("God mode"): gb = b
	if gb == null: fail("no god button")
	else:
		gb.pressed.emit()
		for i in 4: await process_frame
		if not T.god(): fail("god button did not switch god mode on")
		var hp0: int = G.hp
		G.hurt(40)
		if G.hp != hp0: fail("damage landed in god mode")
	hud.close_dialog()
	# round 178: items work but are not used up under god mode
	G.inventory["healing_salve"] = 2
	G.hp = maxi(1, int(G.max_hp() * 0.5))
	G.use_item("healing_salve") if G.has_method("use_item") else null
	for i in 3: await process_frame
	if G.has_method("use_item") and G.count("healing_salve") != 2: fail("a salve was used up under god mode (%d left)" % G.count("healing_salve"))
	# MAP WARP: open the map, tap a free seen cell away from the player, press Warp
	hud._hub.show_page("Map")
	for i in 20: await process_frame
	var map = hud._hub._map
	map.set_view("place")
	for i in 10: await process_frame
	var lv = G.sys("atlas").live_level()
	var pc: Vector2i = lv.world_to_cell(p.global_position)
	var target := Vector2i(-1, -1)
	var best := 0
	for y in map.tex_size.y:
		for x in map.tex_size.x:
			var c := Vector2i(x, y)
			if map._seen_img != null and map._seen_img.get_pixel(x, y).a > 0.5 and lv.is_free(c) and absi(x - pc.x) + absi(y - pc.y) > best and absi(x - pc.x) + absi(y - pc.y) < 40:
				best = absi(x - pc.x) + absi(y - pc.y); target = c
	if target.x < 0: fail("no seen free cell on the map to warp to")
	else:
		var t: float = map.tile()
		var tl: Vector2 = map.origin() - Vector2(map.tex_size) * t * 0.5
		var sp: Vector2 = tl + (Vector2(target) + Vector2(0.5, 0.5)) * t
		map._tap_place(sp)
		for i in 4: await process_frame
		if map.warp_target != target: fail("tap did not pick the cell %s (got %s)" % [str(target), str(map.warp_target)])
		if not map._warp_btn.visible: fail("Warp button not shown after the tap")
		else:
			map._warp_btn.pressed.emit()
			for i in 4: await process_frame
			var now: Vector2i = lv.world_to_cell(p.global_position)
			if now != target: fail("map warp: stood at %s, wanted %s" % [str(now), str(target)])
			else: print("ASSIST map warp OK ", pc, " -> ", now)
	# FLOOR WARP, through the world map: pick floor 2 and warp
	hud._hub.show_page("Map")
	for i in 10: await process_frame
	map.set_view("world")
	for i in 10: await process_frame
	map.picked = "floor2"
	map._set_info()
	if not map._warp_btn.visible or not map._warp_btn2.visible: fail("world map: warp buttons not shown for floor2")
	else:
		map._warp_btn2.pressed.emit()
		for i in 40: await process_frame
		if str(G.current_level) != "floor2": fail("floor warp from the world map: now on %s" % str(G.current_level))
		else: print("ASSIST floor warp OK -> ", G.current_level)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ff))
	Tst.flavor_path = "res://data/build_flavor.json"
	print("ASSIST UI PROBE bad=", bad)
	quit(1 if bad > 0 else 0)

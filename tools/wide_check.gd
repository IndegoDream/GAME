extends SceneTree
## Needs a real display (fonts aren't measured headless): xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x720 --script res://tools/wide_check.gd
## 2026-11-06 ("the buttons continue to get lost"): a late-game character -- hundreds of items, a long kill list, every
## slot worn -- and no menu page may be wider than the window. One unwrapped line (the kills list, 9,666 px) used to
## make the Pack tab ten screens wide and the frame cut every slot and button on the right.
##   godot --headless --path . --resolution 1280x720 --script res://tools/wide_check.gd
var passed := 0
var failed := 0
func check(n: String, ok: bool, d: String = "") -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("  FAIL  " + n + ("  [" + d + "]" if d != "" else ""))
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.save_path = "user://wide_save.json"; G.save_base = "user://wide_slots"; G.playlog_path = "user://wide.jsonl"
	G.new_game()
	var n := 0
	for id in G.items.keys():
		if str(G.item_def(id).get("type", "")) in ["weapon", "armor", "material", "consumable", "ring", "relic", "rune"]:
			G.add_item(id, 3, false); n += 1
		if n >= 600: break
	for e in G.enemies.keys():
		G.kills[str(e)] = 7          # a long career: one of everything
	for s in G.gear_slots():
		var fam: String = G.slot_family(str(s[0]))
		for id in G.inventory:
			if G.gear_family(str(id)) == fam and G.equipped_count(str(id)) < G.count(str(id)):
				G.wear(str(id), str(s[0])); break
	var hud = load("res://scripts/ui/HUD.gd").new()
	root.add_child(hud)
	for i in 10: await process_frame
	var vw: float = 1500.0          # (headless has no real window; the bug this guards was 9,666 px)
	for view in [0.0, 1.0]:
		G.counters["bag_view"] = view
		for tab in ["Pack", "Bench", "Forge", "Formulas", "Runes"]:
			hud.open_kit(tab, "home")
			for i in 6: await process_frame
			var w: float = hud._kit.tabs.get_combined_minimum_size().x
			check("%s (%s) fits the window" % [tab, "list" if view > 0.0 else "slots"], w < vw, "%d px" % int(w))
	for sec in ["You", "Spirit", "Dao", "Mind", "Swarm", "Path", "Party", "Works", "Bonds", "Quests", "Road", "Journal", "Craft", "World", "Guide", "System"]:
		hud.open_hub(sec)
		for i in 6: await process_frame
		var wm := 0.0
		for d in hud._hub.find_children("*", "Control", true, false):
			if (d is Label or d is Button) and (d as Control).is_visible_in_tree():
				wm = maxf(wm, (d as Control).get_combined_minimum_size().x)
		check("the %s page has no line wider than the window" % sec, wm < vw, "%d px" % int(wm))
	print("WIDE CHECK %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

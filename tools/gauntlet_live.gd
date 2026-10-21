extends SceneTree
## round 126b: a whole Ember Gauntlet on real levels: the Stone in the village, ten built rings, foes killed, a boon each wave, a win.
var passed := 0
var failed := 0
var G
var level
var changed := ""
func check(n: String, ok: bool, d: String = "") -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("  FAIL  " + n + ("  [" + d + "]" if d != "" else ""))
func build(id: String) -> void:
	if level:
		level.free()
	level = load("res://scripts/world/Level.gd").new()
	level.name = "Level"
	level.build(G.load_level_def(id))
	root.add_child(level)
	G.current_level = id
	G.mark_level_entered(id, level.counts)
func _initialize() -> void:
	await process_frame
	await process_frame
	G = root.get_node("Game")
	G.save_path = "user://gl_save.json"
	G.save_base = "user://gl_slots"
	G.playlog_path = "user://tool_playlog.jsonl"
	G.sys("quests").quiet = true
	G.new_game()
	G.level_change_requested.connect(func(id, _t): changed = id)
	var hud = load("res://scripts/ui/HUD.gd").new()
	root.add_child(hud)
	await process_frame
	build("village")
	var stone = null
	for n in level.get_children():
		var s = n.get_script()
		if s and str(s.resource_path).ends_with("GauntletStone.gd"):
			stone = n
	check("the Ember Stone stands in the village", stone != null and level.counts.get("ember_stones", 0) == 1)
	var player = load("res://scripts/actors/Player.gd").new()
	root.add_child(player)
	await process_frame
	stone.interact(player)
	await process_frame
	check("E on the Stone opens its window", hud._dialog.visible and str(hud._dialog_title.text) == "The Ember Stone")
	G.hp = G.max_hp()
	for b in hud._dialog_buttons.get_children():
		if (b as Button).text.begins_with("Begin"):
			(b as Button).pressed.emit()
			break
	await process_frame
	check("Begin takes you into the first ring", G.arena_active() and changed == "arena_village_gauntlet_0", changed)
	var waves := 0
	var hp_start: int = G.max_hp()
	for w in 10:
		build(changed)
		await process_frame
		check("wave %d is a real ring with foes" % (w + 1), bool(level.def.get("arena", false)) and level.arena_foes_left() > 0, str(level.arena_foes_left()))
		for e in root.get_tree().get_nodes_in_group("enemy"):
			if not e._dead:
				e.take_damage(9999999)
		check("wave %d: the ring knows it is clear" % (w + 1), level.arena_foes_left() == 0)
		changed = ""
		G.arena_cleared()
		await process_frame
		if w < 9:
			check("wave %d: a boon window" % (w + 1), hud._dialog.visible and hud._dialog_buttons.get_child_count() == 3)
			(hud._dialog_buttons.get_child(0) as Button).pressed.emit()
			await process_frame
			check("wave %d: on to the next ring" % (w + 1), changed == "arena_village_gauntlet_%d" % (w + 1), changed)
		waves += 1
	check("all ten waves fought", waves == 10)
	check("the run ended in a win and back to the village", changed == "village" and str(G.arena.get("result", "")) == "gauntlet" and G.arena.get("won", false) == true, changed)
	check("embers were paid", G.Hook.embers() > 0)
	check("best is ten", int(G.counters["gauntlet_best"]) == 10)
	check("the title is yours", "Ember Victor" in G.titles)
	for fn in DirAccess.get_files_at("user://"):
		if fn.begins_with("gl_"):
			DirAccess.remove_absolute("user://" + fn)
	print("GAUNTLET LIVE %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

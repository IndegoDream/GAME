extends SceneTree
## round 126b/127: the real HUD windows -- boon pick, Ember Stone, Comforts & Style -- opened and clicked.
var passed := 0
var failed := 0
func check(n: String, ok: bool, d: String = "") -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("  FAIL  " + n + ("  [" + d + "]" if d != "" else ""))
func press(hud, starts: String) -> bool:
	for b in hud._dialog_buttons.get_children():
		if b is Button and (b as Button).text.begins_with(starts):
			(b as Button).pressed.emit()
			return true
	return false
func texts(hud) -> Array:
	var out := []
	for b in hud._dialog_buttons.get_children():
		if b is Button:
			out.append((b as Button).text)
	return out
func _initialize() -> void:
	await process_frame
	await process_frame
	var G = root.get_node("Game")
	G.save_path = "user://uih_save.json"
	G.save_base = "user://uih_slots"
	G.playlog_path = "user://tool_playlog.jsonl"
	G.new_game()
	G.store.file_path = "user://uih_store.json"
	G.store.owned = {}
	G.store.backend = "test"
	var hud = load("res://scripts/ui/HUD.gd").new()
	root.add_child(hud)
	await process_frame
	await process_frame
	check("the hud is in its group", hud.is_in_group("hud"))
	# Ember Stone
	G.counters["embers"] = 100.0
	G.Hook.gauntlet_menu(hud)
	await process_frame
	check("the stone's window opens", hud._dialog.visible and texts(hud).size() >= 4, str(texts(hud)))
	var mt: Array = texts(hud)
	check("it offers the run and both blessings", mt[0].begins_with("Begin") and str(mt[1]).begins_with("Might") and str(mt[2]).begins_with("Vigor"))
	var pr: bool = press(hud, "Might")
	await process_frame
	check("buying a blessing from the window", pr and G.Hook.bless_rank("might") == 1 and G.Hook.embers() == 75)
	check("the window shows the new rank", str(texts(hud)[1]).begins_with("Might 1/10"))
	# the run and the boon window
	G.hp = G.max_hp()
	press(hud, "Begin")
	await process_frame
	check("Begin starts the run", G.arena_active() and str(G.arena["event"]) == "gauntlet")
	G.arena_cleared()
	await process_frame
	check("a boon window opens between waves", hud._dialog.visible and texts(hud).size() == 3, str(texts(hud)))
	check("the title says which wave", str(hud._dialog_title.text).begins_with("Wave 1"))
	var level_before: String = G.current_level
	hud.get_viewport()
	var first: Button = hud._dialog_buttons.get_child(0) as Button
	first.pressed.emit()
	await process_frame
	check("taking a boon closes the window and goes on", not hud._dialog.visible and G.arena["boons"].size() == 1 and G.current_level != level_before and int(G.arena["stage"]) == 1, "%s -> %s" % [level_before, G.current_level])
	check("the wave paid embers", int(G.arena.get("embers", 0)) > 0)
	# Comforts & Style: free copy, then the full game
	G.arena = {}
	G.Comfort.menu(hud)
	await process_frame
	var free_t: Array = texts(hud)
	check("a free copy is offered the full game and the style pack", free_t.any(func(t): return str(t).begins_with("Get the full game")) and free_t.any(func(t): return str(t).begins_with("Style pack")), str(free_t))
	check("the window states the promise", str(hud._dialog_body.text).contains("promise"))
	G.store.grant("full_game", "ui_check")
	G.Comfort.menu(hud)
	await process_frame
	var paid_t: Array = texts(hud)
	check("comforts show their controls", paid_t.any(func(t): return str(t).begins_with("Auto-stash")) and paid_t.any(func(t): return str(t).begins_with("Sell spare")))
	press(hud, "Auto-stash")
	await process_frame
	check("the auto-stash toggle works", float(G.counters["comfort_autostash"]) == 0.0)
	G.store.grant("style_pack", "ui_check")
	G.Comfort.menu(hud)
	await process_frame
	press(hud, "Aura")
	await process_frame
	check("the aura button cycles", G.Comfort.aura_index() == 1)
	press(hud, "Close")
	await process_frame
	check("Close closes", not hud._dialog.visible)
	for fn in DirAccess.get_files_at("user://"):
		if fn.begins_with("uih_"):
			DirAccess.remove_absolute("user://" + fn)
	print("UI HOT CHECK %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

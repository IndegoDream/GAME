extends SceneTree
## round 158: button-mash stress -- every action pressed and released at random, with level changes, for a few thousand frames.
## Anything that errors shows up as a SCRIPT ERROR line on stderr (the gate greps for it).
var G
var m
var f := 0
var rng := RandomNumberGenerator.new()
var held := []
var total := 0
func _initialize() -> void:
	rng.seed = int(OS.get_environment("SEED")) if OS.get_environment("SEED") != "" else 7
	await process_frame
	G = root.get_node("Game")
	G.save_path = "user://mash_save.json"
	G.save_base = "user://mash_slots"
	G.playlog_path = "user://mash_playlog.jsonl"
	load("res://Main.gd").force_veil = true
	m = load("res://Main.tscn").instantiate()
	root.add_child(m)
	if OS.get_environment("ARTS") != "":
		await process_frame
		for aid in G.lattice_data().get("arts", {}).keys():
			G.learn(str(aid), "fuzz")
		var ks: Array = G.arts.keys()
		for i in 4:
			if ks.size() > i * 3:
				G.set_quick(i, str(ks[i * 3]))
		G.qi = G.qi_to_next()
		print("MASH arts known: ", G.arts.size(), " quick: ", G.quick_slots)
func _process(_d: float) -> bool:
	if m == null:
		return false
	f += 1
	var acts: Array = InputMap.get_actions().filter(func(a): return not str(a).begins_with("ui_") and str(a) != "pause")
	for i in rng.randi_range(0, 3):
		var a: String = acts[rng.randi() % acts.size()]
		if a in held:
			Input.action_release(a)
			held.erase(a)
		else:
			Input.action_press(a)
			held.append(a)
			total += 1
	if f % 7 == 0 and held.size() > 0:
		Input.action_release(held.pop_front())
	if f % 400 == 0:
		var ids := ["floor1", "village", "floor5", "floor21", "floor2", "floor9"]
		G.go_to(ids[rng.randi() % ids.size()], "<")
	if f % 250 == 0 and G.techniques.size() < 4:
		pass
	if f >= int(OS.get_environment("FRAMES") if OS.get_environment("FRAMES") != "" else "2500"):
		for a in held:
			Input.action_release(a)
		print("MASH done: frames ", f, " presses ", total, " level ", G.current_level, " hp ", G.hp)
		quit()
	return false

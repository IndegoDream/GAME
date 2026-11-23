extends SceneTree
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.new_game()
	var W = G.sys("world")
	var Fr = load("res://scripts/world/Frontier.gd")
	var regs = Fr.data()["regions"]
	var up := 0; var built := 0; var bad := 0
	for rid in regs:
		var r = regs[rid]
		if not r.has("world_boss"): continue
		var slot = int(r["wb_slot"])
		W.day_override = 5 - (2 * slot) % 5 + 100 if false else 100 + ((5 - (2 * slot) % 5) % 5)
		if not W.world_boss_up(slot): bad += 1; print("schedule wrong ", rid); continue
		var def = Fr.make_def("frontier:" + rid, G.enemies)
		var found = false
		for row in def.get("map", []):
			if "V" in row: found = true
		built += 1
		if not found or def["enemies"].get("V", "") != r["world_boss"]: bad += 1; print("NO WB in ", rid, " ", def.get("id"))
		W.day_override = 101 + ((5 - (2 * slot) % 5) % 5)
		var def2 = Fr.make_def("frontier:" + rid, G.enemies)
		for row in def2.get("map", []):
			if "V" in row: bad += 1; print("WB on off day ", rid)
	print("built ", built, " bad ", bad, " today list ", W.world_bosses_today())
	quit()

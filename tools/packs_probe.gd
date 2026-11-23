extends SceneTree
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.save_path = "user://probe_save.json"; G.save_base = "user://probe_slots"; G.playlog_path = "user://probe_playlog.jsonl"
	G.new_game()
	G.store.file_path = "user://probe_store.json"
	G.store.start("test")
	var D = load("res://scripts/systems/Design.gd")
	var bad := 0
	for id in ["wardens_hunt", "land_tales", "designers_trove"]:
		if G.expansion_open(id): bad += 1; print("OPEN BEFORE BUY ", id)
	var before = D.options("forge", "dyes").size()
	var Q = G.sys("quests")
	G.realm = 10
	var qid := "land_whisperwood_gather"
	var had = Q.unlocked(qid)
	G.store.grant("land_tales"); G.store.grant("designers_trove"); G.store.grant("wardens_hunt")
	var after = D.options("forge", "dyes").size()
	print("dyes ", before, " -> ", after, "; quest before ", had, " after ", Q.unlocked(qid))
	if after <= before or had or not Q.unlocked(qid): bad += 1
	for id in ["wardens_hunt", "land_tales", "designers_trove"]:
		if not G.expansion_open(id): bad += 1; print("NOT OPEN AFTER BUY ", id)
	print("PACKS bad=", bad)
	quit()

extends SceneTree
## Plays every Lands side quest through by satisfying its goals; each must complete. godot --headless --path . --script res://tools/lands_quest_probe.gd
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.save_path = "user://probe_save.json"; G.save_base = "user://probe_slots"; G.playlog_path = "user://probe_playlog.jsonl"
	G.new_game()
	await process_frame
	var Q = G.sys("quests")
	Q.quiet = false
	G.realm = 10
	var bad := 0
	var total := 0
	for q in Q.all():
		var qid := str(q.get("id", ""))
		if not qid.begins_with("land_"):
			continue
	var ids: Array = []
	for q in Q.all():
		if str(q.get("id", "")).begins_with("land_"):
			ids.append(str(q["id"]))
	var progress := true
	var guard := 0
	while progress and guard < 20:
		progress = false
		guard += 1
		for qid in ids:
			if Q.done.has(qid):
				continue
			var def: Dictionary = Q.qdef(qid)
			G.current_level = str(def.get("giver_at", ""))
			if not Q.active.has(qid):
				if not Q.unlocked(qid):
					continue
				Q.accept(qid)
			var steps := 0
			while Q.active.has(qid) and steps < 10:
				steps += 1
				var g: Dictionary = Q.goal(qid)
				if g.has("gather"):
					G.add_item(str(g["gather"]["item"]), int(g["gather"]["count"]))
					Q._check(qid)
				elif g.has("event"):
					var e: Dictionary = g["event"]
					for i in int(e.get("count", 1)):
						Q.on_event(str(e["kind"]), (e.get("match", {}) as Dictionary).duplicate())
				elif g.has("talk"):
					Q.advance(qid)
			if Q.done.has(qid):
				progress = true
				total += 1
	for qid in ids:
		if not Q.done.has(qid):
			bad += 1
			print("LANDQ not completed: ", qid)
	print("LANDQ ", ids.size(), " quests, ", total, " completed, ", bad, " stuck")
	quit(1 if bad > 0 else 0)

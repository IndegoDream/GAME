extends SceneTree
## What does each hidden master still want before revealing / completing?
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.save_path = "user://hm_probe_save.json"
	G.save_base = "user://hm_probe_slots"
	G.playlog_path = "user://tool_playlog.jsonl"
	G.new_game()
	G.realm = 6
	for m in G.hm_data()["masters"]:
		var id := str(m["id"])
		G.counters["hm_talk:" + id] = 5.0
		print(id, " reveal_missing: ", G.hm_reveal_missing(id), "  test: ", m.get("test", {}), "  reveal: ", m.get("reveal", m.get("needs", "")))
	print("gear slots ", G.gear_slots().size(), " rings ", G.slots_for("ring").size(), " toe ", G.slots_for("toering").size(), " bracelet ", G.slots_for("bracelet").size())
	print(G.gear_slots())
	quit()

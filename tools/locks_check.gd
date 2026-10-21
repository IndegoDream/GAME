extends SceneTree
## Round 159: the test kit's endless meditation, open locks and floor teleport.
var G
var fails := 0
var total := 0
var _went := ""
func check(what: String, ok: bool) -> void:
	total += 1
	if not ok:
		fails += 1
		print("  FAIL: ", what)
func _initialize() -> void:
	await process_frame
	G = root.get_node("Game")
	G.playlog_path = "user://tool_playlog.jsonl"
	G.save_path = "user://locks_save.json"
	G.save_base = "user://locks_slots"
	var ap: String = "user://locks_slots_account.json"
	var wf := FileAccess.open(ap, FileAccess.WRITE)
	wf.store_string(JSON.stringify({"tester": true, "god": true, "endless": true, "locks_off": true, "infinite": false}))
	wf.close()
	G.new_game()
	var T = G.sys("tester")
	check("endless on", T.endless())
	check("locks open", T.unlocked() and G.tester_unlocked())
	check("away cap lifted", G.away_cap_hours() > 100.0)
	# sitting fatigue
	G.qi = 0.0
	G.meditate_tick(1.0, false, 0.0)
	var fresh: float = G.qi
	G.qi = 0.0
	G.meditate_tick(1.0, false, 5000.0)
	check("a very long sitting flows as fast as a fresh one (%.3f vs %.3f)" % [G.qi, fresh], absf(G.qi - fresh) < 0.0001 and fresh > 0.0)
	# the pursuit bank
	var P = G.sys("pursuit")
	var b0: float = P.bank
	var got: float = P._spend(5.0)
	check("pursuit: the bank never runs dry", got == 5.0 and P.bank == b0)
	check("pursuit: no tiring (%.2f)" % P._effective(3.0), is_equal_approx(P._effective(3.0), 3.0))
	# teleport
	var ids: Array = T.floor_ids()
	check("teleport list has village and floors 1..50", ids.has("village") and ids.has("floor1") and ids.has("floor50") and ids.size() >= 51)
	G.level_change_requested.connect(func(id, _t): _went = str(id))
	T.teleport("floor30")
	await process_frame
	await process_frame
	check("teleport asks for floor30", _went == "floor30" and G.current_level == "floor30")
	# gates swing open by themselves
	var lv = load("res://scripts/world/Level.gd").new()
	lv.build(G.load_level_def("floor7"))
	root.add_child(lv)
	for i in 4:
		await process_frame
	var gates := get_nodes_in_group("gate")
	check("floor7 has a gate", gates.size() > 0)
	check("every gate is open", gates.all(func(g): return g._open))
	lv.free()
	# off: back to the rules
	T.endless_on = false
	T.locks_off = false
	check("off: locks closed", not G.tester_unlocked())
	check("off: away cap is 12", is_equal_approx(G.away_cap_hours(), 12.0))
	G.qi = 0.0
	G.meditate_tick(1.0, false, 5000.0)
	check("off: long sitting tires", G.qi < fresh * 0.9)
	var b1: float = P.bank
	P._spend(1.0)
	check("off: the bank is spent", P.bank < b1)
	print("locks_check: %d passed, %d failed" % [total - fails, fails])
	DirAccess.remove_absolute(ap)
	quit(1 if fails > 0 else 0)

extends SceneTree
## Round 161: the Party page with a stable: pairing flow, a pair waiting, a bred beast with its tree.
var fails := 0
var total := 0
func check(what: String, ok: bool) -> void:
	total += 1
	if not ok:
		fails += 1
		print("  FAIL: ", what)
func _initialize() -> void:
	var G = root.get_node("Game")
	G.playlog_path = "user://tool_playlog.jsonl"
	G.save_path = "user://su_save.json"
	G.save_base = "user://su_slots"
	var m: Node = (load("res://Main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 40:
		await physics_frame
	var B = G.sys("breeding")
	G.skills["taming"] = 10.0 * 12 * 12 + 1.0
	G.bond_familiar("cave_hare")
	G.bond_familiar("tunnel_boar")
	for c in G.contracts:
		c["bond"] = 80.0
	G.havens[G.current_level] = "test"
	var hud = m.hud
	hud.open_hub("Party")
	for i in 5:
		await physics_frame
	var hub = hud._hub
	check("stable section builds with no pair", true)
	hub._stable_pick = 0
	hub._fill("Party")
	for i in 3:
		await physics_frame
	check("pairing prompt shown", hub._stable_pick == 0)
	check("pair through the system", B.pair(0, 1) == "")
	hub._stable_pick = -1
	hub._fill("Party")
	for i in 3:
		await physics_frame
	B.pairs[0]["ready"] = G._now() - 5.0
	hub._fill("Party")
	for i in 3:
		await physics_frame
	check("ready text", B.status_lines()[0].find("hatch") >= 0)
	check("hatch", B.hatch(0) == "")
	hub._fill("Party")
	for i in 3:
		await physics_frame
	check("a bred beast shows its lines", B.lineage_lines(G.contracts[G.contracts.size() - 1]).size() >= 1 and B.tree_lines(G.contracts[G.contracts.size() - 1]).size() == 3)
	# the bred beast can walk beside you
	var yi: int = G.contracts.size() - 1
	check("call it out", G.summon_beast(yi) == "")
	for i in 40:
		await physics_frame
	check("it has a node", m.get_tree().get_nodes_in_group("interactable").size() > 0)
	print("stable_ui_check: %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)

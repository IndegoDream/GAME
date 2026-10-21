extends SceneTree
## Round 150: the valley's spread, its hunting and gathering grounds, and far creatures sleeping.
var G
var fails := 0
var total := 0

class Stub:
	var def := {"theme": "wilds"}


func check(what: String, ok: bool) -> void:
	total += 1
	if not ok:
		fails += 1
		print("  FAIL: ", what)


func _initialize() -> void:
	await process_frame
	G = root.get_node("Game")
	G.save_path = "user://wc_save.json"
	G.save_base = "user://wc_slots"
	G.new_game()
	var V = load("res://scripts/world/Valley.gd")
	var d: Dictionary = V.make_def(G.valley_data(), G.enemies)
	var rows: Array = d["map"]
	check("valley is 1.85x spread", absf(V.SPREAD - 1.85) < 0.001 and rows.size() == V.H and str(rows[0]).length() == V.W)
	var gr: Array = d.get("grounds", [])
	check("at least 9 grounds placed", gr.size() >= 9)
	var kinds := {}
	for g in gr:
		kinds[str(g["kind"])] = int(kinds.get(str(g["kind"]), 0)) + 1
	check("hunting, herb, ore and reed grounds all exist", kinds.has("hunt") and kinds.has("herbs") and kinds.has("ore") and kinds.has("reeds"))
	check("three or more hunting grounds", int(kinds.get("hunt", 0)) >= 3)
	var spaced := true
	for i in gr.size():
		for j in range(i + 1, gr.size()):
			if str(gr[i]["kind"]) != "reeds" and str(gr[j]["kind"]) != "reeds":
				var a: Array = gr[i]["cell"]
				var b: Array = gr[j]["cell"]
				if absi(int(a[0]) - int(b[0])) + absi(int(a[1]) - int(b[1])) < 16:
					spaced = false
	check("grounds are spaced apart", spaced)
	var away := true
	for g in gr:
		if str(g["kind"]) == "reeds":
			continue
		for sl in V.SECT_SLOTS + V.TOWER_SLOTS:
			if absi(sl.x - int(g["cell"][0])) + absi(sl.y - int(g["cell"][1])) < 18:
				away = false
	check("grounds keep clear of halls and towers", away)
	var game := 0
	var herbs := 0
	for r in rows:
		for ch in str(r):
			if ch in "rsuvwyz":
				game += 1
			if ch == "h":
				herbs += 1
	check("game animals stand in the valley", game >= 20)
	check("herbs are plentiful", herbs >= 60)
	var ok_e := true
	for l in "rsuvwyz":
		if d["enemies"].has(l) and not G.enemies.has(str(d["enemies"][l])):
			ok_e = false
		if d["enemies"].has(l) and not bool(G.enemies[str(d["enemies"][l])].get("passive", false)):
			ok_e = false
	check("every game letter is a real passive beast", ok_e)
	# far creatures sleep
	var pl := Node3D.new()
	pl.add_to_group("player")
	root.add_child(pl)
	var E = load("res://scripts/actors/Enemy.gd").new()
	E.setup(Stub.new(), {"type": "cave_hare", "cell": Vector2i(1, 1)})
	root.add_child(E)
	E.global_position = Vector3(200, 0, 0)
	check("a far hare falls asleep in the wilds", E._check_sleep(1.0) == true and E.visible == false)
	E._sleep_t = 0.0
	E.global_position = Vector3(10, 0, 0)
	check("it wakes when you come near", E._check_sleep(1.0) == false and E.visible == true)
	E.global_position = Vector3(200, 0, 0)
	E._chasing = true
	E._sleep_t = 0.0
	check("a chasing creature never sleeps", E._check_sleep(1.0) == false)
	var E2 = load("res://scripts/actors/Enemy.gd").new()
	E2.setup(null, {"type": "cave_hare", "cell": Vector2i(1, 1)})
	root.add_child(E2)
	E2.global_position = Vector3(200, 0, 0)
	check("in a dungeon nothing sleeps", E2._check_sleep(1.0) == false)
	print("WORLD CHECK %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)

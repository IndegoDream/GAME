extends SceneTree
## Round 167: every mutation / hybrid / generation / stage builds a model without error and adds parts as it deepens.
func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c

func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.new_game()
	var BR = G.sys("breeding")
	var fails := 0
	var total := 0
	var sp := "grey_wolf"
	var t: Array = G.enemies[sp]["tint"]
	var base := Color(float(t[0]), float(t[1]), float(t[2]))
	for v in ["gilded", "shadow", "frost", "ember", "jade"]:
		var prev := 0
		for s in 4:
			var m = load("res://scripts/actors/Enemy.gd").make_beast(base, "Grey Wolf")
			m.evolve(s, base)
			var before: int = _count(m)
			var va: Array = BR.data["variants"][v]["color"]
			m.lineage(s, v, Color(float(va[0]), float(va[1]), float(va[2])), Color(0, 0, 0, 0), 0)
			var after: int = _count(m)
			total += 1
			if after <= before:
				fails += 1
				print("  FAIL: ", v, " stage ", s, " adds nothing")
			total += 1
			if s > 0 and after < prev:
				fails += 1
				print("  FAIL: ", v, " shrinks at stage ", s)
			prev = after - 0
			m.free()
	var m2 = load("res://scripts/actors/Enemy.gd").make_beast(base, "Grey Wolf")
	var b2: int = _count(m2)
	m2.lineage(1, "", Color.WHITE, Color(0.5, 0.2, 0.2, 1.0), 0)
	total += 1
	if _count(m2) <= b2:
		fails += 1
		print("  FAIL: hybrid patches")
	var m3 = load("res://scripts/actors/Enemy.gd").make_beast(base, "Grey Wolf")
	var b3: int = _count(m3)
	m3.lineage(0, "", Color.WHITE, Color(0, 0, 0, 0), 7)
	total += 1
	if _count(m3) < b3 + 2:
		fails += 1
		print("  FAIL: generation marks")
	var m4 = load("res://scripts/actors/Enemy.gd").make_beast(base, "Grey Wolf")
	var b4: int = _count(m4)
	m4.lineage(3, "", Color.WHITE, Color(0, 0, 0, 0), 0)
	total += 1
	if _count(m4) != b4:
		fails += 1
		print("  FAIL: plain beast changed")
	print("lineage_check: ", total - fails, "/", total, " passed, ", fails, " failed")
	quit(1 if fails > 0 else 0)

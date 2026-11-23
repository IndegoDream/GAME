extends SceneTree
## 2026-11-06: the pet's moves by stage (Robert's note 2026-10-31, item 5:
## idle, walk, bite, deed, down; faster, heavier, more confident as it grows).
## Run: godot --headless --path . --script tools/pet_motion_check.gd
const B := "res://scripts/actors/Beast.gd"

var ch := []


func _beast(name: String, stage: int) -> Node3D:
	var b: Node3D = load(B).build(name, Color(0.6, 0.45, 0.3))
	root.add_child(b)
	b.set_motion_stage(stage)
	return b


func _walk(b: Node3D, secs: float, speed: float) -> void:
	## move it along +z at so many m/s, frame by frame
	var dt := 1.0 / 60.0
	var n := int(secs / dt)
	for i in n:
		b.global_position += Vector3(0, 0, speed * dt)
		b.animate(dt)


func _still(b: Node3D, secs: float) -> void:
	var dt := 1.0 / 60.0
	for i in int(secs / dt):
		b.animate(dt)


func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.new_game()
	var M: Array = load(B).MOTION
	ch.append(["four stages of motion", M.size() == 4])
	# grown (1) is the old motion: every enemy and wild beast moves as before
	var g1: Dictionary = M[1]
	ch.append(["grown is the old motion exactly", is_equal_approx(float(g1["stride"]), 1.0) and is_equal_approx(float(g1["swing"]), 1.0) and is_equal_approx(float(g1["bob"]), 1.0) and is_equal_approx(float(g1["glance"]), 1.0) and is_equal_approx(float(g1["head"]), 0.0)])
	var heavier := true
	var surer := true
	var quicker := true
	for i in range(1, 4):
		heavier = heavier and float(M[i]["bob"]) > float(M[i - 1]["bob"]) and float(M[i]["swing"]) > float(M[i - 1]["swing"]) and float(M[i]["hop"]) < float(M[i - 1]["hop"])
		surer = surer and float(M[i]["glance"]) < float(M[i - 1]["glance"]) and float(M[i]["head"]) < float(M[i - 1]["head"])
		quicker = quicker and float(M[i]["bite"]) < float(M[i - 1]["bite"]) and float(M[i]["lunge"]) > float(M[i - 1]["lunge"])
	ch.append(["heavier as it grows: longer swing, more weight in each step, less bounce", heavier])
	ch.append(["more confident: head higher, looks about less", surer])
	ch.append(["faster: the bite is quicker and drives further", quicker])
	var b0 := Node3D.new()
	b0.set_script(load(B))
	ch.append(["a wild beast is 'grown' unless told otherwise", int(b0.motion_stage) == 1])
	b0.free()

	for plan_name in ["wolf", "boar", "stag", "hare", "lizard", "crab", "crow", "worm", "toad"]:
		# walk: legs swing; stage 3 swings them further than stage 0
		var y0 := _beast(plan_name, 0)
		var y3 := _beast(plan_name, 3)
		var max0 := 0.0
		var max3 := 0.0
		var dt := 1.0 / 60.0
		for i in 120:
			y0.global_position += Vector3(0, 0, 3.0 * dt)
			y3.global_position += Vector3(0, 0, 3.0 * dt)
			y0.animate(dt)
			y3.animate(dt)
			for L in y0._legs:
				max0 = maxf(max0, absf((L[0] as Node3D).rotation.x))
			for L in y3._legs:
				max3 = maxf(max3, absf((L[0] as Node3D).rotation.x))
		if not y0._legs.is_empty():
			ch.append([plan_name + ": walking, the spirit beast's legs swing further", max3 > max0 * 1.2 and max0 > 0.05, "%.2f vs %.2f" % [max3, max0]])
		# idle: it breathes; the head is carried higher at stage 3
		_still(y3, 1.5)
		var sc: Array = []
		for i in 90:
			y3.animate(dt)
			sc.append(y3._torso.scale.y)
		ch.append([plan_name + ": standing, its chest rises and falls", sc.max() - sc.min() > 0.01])
		if y3._head:
			_still(y0, 1.5)
			ch.append([plan_name + ": head held higher when grown", y3._head.rotation.x < y0._head.rotation.x - 0.1, "%.2f vs %.2f" % [y3._head.rotation.x, y0._head.rotation.x]])
		# bite: a lunge forward, the head snaps down, then it settles
		var z0: float = y3._torso.position.z
		var hx0: float = y3._head.rotation.x if y3._head else 0.0
		y3.act("bite")
		ch.append([plan_name + ": a bite plays", y3.action == "bite"])
		var far := 0.0
		var snap := 0.0
		for i in int(y3.act_seconds() / dt) + 2:
			y3.animate(dt)
			far = maxf(far, y3._torso.position.z - z0)
			if y3._head:
				snap = maxf(snap, y3._head.rotation.x - hx0)
		ch.append([plan_name + ": the bite drives in", far > 0.08])
		if y3._head:
			ch.append([plan_name + ": ...and snaps", snap > 0.2])
		ch.append([plan_name + ": ...and is over, back where it stood", y3.action == "" and absf(y3._torso.position.z - z0) < 0.001])
		# deed: nose down, then up on its haunches
		y3.act("deed")
		var low := 0.0
		var rear := 0.0
		for i in int(y3.act_seconds() / dt) + 2:
			y3.animate(dt)
			if y3._head:
				low = maxf(low, y3._head.rotation.x - hx0)
			rear = minf(rear, y3._torso.rotation.x)
		ch.append([plan_name + ": a find: nose down, then a proud rear", (low > 0.3 or y3._head == null) and rear < -0.15 and y3.action == ""])
		# down: it lies down and stays, and gets up again
		var ty: float = y3._torso.get_meta("y")
		y3.act("down")
		_still(y3, 1.2)
		ch.append([plan_name + ": lies down (body sinks)", y3.is_down() and y3._torso.position.y < ty * 0.6])
		if not y3._legs.is_empty():
			var folded := true
			for L in y3._legs:
				folded = folded and absf((L[0] as Node3D).rotation.x) > 1.0
			ch.append([plan_name + ": ...legs folded under", folded])
		_still(y3, 2.0)
		ch.append([plan_name + ": ...and stays down", y3._torso.position.y < ty * 0.6])
		y3.act("up")
		_still(y3, 1.2)
		ch.append([plan_name + ": gets back up", not y3.is_down() and absf(y3._torso.position.y - ty) < 0.03])
		# a bite gets it up at once
		y3.act("down")
		_still(y3, 1.0)
		y3.act("bite")
		ch.append([plan_name + ": a bite gets it up", not y3.is_down()])
		y0.queue_free()
		y3.queue_free()

	# 2026-11-06 ("the final form is kinda childish and bland"): the spirit beast is rebuilt
	for pn in [["wolf", true], ["boar", true], ["stag", true], ["hare", true], ["salamander", true], ["crow", false], ["crab", false]]:
		var sb: Node3D = load(B).build(str(pn[0]), Color(0.5, 0.45, 0.4))
		root.add_child(sb)
		sb.evolve(3, Color(0.4, 0.8, 1.0))
		var lofted: bool = pn[1]
		var body: Node = sb._torso.get_node_or_null("SpiritBody")
		ch.append([str(pn[0]) + ": final form is one smooth body (not stacked blobs)" if lofted else str(pn[0]) + ": final form keeps its own build", (body != null) == lofted])
		if lofted:
			var shown := 0
			for c2 in sb._torso.get_children():
				if c2 is MeshInstance3D and c2.mesh is SphereMesh and c2.visible and c2.material_override == sb._mat:
					shown += 1
			ch.append([str(pn[0]) + ": ...the cub's blobs are hidden", shown == 0, str(shown)])
			ch.append([str(pn[0]) + ": ...no flat glow over the coat", not sb._mat.emission_enabled])
			var legs_lofted := true
			for L in sb._legs:
				legs_lofted = legs_lofted and (L[0] as Node3D).get_node_or_null("SpiritLeg") != null
			ch.append([str(pn[0]) + ": ...lofted legs", legs_lofted])
			ch.append([str(pn[0]) + ": ...role parts and armour sit on its back", sb._torso.has_meta("back_y")])
		ch.append([str(pn[0]) + ": stripes of light, a pool under it", int(sb.spirit_parts.get("stripes", 0)) >= 6 and bool(sb.spirit_parts.get("pool", false))])
		ch.append([str(pn[0]) + ": an aura (off on phones / Low)", int(sb.spirit_parts.get("aura", 0)) >= 1])
		# it still moves: walk, bite, lie down
		sb.set_motion_stage(3)
		sb.act("down")
		_still(sb, 1.2)
		ch.append([str(pn[0]) + ": the final form still lies down", sb._torso.position.y < float(sb._torso.get_meta("y")) * 0.6])
		sb.queue_free()
	# heads and the other kinds' spirit forms
	for hk in [["wolf", "head"], ["boar", "head"], ["stag", "head"], ["hare", "head"], ["salamander", "head"], ["cave toad", "head"], ["stone crab", "carapace"], ["glow worm", "rings"], ["iron golem", "veins"], ["steel crow", "feathers"]]:
		var hb: Node3D = load(B).build(str(hk[0]), Color(0.5, 0.45, 0.4))
		root.add_child(hb)
		hb.evolve(3, Color(1.0, 0.6, 0.3))
		var got = hb.spirit_parts.get(str(hk[1]), null)
		ch.append([str(hk[0]) + ": spirit form has its " + str(hk[1]), got != null and (got is bool and got or (got is int and int(got) > 0))])
		if str(hk[1]) == "head":
			var sh: Node = hb._head.get_node_or_null("SpiritHead")
			var eyes_on := 0
			for c3 in hb._head.get_children():
				if c3 is MeshInstance3D and c3.has_meta("eye") and c3.visible:
					eyes_on += 1
			ch.append([str(hk[0]) + ": ...one smooth skull and muzzle, eyes on it", sh != null and eyes_on == 2])
		hb.queue_free()
	var gol: Node3D = load(B).build("iron golem", Color(0.5, 0.5, 0.5))
	root.add_child(gol)
	gol.evolve(3, Color(1, 0.5, 0.2))
	ch.append(["a golem doesn't grow a turtle's shell", gol.role_form("sentinel", 3, Color(1, 0.5, 0.2)) == "" and gol.role_form("lantern", 3, Color(1, 0.5, 0.2)) == "antlers"])
	gol.queue_free()
	ch.append(["a fox is built as a fox (it matched 'ox' and came out a stag)", load(B).plan_for("Cinder Fox") == "ferret" and load(B).plan_for("void_fox") == "ferret" and load(B).plan_for("Ox") == "stag"])
	# the familiar wires it: stage, bite, find, resting while you sit
	G.familiar = {"species": "cave_hare", "name": "Pip", "bond": 175.0}
	var F: Node3D = load("res://scripts/actors/Familiar.gd").new()
	root.add_child(F)
	await process_frame
	var m = F._model
	ch.append(["the familiar's beast knows its stage", m != null and m.has_method("act") and int(m.motion_stage) == int(G.familiar_stage(G.familiar)), str(m.motion_stage if m else -1)])
	if m != null and m.has_method("act"):
		var foe := Node3D.new()
		foe.set_script(_dummy_foe())
		root.add_child(foe)
		foe.global_position = F.global_position + Vector3(1.0, 0, 0)
		F.bite(foe)
		ch.append(["its bite plays the bite", m.action == "bite"])
		m.action = ""
		var st: Dictionary = G.enemies.get("cave_hare", {})
		if not st.get("familiar", {}).get("finds", []).is_empty():
			var got: String = F.find_something(0.0)
			ch.append(["a find plays the deed", got == "" or m.action == "deed"])
		foe.queue_free()
	var bad := 0
	for c in ch:
		if not c[1]:
			bad += 1
			print("PET MOTION FAIL: ", c[0], "  ", c[2] if c.size() > 2 else "")
	print("PET MOTION CHECK %d passed, %d failed" % [ch.size() - bad, bad])
	quit()


func _dummy_foe() -> GDScript:
	var s := GDScript.new()
	s.source_code = "extends Node3D\nvar _dead := false\nvar stats := {}\nvar hurt := 0\nfunc take_damage(n, _w = \"\"): hurt += n\n"
	s.reload()
	return s

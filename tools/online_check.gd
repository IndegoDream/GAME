extends SceneTree
## round 125: the Gate, end to end. Needs a development server on 127.0.0.1:18766 (see tools/server/run_online_check.sh).
##   godot --headless --path . --script res://tools/online_check.gd
var G
var passed := 0
var failed := 0
var frames := 0
var started := false
var level
var player
const URL := "ws://127.0.0.1:18766"

func check(n: String, ok: bool, d: String = "") -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("  FAIL  " + n + ("  [" + d + "]" if d != "" else ""))

func _process(_dt: float) -> bool:
	frames += 1
	if frames < 3 or started:
		return false
	started = true
	_run()
	return false

func wait_s(sec: float) -> void:
	var end := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame

func until(cond: Callable, sec: float) -> bool:
	var end := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await process_frame
	return cond.call()

func build(id: String) -> void:
	if level:
		root.remove_child(level)
		level.free()
	if player:
		root.remove_child(player)
		player.free()
	var def: Dictionary = G.load_level_def(id)
	level = load("res://scripts/world/Level.gd").new()
	level.name = "Level"
	level.build(def)
	root.add_child(level)
	player = load("res://scripts/actors/Player.gd").new()
	root.add_child(player)
	player.global_position = level.spawn_point("P")

func _run() -> void:
	G = root.get_node_or_null("Game")
	G.save_base = "user://online_test"
	G.use_slot(1)
	await wait_s(0.5)
	var on = G.online
	check("Game.online exists", on != null)
	on.url = URL
	# --- level defs
	for id in ["online:hub", "online:arena"]:
		var def: Dictionary = G.load_level_def(id)
		check(id + " def", not def.is_empty() and G.level_exists(id))
	var lv = load("res://scripts/world/Level.gd").new()
	lv.build(G.load_level_def("online:hub"))
	check("hub builds without warnings", lv.warnings.is_empty(), str(lv.warnings))
	check("hub has a start and an exit", lv.spawns.has("P") and lv.spawns.has("<"))
	lv.free()
	# --- the village has the Gate
	var vl = load("res://scripts/world/Level.gd").new()
	vl.build(G.load_level_def("village"))
	check("the village has the Gate", vl.spawns.has("gate"), str(vl.warnings))
	vl.free()
	# --- connect, make a hero
	check("connect starts", on.connect_now())
	var st: String = await on.wait_state(["nochar", "char"], 10.0)
	check("logged in with no hero", st == "nochar", st + " " + on.last_error)
	on.send({"t": "create_char", "name": "x", "realm": 0, "step": 1})
	var r: Dictionary = await on.wait_any(["char", "char_error"], 4.0)
	check("a bad name is refused", r.get("t", "") == "char_error")
	on.send({"t": "create_char", "name": "Tester", "realm": 0, "step": 1})
	r = await on.wait_any(["char", "char_error"], 4.0)
	check("hero created", r.get("t", "") == "char" and on.state == "char", str(r))
	# --- the hub
	build("online:hub")
	await wait_s(1.0)
	check("in the hub", on.state == "hub", on.state)
	var stands := 0
	for n in root.get_tree().get_nodes_in_group("interactable"):
		if n.get_script() and str(n.get_script().resource_path).ends_with("Pedestal.gd"):
			stands += 1
	check("seven stands", stands == 7, str(stands))
	# a second client
	var b = load("res://scripts/net/Online.gd").new()
	b.name = "Bot2"
	b.dev_name = "Bot2"
	b.drive_game = false
	b.url = URL
	root.add_child(b)
	b.connect_now()
	await b.wait_state(["nochar", "char"], 10.0)
	b.send({"t": "create_char", "name": "Bot2", "realm": 0, "step": 1})
	await b.wait_for("char", 4.0)
	b.send({"t": "enter_hub"})
	await b.wait_state(["hub"], 4.0)
	await wait_s(1.0)
	check("I can see the other player", on.players.size() == 2, str(on.players.size()))
	var rp := 0
	for c in level.get_children():
		if c.get_script() and str(c.get_script().resource_path).ends_with("OnlineWorld.gd"):
			for cc in c.get_children():
				if cc.get_script() and str(cc.get_script().resource_path).ends_with("RemotePlayer.gd"):
					rp += 1
	check("their body stands in the hub", rp == 1, str(rp))
	on.send({"t": "chat", "ch": "hub", "text": "hello there"})
	var ch: Dictionary = await b.wait_for("chat", 3.0)
	check("chat arrives", ch.get("text", "") == "hello there")
	# --- party and a run
	on.send({"t": "p_invite", "name": "Bot2"})
	var inv: Dictionary = await b.wait_for("p_invited", 4.0)
	check("invited", inv.has("pid"))
	b.send({"t": "p_accept", "pid": int(inv.get("pid", 0))})
	await until(func(): return on.party.get("members", []).size() == 2, 4.0)
	check("a party of two", on.party.get("members", []).size() == 2)
	G.level_change_requested.connect(func(id, _tag): build(id))
	var hp_before: int = G.hp
	on.send({"t": "p_start", "kind": "run", "tier": 1})
	await until(func(): return on.state == "instance" and b.state == "instance", 6.0)
	check("both in the instance", on.state == "instance" and b.state == "instance")
	await wait_s(1.0)
	check("the arena level is up", level != null and str(level.level_id) == "online:arena", str(level.level_id if level else ""))
	await until(func(): return on.inst.get("foes", {}).size() > 0, 20.0)
	check("foes are announced", on.inst.get("foes", {}).size() > 0)
	await wait_s(1.0)
	var nf := root.get_tree().get_nodes_in_group("enemy").size()
	check("foes stand in the arena", nf > 0, str(nf))
	# --- fight: the player swings at the nearest foe; the bot at everything
	var t0 := Time.get_ticks_msec()
	var bpos := Vector2(0, 9)
	while not on.inst.has("end") and Time.get_ticks_msec() - t0 < 150000:
		await wait_s(0.15)
		for id in b.inst.get("foes", {}):
			b.send({"t": "i_hit", "foe": int(id), "amt": 500})
		var best = null
		var bd := 1e9
		for e in root.get_tree().get_nodes_in_group("enemy"):
			var d: float = e.global_position.distance_to(player.global_position)
			if d < bd:
				bd = d
				best = e
		if best != null:
			best.take_damage(500, "you")
		# step out of any red circle (both of us)
		var cc: Vector3 = level.cell_to_world(Vector2i(level.width / 2, level.height / 2))
		for who in [0, 1]:
			var pos2: Vector2 = bpos if who == 1 else Vector2(player.global_position.x - cc.x, player.global_position.z - cc.z)
			var moved := false
			for hid in on.inst.get("haz", {}):
				var h: Dictionary = on.inst["haz"][hid]
				if str(h.get("kind", "")) == "circle":
					var dv := pos2 - Vector2(float(h["x"]), float(h["z"]))
					if dv.length() < float(h["r"]) + 0.8:
						pos2 += dv.normalized() * 3.0 if dv.length() > 0.01 else Vector2(3, 0)
						moved = true
				elif str(h.get("kind", "")) == "safe" and (h.get("zones", []) as Array).size() > 0:
					var z: Array = h["zones"][0]
					pos2 = Vector2(float(z[0]), float(z[1]))
					moved = true
			if who == 1:
				bpos = pos2
				if moved:
					b.send({"t": "i_move", "x": bpos.x, "z": bpos.y, "yaw": 0})
			elif moved:
				player.global_position = cc + Vector3(pos2.x, 0.6, pos2.y)
	check("the fight ended", on.inst.has("end"), "after %d s" % int((Time.get_ticks_msec() - t0) / 1000))
	var e: Dictionary = on.inst.get("end", {})
	print("   fight: ", e.get("result", "?"), " in ", e.get("time", "?"), " s; reward ", e.get("reward", {}))
	check("HP stayed alive while mirrored", G.hp >= 1)
	if e.get("result", "") == "won":
		check("won: paid", int(e.get("reward", {}).get("gold", 0)) > 0)
		check("won: my hero is richer", int(on.char.get("gold", 0)) > 0)
		check("won: no pills", not e.get("reward", {}).get("items", {}).has("breakthrough_pill"))
	# --- back out: the solo hp is put back, the save names the village
	on.leave_instance(true)
	await until(func(): return on.state == "hub" or (level and str(level.level_id) == "online:hub" and on.state == "char"), 8.0)
	check("back to the hub level", level != null and str(level.level_id) == "online:hub", str(level.level_id if level else ""))
	check("solo hp restored", G.hp == hp_before, "%d vs %d" % [G.hp, hp_before])
	G.save_game()
	var txt := FileAccess.get_file_as_string(G.save_path)
	if txt == "":
		print("   save path ", G.slot_path(G.slot), " files: ", Array(DirAccess.get_files_at("user://")).filter(func(f): return f.begins_with("online_test")))
	var sd = JSON.parse_string(txt)
	check("a save made in the Gate names the village", sd is Dictionary and str(sd.get("current_level", "")) == "village", str(sd.get("current_level", "")) if sd is Dictionary else "no json")
	# --- take materials out (if any) and the grant
	var inv_c: Dictionary = on.char.get("inv", {})
	if inv_c.size() > 0:
		var k: String = inv_c.keys()[0]
		var before: int = G.count(k)
		on.send({"t": "withdraw", "items": {k: 1}})
		await wait_s(1.0)
		check("a withdrawn material reaches the pouch", G.count(k) == before + 1, "%d -> %d" % [before, G.count(k)])
		check("the grant is remembered", G.flags.size() > 0)
	# --- the season ladder (round 134): the client asks, the server answers with this season's board and my place on it
	var lad: Dictionary = await on.ask({"t": "season"}, "season", 4.0)
	check("the season ladder answers", lad.has("rows") and lad.has("me") and not bool(lad.get("past", true)), str(lad))
	if str(e.get("result", "")) == "won":
		check("a won fight scored season points", int(lad.get("me", {}).get("points", 0)) > 0, str(lad.get("me", {})))
	var menu = load("res://scripts/net/OnlineMenu.gd")
	check("the ladder window exists and counts down", menu.has_method("ladder") and menu._days_left(200000.0, 0.0) == "2 days 7 h" and menu._days_left(7200.0, 0.0) == "2 h")
	# --- leaving closes the connection
	G.go_to("village", "P")
	await wait_s(0.5)
	check("leaving the Gate closes the connection", on.state == "off", on.state)
	for f in DirAccess.get_files_at("user://"):
		if f.begins_with("online_test"):
			DirAccess.remove_absolute("user://" + f)
	print("ONLINE CHECK %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

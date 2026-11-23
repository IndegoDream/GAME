extends SceneTree
## Round 188 (pictures only): each Strike Style swung at a goblin, and some weapon arts, in a real place.
##   xvfb-run godot --rendering-driver opengl3 --path . --script res://tools/_strike_shot.gd   -> /tmp/strike_*.png


func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.save_base = "user://tool_shot"
	G.save_path = "user://tool_shot.json"
	G.playlog_path = "user://tool_playlog.jsonl"
	load("res://Main.gd").force_veil = true
	var m = load("res://Main.tscn").instantiate()
	root.add_child(m)
	for i in 4:
		await process_frame
	G.new_game()
	G.go_to("floor1", "<")
	var lv = null
	for i in 600:
		await process_frame
		lv = root.get_tree().get_first_node_in_group("level")
		if lv != null and str(lv.level_id) == "floor1" and lv.stream_left() == 0 and i > 10:
			break
	var pl = root.get_tree().get_first_node_in_group("player")
	for e in root.get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	var hud = root.find_child("HUD", true, false)
	if hud and hud.has_method("close_title"):
		hud.close_title()
	for c in root.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	G.store.backend = "full"
	var LK = G.sys("looks")
	var fwd := Vector3(sin(pl._model.rotation.y), 0, cos(pl._model.rotation.y))
	var side := Vector3(fwd.z, 0, -fwd.x)
	var foes := []
	for k in 3:
		var at: Vector3 = pl.global_position + fwd * (1.9 + 0.9 * k) + side * (k - 1) * 1.1
		var e = lv._spawn_script("res://scripts/actors/Enemy.gd", at, {"type": "goblin", "cell": lv.world_to_cell(at)})
		foes.append(e)
	await process_frame
	for e in foes:
		e.stats["hp"] = 999999
		e.hp = 999999
		e.set_physics_process(false)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.global_position = pl.global_position + fwd * 0.6 + side * 3.4 + Vector3(0, 2.4, 0)
	cam.look_at(pl.global_position + fwd * 1.2 + Vector3(0, 1.0, 0))
	cam.make_current()
	G.hp = 999999
	var want := OS.get_environment("ONLY")
	for sid in ["", "crescent", "petals", "dragonfire", "thunder", "ink", "frost"]:
		if want != "" and not (sid in want.split(",")):
			continue
		LK.choose("strikes", sid)
		Engine.time_scale = float(OS.get_environment("TS")) if OS.get_environment("TS") != "" else 0.03
		pl._deal_hit()
		for i in int(OS.get_environment("WAIT") if OS.get_environment("WAIT") != "" else "2"):
			await process_frame
		var parts := root.find_children("*", "CPUParticles3D", true, false)
		print("STYLE ", sid, " particles ", parts.size(), " ", parts.map(func(q): return [q.amount, q.emitting, q.global_position.snapped(Vector3.ONE * 0.1)]))
		root.get_viewport().get_texture().get_image().save_png("/tmp/strike_%s.png" % (sid if sid != "" else "plain"))
		Engine.time_scale = 1.0
		for i in 30:
			await process_frame
	if OS.get_environment("PTEST") != "":
		Engine.time_scale = 1.0
		var FXs = load("res://scripts/fx/FX.gd")
		FXs._drift(pl, pl.global_position + Vector3(0, 1.5, 0) + fwd, Color(1, 0, 0), 30, 0.4, Vector3.ZERO, 3.0, "mix")
		FXs._drift(pl, pl.global_position + Vector3(0, 1.5, 0) + fwd * 2.0, Color(0, 1, 0), 30, 0.4, Vector3.ZERO, 3.0, "add")
		for i in 6:
			await process_frame
		var ps := root.find_children("*", "CPUParticles3D", true, false)
		for q in ps:
			print("P ", q.amount, " ", q.emitting, " vis ", q.visible, " ", q.is_visible_in_tree(), " mesh ", q.mesh, " mat ", q.material_override, " box ", q.get_aabb())
		root.get_viewport().get_texture().get_image().save_png("/tmp/strike_ptest.png")
		quit(0)
		return
	if OS.get_environment("NOARTS") != "":
		quit(0)
		return
	LK.choose("strikes", "dragonfire")
	for aid in ["w_cleaving_arc", "w_crescent_moon", "w_fan_of_knives", "w_rain_of_arrows", "w_spirit_orbs", "w_cyclone_edge"]:
		var w: String = G.sys("arts").weapon_of(aid)
		for id in G.items:
			var d: Dictionary = G.items[id]
			if w != "unarmed" and str(d.get("type", "")) == "weapon" and str(G.WEAPON_SKILL.get(str(d.get("kind", "sword")), "")) == w:
				G.inventory[id] = 1
				G.weapon = id
				break
		G.techniques[aid] = true
		G.heat = 0.0
		G.qi = 1e9
		pl._cool.clear()
		pl.cast_art(aid, fwd)
		Engine.time_scale = 0.1
		for i in 9:
			await process_frame
		root.get_viewport().get_texture().get_image().save_png("/tmp/strike_%s.png" % aid)
		Engine.time_scale = 1.0
		for i in 60:
			await process_frame
	quit(0)

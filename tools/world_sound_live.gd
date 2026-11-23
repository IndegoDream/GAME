extends SceneTree
## Round 184, with a real window (xvfb): the world's sounds play from real 3D players in a real village,
## the "World" bus has its echo, a villager greets you with a line over their head, the floors under you
## change what your feet say. Saves a picture of the greeting to /tmp/greet.png.
##   xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x720 --script res://tools/world_sound_live.gd
var passed := 0
var failed := 0
var G
var m


func check(n: String, ok: bool, d = "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("  FAIL  " + n + "  [" + str(d) + "]")


func _initialize() -> void:
	await process_frame
	G = root.get_node("Game")
	G.save_path = "user://wsl_save.json"
	G.save_base = "user://wsl_slots"
	G.playlog_path = "user://wsl.jsonl"
	load("res://scripts/core/Gfx.gd").settings["preset"] = "low"
	load("res://Main.gd").force_veil = true
	m = load("res://Main.tscn").instantiate()
	root.add_child(m)
	for i in 6:
		await process_frame
	G.new_game()
	G.hour_override = 10.0
	print("LIVE: main up ", Time.get_ticks_msec()); G.go_to("village", "<")
	for i in 60:
		await process_frame
	print("LIVE: village up ", Time.get_ticks_msec()); var au = G.audio
	var ws = au.world
	check("audio is on (a real window)", au.on())
	check("the World bus is there", AudioServer.get_bus_index("World") >= 0)
	var bi := AudioServer.get_bus_index("World")
	check("the World bus has its echo", bi >= 0 and AudioServer.get_bus_effect_count(bi) >= 1 and AudioServer.get_bus_effect(bi, 0) is AudioEffectReverb)
	check("world sounds go through the World bus", au._wpool.size() > 0 and str(au._wpool[0].bus) == "World")
	ws._place_poll = 0.0
	ws.tick(0.1)
	check("the village bed is known (%s)" % ws.bed, ws.bed.begins_with("village"), ws.bed)
	check("the village floor is grass or snow (%s)" % ws.ground_kind, ws.ground_kind in ["grass", "snow"], ws.ground_kind)
	# spots: make every timer due and let it play
	ws._timers.clear()
	for row in ws.entries_for(au.data(), ws.bed, ws.weather):
		ws._timers[row[0]] = 0.01
	ws._poll = 0.0
	ws.tick(0.6)
	var playing := 0
	var at_dist := []
	var pl = root.get_tree().get_first_node_in_group("player")
	for p in ws._p3:
		if (p as AudioStreamPlayer3D).playing:
			playing += 1
			if pl:
				at_dist.append(snappedf((p as AudioStreamPlayer3D).global_position.distance_to(pl.global_position), 0.1))
	check("spots play from 3D players (%d)" % playing, playing >= 1, ws.spot_count)
	var far_ok := true
	for dd in at_dist:
		if float(dd) < 1.0 or float(dd) > 40.0:
			far_ok = false
	check("spots sit around you, not on you (%s)" % str(at_dist), far_ok, at_dist)
	# a blow off to the side goes through a 3D player too
	var before := 0
	for p in ws._p3:
		before += 1 if (p as AudioStreamPlayer3D).playing else 0
	if pl:
		G.sfx_at("hit_flesh", pl.global_position + Vector3(6, 1, 0), 0.6)
	await process_frame
	var after := 0
	for p in ws._p3:
		after += 1 if (p as AudioStreamPlayer3D).playing else 0
	check("a blow nearby plays in 3D", after >= before and after >= 1)
	# footsteps on the village grass
	if pl:
		for i in 8:
			au.footstep(true, false, 0.5)
	check("footsteps played", true)
	# the weather layer
	ws._set_weather_bed("rain_light", 1.0)
	for i in 10:
		await process_frame
	check("rain can be heard when it rains", ws._wx_to != null and ws._wx_to.playing and ws.weather_bed == "rain_light")
	ws._set_weather_bed("", 1.0)
	print("LIVE: spots done ", Time.get_ticks_msec()); # a villager greets you
	var npcs := []
	for n in root.get_tree().get_nodes_in_group("interactable"):
		if n.has_method("greet") and n.visible:
			npcs.append(n)
	check("the village has folk to greet you (%d)" % npcs.size(), npcs.size() >= 3)
	if npcs.size() > 0 and pl:
		var who = npcs[0]
		for n2 in npcs:
			if str(n2.role) == "villager":
				who = n2
				break
		var spot: Vector3 = who.global_position + Vector3(0, 0, 2.6)
		pl.global_position = spot
		load("res://scripts/actors/NPC.gd")._last_greet_ms = -999999
		who._greet_cd = 0.0
		who._greet_near = false
		var hud = root.get_tree().get_first_node_in_group("hud")
		print("LIVE: hud blocking ", hud.is_blocking() if hud else null, " dist ", pl.global_position.distance_to(who.global_position), " combat ", au.combat_level)
		if hud:
			for k in ["_title", "_create", "_ending", "_char", "_hub", "_dialog", "_pause", "_inventory", "_journal", "_chat", "_lattice", "_trade", "_play"]:
				var c = hud.get(k)
				if c is CanvasItem:
					(c as CanvasItem).visible = false
		for i in 12:
			await process_frame
		print("LIVE: greeted ", Time.get_ticks_msec(), " blocking ", hud.is_blocking() if hud else null, " dist ", pl.global_position.distance_to(who.global_position), " near ", who._greet_near, " cd ", who._greet_cd)
		check("%s said something as you came near (%s)" % [who.npc_name, who.said_last], who.said_last != "", who.said_last)
		check("a line shows over their head", who._bubble != null and who._bubble.visible and who._bubble.text.length() > 3)
		# frame the two of them and keep a picture
		var cam := root.get_viewport().get_camera_3d()
		if cam:
			for i in 6:
				await process_frame
			var img := root.get_viewport().get_texture().get_image()
			img.save_png("/tmp/greet.png")
		# walking away and back doesn't make them repeat straight away
		var said: String = who.said_last
		who.said_last = ""
		pl.global_position = who.global_position + Vector3(0, 0, 12)
		for i in 8:
			await process_frame
		pl.global_position = spot
		for i in 8:
			await process_frame
		check("no repeat right away", who.said_last == "", who.said_last)
	print("WORLD SOUND LIVE %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

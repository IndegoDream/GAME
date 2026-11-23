extends SceneTree
## round 184b: pictures of the life of the air in the village -- fireflies at night, petals by day, rain
## landing, breath and a snow puff. xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 960x540 --script res://tools/_life_shot.gd
var G


func _initialize() -> void:
	await process_frame
	G = root.get_node("Game")
	G.save_path = "user://life_save.json"
	G.save_base = "user://life_slots"
	G.playlog_path = "user://life.jsonl"
	load("res://scripts/core/Gfx.gd").settings["preset"] = "medium"
	load("res://Main.gd").force_veil = true
	var m = load("res://Main.tscn").instantiate()
	root.add_child(m)
	for i in 4:
		await process_frame
	G.new_game()
	var hud = root.get_tree().get_first_node_in_group("hud")
	G.hour_override = 23.0
	G.go_to("village", "<")
	for i in 14:
		await process_frame
	if hud:
		for k in ["_title", "_create", "_ending", "_char", "_hub", "_dialog", "_pause", "_inventory", "_journal", "_chat", "_lattice", "_trade", "_play"]:
			var c = hud.get(k)
			if c is CanvasItem:
				(c as CanvasItem).visible = false
	var lv = root.get_tree().get_first_node_in_group("level")
	var wfx = lv.get_node_or_null("WorldFX")
	wfx.apply()
	for kind in ["fireflies", "petals", "splashes"]:
		G.hour_override = 23.0 if kind == "fireflies" else 11.0
		wfx.apply()
		wfx._set_life(kind)
		for i in 8:
			await process_frame
		root.get_viewport().get_texture().get_image().save_png("/tmp/life_%s.png" % kind)
		print("SHOT ", kind, " life=", wfx._life_kind)
	# breath and a snow step
	G.hour_override = 9.0
	wfx.apply()
	wfx._set_life("")
	var pl = root.get_tree().get_first_node_in_group("player")
	var FX = load("res://scripts/fx/FX.gd")
	for i in 3:
		var yaw: float = pl._model.rotation.y
		var fwd := Vector3(sin(yaw), 0, cos(yaw))
		FX.breath(pl.global_position + Vector3(0, 1.55, 0) + fwd * 0.22, fwd)
		FX.step_puff(pl.global_position + fwd * 0.4, "snow", true)
		FX.step_puff(pl.global_position - fwd * 0.6, "water", false)
		await process_frame
	await process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/life_breath.png")
	print("SHOT breath")
	quit(0)

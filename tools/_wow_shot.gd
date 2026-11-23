extends SceneTree
## round 185: lantern night over Eliet with the northern lights, and cloud shadows by day (/tmp/wow_*.png)
var G


func _initialize() -> void:
	await process_frame
	G = root.get_node("Game")
	G.save_path = "user://wow_save.json"
	G.save_base = "user://wow_slots"
	G.playlog_path = "user://wow.jsonl"
	load("res://scripts/core/Gfx.gd").settings["preset"] = "medium"
	load("res://Main.gd").force_veil = true
	var m = load("res://Main.tscn").instantiate()
	root.add_child(m)
	for i in 4:
		await process_frame
	G.new_game()
	G.hour_override = 21.0
	var W = G.sys("world")
	for dd in range(0, 200, 2):
		W.day_override = dd
		if str(W.weather("surface").get("id", "")) == "clear":
			break
	print("DAY ", W.day_override, " ", W.weather("surface").get("id"), " ", W.season_id())
	G.go_to("village", "<")
	for i in 12:
		await process_frame
	var hud = root.get_tree().get_first_node_in_group("hud")
	if hud:
		hud.visible = false
	var lv = root.get_tree().get_first_node_in_group("level")
	var wfx = lv.get_node_or_null("WorldFX")
	var pl = root.get_tree().get_first_node_in_group("player")
	wfx.apply()
	if wfx._lanterns == null:
		wfx._lanterns = load("res://scripts/world/SkyLanterns.gd").new()
		wfx._lanterns.setup(lv)
		wfx.add_child(wfx._lanterns)
	wfx._lanterns.start(true)
	for i in 60:
		wfx._lanterns._process(1.0)
	if lv._sky_mat:
		lv._sky_mat.set_shader_parameter("aurora", 1.0)
		lv._sky_mat.set_shader_parameter("cloud_cover", 0.2)
	var cam := Camera3D.new()
	cam.fov = 70
	root.add_child(cam)
	cam.global_position = pl.global_position + Vector3(0, 2.0, 9)
	cam.look_at(pl.global_position + Vector3(0, 14, -30))
	cam.make_current()
	for i in 6:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/wow_lanterns.png")
	print("SHOT lanterns alive=", wfx._lanterns.alive())
	# by day: the clouds' shadows on the land
	G.hour_override = 12.0
	wfx._lanterns.stop()
	for l in wfx._lanterns._lanterns:
		(l[0] as Node3D).visible = false
	wfx.apply()
	var lm = load("res://scripts/world/Horizon.gd").land_material(lv)
	if lm is ShaderMaterial:
		lm.set_shader_parameter("cloud_shadow", float(OS.get_environment("CS")) if OS.get_environment("CS") != "" else 0.34)
		print("LANDMAT ok")
	cam.global_position = pl.global_position + Vector3(0, 14, 22)
	cam.look_at(pl.global_position + Vector3(0, 0, -20))
	for i in 6:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/wow_clouds.png")
	print("SHOT clouds")
	quit(0)

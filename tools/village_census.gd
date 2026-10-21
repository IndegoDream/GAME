extends SceneTree
## what stands near the village fountain; optional top-down picture (arg: out.png)
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.new_game()
	var L = load("res://scripts/world/Level.gd")
	L.stream_on = false
	var lv = L.new()
	lv.build(G.load_level_def("village"))
	root.add_child(lv)
	await process_frame
	var fc: Vector2i = lv.fountain_cell()
	var fw: Vector3 = lv.cell_to_world(fc) if lv.has_method("cell_to_world") else Vector3.ZERO
	print("fountain cell ", fc, " world ", fw)
	var rows := []
	for n in lv.get_children():
		if not (n is Node3D) or n is Camera3D or n is Light3D:
			continue
		var d := Vector2(n.global_position.x - fw.x, n.global_position.z - fw.z).length()
		if d < 18.0:
			rows.append([d, String(n.name), n.get_class(), n.global_position])
	rows.sort_custom(func(a, b): return a[0] < b[0])
	for r in rows:
		print("%5.1f  %s (%s) at %s" % [r[0], r[1], r[2], str(r[3])])
	var out := OS.get_cmdline_user_args()
	if out.size() > 0:
		var env := WorldEnvironment.new()
		var e := Environment.new()
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.8, 0.8, 0.8)
		env.environment = e
		root.add_child(env)
		var cam := Camera3D.new()
		root.add_child(cam)
		cam.global_position = fw + Vector3(0, 40, 0.1)
		cam.look_at(fw, Vector3.UP)
		cam.fov = 50
		cam.current = true
		for i in 12:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_viewport().get_texture().get_image().save_png(out[0])
	quit()

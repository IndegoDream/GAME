extends SceneTree
## Round 165: a picture of the photo mode's own screen (a small stage, not the whole game). Args after --: output png path.
func _initialize() -> void:
	var out := "/tmp/photo_shot.png"
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	var G = root.get_node("Game")
	G.new_game()
	G.char_name = "Robert"
	var w := Node3D.new()
	root.add_child(w)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.45, 0.6, 0.8)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.environment = e
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	w.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.3, 0.5, 0.3)
	ground.material_override = gm
	w.add_child(ground)
	var pl := Node3D.new()
	pl.add_to_group("player")
	w.add_child(pl)
	var body := MeshInstance3D.new()
	body.mesh = CapsuleMesh.new()
	body.position = Vector3(0, 1, 0)
	pl.add_child(body)
	var pb = load("res://scripts/ui/PhotoMode.gd").new()
	root.add_child(pb)
	await process_frame
	pb.open()
	pb.caption_on = true
	pb.filter_i = 1
	pb._sync()
	for i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(out)
	print("saved ", out, " ", img.get_size())
	quit(0)

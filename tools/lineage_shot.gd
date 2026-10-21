extends SceneTree
## Round 167: bred beasts by stage -- rows are mutations (plus a hybrid and a generation line), columns are stages 0-3.
func _initialize() -> void:
	await process_frame
	var out := "/tmp/lineage.png"
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	var sp := "grey_wolf"
	if a.size() > 1:
		sp = a[1]
	var G = root.get_node("Game")
	G.new_game()
	var w := Node3D.new()
	root.add_child(w)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.3, 0.36, 0.45)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.environment = e
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.5, 0)
	w.add_child(sun)
	var BR = G.sys("breeding")
	var st: Dictionary = G.enemies.get(sp, {})
	var t: Array = st.get("tint", [0.7, 0.6, 0.5])
	var base := Color(float(t[0]), float(t[1]), float(t[2]))
	var rows := ["", "gilded", "shadow", "frost", "ember", "jade", "hybrid", "gen"]
	var mixk := "slime"
	for k in G.enemies.keys():
		if k != sp and G.enemies[k].has("tint"):
			mixk = k
			break
	for r in rows.size():
		for s in 4:
			var c := {"species": sp, "variant": "", "mix": "", "gen": 0}
			if rows[r] == "hybrid":
				c["mix"] = mixk
			elif rows[r] == "gen":
				c["gen"] = 2 + s * 2
			elif rows[r] != "":
				c["variant"] = rows[r]
			var col: Color = BR.tint_for(c, base)
			var m = load("res://scripts/actors/Enemy.gd").make_beast(col, str(st.get("name", sp)))
			m.evolve(s, col.lightened(0.35))
			var vc := Color(1, 1, 1)
			if c["variant"] != "":
				var va: Array = BR.data["variants"][c["variant"]]["color"]
				vc = Color(float(va[0]), float(va[1]), float(va[2]))
			var mc := Color(0, 0, 0, 0)
			if c["mix"] != "":
				var mt: Array = G.enemies[mixk]["tint"]
				mc = Color(float(mt[0]), float(mt[1]), float(mt[2]), 1.0)
			m.lineage(s, str(c["variant"]), vc, mc, int(c["gen"]))
			m.scale = Vector3.ONE * 2.0 * (0.8 + 0.12 * s)
			m.position = Vector3(float(s) * 3.4 - 5.1, 0, float(r) * 2.2 - 7.7)
			m.rotation.y = 1.2
			w.add_child(m)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 19.0
	w.add_child(cam)
	cam.position = Vector3(0, 16, 12)
	cam.look_at(Vector3(0, 0, 0))
	cam.current = true
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	img.save_png(out)
	print("saved ", out, " ", img.get_size(), " mix=", mixk)
	quit(0)

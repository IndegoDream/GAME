extends SceneTree
## round 183: a picture of the four Cultivation Seats and a Tribulation Sky strike
##   xvfb-run -a godot --path . --rendering-driver opengl3 --script res://tools/_looks_shot.gd -- out.png
var f := 0
func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		var env := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.05, 0.06, 0.09)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.5, 0.5, 0.6)
		e.glow_enabled = true
		env.environment = e
		root.add_child(env)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-50, 30, 0)
		sun.light_energy = 0.8
		root.add_child(sun)
		var g := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(40, 40)
		g.mesh = pm
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.22, 0.24, 0.2)
		g.material_override = gm
		root.add_child(g)
		var L = load("res://scripts/systems/Looks.gd")
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/looks.json"))
		var ids := ["lotus", "stones", "koi", "ink"]
		for i in ids.size():
			var c: Array = d["packs"]["seats_pack"]["items"][ids[i]]["color"]
			var s: Node3D = L.make_seat(ids[i], Color(c[0], c[1], c[2]))
			s.position = Vector3(-4.8 + 3.2 * i, 0, 0)
			root.add_child(s)
			var who := MeshInstance3D.new()
			var cm := CapsuleMesh.new()
			cm.radius = 0.3
			cm.height = 1.0
			who.mesh = cm
			var wm := StandardMaterial3D.new()
			wm.albedo_color = Color(0.55, 0.45, 0.4)
			who.material_override = wm
			who.position = s.position + Vector3(0, 0.5, 0)
			root.add_child(who)
			s._process(0.3)
		var vc: Array = d["packs"]["skies_pack"]["items"]["violet"]["color"]
		set_meta("vc", Color(vc[0], vc[1], vc[2]))
		var cam := Camera3D.new()
		root.add_child(cam)
		cam.position = Vector3(0, 4.2, 6.5)
		cam.look_at(Vector3(0, 0.6, -0.8))
		cam.fov = 55
	if f == 7:
		load("res://scripts/systems/Looks.gd")._bolt(root, Vector3(-1.6, 0, -4), get_meta("vc"))
	if f == 9:
		var img := root.get_viewport().get_texture().get_image()
		var out := "/tmp/looks.png"
		for a in OS.get_cmdline_user_args():
			out = a
		img.save_png(out)
		quit()
	return false

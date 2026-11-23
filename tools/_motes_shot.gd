extends SceneTree
## round 184b: each new mote kind alone, close up (for tuning)
var f := 0
func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		var env := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.05, 0.06, 0.1) if OS.get_environment("KIND") == "fireflies" else Color(0.45, 0.55, 0.4)
		env.environment = e
		root.add_child(env)
		var pl := Node3D.new()
		pl.add_to_group("player")
		root.add_child(pl)
		var g := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(60, 60)
		g.mesh = pm
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.25, 0.3, 0.2)
		g.material_override = gm
		root.add_child(g)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-50, 30, 0)
		root.add_child(sun)
		var m = load("res://scripts/fx/Motes.gd").new()
		m.kind = OS.get_environment("KIND")
		root.add_child(m)
		var cam := Camera3D.new()
		root.add_child(cam)
		cam.position = Vector3(0, 6, 11)
		cam.look_at(Vector3(0, 1, 0))
	if f == 40:
		root.get_viewport().get_texture().get_image().save_png("/tmp/m_%s.png" % OS.get_environment("KIND"))
		print("SHOT ", OS.get_environment("KIND"))
		quit(0)
	return false

extends SceneTree
## a row of houses from the CC0 kit, on bare ground, from a few angles
var _f := 0
var _cams := []
var _out := "/tmp/houses"

func _process(_d: float) -> bool:
	_f += 1
	if _f == 2:
		DirAccess.make_dir_recursive_absolute(_out)
		var H := load("res://scripts/world/Houses.gd")
		print("HOUSES available ", H.available())
		var env := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.55, 0.7, 0.9)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.6, 0.6, 0.62)
		e.ambient_light_energy = 0.8
		e.tonemap_mode = Environment.TONE_MAPPER_AGX
		env.environment = e
		root.add_child(env)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-50, 35, 0)
		sun.shadow_enabled = true
		root.add_child(sun)
		var g := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(120, 120)
		g.mesh = pm
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.35, 0.45, 0.28)
		g.material_override = gm
		root.add_child(g)
		var c2w := func(c: Vector2i) -> Vector3: return Vector3(c.x * 2.0 + 1.0, 0, c.y * 2.0 + 1.0)
		var specs := [[Rect2i(0, 0, 3, 4), Vector2i(0, 1)], [Rect2i(5, 0, 2, 2), Vector2i(0, 1)], [Rect2i(9, 0, 4, 5), Vector2i(0, 1)], [Rect2i(15, 0, 5, 3), Vector2i(0, 1)], [Rect2i(0, 7, 3, 7), Vector2i(1, 0)]]
		var seed := 11
		for sp in specs:
			for r in H.fit(sp[0]):
				var h: Dictionary = H.make(r, sp[1], seed, c2w)
				seed += 7
				root.add_child(h["node"])
				print("HOUSE ", r, " ok ", h["node"].mesh.get_surface_count(), " surfaces")
		var kinds := ["cow", "horse", "sheep", "pig", "llama"]
		for i in kinds.size():
			var cr = load("res://scripts/actors/Critter.gd").new()
			cr.setup(null, {"kind": kinds[i], "seed": i})
			cr.position = Vector3(2.0 + i * 3.2, 0, 18)
			root.add_child(cr)
			var ref := MeshInstance3D.new()          # a 1.8 m post to judge size by
			var bm := BoxMesh.new()
			bm.size = Vector3(0.15, 1.8, 0.15)
			ref.mesh = bm
			ref.position = Vector3(0.5 + i * 3.2, 0.9, 19.5)
			root.add_child(ref)
		for spec in [[Vector3(9, 3, 26), Vector3(9, 0.8, 18)], [Vector3(18, 9, 30), Vector3(18, 2, 4)], [Vector3(-6, 6, 18), Vector3(6, 2, 4)], [Vector3(20, 14, -16), Vector3(16, 1, 4)]]:
			var cam := Camera3D.new()
			root.add_child(cam)
			cam.position = spec[0]
			cam.look_at(spec[1])
			_cams.append(cam)
	if _f >= 8 and _f < 8 + _cams.size() * 4 and (_f - 8) % 4 == 0:
		var i := (_f - 8) / 4
		_cams[i].current = true
	if _f >= 10 and (_f - 10) % 4 == 0 and (_f - 10) / 4 < _cams.size():
		root.get_texture().get_image().save_png("%s/h%d.png" % [_out, (_f - 10) / 4])
	return _f > 10 + _cams.size() * 4

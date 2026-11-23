extends SceneTree
## r186: a full scan beside its low-poly copy (ID=grass_medium_01 ...) -> /tmp/lo_<id>.png
var f := 0
func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		var id := OS.get_environment("ID")
		var env := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.55, 0.65, 0.75)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.6, 0.6, 0.6)
		env.environment = e
		root.add_child(env)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-45, 35, 0)
		root.add_child(sun)
		var a: Node3D = load("res://assets/realistic/%s/%s.gltf" % [id, id]).instantiate()
		var b: Node3D = load("res://assets/realistic/%s/%s_lo.gltf" % [id, id]).instantiate()
		root.add_child(a)
		root.add_child(b)
		var ab := AABB()
		for mi in a.find_children("*", "MeshInstance3D", true, false):
			ab = ab.merge((mi as MeshInstance3D).get_aabb()) if ab.size != Vector3.ZERO else (mi as MeshInstance3D).get_aabb()
		var w := maxf(ab.size.x, ab.size.z) * 1.2
		a.position = Vector3(-w * 0.55, 0, 0)
		b.position = Vector3(w * 0.55, 0, 0)
		var cam := Camera3D.new()
		root.add_child(cam)
		var c := ab.get_center()
		cam.position = Vector3(0, c.y + ab.size.y * 0.6, w * 1.6)
		cam.look_at(Vector3(0, c.y, 0))
	if f == 12:
		root.get_viewport().get_texture().get_image().save_png("/tmp/lo_%s.png" % OS.get_environment("ID"))
		quit(0)
	return false

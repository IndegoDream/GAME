extends SceneTree
## round 185: the night sky -- northern lights and a shooting star (pictures in /tmp/sky_*.png)
var f := 0
var cam: Camera3D
var mat: ShaderMaterial
func _process(_d: float) -> bool:
	f += 1
	if f == 2:
		mat = ShaderMaterial.new()
		mat.shader = load("res://assets/shaders/sky.gdshader")
		mat.set_shader_parameter("daylight", 0.0)
		mat.set_shader_parameter("cloud_cover", float(OS.get_environment("CLOUD")) if OS.get_environment("CLOUD") != "" else 0.25)
		mat.set_shader_parameter("aurora", float(OS.get_environment("AURORA")) if OS.get_environment("AURORA") != "" else 1.0)
		mat.set_shader_parameter("meteors", 1.0)
		var sky := Sky.new()
		sky.sky_material = mat
		var e := Environment.new()
		e.background_mode = Environment.BG_SKY
		e.sky = sky
		e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		var we := WorldEnvironment.new()
		we.environment = e
		root.add_child(we)
		cam = Camera3D.new()
		cam.fov = float(OS.get_environment("FOV")) if OS.get_environment("FOV") != "" else 80.0
		root.add_child(cam)
		cam.rotation_degrees = Vector3(18, 0, 0)
	if f == 30:
		root.get_viewport().get_texture().get_image().save_png("/tmp/sky_north.png")
		cam.rotation_degrees = Vector3(float(OS.get_environment("PITCH")) if OS.get_environment("PITCH") != "" else 40.0, float(OS.get_environment("YAW")) if OS.get_environment("YAW") != "" else 60.0, 0)
	if f == 32:
		mat.set_shader_parameter("meteor_test", 0.35)
	if f == 36:
		root.get_viewport().get_texture().get_image().save_png("/tmp/sky_meteor.png")
		mat.set_shader_parameter("meteor_test", -1.0)
	if f >= 37 and f <= 120 and f % 3 == 0:
		root.get_viewport().get_texture().get_image().save_png("/tmp/sky_m%03d.png" % f)
	if f % 30 == 0:
		print("T ", f, " ", Time.get_ticks_msec())
	if f == 121:
		print("SKY SHOTS")
		quit(0)
	return false

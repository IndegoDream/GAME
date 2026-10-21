extends SceneTree
## r121: the wired effects work. Prints "WIRECHECK n passed, m failed".
var ok := 0
var bad := 0
func t(c: bool, m: String) -> void:
	if c:
		ok += 1
	else:
		bad += 1
		print("WIRECHECK FAIL ", m)
func _initialize() -> void:
	_run()
func _run() -> void:
	await process_frame
	var O = load("res://scripts/fx/OwnFX.gd")
	t(O != null, "OwnFX loads")
	t(not O.on(), "off in headless unless forced")
	var root3 := Node3D.new()
	root.add_child(root3)
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.2, 0.6, 0.3)
	mi.material_override = sm
	root3.add_child(mi)
	t(not O.dissolve(root3), "no dissolve when off")
	t(O.dissolve(root3, 0.0, 0.2, true), "dissolve starts when forced")
	var m = mi.material_override
	t(m is ShaderMaterial, "the mesh override became the dissolve material")
	var mi2 := MeshInstance3D.new()
	mi2.mesh = BoxMesh.new()
	var r2 := Node3D.new()
	root.add_child(r2)
	r2.add_child(mi2)
	t(O.dissolve(r2, 0.0, 0.2, true) and mi2.get_surface_override_material(0) is ShaderMaterial, "a plain surface gets it per surface")
	t(m != null and (m as ShaderMaterial).get_shader_parameter("albedo") == Color(0.2, 0.6, 0.3), "colour carried over")
	await create_timer(0.5).timeout
	t(m != null and float((m as ShaderMaterial).get_shader_parameter("progress")) > 0.95, "progress reaches 1")
	t(not root3.visible, "model hidden at the end")
	t(O.sfx("hit_flesh") == null, "classic sfx by default")
	var G = load("res://scripts/core/Gfx.gd")
	G.settings["sfx_style"] = "own"
	var s = O.sfx("hit_flesh")
	t(s is AudioStream, "own sfx found")
	t(O.sfx("no_such_sound") == null, "unmapped name falls through")
	for k in O.SFX_MAP:
		for f in O.SFX_MAP[k]:
			t(ResourceLoader.exists("res://assets/own/sfx/" + f + ".wav"), "file for " + k + ": " + f)
	print("WIRECHECK %d passed, %d failed" % [ok, bad])
	quit()

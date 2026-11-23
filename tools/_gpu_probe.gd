extends SceneTree
## r188: what costs the frame in Forward+ (software Vulkan -- ratios, not real numbers). Robert's settings:
## Medium, effects Low, fog off. ID= (default village). Each suspect is switched off alone, then back on.
var G
var vp_rid: RID
var lv


func _measure(label: String, frames: int = 5) -> float:
	for i in 2:
		await process_frame
	var gpu := 0.0
	var cpu := 0.0
	var t := Time.get_ticks_usec()
	for i in frames:
		await process_frame
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp_rid) + RenderingServer.get_frame_setup_time_cpu()
	var wall := (Time.get_ticks_usec() - t) / 1000.0 / frames
	print("PROBE %-34s wall %8.1f ms  gpu %8.1f  cpu %7.1f  draws %6d  prims %9d" % [label, wall, gpu / frames, cpu / frames,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	return wall


func _initialize() -> void:
	await process_frame
	vp_rid = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	G = root.get_node("Game")
	G.save_base = "user://tool_shot"      # (never the real account: the test kit would switch itself on there)
	G.save_path = "user://gpu_probe.json"
	G.playlog_path = "user://gpu_probe.jsonl"
	var Gf = load("res://scripts/core/Gfx.gd")
	Gf.settings["preset"] = "medium"
	Gf.settings["effects"] = "low"
	Gf.settings["fog"] = "off"
	if OS.get_environment("FULL") != "":
		load("res://scripts/core/Art.gd").full_detail = true
	load("res://Main.gd").force_veil = true
	var m = load("res://Main.tscn").instantiate()
	root.add_child(m)
	for i in 10:
		await process_frame
	await _measure("title screen")
	if OS.get_environment("ROB") != "":
		G.save_base = "user://tool_rob"          # a copy of Robert's own save (realm 15, his home, pets, farm ...)
		G.use_slot(2)
		print("PROBE rob save loaded: ", G.load_game())
		G.save_base = "user://tool_shot"
		G.save_path = "user://gpu_probe.json"
	else:
		G.new_game()
	G.hour_override = 11.0
	var want := OS.get_environment("ID") if OS.get_environment("ID") != "" else "village"
	G.go_to(want, "<")
	for i in 900:
		await process_frame
		lv = root.get_tree().get_first_node_in_group("level")
		if lv and lv.stream_left() == 0 and i > 20:
			break
	if OS.get_environment("NOBATCH") == "":
		lv.batch_trees_now()
		lv.batch_props_now()
	else:
		lv.set_process(false)          # (as before r186: every tree, shrub and wall piece its own draw)
	for c in root.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	await _measure("BASE (all on)")
	var env: Environment = null
	for we in root.find_children("*", "WorldEnvironment", true, false):
		env = (we as WorldEnvironment).environment
	if env:
		print("ENV ssao=%s ssil=%s glow=%s sdfgi=%s vfog=%s fog=%s ssr=%s sky=%s" % [env.ssao_enabled, env.ssil_enabled, env.glow_enabled, env.sdfgi_enabled, env.volumetric_fog_enabled, env.fog_enabled, env.ssr_enabled, env.sky != null])
		if env.sky:
			print("SKY process_mode=%d radiance=%d mat=%s" % [env.sky.process_mode, env.sky.radiance_size, env.sky.sky_material])
	var suns := root.find_children("*", "DirectionalLight3D", true, false)
	for s in suns:
		print("SUN shadow=%s splits=%d max=%.0f" % [(s as Light3D).shadow_enabled, (s as DirectionalLight3D).directional_shadow_mode, (s as DirectionalLight3D).directional_shadow_max_distance])
	var vp := root.get_viewport()
	print("VP size=%s scale3d=%.2f msaa=%d aa=%d taa=%s mode=%d" % [vp.get_visible_rect().size, vp.scaling_3d_scale, vp.msaa_3d, vp.screen_space_aa, vp.use_taa, vp.scaling_3d_mode])
	if OS.get_environment("QUICK") != "":
		for s in suns:
			(s as Light3D).shadow_enabled = false
		await _measure("- sun shadows")
		quit(0)
		return
	# --- one at a time ---
	for s in suns:
		(s as Light3D).shadow_enabled = false
	await _measure("- sun shadows")
	for s in suns:
		(s as Light3D).shadow_enabled = true
	if env:
		for k in ["ssao_enabled", "ssil_enabled", "glow_enabled", "sdfgi_enabled", "ssr_enabled", "volumetric_fog_enabled", "fog_enabled"]:
			if env.get(k):
				env.set(k, false)
				await _measure("- env " + k)
				env.set(k, true)
		if env.sky:
			var old = env.sky.sky_material
			env.sky.sky_material = ProceduralSkyMaterial.new()
			await _measure("- sky shader (plain sky)")
			env.sky.sky_material = old
			var oldm = env.sky.process_mode
			env.sky.process_mode = Sky.PROCESS_MODE_QUALITY
			await _measure("- sky realtime (quality mode)")
			env.sky.process_mode = oldm
	var groups := {
		"horizon": func(n): return n.get_script() != null and str(n.get_script().resource_path).ends_with("Horizon.gd"),
		"deco tufts": func(n): return n is MultiMeshInstance3D and str(n.name).begins_with("Deco_"),
		"tree batches": func(n): return n is GeometryInstance3D and (str(n.name).begins_with("TreeBark") or str(n.name).begins_with("TreeLeaves")),
		"prop batches": func(n): return n is MultiMeshInstance3D and str(n.name).begins_with("Props"),
		"ground plane": func(n): return str(n.name) == "OutdoorGround",
		"houses": func(n): return n.get_script() == null and str(n.name).begins_with("House"),
		"particles": func(n): return n is GPUParticles3D or n is CPUParticles3D,
		"omni/spot lights": func(n): return n is OmniLight3D or n is SpotLight3D,
		"actors (npc/enemy)": func(n): return n is CharacterBody3D or (n is StaticBody3D and n.get_script() != null),
	}
	for gname in groups:
		var hidden := []
		for n in root.find_children("*", "Node", true, false):
			if (groups[gname] as Callable).call(n) and n is Node3D and (n as Node3D).visible:
				(n as Node3D).visible = false
				hidden.append(n)
		await _measure("- %s (%d)" % [gname, hidden.size()])
		for n in hidden:
			if is_instance_valid(n):
				(n as Node3D).visible = true
	# all 3D off: what's left is the 2D/post
	var cam := root.get_viewport().get_camera_3d()
	var all3 := []
	for n in lv.get_children():
		if n is Node3D and (n as Node3D).visible:
			(n as Node3D).visible = false
			all3.append(n)
	await _measure("- the whole level")
	for n in all3:
		(n as Node3D).visible = true
	await _measure("BASE again")
	quit(0)

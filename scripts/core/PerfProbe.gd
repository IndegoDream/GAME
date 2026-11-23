extends Node
## Round 188: what is slow on THIS machine. Robert's PC (RTX 5060 Ti) showed 3-4 frames a second in Eliet, and
## nothing in the cloud can draw with his card. This rides along in play (Main adds it):
##  - every 15 s a "perf" line in crumbs.txt: frame rate, GPU and CPU time to draw, draws, triangles, nodes;
##  - if the frame rate stays under 12 for ~8 s once a place has settled, it checks -- once a run, test builds
##    only -- by switching each suspect off for about a second and timing the frame without it (sun shadows,
##    each screen effect, the sky, resolution, lamps, particles, the land beyond the map, each kind of thing in
##    the place, the HUD), then puts everything back. The answer goes to crumbs.txt and perf_probe.txt.
const SLOW_FPS := 12.0
const SLOW_SECONDS := 8.0
const LINE_EVERY := 15.0
const MAX_LINES := 240
const OUT := "user://perf_probe.txt"

static func wanted() -> bool:
	## r271: the debug tools (timing probes, crumbs, the crash banner) run only while the game is played or edited from the Godot editor,
	## or when this machine asks for them by having a file named debug_on.txt in the game's data folder. A normal build runs none of it.
	return OS.has_feature("editor") or FileAccess.file_exists("user://debug_on.txt")


static var probed := false            # once a run
var _line_t := 0.0
var _lines := 0
var _slow_t := 0.0
var _settle_t := 0.0
var running := false
var results: Array = []               # [label, wall ms, gpu ms, cpu ms, draws]  (tests read it)
var force := false                    # (tests) run even in a clean build


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


static func stats(vp: Viewport) -> String:
	var rid := vp.get_viewport_rid()
	return "gpu=%.1f cpu=%.1f setup=%.1f proc=%.1f draws=%d prims=%dk objs=%d" % [
		RenderingServer.viewport_get_measured_render_time_gpu(rid), RenderingServer.viewport_get_measured_render_time_cpu(rid),
		RenderingServer.get_frame_setup_time_cpu(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))]


func _crumb(msg: String) -> void:
	var ml = get_node_or_null("/root/MemLog")
	if ml != null:
		ml.crumb(msg)


func _level() -> Node:
	return get_tree().get_first_node_in_group("level")


func _process(delta: float) -> void:
	if running:
		return
	var lv := _level()
	_line_t += delta
	if _line_t >= LINE_EVERY and _lines < MAX_LINES:
		_line_t = 0.0
		_lines += 1
		_crumb("perf fps=%d %s nodes=%d lvl=%s" % [int(Performance.get_monitor(Performance.TIME_FPS)), stats(get_viewport()),
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), str(lv.level_id) if lv != null else "-"])
	if probed:
		return
	if lv == null or (lv.has_method("stream_left") and lv.stream_left() > 0):
		_settle_t = 0.0
		_slow_t = 0.0
		return
	_settle_t += delta
	if _settle_t < 6.0:
		return
	if Performance.get_monitor(Performance.TIME_FPS) < SLOW_FPS:
		_slow_t += delta
	else:
		_slow_t = 0.0
	if _slow_t >= SLOW_SECONDS and (force or not load("res://scripts/systems/Tester.gd").clean()):
		probe()


# ---------------------------------------------------------------------------------------------------------

func _measure(frames: int = 3) -> Array:
	for i in 2:
		await get_tree().process_frame
	var rid := get_viewport().get_viewport_rid()
	var gpu := 0.0
	var cpu := 0.0
	var draws := 0
	var t := Time.get_ticks_usec()
	for i in frames:
		await get_tree().process_frame
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu()
		draws += int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	return [(Time.get_ticks_usec() - t) / 1000.0 / frames, gpu / frames, cpu / frames, draws / frames]


func _hide(nodes: Array) -> Callable:
	var hidden := []
	for n in nodes:
		if n is Node3D and is_instance_valid(n) and (n as Node3D).visible:
			(n as Node3D).visible = false
			hidden.append(n)
	return func():
		for h in hidden:
			if is_instance_valid(h):
				(h as Node3D).visible = true


func _swap(obj: Object, prop: String, value) -> Callable:
	var old = obj.get(prop)
	obj.set(prop, value)
	return func():
		if is_instance_valid(obj):
			obj.set(prop, old)


func _suspects() -> Array:
	## [label, func() -> restore func]; each is tried alone
	var out := []
	var vp := get_viewport()
	var tree := get_tree()
	var lv := _level()
	var env: Environment = null
	var w3 := vp.find_world_3d()
	if w3 != null:
		env = w3.environment
	for we in tree.root.find_children("*", "WorldEnvironment", true, false):
		if (we as WorldEnvironment).environment != null:
			env = (we as WorldEnvironment).environment
	var suns := tree.root.find_children("*", "DirectionalLight3D", true, false)
	out.append(["sun shadows", func():
		var back := []
		for s in suns:
			if is_instance_valid(s) and (s as Light3D).shadow_enabled:
				back.append(_swap(s, "shadow_enabled", false))
		return func():
			for b in back:
				(b as Callable).call()])
	if env != null:
		for k in ["ssao_enabled", "ssil_enabled", "glow_enabled", "ssr_enabled", "sdfgi_enabled", "volumetric_fog_enabled", "fog_enabled"]:
			if bool(env.get(k)):
				var kk: String = k
				out.append(["screen effect " + kk.trim_suffix("_enabled"), func(): return _swap(env, kk, false)])
		if env.sky != null and env.sky.sky_material != null:
			out.append(["the sky shader", func(): return _swap(env.sky, "sky_material", ProceduralSkyMaterial.new())])
	if vp.msaa_3d != Viewport.MSAA_DISABLED:
		out.append(["MSAA", func(): return _swap(vp, "msaa_3d", Viewport.MSAA_DISABLED)])
	out.append(["half resolution (3D)", func(): return _swap(vp, "scaling_3d_scale", 0.5)])
	out.append(["lamps", func(): return _hide(tree.root.find_children("*", "OmniLight3D", true, false) + tree.root.find_children("*", "SpotLight3D", true, false))])
	out.append(["particles", func(): return _hide(tree.root.find_children("*", "GPUParticles3D", true, false) + tree.root.find_children("*", "CPUParticles3D", true, false))])
	if lv != null:
		var kinds := {
			"the land beyond the map": func(n): return n.get_script() != null and str(n.get_script().resource_path).ends_with("Horizon.gd"),
			"ground tufts": func(n): return str(n.name).contains("Deco_"),
			"rock edges": func(n): return str(n.name).contains("Crags_"),
			"trees": func(n): return str(n.name).contains("Tree") or n.has_meta("realistic_tree"),
			"still props": func(n): return str(n.name).contains("Props") or n.has_meta("pp"),
			"water": func(n): return str(n.name).contains("Water") or n.has_meta("batch_water"),
			"people and creatures": func(n): return n is CharacterBody3D or (n is StaticBody3D and n.get_script() != null),
			"other scripted things": func(n): return n.get_script() != null and not (n is CharacterBody3D) and not str(n.get_script().resource_path).ends_with("Horizon.gd"),
			"plain level meshes": func(n): return (n is MeshInstance3D or n is MultiMeshInstance3D) and n.get_script() == null,
		}
		for kname in kinds:
			var test: Callable = kinds[kname]
			out.append([kname, func():
				var pick := []
				for c in lv.get_children():
					if test.call(c):
						pick.append(c)
				return _hide(pick)])
		out.append(["the whole place", func(): return _hide([lv])])
	out.append(["all 3D", func(): return _swap(vp, "disable_3d", true)])
	out.append(["the HUD", func():
		var back := []
		for c in tree.root.find_children("*", "CanvasLayer", true, false):
			if (c as CanvasLayer).visible:
				back.append(_swap(c, "visible", false))
		return func():
			for b in back:
				(b as Callable).call()])
	return out


func probe() -> void:
	if running:
		return
	running = true
	probed = true
	results.clear()
	var ar = get_parent().get("auto_res") if get_parent() != null else null      # (round 192: hold the picture size still while measuring)
	if ar != null:
		ar.set_process(false)
	var lv := _level()
	var lid := str(lv.level_id) if lv != null else "-"
	if not force:
		Game.message.emit("The drawing is slow -- checking what slows it (about half a minute; things may blink).")
	_crumb("probe start: fps=%d %s lvl=%s size=%s" % [int(Performance.get_monitor(Performance.TIME_FPS)), stats(get_viewport()), lid, str(get_viewport().get_visible_rect().size)])
	# round 198: wait for the slowness to settle before blaming anything. Robert's floor-24 probe caught a passing storm
	# (420 ms frames, then 19 ms a few rows later) and so "found" sun shadows and SSAO costing 90% -- it was the first
	# rows, not the switches. Measure until two looks agree (within a quarter) or ~3 s go by; say if it eased by itself.
	var first: Array = await _measure()
	var base: Array = first
	var settle := PackedStringArray(["%.0f" % float(first[0])])
	for k in 8:
		await get_tree().create_timer(0.35).timeout
		var nxt: Array = await _measure()
		settle.append("%.0f" % float(nxt[0]))
		var agree := absf(float(nxt[0]) - float(base[0])) <= 0.25 * maxf(float(base[0]), 1.0)
		base = nxt
		if agree:
			break
	var eased := float(base[0]) < 0.6 * float(first[0])
	results.append(["(everything on)", base[0], base[1], base[2], base[3]])
	for s in _suspects():
		if _level() != lv:
			break                                   # the place changed under us -- stop (what was switched off is back already)
		var restore: Callable = (s[1] as Callable).call()
		var m: Array = await _measure()
		restore.call()
		results.append([s[0], m[0], m[1], m[2], m[3]])
		await get_tree().process_frame
	var again: Array = await _measure()
	results.append(["(everything on, again)", again[0], again[1], again[2], again[3]])
	var lines := PackedStringArray()
	lines.append("perf probe %s  lvl=%s  window=%s  picture=%d%%  preset=%s  effects=%s" % [Time.get_datetime_string_from_system(), lid, str(get_viewport().get_visible_rect().size),
		int(round(get_viewport().scaling_3d_scale * 100.0)), preload("res://scripts/core/Gfx.gd").preset(), str(preload("res://scripts/core/Gfx.gd").settings.get("effects", "?"))])
	var gc = get_parent().get("gpu_courtesy") if get_parent() != null else null
	lines.append("video memory: the game %.0f MB%s" % [RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0,
		("   other: " + str(gc.last_seen)) if gc != null and str(gc.last_seen) != "" else ""])
	lines.append("settling (frame ms): %s%s" % [" -> ".join(settle), "   -- it eased by itself before anything was switched off (likely the card preparing shaders for a new place)" if eased else ""])
	lines.append("%-26s %9s %9s %9s %7s" % ["without", "frame ms", "gpu ms", "cpu ms", "draws"])
	for r in results:
		lines.append("%-26s %9.1f %9.1f %9.1f %7d" % r)
	var ranked := results.slice(1, results.size() - 1)
	ranked.sort_custom(func(a, b): return float(a[1]) < float(b[1]))
	var ref: float = (float(base[0]) + float(again[0])) * 0.5
	var top := PackedStringArray()
	for r in ranked.slice(0, 4):
		top.append("%s %.0f%%" % [r[0], 100.0 * (1.0 - float(r[1]) / maxf(ref, 0.001))])
	lines.append("biggest savings: " + ", ".join(top))
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
		f.close()
	for l in lines:
		_crumb("probe " + l)
	if not force:
		Game.message.emit("Done checking -- noted for the developer.")
	if ar != null and is_instance_valid(ar):
		ar.set_process(true)
	running = false

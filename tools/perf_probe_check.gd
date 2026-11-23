extends SceneTree
## Round 188: the in-play slowness probe switches each suspect off and puts EVERYTHING back.
##   godot --headless --path . --script res://tools/perf_probe_check.gd
var _pass := 0
var _fail := 0


func check(what: String, ok: bool, detail = "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL  ", what, "  [", str(detail), "]")


func _snap(lv: Node) -> Dictionary:
	var d := {}
	for n in root.find_children("*", "Node", true, false):
		if n is Node3D:
			d[n.get_instance_id()] = (n as Node3D).visible
		elif n is CanvasLayer:
			d[n.get_instance_id()] = (n as CanvasLayer).visible
		if n is Light3D:
			d[str(n.get_instance_id()) + "s"] = (n as Light3D).shadow_enabled
	var vp := root.get_viewport()
	d["msaa"] = vp.msaa_3d
	d["scale"] = vp.scaling_3d_scale
	d["d3"] = vp.disable_3d
	var w3 := vp.find_world_3d()
	if w3 and w3.environment:
		var e := w3.environment
		d["env"] = [e.ssao_enabled, e.ssil_enabled, e.glow_enabled, e.fog_enabled, e.sdfgi_enabled, e.volumetric_fog_enabled, e.ssr_enabled, e.sky.sky_material if e.sky else null]
	return d


func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.save_path = "user://perf_probe_check.json"
	G.playlog_path = "user://tool_playlog.jsonl"
	load("res://Main.gd").force_veil = true
	var m = load("res://Main.tscn").instantiate()
	root.add_child(m)
	for i in 4:
		await process_frame
	G.new_game()
	G.go_to("village", "<")
	var lv = null
	for i in 3000:
		await process_frame
		lv = root.get_tree().get_first_node_in_group("level")
		if lv and str(lv.level_id) == "village" and lv.stream_left() == 0 and i > 10:
			break
	check("the village is up", lv != null)
	var pp = m.get_node_or_null("PerfProbe")
	check("Main carries the probe", pp != null)
	if pp == null or lv == null:
		print("PERF PROBE CHECK %d passed, %d failed" % [_pass, _fail])
		quit(1)
		return
	check("the probe keeps running while the world is held for a menu", pp.process_mode == Node.PROCESS_MODE_ALWAYS)
	var stat: String = pp.stats(root.get_viewport())
	check("a perf line has the draw times and counts", stat.contains("gpu=") and stat.contains("cpu=") and stat.contains("draws="), stat)
	lv.batch_trees_now()
	lv.batch_props_now()
	for i in 3:
		await process_frame
	var before := _snap(lv)
	pp.force = true
	pp.probe()
	var waited := 0
	while pp.running and waited < 2000:
		await process_frame
		waited += 1
	check("the probe finishes", not pp.running, waited)
	var labels: Array = pp.results.map(func(r): return str(r[0]))
	check("it tried every suspect (%d)" % labels.size(), labels.size() >= 16, labels)
	for want in ["sun shadows", "the sky shader", "half resolution (3D)", "lamps", "trees", "ground tufts", "still props", "the whole place", "all 3D", "the HUD"]:
		check("...including " + want, labels.has(want), labels)
	for i in 3:
		await process_frame
	var after := _snap(lv)
	var diffs := []
	for k in before:
		if after.has(k) and after[k] != before[k]:
			diffs.append([k, before[k], after[k]])
	check("everything is back as it was (%d differences)" % diffs.size(), diffs.is_empty(), diffs.slice(0, 5))
	check("the answer is written to perf_probe.txt", FileAccess.file_exists("user://perf_probe.txt") and FileAccess.get_file_as_string("user://perf_probe.txt").contains("biggest savings"))
	var cr := FileAccess.get_file_as_string("user://crumbs.txt")
	check("it waits for the frame time to settle before switching things off, and says so", FileAccess.get_file_as_string("user://perf_probe.txt").contains("settling (frame ms):"))
	check("...and to crumbs.txt", cr.contains("probe start") and cr.contains("probe biggest savings"))
	check("once a run", load("res://scripts/core/PerfProbe.gd").probed)
	print("PERF PROBE CHECK %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

extends SceneTree
## Round 192: picture size follows the GPU (AutoRes.gd), and 100% (the old default) moves to auto once.
var passed := 0
var failed := 0
func check(n: String, ok: bool, d = "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("  FAIL  " + n + "  [" + str(d) + "]")


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	await process_frame
	var Gf = load("res://scripts/core/Gfx.gd")
	# --- the one-time move to auto
	var tmp := "user://auto_res_check_settings.json"
	check("auto is the default picture size", str(Gf.settings.get("scale", "")) == "auto" or str(Gf.settings.get("res_v", "")) == "2")
	Gf.settings["scale"] = "auto"
	check("auto is in the list of sizes", Gf.SCALES.has("auto"))
	# --- the controller
	var AR = load("res://scripts/core/AutoRes.gd")
	var ar = AR.new()
	root.add_child(ar)
	await process_frame
	Engine.max_fps = 60
	check("its budget at 60 fps is ~16.7 ms", absf(ar.budget_ms() - 16.67) < 0.1, ar.budget_ms())
	ar.scale = 1.0
	root.get_viewport().scaling_3d_scale = 1.0
	ar.test_gpu_ms = 500.0                       # Robert's card, sharing itself with a local AI
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 6500:
		await process_frame
	check("a GPU that can't keep up: the picture gets smaller", ar.scale < 1.0 and ar.changes > 0, ar.scale)
	check("...but never below 60%", ar.scale >= 0.6 - 0.001, ar.scale)
	check("...and the viewport really draws at that size", absf(root.get_viewport().scaling_3d_scale - ar.scale) < 0.001, root.get_viewport().scaling_3d_scale)
	var low: float = ar.scale
	ar.test_gpu_ms = 16.0                        # right at the budget: hold still
	var c0: int = ar.changes
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000:
		await process_frame
	check("at the budget it holds still (no see-saw)", ar.changes == c0 and absf(ar.scale - low) < 0.001, ar.scale)
	ar.test_gpu_ms = 4.0                         # plenty of room
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 9000:
		await process_frame
	check("room again: it climbs back up", ar.scale > low + 0.001, "%s -> %s" % [low, ar.scale])
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 60000 and ar.scale < 0.999:
		await process_frame
	check("...to full size, not past it", absf(ar.scale - 1.0) < 0.001, ar.scale)
	# a size the player picked is left alone
	Gf.settings["scale"] = "0.75"
	var c1: int = ar.changes
	ar.test_gpu_ms = 500.0
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 3500:
		await process_frame
	check("a size the player chose is never moved", ar.changes == c1)
	Gf.settings["scale"] = "auto"
	Engine.max_fps = 0
	print("AUTO RES CHECK %d passed, %d failed" % [passed, failed])
	quit(0)

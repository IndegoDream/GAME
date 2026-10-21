extends SceneTree
var ok := 0
var bad := 0
func t(c: bool, n: String) -> void:
	if c: ok += 1
	else:
		bad += 1
		print("FAIL ", n)
func _initialize() -> void:
	await process_frame
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/warm_list.json"))
	t(d is Array and d.size() > 100, "list has the models")
	var missing := 0
	for p in d:
		if not ResourceLoader.exists(str(p)):
			missing += 1
	t(missing == 0, "every listed model exists (%d missing)" % missing)
	# every kenney model a script names is on the list
	var names := {}
	for p in d:
		names[str(p)] = true
	var rx := RegEx.new()
	rx.compile("\"([a-z0-9_-]+/[a-zA-Z0-9_.-]+\\.glb)\"")
	var unlisted := []
	for f in ["res://scripts/world/Level.gd", "res://scripts/world/SetPieces.gd", "res://scripts/world/TechDress.gd", "res://scripts/world/ReachDress.gd"]:
		for m in rx.search_all(FileAccess.get_file_as_string(f)):
			var full: String = "res://assets/kenney/" + m.get_string(1)
			if ResourceLoader.exists(full) and not names.has(full) and not unlisted.has(full):
				unlisted.append(full)
	t(unlisted.is_empty(), "no level model missing from the list: %s" % str(unlisted.slice(0, 5)))
	# the warmer drains
	var W = load("res://scripts/core/Warm.gd").new()
	W.start()
	var n := 0
	while W.pending() > 0 and n < 6000:
		W.tick()
		await process_frame
		n += 1
	t(W.pending() == 0, "warmer drains (%d frames, %d/%d)" % [n, W.done, W.total])
	print("warm_check: %d passed, %d failed" % [ok, bad])
	quit(1 if bad > 0 else 0)

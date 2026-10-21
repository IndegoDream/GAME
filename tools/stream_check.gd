extends SceneTree
## round 158: dressing a level nearest-first (Level.stream_on) must end up exactly as the all-at-once build
var ok := 0
var bad := 0
func t(c: bool, n: String) -> void:
	if c: ok += 1
	else:
		bad += 1
		print("FAIL ", n)
func _build(id: String, stream: bool):
	var G = root.get_node("Game")
	var L = load("res://scripts/world/Level.gd")
	L.stream_on = stream
	var lv = L.new()
	lv.build(G.load_level_def(id))
	root.add_child(lv)
	return lv
func _initialize() -> void:
	await process_frame
	for id in ["village", "floor1", "floor21"]:
		var a = _build(id, false)
		var na: int = a.find_children("*", "", true, false).size()
		var ca: Dictionary = a.counts.duplicate()
		a.free()
		var b = _build(id, true)
		var nb0: int = b.find_children("*", "", true, false).size()
		var left: int = b.stream_left()
		t(left > 0, id + ": something is queued")
		t(nb0 < na, id + ": fewer nodes before the queue drains (%d < %d)" % [nb0, na])
		t(b.counts == ca, id + ": same counts")
		var frames := 0
		while b.stream_left() > 0 and frames < 3000:
			await process_frame
			frames += 1
		var nb: int = b.find_children("*", "", true, false).size()
		t(b.stream_left() == 0, id + ": drains by itself (%d frames)" % frames)
		t(absf(float(nb - na)) <= 0.02 * float(na), id + ": same node count after, within chance variation (%d vs %d)" % [nb, na])
		b.free()
		var c = _build(id, true)
		c.finish_stream()
		t(absf(float(c.find_children("*", "", true, false).size() - na)) <= 0.02 * float(na), id + ": finish_stream completes it")
		c.free()
	load("res://scripts/world/Level.gd").stream_on = false
	print("stream_check: %d passed, %d failed" % [ok, bad])
	quit(1 if bad > 0 else 0)

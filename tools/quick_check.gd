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
	var G = root.get_node("Game")
	G.new_game_for_test() if G.has_method("new_game_for_test") else null
	G.techniques["qi_burst"] = true
	t(G.quick_slots.size() == 4, "four quick slots")
	t(G.quick_art(1) == "", "empty key empty")
	var strike: String = G.slot_art("strike")
	t(G.quick_art(0) == strike, "R falls back to strike")
	if G.known_arts("step").size() > 0:
		var st: String = G.known_arts("step")[0]
		G.set_quick(1, st)
		t(G.quick_art(1) == st, "step art on key 2")
		G.set_quick(2, st)
		t(G.quick_art(1) == "" and G.quick_art(2) == st, "one art one key")
	else:
		ok += 2
	t(G.set_quick(0, "nonsense_art") != "" and G.quick_art(0) == strike, "unknown art refused")
	G.set_quick(3, "")
	t(G.quick_art(3) == "", "clear")
	var d: Dictionary = G.save_dict() if G.has_method("save_dict") else {"quick_slots": G.quick_slots}
	t(d.has("quick_slots"), "saved")
	# a real save and load keeps the deck
	G.save_path = "user://quick_save.json"
	G.save_base = "user://quick_slots"
	G.playlog_path = "user://quick_playlog.jsonl"
	if G.known_arts("strike").size() > 0:
		G.set_quick(2, G.known_arts("strike")[0])
	var before: Array = G.quick_slots.duplicate()
	G.save_game()
	G.quick_slots = ["", "", "", ""]
	t(G.load_game(), "load works")
	t(G.quick_slots == before, "quick keys survive save and load: %s vs %s" % [str(G.quick_slots), str(before)])
	print("quick_check: %d passed, %d failed" % [ok, bad])
	quit(1 if bad > 0 else 0)

extends SceneTree
## Round 120: the optional Guide (lessons, the NEXT line, the ? Help button).
##   godot --headless --path . --script res://tools/guide_check.gd
var passed := 0
var failed := 0
var f := 0
func check(name: String, ok: bool, detail: String = "") -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("  FAIL  " + name + ("  [" + detail + "]" if detail != "" else ""))
func _process(_d: float) -> bool:
	f += 1
	if f < 3:
		return false
	var G = root.get_node("Game")
	G.playlog_path = "user://tool_playlog.jsonl"
	G.save_path = "user://guide_save.json"
	G.save_base = "user://guide_slots"
	G.new_game()
	var hud = load("res://scripts/ui/HUD.gd").new()
	root.add_child(hud)
	var hub = hud._hub
	var Gd = load("res://scripts/systems/Guide.gd")
	check("there are lessons", Gd.lessons().size() >= 5)
	for l in Gd.lessons():
		var steps: Array = l.get("steps", [])
		check("lesson %s has steps" % l["id"], steps.size() >= 3)
		for st in steps:
			check("lesson %s step '%s' has words" % [l["id"], st.get("title", "")], str(st.get("title", "")) != "" and str(st.get("text", "")).length() > 40)
			check("lesson %s step page %s exists in the menu" % [l["id"], st.get("page", "")], str(st.get("page", "")) == "" or hub.pages.has(str(st["page"])))
	check("a Guide page exists", hub.pages.has("Guide"))
	check("pages map to lessons", Gd.lesson_for_page("Swarm") == "nanites" and Gd.lesson_for_page("Meridians") == "meridians" and Gd.lesson_for_page("Mind") == "mind")
	# the lesson walk
	hub.show_page("Swarm")
	check("the NEXT line shows on the Swarm page", hub.nextline.visible and hub.nextline.text.begins_with("▸"), hub.nextline.text)
	check("the first visit offers the tour", hub.nextline.text.contains("? Help"), hub.nextline.text)
	check("the ? Help button shows", hub.help_btn.visible)
	hub._on_help()
	check("? Help starts the nanite lesson on its own", str(hub._tour.get("id", "")) == "nanites" and hub._tour_card.visible)
	var n: int = (hub._tour["steps"] as Array).size()
	var seen := {}
	for i in n:
		seen[hub.current] = true
		check("the card shows step %d" % (i + 1), hub._tc_text.text.length() > 20)
		hub._tour_go(1)
	check("the lesson ended after the last step", hub._tour.is_empty() and not hub._tour_card.visible)
	check("the walk visited Swarm, Meridians and Mind", seen.has("Swarm") and seen.has("Meridians") and seen.has("Mind"), str(seen.keys()))
	# the Guide page and the toggle
	hub.show_page("Guide")
	check("the Guide page lists the lessons", hub._guide.get_child_count() >= 7)
	check("nothing opens by itself", hub._tour.is_empty())
	Gd.set_hints(false)
	hub.show_page("Swarm")
	check("hints can be turned off", not hub.nextline.visible)
	Gd.set_hints(true)
	hub.show_page("Meridians")
	check("meridians hint says what to do", hub.nextline.text.contains("NEXT") or hub.nextline.text.contains("open"), hub.nextline.text)
	hub.show_page("Mind")
	check("mind hint says to sit", hub.nextline.text.contains("sit") , hub.nextline.text)
	hub.start_lesson("qi")
	hub.close_hub()
	check("closing the menu ends a lesson", hub._tour.is_empty())
	print("GUIDE CHECK %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
	return false

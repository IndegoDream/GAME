extends SceneTree
## Round 119: the menu's tabs. godot --headless --path . --script tools/menu_tabs_check.gd
func _initialize() -> void:
	await process_frame
	var PT = load("res://scripts/ui/PageTabs.gd")
	var box := VBoxContainer.new()
	root.add_child(box)
	var mk := func(text: String, size: int):
		var l := Label.new()
		l.text = text
		l.add_theme_font_size_override("font_size", size)
		box.add_child(l)
		return l
	mk.call("intro line", 13)
	var h1 = mk.call("Companions", 20)
	var a1 = mk.call("body one", 14)
	var h2 = mk.call("Contract beasts", 20)
	var a2 = mk.call("body two", 14)
	var h3 = mk.call("The taming tree -- Taming 3 (Novice)", 16)
	var a3 = mk.call("body three", 14)
	PT.apply(box, "t")
	var bar = box.get_node("PageTabs")
	var checks := [
		["a tab row was added first", box.get_child(0) == bar],
		["three tabs", bar.get_child_count() == 3],
		["first tab shown", h1.visible and a1.visible and not h2.visible and not a2.visible and not a3.visible],
		["intro always visible", box.get_child(1).visible],
		["tab names tidy", bar.get_child(2).text == "Taming tree"],
	]
	bar.get_child(1).pressed.emit()
	checks.append(["second tab shown on press", h2.visible and a2.visible and not a1.visible and not a3.visible])
	var box2 := VBoxContainer.new()
	root.add_child(box2)
	var x := Label.new(); x.text = "Only"; x.add_theme_font_size_override("font_size", 20); box2.add_child(x)
	PT.apply(box2, "t2")
	checks.append(["a short page gets no tabs", box2.get_child_count() == 1 and x.visible])
	var ok := 0
	var bad := 0
	for c in checks:
		if c[1]:
			ok += 1
		else:
			bad += 1
			print("MENU TABS FAIL: ", c[0])
	print("MENU TABS CHECK %d passed, %d failed" % [ok, bad])
	quit(1 if bad > 0 else 0)

extends RefCounted
## Round 119 (Robert, 2026-10-13): "Fix the menu screen too it needs to be more
## intuitive and clear some of the pages are crowded with info ... maybe break
## it down more into tabs."
##
## A menu page is one long column of headed sections. apply() turns it into
## tabs: each big heading directly in the page starts a tab, only the chosen
## tab's section is shown, and a row of tab buttons sits at the top. Whatever
## comes before the first heading stays visible on every tab. The chosen tab
## is remembered per page, so a page that refreshes keeps its place. A page
## with fewer than min_tabs headed sections is left exactly as it was.

const BAR := "PageTabs"
static var _sel := {}


static func _title(t: String) -> String:
	var s := t.strip_edges()
	for sep in [" -- ", "  --  ", ":", "  (", " ("]:
		var i := s.find(sep)
		if i > 2:
			s = s.substr(0, i)
	s = s.strip_edges().trim_prefix("The ").trim_prefix("Your ")
	if s.length() > 0:
		s = s[0].to_upper() + s.substr(1)
	if s.length() > 22:
		s = s.substr(0, 21).strip_edges() + "…"
	return s.capitalize() if s == s.to_upper() else s


static func apply(box: Node, key: String, accent: Color = Color(1.0, 0.85, 0.5), min_font: int = 16, min_tabs: int = 3) -> void:
	if box == null:
		return
	for c in box.get_children():
		if c.name == BAR:
			c.queue_free()
	var segs: Array = []
	for c in box.get_children():
		if c.is_queued_for_deletion() or c.name == BAR:
			continue
		if c is Label and c.text.strip_edges() != "" and c.get_theme_font_size("font_size") >= min_font:
			segs.append({"title": _title(c.text), "nodes": [c]})
		elif not segs.is_empty():
			segs.back()["nodes"].append(c)
	if segs.size() < min_tabs:
		return
	if str(segs[0]["title"]).to_lower() == key.to_lower():
		segs[0]["title"] = "Overview"          # (the page's own title heading)
	var seen := {}
	for s in segs:
		var t: String = s["title"]
		var n := 2
		while seen.has(t):
			t = "%s %d" % [s["title"], n]
			n += 1
		s["title"] = t
		seen[t] = true
	var chosen := str(_sel.get(key, ""))
	if not seen.has(chosen):
		chosen = str(segs[0]["title"])
	var bar := HFlowContainer.new()
	bar.name = BAR
	bar.add_theme_constant_override("h_separation", 6)
	bar.add_theme_constant_override("v_separation", 4)
	box.add_child(bar)
	box.move_child(bar, 0)
	var grp := ButtonGroup.new()
	var show_seg := func(title: String) -> void:
		for s2 in segs:
			var vis: bool = (s2["title"] == title)
			for nd in s2["nodes"]:
				if is_instance_valid(nd):
					nd.visible = vis
	for s in segs:
		var b := Button.new()
		b.text = s["title"]
		b.toggle_mode = true
		b.button_group = grp
		b.theme_type_variation = "RailButton"
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_color_override("font_pressed_color", accent)
		b.add_theme_color_override("font_hover_pressed_color", accent)
		b.custom_minimum_size = Vector2(0, 30)
		b.focus_mode = Control.FOCUS_ALL
		var title: String = s["title"]
		b.set_pressed_no_signal(title == chosen)
		b.pressed.connect(func():
			_sel[key] = title
			show_seg.call(title)
			var sc = box.get_parent()
			if sc is ScrollContainer:
				sc.scroll_vertical = 0
			Game.sfx("ui_select", 0.35))
		bar.add_child(b)
	show_seg.call(chosen)

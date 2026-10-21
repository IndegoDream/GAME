extends SceneTree
## Round 142a: accessibility -- settings, the colour filter's maths, text scaling, tap-to-hold, captions.
var fails := 0
var total := 0
var Acc
var Gfx


func check(what: String, ok: bool) -> void:
	total += 1
	if not ok:
		fails += 1
		print("  FAIL: ", what)


func _press(a: String, down: bool) -> void:
	var e := InputEventAction.new()
	e.action = a
	e.pressed = down
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _initialize() -> void:
	await process_frame
	Acc = load("res://scripts/core/Access.gd")
	Gfx = load("res://scripts/core/Gfx.gd")
	Gfx.load_settings()
	var saved := {}
	for k in Acc.ORDER:
		saved[k] = Acc.get_opt(k)
		Acc.set_opt(k, Acc.DEFAULTS[k])
	# ---- settings
	for k in Acc.ORDER:
		check("%s starts at its default" % k, Acc.get_opt(k) == Acc.DEFAULTS[k])
		check("%s has a title, help and a label for every choice" % k, Acc.TITLE.has(k) and Acc.HELP.has(k) and Acc.OPTIONS[k].all(func(o): return Acc.LABEL.has(str(o))))
		check("%s's default is one of its choices" % k, Acc.DEFAULTS[k] in Acc.OPTIONS[k])
	Acc.set_opt("a_text", "9.9")
	check("a value that isn't a choice is ignored", Acc.get_opt("a_text") == "1.0")
	Acc.set_opt("a_nonsense", "on")
	check("an unknown setting is ignored", not Gfx.settings.has("a_nonsense"))
	var seen := {}
	for i in 5:
		seen[Acc.step("a_text", self)] = true
	check("stepping cycles through all four sizes and comes round", seen.size() == 4 and Acc.get_opt("a_text") == "1.15")
	Acc.set_opt("a_text", "1.0")
	check("every setting is also a key Gfx keeps", Acc.ORDER.all(func(k): return Gfx.settings.has(k)))
	check("motion is 1 / 0.5 / 0", (func():
		var r := []
		for m in ["full", "reduced", "none"]:
			Acc.set_opt("a_motion", m)
			r.append(Acc.motion())
		Acc.set_opt("a_motion", "full")
		return r == [1.0, 0.5, 0.0]).call())
	# ---- the colour filter
	for mode in ["deut", "prot", "trit"]:
		var grey_ok := true
		for g in [0.0, 0.25, 0.5, 0.8, 1.0]:
			var o: Color = Acc.cb_apply(Color(g, g, g), mode)
			if absf(o.r - g) > 0.01 or absf(o.g - g) > 0.01 or absf(o.b - g) > 0.01:
				grey_ok = false
		check("%s: greys stay grey" % mode, grey_ok)
		var in_range := true
		for c in [Color.RED, Color.GREEN, Color.BLUE, Color.YELLOW, Color(0.8, 0.3, 0.5)]:
			var o2: Color = Acc.cb_apply(c, mode)
			if o2.r < 0.0 or o2.r > 1.0 or o2.g < 0.0 or o2.g > 1.0 or o2.b < 0.0 or o2.b > 1.0:
				in_range = false
		check("%s: colours stay in range" % mode, in_range)
		check("%s: a colour is changed" % mode, Acc.cb_apply(Color.RED, mode) != Color.RED or Acc.cb_apply(Color.BLUE, mode) != Color.BLUE)
	check("off changes nothing", Acc.cb_apply(Color(0.7, 0.2, 0.4), "off") == Color(0.7, 0.2, 0.4))
	for mode in ["deut", "prot"]:
		# what a red-green-weak viewer sees: the simulation. After the shift, red and green must be further apart than before.
		var p: Dictionary = Acc.cb_params(mode)
		var simf := func(c: Color) -> Vector3:
			var v := Vector3(c.r, c.g, c.b)
			return Vector3((p["s0"] as Vector3).dot(v), (p["s1"] as Vector3).dot(v), (p["s2"] as Vector3).dot(v))
		var before: float = (simf.call(Color(0.8, 0.2, 0.2)) as Vector3).distance_to(simf.call(Color(0.2, 0.7, 0.2)))
		var after: float = (simf.call(Acc.cb_apply(Color(0.8, 0.2, 0.2), mode)) as Vector3).distance_to(simf.call(Acc.cb_apply(Color(0.2, 0.7, 0.2), mode)))
		check("%s: red and green are easier to tell apart after the filter (%.3f -> %.3f)" % [mode, before, after], after > before)
	# the shader itself must compile
	var sh := Shader.new()
	sh.code = Acc.CB_SHADER
	check("the filter shader has code", sh.code.length() > 100)
	# ---- text size
	check("scaled_size rounds and has a floor", Acc.scaled_size(14, 1.3) == 18 and Acc.scaled_size(8, 1.0) == 8 and Acc.scaled_size(6, 1.0) == 8)
	var holder := Control.new()
	root.add_child(holder)
	var lab := Label.new()
	lab.text = "x"
	holder.add_child(lab)
	var btn := Button.new()
	btn.add_theme_font_size_override("font_size", 22)
	holder.add_child(btn)
	var rt := RichTextLabel.new()
	holder.add_child(rt)
	var base_l: int = lab.get_theme_font_size("font_size")
	Acc.scale_tree(holder, 1.5)
	check("a label grows with the size", lab.get_theme_font_size("font_size") == Acc.scaled_size(base_l, 1.5))
	check("a button that set its own size grows from that", btn.get_theme_font_size("font_size") == 33)
	check("rich text grows too", rt.get_theme_font_size("normal_font_size") > 14)
	Acc.scale_tree(holder, 1.15)
	check("changing size scales from the original, not the last size", btn.get_theme_font_size("font_size") == Acc.scaled_size(22, 1.15))
	Acc.scale_tree(holder, 1.0)
	check("back to standard puts every size back", lab.get_theme_font_size("font_size") == base_l and not lab.has_theme_font_size_override("font_size") and btn.get_theme_font_size("font_size") == 22 and btn.has_theme_font_size_override("font_size"))
	holder.queue_free()
	# ---- tap to hold
	Acc.set_opt("a_toggle", "off")
	_press("guard", true)
	await physics_frame
	check("toggle off: held follows the button", Acc.held("guard"))
	_press("guard", false)
	await physics_frame
	check("...and lets go with it", not Acc.held("guard"))
	Acc.set_opt("a_toggle", "on")
	Acc.release("guard")
	_press("guard", true)
	await physics_frame
	check("toggle on: one press raises the guard", Acc.held("guard"))
	check("...asking twice in one frame says the same thing", Acc.held("guard") and Acc.held("guard"))
	_press("guard", false)
	await physics_frame
	await physics_frame
	check("...and it stays up after the button is let go", Acc.held("guard"))
	_press("guard", true)
	await physics_frame
	check("a second press lowers it", not Acc.held("guard"))
	_press("guard", false)
	await physics_frame
	Acc.release("guard")
	Acc.set_opt("a_toggle", "off")
	# ---- captions
	check("direction: ahead / right / left / behind / close", Acc.direction_word(Vector3(0, 0, -10)) == "ahead" and Acc.direction_word(Vector3(10, 0, 0)) == "right" and Acc.direction_word(Vector3(-10, 0, 0)) == "left" and Acc.direction_word(Vector3(0, 0, 10)) == "behind" and Acc.direction_word(Vector3(0.5, 0, 0.5)) == "close")
	check("a caption exists for the sounds that warn you", ["windup", "stamp", "hurt", "bell", "thud", "hit_heavy"].all(func(n): return Acc.caption_text(n) != ""))
	Acc.install(self)
	for i in 3:
		await process_frame
	var box: VBoxContainer = Acc._cap_box
	check("the caption box is in the tree", box != null and box.is_inside_tree())
	Acc.set_opt("a_caps", "off")
	Acc.caption("windup")
	check("captions off: nothing shows", box.get_child_count() == 0)
	Acc.set_opt("a_caps", "on")
	Acc._cap_last.clear()
	Acc.caption("windup")
	check("captions on: a caption shows", box.get_child_count() == 1 and (box.get_child(0) as Label).text.find("winds up") >= 0)
	Acc.caption("windup")
	check("the same sound twice in a moment shows once", box.get_child_count() == 1)
	Acc.caption("nonsense_sound")
	check("a sound with no caption shows nothing", box.get_child_count() == 1)
	for n in ["stamp", "bell", "thud", "hurt", "door"]:
		Acc.caption(n)
	check("never more than four at once", box.get_child_count() <= 4)
	Acc.set_opt("a_caps", "off")
	for k in Acc.ORDER:
		Acc.set_opt(k, saved[k])
	print("ACCESS CHECK %d passed, %d failed" % [total - fails, fails])
	quit(1 if fails > 0 else 0)

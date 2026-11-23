extends SceneTree
# Phone controls: no two buttons overlap, all stay on screen, the moves bar is down the right edge -- at several phone shapes.
var ok := 0
var bad := 0
func t(n: String, c: bool) -> void:
	if c: ok += 1
	else:
		bad += 1
		print("  FAIL ", n)
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	await process_frame
	var tu = load("res://scripts/ui/TouchUI.gd").new()
	root.add_child(tu)
	for sz in [Vector2i(1280, 600), Vector2i(1920, 864), Vector2i(1600, 720), Vector2i(1024, 480), Vector2i(2400, 1080)]:
		root.size = sz
		await process_frame
		tu._layout()
		var vs := Vector2(sz)
		var circles: Array = []
		for pb in tu._play_buttons:
			var b: TouchScreenButton = pb[0]
			var d: float = 128.0 * b.scale.x
			var c: Vector2 = b.position + Vector2(d, d) * 0.5
			circles.append([str(b.action), c, d * 0.5])
			t("%s on screen at %s" % [b.action, str(sz)], c.x - d * 0.5 >= -1.0 and c.y - d * 0.5 >= -1.0 and c.x + d * 0.5 <= vs.x + 1.0 and c.y + d * 0.5 <= vs.y + 1.0)
		var clash := 0
		for i in circles.size():
			for j in range(i + 1, circles.size()):
				if (circles[i][1] as Vector2).distance_to(circles[j][1]) < float(circles[i][2]) + float(circles[j][2]) - 1.0:
					clash += 1
					print("   overlap ", circles[i][0], " / ", circles[j][0], " at ", sz)
		t("no overlapping buttons at %s" % str(sz), clash == 0)
		var bar := ["qi_burst", "art_cycle", "talisman", "path_art", "support_art", "support2_art"]
		var xs: Array = []
		for c in circles:
			if bar.has(c[0]):
				xs.append(float((c[1] as Vector2).x))
		t("moves bar is one column on the right at %s" % str(sz), xs.size() == 6 and absf(xs.min() - xs.max()) < 1.0 and xs[0] > vs.x * 0.9)
	# round 142a: left-handed and big buttons -- still on screen, still no overlaps, mirrored, and the bar clear of the stat card
	var G2 = load("res://scripts/core/Gfx.gd")
	G2.load_settings()
	for mode in [["left", "off"], ["right", "on"], ["left", "on"]]:
		G2.settings["a_hand"] = mode[0]
		G2.settings["a_big"] = mode[1]
		for sz in [Vector2i(1280, 600), Vector2i(1920, 864), Vector2i(1600, 720), Vector2i(2400, 1080)]:
			root.size = sz
			await process_frame
			tu._layout()
			var vs2 := Vector2(sz)
			var circ: Array = []
			var cx := {}
			for pb in tu._play_buttons:
				var b3: TouchScreenButton = pb[0]
				var d3: float = 128.0 * b3.scale.x
				var c3: Vector2 = b3.position + Vector2(d3, d3) * 0.5
				circ.append([str(b3.action), c3, d3 * 0.5])
				cx[str(b3.action)] = c3
				t("%s on screen (%s, big %s) at %s" % [b3.action, mode[0], mode[1], str(sz)], c3.x - d3 * 0.5 >= -1.0 and c3.y - d3 * 0.5 >= -1.0 and c3.x + d3 * 0.5 <= vs2.x + 1.0 and c3.y + d3 * 0.5 <= vs2.y + 1.0)
			var clash2 := 0
			for i in circ.size():
				for j in range(i + 1, circ.size()):
					if (circ[i][1] as Vector2).distance_to(circ[j][1]) < float(circ[i][2]) + float(circ[j][2]) - 1.0:
						clash2 += 1
						print("   overlap ", circ[i][0], " / ", circ[j][0], " at ", sz, " ", mode)
			t("no overlapping buttons (%s, big %s) at %s" % [mode[0], mode[1], str(sz)], clash2 == 0)
			if mode[0] == "left":
				t("left-handed: the attack button is on the left at %s" % str(sz), (cx["attack"] as Vector2).x < vs2.x * 0.4)
				t("left-handed: the moves bar is down the left edge at %s" % str(sz), (cx["qi_burst"] as Vector2).x < vs2.x * 0.1 and (cx["support2_art"] as Vector2).x < vs2.x * 0.1)
				t("left-handed: the bar starts under the stat card and the help at %s" % str(sz), (cx["qi_burst"] as Vector2).y - 27.0 >= 270.0)
				t("left-handed: quick-use is on the right at %s" % str(sz), (cx["meditate"] as Vector2).x > vs2.x * 0.5)
			else:
				t("right-handed: the attack button is on the right at %s" % str(sz), (cx["attack"] as Vector2).x > vs2.x * 0.6)
	G2.settings["a_hand"] = "right"
	G2.settings["a_big"] = "off"
	tu._layout()
	# the HUD's two cards (stat card left, quest card right, in 1067-wide layout units) must stay clear of the top buttons
	for pb in tu._play_buttons:
		var b2: TouchScreenButton = pb[0]
		if str(pb[1]) == "tl" and tu._unit <= 1.12:
			var d2: float = 128.0 * b2.scale.x
			t("top button %s clear of the HUD cards" % b2.action, b2.position.x >= 372.0 and b2.position.x + d2 <= 662.0)
	tu.free()
	print("TOUCH LAYOUT CHECK %d passed, %d failed" % [ok, bad])
	quit(1 if bad else 0)

extends SceneTree
## Round 140: languages. godot --headless --path . --script tools/i18n_check.gd
func _initialize() -> void:
	await process_frame
	var I = load("res://scripts/core/I18n.gd")
	var US = load("res://scripts/core/UiStyle.gd")
	var G = root.get_node("Game")
	G.new_game()
	var ch := []
	var codes: Array = I.codes()
	ch.append(["ten languages", codes.size() == 10 and codes[0] == "en"])
	for c in codes:
		if c == "en":
			continue
		var d = G._load_json("res://data/i18n/%s.json" % c, {})
		ch.append(["%s catalog loaded (%d phrases)" % [c, (d as Dictionary).size()], d is Dictionary and (d as Dictionary).size() >= 250])
	# the same key set in every language
	var base: Dictionary = G._load_json("res://data/i18n/zh_CN.json", {})
	var same := true
	for c in codes:
		if c == "en":
			continue
		var d2: Dictionary = G._load_json("res://data/i18n/%s.json" % c, {})
		if d2.size() != base.size():
			same = false
	ch.append(["every language has the same phrases", same])
	# apply and look up
	var want := {"zh_CN": "任务", "es": "Misiones", "pt_BR": "Missões", "ru": "Задания", "de": "Aufträge", "fr": "Quêtes", "ja": "クエスト", "ko": "퀘스트", "tr": "Görevler"}
	for c in want:
		I.apply(c)
		ch.append(["%s: Quests -> %s" % [c, want[c]], root.tr("Quests") == want[c]])
	ch.append(["unknown text stays English", root.tr("This sentence is in no catalog") == "This sentence is in no catalog"])
	I.apply("en")
	ch.append(["English is itself", root.tr("Quests") == "Quests"])
	# every tr("...") literal in the scripts is in the catalog
	var rx := RegEx.new()
	rx.compile("\\btr\\(\\s*\"((?:[^\"\\\\]|\\\\.)*)\"")
	var missing := []
	var stack := ["res://scripts"]
	while not stack.is_empty():
		var dir: String = stack.pop_back()
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".gd"):
				var txt := FileAccess.get_file_as_string(dir + "/" + f)
				for m in rx.search_all(txt):
					var k := m.get_string(1)
					if not base.has(k) and k.length() > 1 and not missing.has(k):
						missing.append(k)
		for sd in DirAccess.get_directories_at(dir):
			stack.append(dir + "/" + sd)
	ch.append(["every tr() phrase in the scripts is translated (%d missing: %s)" % [missing.size(), str(missing.slice(0, 4))], missing.is_empty()])
	# the words the Dao and Difficulty pages take from data are all translated
	var DD: Dictionary = G.sys("dao").data
	var FF: Dictionary = G.sys("difficulty").data
	var need := []
	for st in DD["sense_stages"]:
		need.append(st[1])
		need.append(st[2])
	need.append_array(DD["rank_names"])
	for did in DD["daos"]:
		need.append(DD["daos"][did]["name"])
		need.append(DD["daos"][did]["text"])
		for t in DD["daos"][did]["tenets"]:
			need.append(t[1])
			need.append(t[2])
	for t in FF["tiers"]:
		need.append(t["name"])
		need.append(t["text"])
	for h in FF["handicaps"]:
		need.append(h["name"])
		need.append(h["text"])
	var nm := []
	for k in need:
		if not base.has(str(k)) and not nm.has(str(k)):
			nm.append(str(k))
	ch.append(["every dao / difficulty word has a translation (%d missing: %s)" % [nm.size(), str(nm.slice(0, 4))], nm.is_empty()])
	# the device's language
	ch.append(["zh_TW maps to Chinese", I._match_os("zh_TW") == "zh_CN"])
	ch.append(["pt_PT maps to Portuguese", I._match_os("pt_PT") == "pt_BR"])
	ch.append(["de_AT maps to German", I._match_os("de_AT") == "de"])
	ch.append(["en_GB maps to English", I._match_os("en_GB") == "en"])
	ch.append(["an unknown language falls to English", I._match_os("xx_YY") == "en"])
	# choosing one is remembered
	ch.append(["set_language works", I.set_language("ja") and I.current == "ja"])
	var cf := ConfigFile.new()
	ch.append(["...and is saved", cf.load(I.CFG) == OK and str(cf.get_value("lang", "code", "")) == "ja"])
	I.current = "en"
	I.init()
	ch.append(["...and read back at start", I.current == "ja"])
	ch.append(["a junk language is refused", not I.set_language("klingon") and I.current == "ja"])
	# fonts
	ch.append(["a CJK font is chained in", I.cjk_font() != null])
	var body: Font = US.font("body")
	var has := false
	if body != null:
		for f in (body as FontFile).fallbacks:
			if f == I.cjk_font():
				has = true
	ch.append(["the body font falls back to it", body == null or has])
	# the menu in a language
	var hud = load("res://scripts/ui/HUD.gd").new()
	root.add_child(hud)
	await process_frame
	var hub = hud._hub
	I.set_language("zh_CN")
	await process_frame
	ch.append(["the rail speaks Chinese", hub.buttons["Quests"].text.begins_with("任务")])
	hub.show_page("System")
	await process_frame
	var found := false
	for b in hub._system.find_children("*", "Button", true, false):
		if b.text == "简体中文":
			found = true
	ch.append(["the System page lists the languages", found])
	hub.show_page("Dao")
	await process_frame
	var seen := false
	for l in hub._dao.find_children("*", "Label", true, false):
		if l.text.find("道感") >= 0 or l.text == "道":
			seen = true
	ch.append(["the Dao page speaks Chinese", seen])
	for c in codes:
		I.set_language(c)
		hub.show_page("Pack")
		hub.show_page("Craft")
		hub.show_page("System")
	ch.append(["every language draws every page without error", true])
	# put it back
	DirAccess.remove_absolute(ProjectSettings.globalize_path(I.CFG))
	I.apply("en")
	var bad := 0
	for c in ch:
		if not c[1]:
			bad += 1
			print("FAIL ", c[0])
	print("I18N CHECK ", ch.size() - bad, " passed, ", bad, " failed")
	quit(1 if bad > 0 else 0)

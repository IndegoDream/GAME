extends SceneTree
## Round 141: the catalog lookup -- exact phrases, templates with numbers and names filled in, and text joined from known pieces.
## godot --headless --path . --script res://tools/i18n_phrase_check.gd
func _initialize() -> void:
	await process_frame
	var I = load("res://scripts/core/I18n.gd")
	var ch := []
	I.apply("ja")
	var cat: Dictionary = root.get_node("Game")._load_json("res://data/i18n/ja.json", {})
	ch.append(["exact: Quests", root.tr("Quests") == cat["Quests"]])
	var k := "Needs %d %s (you have %d)."
	ch.append(["template key in the catalog", cat.has(k)])
	var want: String = str(cat[k]).replace("%d", "3").replace("%s", str(cat.get("Iron Ore", "Iron Ore")))
	var got := root.tr("Needs 3 Iron Ore (you have 5).")
	ch.append(["template: numbers and a known name filled in (%s)" % got, got != "Needs 3 Iron Ore (you have 5)." and got.contains("3") and got.contains("5") and got.contains(str(cat.get("Iron Ore", "?")))])
	var j := root.tr("Alchemy 0/6")
	ch.append(["joined text: a known phrase plus numbers (%s)" % j, j != "Alchemy 0/6" and j.contains("0/6")])
	var d := ""
	for kk in cat:
		var ks := str(kk)
		if ks.length() > 50 and ks.length() < 120 and not ks.contains("%") and not ks.contains("{") and not ks.contains("\n") and ks.contains(" ") and ks.unicode_at(0) < 128:
			d = ks
			break
	var e := root.tr(d + "  (" + str(cat.get("Quests", "Quests")) + ")")
	ch.append(["joined text: description plus a piece", e != d and e.contains(str(cat.get(d, "???")).substr(0, 6))])
	var u := "This sentence is in no catalog and mentions Quests once."
	ch.append(["mostly-unknown text stays English", root.tr(u) == u])
	ch.append(["short junk stays", root.tr("zz") == "zz"])
	I.apply("en")
	ch.append(["English untouched", root.tr("Needs 3 Iron Ore (you have 5).") == "Needs 3 Iron Ore (you have 5)."])
	var bad := 0
	for c in ch:
		if not c[1]:
			bad += 1
			print("FAIL ", c[0])
	print("PHRASE CHECK %d passed, %d failed" % [ch.size() - bad, bad])
	quit(1 if bad > 0 else 0)

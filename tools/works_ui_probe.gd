extends SceneTree
## Round 177: the Works page, the Party page (aptitude bars, splicer, tattoos, eggs) and unlimited stores, in the real HUD.
## godot --path . --script res://tools/works_ui_probe.gd   (xvfb)
var G
var m
var bad := 0
func fail(s: String) -> void:
	bad += 1
	print("WORKS FAIL ", s)
func texts(node: Node) -> String:
	var out := ""
	for l in node.find_children("*", "Label", true, false):
		out += (l as Label).text + "\n"
	for b in node.find_children("*", "Button", true, false):
		out += "[" + (b as Button).text + "]\n"
	return out
func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	await process_frame
	G = root.get_node("Game")
	G.save_path = "user://wprobe_save.json"; G.save_base = "user://wprobe_slots"; G.playlog_path = "user://wprobe_playlog.jsonl"
	var ff := "user://wprobe_flavor.json"
	var fw := FileAccess.open(ff, FileAccess.WRITE); fw.store_string(JSON.stringify({"clean": true, "assist": true})); fw.close()
	load("res://scripts/systems/Tester.gd").flavor_path = ff
	load("res://scripts/core/I18n.gd").set_language("en")
	G.new_game()
	G.current_level = "village"
	var hud = load("res://scripts/ui/HUD.gd").new()
	root.add_child(hud)
	for i in 20: await process_frame
	# unlimited stores
	if not G.unlimited_stores(): fail("stores are not unlimited in the assist build")
	G.add_item("iron_ore", 500)
	if G.count("iron_ore") != 500: fail("pouch took only %d of 500 iron ore" % G.count("iron_ore"))
	# state to show
	G.skills["taming"] = 10.0 * 12 * 12 + 1.0
	G.skills["runecraft"] = 9999.0
	G.realm = 10
	G.integration = 100000.0
	G.home["have"] = true
	G.gold = 5000
	G.sys("research").researched["animation"] = true
	G.bond_familiar("cave_hare"); G.bond_familiar("tunnel_boar")
	for c in G.contracts: c["bond"] = 90.0
	G.contracts.append({"species": "golem_clay", "name": "Lump", "bond": 0.0, "tier": 0, "out": false, "construct": true})
	G.current_level = "village"; G.havens["village"] = "the village"
	G.add_item("edge_rune", 3)
	G.sys("eggs").lay("floor", true)
	G.sys("genome").take_sample(G.contracts[0], "nose")
	G.sys("foundry").bin["clay_frame"] = 1
	G.add_item("nanite_shard", 6)
	if G.sys("farm").build_vat() != "": fail("vat did not build")
	G.sys("farm").event = {"id": "rut"}
	var H = hud._hub
	H.visible = true
	H.show_page("Party")
	for i in 4: await process_frame
	H._gs_open = true; H._tt_open = true
	H._fill("Party")
	for i in 3: await process_frame
	DirAccess.make_dir_recursive_absolute("/tmp/shots")
	root.get_texture().get_image().save_png("/tmp/shots/party.png")
	var t: String = texts(H.pages["Party"])
	for want in ["Best at", "Fighting", "Gene Splicer", "1. Take a sample", "Tattoo Parlour", "Eggs", "Feed essence", "Constructs"]:
		if not t.contains(want): fail("Party page lacks '%s'" % want)
	# press real buttons: take a sample, warm the egg, hatch (test kit not on, so just warm)
	for b in H.pages["Party"].find_children("*", "Button", true, false):
		if (b as Button).text == "Warm" and not (b as Button).disabled:
			(b as Button).pressed.emit()
			break
	for i in 3: await process_frame
	if G.sys("eggs").warming() != 1: fail("Warm button did not warm the egg")
	H.show_page("Works")
	for i in 4: await process_frame
	H._fill("Works")
	for i in 3: await process_frame
	DirAccess.make_dir_recursive_absolute("/tmp/shots")
	root.get_texture().get_image().save_png("/tmp/shots/works.png")
	var w: String = texts(H.pages["Works"])
	for want in ["Foundry", "Lump", "The power frame", "The skiff", "Make parts", "Nanite Farm", "Self-replication skills", "Tailor", "Colony", "A rut"]:
		if not w.contains(want): fail("Works page lacks '%s'" % want)
	var fit_ok := false
	for b in H.pages["Works"].find_children("*", "Button", true, false):
		if str((b as Button).text).begins_with("Fit Clay Frame") and not (b as Button).disabled:
			(b as Button).pressed.emit(); fit_ok = true; break
	for i in 3: await process_frame
	if not fit_ok or not G.sys("foundry").target_parts("golem:Lump").has("frame"): fail("Fit button did not fit the frame")
	for b in H.pages["Works"].find_children("*", "Button", true, false):
		if str((b as Button).text).begins_with("Prune the dominant"):
			(b as Button).pressed.emit(); break
	for i in 3: await process_frame
	if not G.sys("farm").event.is_empty(): fail("farm choice button did not resolve the event")
	# round 179: the crew -- press a job button
	H.show_page("Works")
	for i in 3: await process_frame
	var job_ok := false
	for b in H.pages["Works"].find_children("*", "Button", true, false):
		if str((b as Button).text).begins_with("Go out and gather") and not (b as Button).disabled:
			(b as Button).pressed.emit(); job_ok = true; break
	for i in 3: await process_frame
	if not job_ok or G.sys("crew").working() < 1: fail("crew job button did not set a job")
	# every page opens without errors
	for sec in H.ORDER:
		H.show_page(sec)
		for i in 2: await process_frame
	print("works_ui_probe: %s" % ("OK" if bad == 0 else "%d problems" % bad))
	quit(1 if bad > 0 else 0)

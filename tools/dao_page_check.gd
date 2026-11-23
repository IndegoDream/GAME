extends SceneTree
## Round 139: the Dao page and the difficulty section, drawn in the real menu.
func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.new_game()
	var hud = load("res://scripts/ui/HUD.gd").new()
	root.add_child(hud)
	await process_frame
	var hub = hud._hub
	var D = G.sys("dao")
	var ch := []
	ch.append(["Dao is a page", hub.pages.has("Dao") and hub.buttons.has("Dao")])
	hub.show_page("Dao")
	await process_frame
	ch.append(["draws when dull", hub._dao.get_child_count() > 5])
	D.sense = 300.0
	D.pts["blade"] = 200.0
	D.focus = "blade"
	G.current_level = "floor_2"
	hub.show_page("Dao")
	await process_frame
	var btns = hub._dao.find_children("*", "Button", true, false)
	var cont = null
	var follow = null
	for b in btns:
		if b.text.begins_with("Contemplate"):
			cont = b
		if b.text == "Follow this way" and follow == null:
			follow = b
	ch.append(["contemplate button and follow buttons exist", cont != null and follow != null])
	cont.pressed.emit()
	await process_frame
	ch.append(["pressing contemplate worked", D.cont["day"] == G.today() and int(D.cont["n"]) == 1])
	D.pts["blade"] = 1500.0
	D.sense = 1200.0
	hub.show_page("Dao")
	await process_frame
	var tenets := []
	for b in hub._dao.find_children("*", "Button", true, false):
		if b.text.find(" -- ") > 0:
			tenets.append(b)
	ch.append(["three tenet buttons when ready", tenets.size() == 3])
	var le = hub._dao.find_children("*", "LineEdit", true, false)
	le[0].text = "Test Way"
	tenets[0].pressed.emit()
	await process_frame
	ch.append(["founding from the page works", D.is_founded("blade") and D.founded["name"] == "Test Way"])
	# difficulty
	G.current_level = "village"
	hub.show_page("System")
	await process_frame
	var hard = null
	for b in hub._system.find_children("*", "Button", true, false):
		if b.text == "Hard":
			hard = b
	ch.append(["difficulty buttons in System", hard != null])
	hard.pressed.emit()
	await process_frame
	ch.append(["pressing Hard sets it", G.sys("difficulty").tier == "hard"])
	var bad := 0
	for c in ch:
		if not c[1]:
			bad += 1
			print("FAIL ", c[0])
	print("DAO PAGE CHECK ", ch.size() - bad, " passed, ", bad, " failed")
	quit(1 if bad > 0 else 0)

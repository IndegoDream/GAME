extends SceneTree
## Round 188: the Guild page (menu > Guild, F6) and the chat box work through the real menus.
##   godot --headless --path . --script res://tools/guild_ui_check.gd
## (SHOTS=1 with a display: pictures of each tab in /tmp/guild_<tab>.png)
var _pass := 0
var _fail := 0


func check(what: String, ok: bool, detail = "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL  ", what, "  [", str(detail), "]")


func _buttons(n: Node, text: String) -> Array:
	return n.find_children("*", "Button", true, false).filter(func(b): return (b as Button).text == text and (b as Button).is_visible_in_tree())


func _shot(nm: String) -> void:
	if OS.get_environment("SHOTS") == "":
		return
	for i in 3:
		await process_frame
	root.get_viewport().get_texture().get_image().save_png("/tmp/guild_%s.png" % nm)


func _initialize() -> void:
	await process_frame
	var G = root.get_node("Game")
	G.save_base = "user://tool_shot"      # (never the real account: the test kit would switch itself on there)
	G.save_path = "user://guild_ui_check.json"
	G.playlog_path = "user://tool_playlog.jsonl"
	load("res://Main.gd").force_veil = true
	var m = load("res://Main.tscn").instantiate()
	root.add_child(m)
	for i in 6:
		await process_frame
	G.new_game()
	G.char_name = "Rob"
	for id in ["spirit_herb", "iron_ore", "bone_shard"]:
		G.note_item(id)
	G.gold = 50000
	var hud = root.get_tree().get_first_node_in_group("hud")
	for i in 30:
		await process_frame
	if hud != null and hud._title != null and hud._title.visible:
		hud.close_title()
	await process_frame
	for nm in ["_title", "_create", "_ending"]:
		if hud != null and hud.get(nm) != null:
			hud.get(nm).visible = false
	if hud != null and hud._dialog.visible:
		hud.close_dialog()
	check("the HUD is up", hud != null)
	check("the Guild page is in the menu", hud._hub.pages.has("Guild") and hud._hub.guild_page != null)
	check("F6 is the Guild key", InputMap.has_action("guild") and InputMap.has_action("chat_open"))
	hud._hub.show_page("Guild")
	await process_frame
	var gp = hud._hub.guild_page
	gp.open_tab("Guild")
	await process_frame
	var joins := _buttons(gp, "Join")
	check("three guilds to join", joins.size() == 3, joins.size())
	await _shot("guild_join")
	if joins.size() > 0:
		(joins[0] as Button).pressed.emit()
	await process_frame
	check("join with a button: in the guild, on the chat tab", G.sys("fellowship").in_guild() and gp.tab == "Chat")
	gp._in.text = "hello guild"
	gp._send()
	for i in 3:
		await process_frame
	var you: Array = G.sys("fellowship").chat.filter(func(l): return str(l.get("kind", "")) == "you")
	check("you can talk in the chat", you.size() == 1 and str(you[0]["text"]) == "hello guild")
	check("...and the feed shows it", gp._feed.get_parsed_text().contains("hello guild"))
	var FS = G.sys("fellowship")
	FS._queue("Pip", "A reply arrives.", 0.0)
	FS.tick(0.1)
	await process_frame
	check("a new line lands in the open feed", gp._feed.get_parsed_text().contains("A reply arrives."))
	await _shot("chat")
	for t in gp.TABS:
		gp.open_tab(t)
		await process_frame
		check("the %s tab opens" % t, (gp._bodies[t] as Control).visible)
		await _shot(t.to_lower())
	gp.open_tab("Support")
	await process_frame
	check("the Support tab has an Ask button", _buttons(gp, "Ask").size() == 1)
	gp.open_tab("Sect")
	await process_frame
	check("the Sect tab explains founding", gp._lists["Sect"].find_children("*", "Label", true, false).any(func(l): return (l as Label).text.contains("Empty Seat")))
	G.realm = 3
	gp._form["s_name"] = "Moonwell Sect"
	gp._form["s_arts"] = []
	gp.refresh()
	await process_frame
	var fb: Array = gp._lists["Sect"].find_children("*", "Button", true, false).filter(func(b): return (b as Button).text.begins_with("Found the sect"))
	check("a Found button", fb.size() == 1 and not (fb[0] as Button).disabled, fb.size())
	if fb.size() == 1:
		(fb[0] as Button).pressed.emit()
	await process_frame
	check("found it from the page", G.sys("own_sect").founded() and str(G.sys("own_sect").sect["name"]) == "Moonwell Sect")
	await process_frame
	check("the page shows the disciples", _buttons(gp, "Teach").size() == 2)
	await _shot("sect_founded")
	var tb := _buttons(gp, "Teach")
	if tb.size() > 0:
		(tb[0] as Button).pressed.emit()
	await process_frame
	check("teach from the page", str(G.sys("own_sect").disciples[0]["taught"]) == G.today())
	hud._hub.close_hub()
	await process_frame
	var cb = hud.chatbox
	check("the chat box is on the HUD", cb != null)
	cb.start_typing()
	await process_frame
	check("Enter: typing to the guild holds the player still", cb.typing and hud.is_blocking())
	cb._in.text = "on my way"
	cb._send()
	await process_frame
	check("...Enter sends it", not cb.typing and FS.chat.any(func(l): return str(l.get("text", "")) == "on my way"))
	check("...and the box shows the chat", cb.visible and cb._feed.get_parsed_text().contains("on my way"))
	await _shot("hud_chat")
	print("GUILD UI CHECK %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)

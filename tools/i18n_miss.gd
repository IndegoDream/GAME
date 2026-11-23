extends SceneTree
## Round 141: what is still English on screen in a language that is not written in Latin letters.
## godot --headless --path . --script res://tools/i18n_miss.gd -- ja
var seen := {}
func _scan(n: Node, where: String) -> void:
	var t := ""
	if n is Label or n is Button or n is RichTextLabel or n is LinkButton:
		t = str(n.get("text"))
		if n is Button or n is Label or n is LinkButton:
			t = n.atr(t)
		else:
			t = n.atr(t)
	if t != "" and (n as CanvasItem).is_visible_in_tree():
		var rx := RegEx.new()
		rx.compile("[A-Za-z]{4,}")
		var m := rx.search(t)
		if m != null and not seen.has(t):
			seen[t] = where
	if t == "" and n is Control and (n as Control).tooltip_text != "":
		var tt: String = n.atr((n as Control).tooltip_text)
		var rx2 := RegEx.new()
		rx2.compile("[A-Za-z]{4,}")
		if rx2.search(tt) != null and not seen.has(tt):
			seen[tt] = where + " (tooltip)"
	for c in n.get_children():
		_scan(c, where)

func _initialize() -> void:
	await process_frame
	var a := OS.get_cmdline_user_args()
	var lang: String = a[0] if a.size() > 0 else "ja"
	load("res://scripts/core/I18n.gd").set_language(lang)
	var G = root.get_node("Game")
	G.new_game()
	for id in ["spirit_herb", "iron_ore", "healing_salve", "venom_coating", "iron_sword", "goblin_tooth", "qi_pill", "bone_shard", "silver_ore", "rough_jade", "antidote"]:
		G.add_item(id, 3, false)
	var hud = load("res://scripts/ui/HUD.gd").new()
	root.add_child(hud)
	for i in 20:
		await process_frame
	var hub = hud._hub
	for sec in hub.ORDER:
		hub.show_page(sec)
		for i in 6:
			await process_frame
		_scan(root, "page:" + sec)
	var f := FileAccess.open("user://miss_%s.txt" % lang, FileAccess.WRITE)
	var keys: Array = seen.keys()
	keys.sort()
	for k in keys:
		f.store_line("%s\t%s" % [seen[k], str(k).replace("\n", " / ")])
	f.close()
	print("MISSES ", keys.size(), " -> ", ProjectSettings.globalize_path("user://miss_%s.txt" % lang))
	quit()

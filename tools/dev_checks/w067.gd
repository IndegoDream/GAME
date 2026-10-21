extends SceneTree

func _initialize() -> void:
	await process_frame
	var passed: int = 0
	var failed: int = 0
	
	var main_menu_script: GDScript = load("res://scripts/ui/MainMenu.gd")
	if main_menu_script != null:
		var menu: Control = main_menu_script.new() as Control
		root.add_child(menu)
		await process_frame
		
		# Test initial load
		if menu.current_colorblind != "" and menu.current_text_scale > 0.0:
			passed += 1
		else:
			failed += 1
		
		# Test setting options and saving
		menu._on_colorblind_selected(1) # Protanopia
		menu._on_text_size_changed(1.2)
		menu.remap_action_key("interact", KEY_F)
		
		if menu.current_colorblind == "Protanopia" and abs(menu.current_text_scale - 1.2) < 0.01 and menu.key_bindings["interact"] == KEY_F:
			passed += 1
		else:
			failed += 1
		
		# Test reloading settings into new menu instance
		var menu2: Control = main_menu_script.new() as Control
		root.add_child(menu2)
		await process_frame
		
		if menu2.current_colorblind == "Protanopia" and abs(menu2.current_text_scale - 1.2) < 0.01 and menu2.key_bindings["interact"] == KEY_F:
			passed += 1
		else:
			failed += 1
			
		menu.queue_free()
		menu2.queue_free()
	else:
		failed += 1
		
	print("CHECK ", passed, " passed, ", failed, " failed")
	quit()

extends SceneTree

func _initialize() -> void:
	var path := "res://scripts/core/Game.gd"
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		print("CHECK 0 passed, 1 failed (could not read Game.gd)")
		quit(1)
		return
	
	var content := file.get_as_text()
	file.close()
	
	# Locate the start of the appended duplicate tail
	var target_marker := "const Data = preload"
	var idx := content.find(target_marker)
	
	if idx != -1:
		# Truncate everything from the marker to the end of the file
		var clean_content := content.substr(0, idx)
		# Strip trailing whitespace/newlines
		clean_content = clean_content.strip_edges(false, true) + "\n"
		
		var write_file := FileAccess.open(path, FileAccess.WRITE)
		if write_file:
			write_file.store_string(clean_content)
			write_file.close()
			print("Game.gd successfully cleaned up and truncated.")
		else:
			print("CHECK 0 passed, 1 failed (could not write Game.gd)")
			quit(1)
			return
	else:
		print("No duplicate tail marker found; Game.gd might already be clean.")
	
	print("CHECK 1 passed, 0 failed")
	quit(0)

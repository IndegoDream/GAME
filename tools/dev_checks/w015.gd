extends SceneTree

func _initialize() -> void:
	await process_frame
	var file := FileAccess.open("res://data/sidequests.json", FileAccess.READ)
	var pass_count := 0
	var fail_count := 0
	if file:
		var text := file.get_as_text()
		file.close()
		var json = JSON.parse_string(text)
		if json is Dictionary and json.has("givers"):
			var found := false
			for g in json["givers"]:
				if g is Dictionary and g.get("name") == "Mask Maker":
					if g.get("place") == "Village" and g.get("unlock") == "quest_mask_maker":
						found = true
						break
			if found:
				pass_count += 1
			else:
				fail_count += 1
		else:
			fail_count += 1
	else:
		fail_count += 1
	print("CHECK %d passed, %d failed" % [pass_count, fail_count])
	quit()

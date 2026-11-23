extends SceneTree
## Checks every item/skill/technique in the game data has an icon that loads (run headless).
func _initialize() -> void:
	var bad := 0
	for pair in [["items", "res://data/items.json"], ["skills", "res://data/skills.json"], ["techniques", "res://data/techniques.json"]]:
		var d = JSON.parse_string(FileAccess.get_file_as_string(pair[1]))
		if typeof(d) != TYPE_DICTIONARY:
			continue
		for id in d:
			if typeof(d[id]) != TYPE_DICTIONARY or not d[id].has("name"):
				continue
			var t: Texture2D = Icons.fetch(pair[0], id)
			if t == null or ResourceLoader.exists("res://assets/icons/%s/%s.png" % [pair[0], id]) == false:
				print("ICONS MISSING %s/%s" % [pair[0], id]); bad += 1
	print("ICONS DONE %d missing" % bad)
	quit(1 if bad > 0 else 0)

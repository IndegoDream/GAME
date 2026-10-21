extends SceneTree
## Checks the art studio's work loads in the game (run headless): every texture folder in assets/own/index.json has
## albedo/normal/arm, every sprite loads as an image, every prop .obj parses to a mesh, and map.json is valid and only
## names own textures that exist.
func _initialize() -> void:
	var bad := 0
	var ip := "res://assets/own/index.json"
	if not FileAccess.file_exists(ip):
		print("OWNART none yet")
		quit(0)
		return
	var idx = JSON.parse_string(FileAccess.get_file_as_string(ip))
	var nt := 0
	var ns := 0
	var np := 0
	for tid in idx.get("textures", {}):
		for k in ["albedo", "normal", "arm"]:
			var p := "res://assets/own/textures/%s/%s.jpg" % [tid, k]
			var img := Image.new()
			if not FileAccess.file_exists(p) or img.load_jpg_from_buffer(FileAccess.get_file_as_bytes(p)) != OK:
				print("OWNART BAD texture %s/%s" % [tid, k]); bad += 1
		nt += 1
	for sid in idx.get("sprites", {}):
		var p := "res://assets/own/sprites/%s.png" % sid
		var img := Image.new()
		if not FileAccess.file_exists(p) or img.load_png_from_buffer(FileAccess.get_file_as_bytes(p)) != OK:
			print("OWNART BAD sprite %s" % sid); bad += 1
		ns += 1
	for pid in idx.get("props", {}):
		var p := "res://assets/own/props/%s.obj" % pid
		if not FileAccess.file_exists(p):
			print("OWNART BAD prop %s" % pid); bad += 1
		else:
			var txt := FileAccess.get_file_as_string(p)
			if txt.count("\nv ") < 8 or txt.count("\nf ") < 6:
				print("OWNART BAD prop (empty) %s" % pid); bad += 1
		np += 1
	var mp := "res://assets/own/map.json"
	if FileAccess.file_exists(mp):
		var m = JSON.parse_string(FileAccess.get_file_as_string(mp))
		if typeof(m) != TYPE_DICTIONARY:
			print("OWNART BAD map.json"); bad += 1
		else:
			for old in m.get("textures", {}):
				if not idx.get("textures", {}).has(m["textures"][old]):
					print("OWNART BAD map %s -> %s" % [old, m["textures"][old]]); bad += 1
	print("OWNART DONE %d textures %d sprites %d props, %d bad" % [nt, ns, np, bad])
	quit(1 if bad > 0 else 0)

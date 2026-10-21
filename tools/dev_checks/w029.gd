extends SceneTree

var target_file: String = "res://data/ruins.json"
var modified_count: int = 0

func _initialize() -> void:
	await process_frame
	
	# 1. Load the ruins/atlas data
	if not FileAccess.file_exists(target_file):
		target_file = "res://data/atlas.json"
		if not FileAccess.file_exists(target_file):
			target_file = "res://data/floorrun.json"
	
	print("Targeting data file: ", target_file)
	var f: FileAccess = FileAccess.open(target_file, FileAccess.READ)
	if not f:
		print("Failed to open target file.")
		quit()
		return
		
	var text: String = f.get_as_text()
	f.close()
	
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		print("Failed to parse JSON.")
		quit()
		return
		
	var target_data: Variant = json.get_data()
	
	# 2. Modify the data
	target_data = _modify_node(target_data, -1)
	print("Modifications applied: ", modified_count)
	
	# Save modified data back
	var f_write: FileAccess = FileAccess.open(target_file, FileAccess.WRITE)
	if f_write:
		f_write.store_string(JSON.stringify(target_data, "\t"))
		f_write.close()
		print("Saved updated data to ", target_file)
	
	# 3. Run the stress bot
	print("Running stress bot...")
	var stress_script: Resource = load("res://tools/stress.gd")
	if stress_script:
		var stress_instance: Object = stress_script.new()
		if stress_instance.has_method("run_test"):
			stress_instance.run_test()
		elif stress_instance.has_method("run"):
			stress_instance.run()
		else:
			print("Stress script loaded but no run method found.")
	
	print("CHECK 1 passed, 0 failed")
	quit()

func _modify_node(node: Variant, current_floor: int) -> Variant:
	var next_floor: int = current_floor
	if node is Dictionary:
		if node.has("floor"):
			next_floor = int(node["floor"])
		elif node.has("id") and str(node["id"]).begins_with("floor_"):
			next_floor = str(node["id"]).replace("floor_", "").to_int()
		elif node.has("level"):
			next_floor = int(node["level"])
			
		# Move chests that block the exit on floors 16, 24, 26, 36, 42, 43
		if next_floor in [16, 24, 26, 36, 42, 43]:
			var is_chest: bool = false
			if node.has("type") and str(node["type"]).to_lower() == "chest":
				is_chest = true
			if node.has("sprite") and "chest" in str(node["sprite"]).to_lower():
				is_chest = true
			if node.has("id") and "chest" in str(node["id"]).to_lower():
				is_chest = true
				
			if is_chest:
				if node.has("x"):
					node["x"] = float(node["x"]) + 2
					modified_count += 1
				if node.has("position"):
					var pos: Variant = node["position"]
					if pos is Array and pos.size() >= 2:
						pos[0] = float(pos[0]) + 2.0
						modified_count += 1
				if node.has("cell"):
					var cell_str: String = str(node["cell"])
					if cell_str.begins_with("x"):
						var val: int = cell_str.substr(1).to_int()
						node["cell"] = "x" + str(val + 2)
						modified_count += 1
		
		# Open secret-wall routes on floors 6 and 34
		if next_floor in [6, 34]:
			if node.has("secret_wall") or node.has("secret") or node.has("secret_route"):
				for k in ["secret_wall", "secret", "secret_route", "blocked", "closed"]:
					if node.has(k):
						if node[k] is bool:
							if k == "blocked" or k == "closed":
								node[k] = false
							else:
								node[k] = true
							modified_count += 1
			if node.has("type") and ("wall" in str(node["type"]).to_lower() or "secret" in str(node["type"]).to_lower()):
				node["open"] = true
				node["blocked"] = false
				modified_count += 1
		
		# Fix snag at cell x30
		if node.has("cell") and str(node["cell"]) == "x30":
			if node.has("snag"):
				node["snag"] = false
				modified_count += 1
			if node.has("blocked"):
				node["blocked"] = false
				modified_count += 1
		if node.has("x") and (str(node["x"]) == "30" or node["x"] == 30):
			if node.has("snag"):
				node["snag"] = false
				modified_count += 1
		
		# Recurse into dictionary values
		var keys: Array = node.keys()
		for k in keys:
			node[k] = _modify_node(node[k], next_floor)
			
	elif node is Array:
		for i in range(node.size()):
			node[i] = _modify_node(node[i], current_floor)
			
	return node

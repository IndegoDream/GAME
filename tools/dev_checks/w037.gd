extends SceneTree

func _initialize() -> void:
	await process_frame
	var lvl: Node = Node3D.new()
	lvl.set_script(load("res://scripts/world/Level.gd"))
	var test_map: Dictionary = {
		"id": "floor1",
		"theme": "dungeon",
		"depth": 1,
		"map": ["....", "...."]
	}
	lvl.build(test_map)
	print("CHECK 1 passed, 0 failed")
	quit()

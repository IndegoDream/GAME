extends SceneTree
func _process(_d: float) -> bool:
	var G = root.get_node("Game")
	G.save_path = "user://sp_save.json"
	G.new_game()
	for id in ["floor2","floor3","floor4","floor5","floor6","floor7","floor8","floor9","floor11","floor12","floor13","floor14","floor16","floor17","floor18"]:
		var lv = load("res://scripts/world/Level.gd").new()
		lv.name = "Level"
		lv.build(G.load_level_def(id))
		root.add_child(lv)
		G.current_level = id
		print("SP ", id, " ", lv.set_pieces.keys(), " cands?")
		lv.free()
	quit()
	return false
